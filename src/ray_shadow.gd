extends RefCounted

const MAP_SIZE := 768
const RAYGEN := """
#version 460
#extension GL_EXT_ray_tracing : require
layout(set = 0, binding = 0) uniform accelerationStructureEXT vehicle;
layout(set = 0, binding = 1, r32f) uniform writeonly image2D shadow_mask;
layout(push_constant, std430) uniform Parameters {
	vec4 footprint;
	vec4 light; // direction toward the light, tangent of its angular radius
	vec4 quality; // samples, ray range
} params;
layout(location = 0) rayPayloadEXT float blocked;

void main() {
	vec2 uv = (vec2(gl_LaunchIDEXT.xy) + 0.5) / vec2(gl_LaunchSizeEXT.xy);
	vec2 floor_point = params.footprint.xy + uv * params.footprint.zw;
	vec3 source = vec3(floor_point.x, 0.004, floor_point.y);
	vec3 axis = normalize(params.light.xyz);
	vec3 side = normalize(cross(axis, vec3(0.0, 0.0, 1.0)));
	vec3 up = cross(side, axis);
	int sample_count = int(params.quality.x);
	float occlusion = 0.0;
	for (int index = 0; index < sample_count; index++) {
		float angle = float(index) * 2.39996323;
		float radius = sqrt((float(index) + 0.5) / float(sample_count)) * params.light.w;
		vec3 ray = normalize(axis + radius * (cos(angle) * side + sin(angle) * up));
		blocked = 1.0;
		traceRayEXT(vehicle,
			gl_RayFlagsOpaqueEXT | gl_RayFlagsTerminateOnFirstHitEXT,
			0xff, 0, 0, 0, source, 0.002, ray, params.quality.y, 0);
		occlusion += blocked;
	}
	imageStore(shadow_mask, ivec2(gl_LaunchIDEXT.xy), vec4(occlusion / float(sample_count)));
}
"""

const MISS := """
#version 460
#extension GL_EXT_ray_tracing : require
layout(location = 0) rayPayloadInEXT float blocked;
void main() { blocked = 0.0; }
"""

const CLOSEST := """
#version 460
#extension GL_EXT_ray_tracing : require
layout(location = 0) rayPayloadInEXT float blocked;
hitAttributeEXT vec2 barycentric;
void main() { blocked = 1.0; }
"""

var texture := Texture2DRD.new()
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _hit_table: RID
var _hit_range := -1
var _image: RID
var _vertices: RID
var _indices: RID
var _blas: RID
var _tlas: RID
var _uniforms: RID


static func is_supported() -> bool:
	var rd := RenderingServer.get_rendering_device()
	return rd != null and rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE) and rd.has_feature(RenderingDevice.SUPPORTS_BUFFER_DEVICE_ADDRESS)


func prepare(vertices: PackedVector3Array, indices: PackedInt32Array, parameters: PackedFloat32Array, callback: Callable) -> void:
	RenderingServer.call_on_render_thread(_prepare_render_thread.bind(
		vertices.to_byte_array(), vertices.size(), indices.to_byte_array(), indices.size(), parameters, callback))


func update(parameters: PackedFloat32Array) -> void:
	RenderingServer.call_on_render_thread(_dispatch.bind(parameters))


func release() -> void:
	RenderingServer.call_on_render_thread(_release_render_thread)


func _prepare_render_thread(vertices: PackedByteArray, vertex_count: int, indices: PackedByteArray, index_count: int, parameters: PackedFloat32Array, callback: Callable) -> void:
	if not _pipeline.is_valid() and not _initialize():
		_release_render_thread()
		callback.call_deferred(false)
		return
	_free_geometry()
	var usage := RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT | RenderingDevice.BUFFER_CREATION_DEVICE_ADDRESS_BIT
	_vertices = _rd.vertex_buffer_create(vertices.size(), vertices, usage)
	_indices = _rd.index_buffer_create(index_count, RenderingDevice.INDEX_BUFFER_FORMAT_UINT32, indices, false, usage)
	if not _vertices.is_valid() or not _indices.is_valid():
		_free_geometry()
		callback.call_deferred(false)
		return
	var geometry := RDAccelerationStructureGeometry.new()
	geometry.flags = RenderingDevice.ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT
	geometry.vertex_buffer = _vertices
	geometry.vertex_stride = 12
	geometry.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	geometry.vertex_count = vertex_count
	geometry.index_buffer = _indices
	geometry.index_count = index_count
	_blas = _rd.blas_create([geometry], 0)
	_tlas = _rd.tlas_create(1, 0)
	if not _blas.is_valid() or not _tlas.is_valid() or _rd.blas_build(_blas) != OK:
		_free_geometry()
		callback.call_deferred(false)
		return
	var instance := RDAccelerationStructureInstance.new()
	instance.blas = _blas
	instance.transform = Transform3D.IDENTITY
	instance.mask = 255
	instance.hit_sbt_range = _hit_range
	if _rd.tlas_build(_tlas, [instance]) != OK:
		_free_geometry()
		callback.call_deferred(false)
		return
	_uniforms = _rd.uniform_set_create([
		_uniform(0, RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE, _tlas),
		_uniform(1, RenderingDevice.UNIFORM_TYPE_IMAGE, _image),
	], _shader, 0)
	if not _uniforms.is_valid():
		_free_geometry()
		callback.call_deferred(false)
		return
	_dispatch(parameters)
	callback.call_deferred(true)


func _initialize() -> bool:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return false
	var source := RDShaderSource.new()
	source.source_raygen = RAYGEN
	source.source_miss = MISS
	source.source_closest_hit = CLOSEST
	var spirv := _rd.shader_compile_spirv_from_source(source)
	for stage in [RenderingDevice.SHADER_STAGE_RAYGEN, RenderingDevice.SHADER_STAGE_MISS, RenderingDevice.SHADER_STAGE_CLOSEST_HIT]:
		var error := spirv.get_stage_compile_error(stage)
		if not error.is_empty():
			push_error(error)
			return false
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		return false
	var raygen := RDPipelineShader.new()
	raygen.shader = _shader
	var miss := RDPipelineShader.new()
	miss.shader = _shader
	var closest := RDPipelineShader.new()
	closest.shader = _shader
	var hit := RDHitGroup.new()
	hit.closest_hit_shader = closest
	_pipeline = _rd.raytracing_pipeline_create([raygen], [miss], [hit], 1)
	if not _pipeline.is_valid():
		return false
	_hit_table = _rd.hit_sbt_create(_pipeline, 1)
	if not _hit_table.is_valid():
		return false
	_hit_range = _rd.hit_sbt_range_alloc(_hit_table, 1)
	if _hit_range < 0 or _rd.hit_sbt_range_update(_hit_table, _hit_range, 0, PackedInt32Array([0])) != OK:
		return false
	var format := RDTextureFormat.new()
	format.width = MAP_SIZE
	format.height = MAP_SIZE
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_image = _rd.texture_create(format, RDTextureView.new())
	if not _image.is_valid():
		return false
	texture.texture_rd_rid = _image
	return true


func _uniform(binding: int, type: RenderingDevice.UniformType, rid: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.binding = binding
	uniform.uniform_type = type
	uniform.add_id(rid)
	return uniform


func _dispatch(parameters: PackedFloat32Array) -> void:
	if not _uniforms.is_valid():
		return
	var commands := _rd.raytracing_list_begin()
	_rd.raytracing_list_bind_raytracing_pipeline(commands, _pipeline)
	_rd.raytracing_list_bind_uniform_set(commands, _uniforms, 0)
	var bytes := parameters.to_byte_array()
	_rd.raytracing_list_set_push_constant(commands, bytes, bytes.size())
	_rd.raytracing_list_trace_rays(commands, 0, _hit_table, MAP_SIZE, MAP_SIZE, 1)
	_rd.raytracing_list_end()


func _free_geometry() -> void:
	for resource in [_uniforms, _tlas, _blas, _indices, _vertices]:
		if resource.is_valid():
			_rd.free_rid(resource)
	_uniforms = RID()
	_tlas = RID()
	_blas = RID()
	_indices = RID()
	_vertices = RID()


func _release_render_thread() -> void:
	_free_geometry()
	if _image.is_valid():
		texture.texture_rd_rid = RID()
	for resource in [_image, _pipeline, _shader]:
		if resource.is_valid():
			_rd.free_rid(resource)
	_image = RID()
	_pipeline = RID()
	_shader = RID()
	_hit_table = RID()
