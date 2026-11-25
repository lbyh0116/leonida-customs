shader_type spatial;
render_mode cull_disabled;

uniform float surface_roughness : hint_range(0.08, 0.9) = 0.29;
uniform bool show_grid = false;
uniform vec4 backdrop_color : source_color = vec4(0.91, 0.93, 0.95, 1.0);
uniform sampler2D ray_shadow : filter_linear, repeat_disable;
uniform vec4 shadow_rect;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.7;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_point.xz;
	float distance_from_center = length(p);
	float edge = smoothstep(4.0, 19.0, distance_from_center);
	vec3 color = mix(vec3(0.78, 0.79, 0.82), vec3(0.67, 0.69, 0.72), edge);
	float grain = fract(sin(dot(floor(p * 240.0), vec2(127.1, 311.7))) * 43758.5453);
	color *= 0.98 + grain * 0.04;
	if (show_grid) {
		vec2 derivative = max(fwidth(p), vec2(0.0001));
		vec2 grid = abs(fract(p + 0.5) - 0.5) / derivative;
		float line = 1.0 - clamp(min(grid.x, grid.y), 0.0, 1.0);
		color = mix(color, vec3(0.10, 0.12, 0.17), line * (1.0 - edge) * 0.45);
	}
	if (shadow_rect.z > 0.0) {
		vec2 uv = (p - shadow_rect.xy) / shadow_rect.zw;
		if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
			vec2 edge_uv = min(uv, 1.0 - uv);
			float fade = smoothstep(0.0, 0.035, min(edge_uv.x, edge_uv.y));
			color *= 1.0 - shadow_strength * fade * texture(ray_shadow, uv).r;
		}
	}
	float sweep = smoothstep(22.0, 95.0, distance_from_center);
	ALBEDO = color * (1.0 - sweep);
	EMISSION = mix(vec3(0.11), backdrop_color.rgb, sweep);
	METALLIC = 0.025;
	ROUGHNESS = mix(surface_roughness, 0.68, edge);
	SPECULAR = 0.34;
}
