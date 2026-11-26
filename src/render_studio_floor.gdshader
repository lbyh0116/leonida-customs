shader_type spatial;
render_mode cull_disabled;

uniform float surface_roughness : hint_range(0.08, 0.9) = 0.29;
uniform bool show_grid = false;
uniform vec4 backdrop_color : source_color = vec4(0.91, 0.93, 0.95, 1.0);
uniform vec4 floor_color : source_color = vec4(0.56, 0.58, 0.62, 1.0);
uniform sampler2D floor_reflection : filter_linear, repeat_disable;
uniform bool show_reflection = false;
uniform vec4 tire_patches[8];
uniform int tire_count = 0;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_point.xz;
	float distance_from_center = length(p);
	float edge = smoothstep(4.0, 19.0, distance_from_center);
	vec3 color = mix(floor_color.rgb, floor_color.rgb * 1.11, edge);
	float grain = fract(sin(dot(floor(p * 240.0), vec2(127.1, 311.7))) * 43758.5453);
	color *= 0.98 + grain * 0.04;
	if (show_grid) {
		vec2 derivative = max(fwidth(p), vec2(0.0001));
		vec2 grid = abs(fract(p + 0.5) - 0.5) / derivative;
		float line = 1.0 - clamp(min(grid.x, grid.y), 0.0, 1.0);
		color = mix(color, vec3(0.10, 0.12, 0.17), line * (1.0 - edge) * 0.45);
	}
	float visibility = 1.0;
	for (int i = 0; i < tire_count; ++i) {
		vec2 patch = (p - tire_patches[i].xy) / tire_patches[i].zw;
		visibility *= 1.0 - 0.84 * (1.0 - smoothstep(0.14, 1.0, dot(patch, patch)));
	}
	float sweep = smoothstep(22.0, 95.0, distance_from_center);
	float reflectivity = 0.0;
	vec4 reflected = vec4(0.0);
	if (show_reflection) {
		vec2 uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y);
		vec2 blur = vec2(surface_roughness * 0.021);
		reflected = texture(floor_reflection, uv) * 0.44;
		reflected += (texture(floor_reflection, uv + vec2(blur.x, 0.0))
			+ texture(floor_reflection, uv - vec2(blur.x, 0.0))
			+ texture(floor_reflection, uv + vec2(0.0, blur.y))
			+ texture(floor_reflection, uv - vec2(0.0, blur.y))) * 0.14;
		float grazing = pow(1.0 - max(0.0, dot(NORMAL, VIEW)), 2.0);
		reflectivity = (0.20 + 0.31 * grazing) * (1.0 - smoothstep(0.13, 0.68, surface_roughness)) * (1.0 - edge);
	}
	ALBEDO = color * visibility * (1.0 - sweep) * (1.0 - reflectivity * reflected.a);
	EMISSION = mix(vec3(0.034) * visibility, backdrop_color.rgb, sweep) + reflected.rgb * reflectivity * mix(0.65, 1.0, visibility) * 1.35;
	METALLIC = 0.0;
	ROUGHNESS = mix(surface_roughness, 0.68, edge);
	SPECULAR = 0.23;
}
