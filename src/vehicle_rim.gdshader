shader_type spatial;
render_mode cull_disabled;

uniform sampler2D occlusion_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_vertex_tint = false;
uniform bool polished = false;
uniform bool use_normal_map = false;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform float normal_scale = 1.0;
uniform float surface_roughness = 0.35;
uniform float outward_sign = 1.0;
uniform float opening_x = 0.0;
uniform float barrel_width = 0.26;
varying float axial_depth;

void vertex() {
	float x = (MODEL_MATRIX * vec4(VERTEX, 1.0)).x;
	axial_depth = (opening_x - x) * outward_sign;
}

void fragment() {
	vec3 tint = use_vertex_tint ? COLOR.rgb : base_tint.rgb;
	float depth_ratio = max(0.0, axial_depth / barrel_width);
	// The recessed barrel has a smaller unobstructed view of the studio
	// lights than the spoke faces. Keep the material's tint on both.
	float outer_face = polished ? 1.0 - smoothstep(0.17, 0.52, depth_ratio) : 0.0;
	float aperture = mix(1.0, 0.18, smoothstep(0.16, 0.68, depth_ratio));
	float texture_visibility = texture(occlusion_map, UV).b;
	float rim_visibility = aperture * mix(texture_visibility, max(0.76, texture_visibility), outer_face);
	float finish = round(COLOR.a * 255.0);
	float decoded_roughness = clamp(mod(finish, 50.0) / 49.0, 0.08, 1.0);
	ALBEDO = mix(tint, max(tint, vec3(0.47, 0.49, 0.52)), outer_face * 0.80);
	METALLIC = polished ? 1.0 : 0.35;
	float roughness = use_vertex_tint && finish < 200.0 ? decoded_roughness : surface_roughness;
	ROUGHNESS = mix(roughness, 0.14, outer_face);
	AO = rim_visibility;
	AO_LIGHT_AFFECT = 0.73;
	RADIANCE = vec4(vec3(0.0), 1.0 - aperture);
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale * mix(1.0, 0.27, outer_face);
	}
}
