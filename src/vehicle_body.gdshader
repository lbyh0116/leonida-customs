shader_type spatial;
render_mode cull_disabled;

uniform sampler2D base_map : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D occlusion_map : hint_default_white, filter_linear_mipmap_anisotropic;
uniform bool use_normal_map = false;
uniform float normal_scale = 1.0;
uniform float base_metallic = 0.0;
uniform float base_roughness = 0.5;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform vec4 paint_color : source_color = vec4(1.0);
uniform bool recolor = false;
uniform int finish = 0;
uniform bool path_tracing = false;
uniform vec3 front_bounds;
#ifdef VEHICLE_CUTOUT
uniform float alpha_cutoff = 0.5;
#endif
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float flake_variation(vec3 position, float distance_to_camera) {
	// Car-scale flakes fade out as they become smaller than a pixel.
	vec3 cell = fract(floor(position * 280.0) * 0.1031);
	cell += dot(cell, cell.yzx + 33.33);
	float grain = fract((cell.x + cell.y) * cell.z);
	return (smoothstep(0.82, 1.0, grain) - 0.09) * (1.0 - smoothstep(0.7, 2.6, distance_to_camera));
}

void fragment() {
	float code = round(COLOR.a * 255.0);
	float paint = smoothstep(251.0, 254.0, code);
	vec4 base = texture(base_map, UV);
	vec3 part_color = COLOR.rgb * base_tint.rgb * base.rgb;
#ifdef VEHICLE_CUTOUT
	ALPHA = base.a * base_tint.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
#endif
	vec3 body_color = recolor ? paint_color.rgb : COLOR.rgb;
	vec3 tint = mix(part_color, body_color, paint);
	float metalness = code < 200.0 ? floor(code / 50.0) / 3.0 : base_metallic;
	float roughness = code < 200.0 ? clamp(mod(code, 50.0) / 49.0, 0.06, 1.0) : base_roughness;
	float body_metal = 0.43;
	float body_roughness = 0.30;
	float coat = 0.73;
	float coat_roughness = 0.13;
	if (finish == 1) {
		body_metal = 0.08;
		body_roughness = 0.20;
		coat = 1.0;
		coat_roughness = 0.055;
	} else if (finish == 2) {
		body_metal = 0.38;
		body_roughness = 0.25;
		coat = 0.97;
		coat_roughness = 0.075;
		float flakes = flake_variation(world_point, length(VERTEX));
		body_metal += 0.18 * flakes;
		vec3 flake_color = clamp(body_color + (vec3(0.15) + 0.35 * body_color) * flakes, vec3(0.0), vec3(1.0));
		tint += (flake_color - body_color) * paint;
	} else if (finish == 3) {
		body_metal = 0.06;
		body_roughness = 0.72;
		coat = 0.0;
	} else if (finish == 4) {
		float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
		vec3 pearl = mix(body_color.brg, vec3(0.70, 0.75, 1.0) * max(max(body_color.r, body_color.g), body_color.b), 0.38);
		tint = mix(tint, pearl, paint * (0.17 + 0.60 * pow(1.0 - facing, 2.2)));
		body_metal = 0.36;
		body_roughness = 0.24;
		coat = 0.97;
		coat_roughness = 0.085;
	}

	// RTX evaluates one reflection lobe for a custom spatial material. Use
	// the coat's roughness in that lobe while keeping a broader base in raster.
	float body_specular = 0.5;
	if (path_tracing) {
		body_roughness = sqrt(mix(body_roughness * body_roughness, coat_roughness * coat_roughness, coat));
		body_specular = mix(0.5, 0.68, coat);
	}

	// SixNG merges grilles, ducting and painted panels into shared surfaces.
	// Limit extra cavity attenuation to dark dielectric parts low in the nose.
	float depth = (world_point.z - front_bounds.x) / front_bounds.y;
	float low_nose = 1.0 - smoothstep(0.32, 0.45, world_point.y / front_bounds.z);
	float plastic = (1.0 - smoothstep(0.0, 0.3, metalness)) * (1.0 - smoothstep(0.035, 0.18, dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722))));
	float recess = low_nose * plastic * (1.0 - paint) * smoothstep(0.010, 0.056, depth) * (1.0 - smoothstep(0.13, 0.21, depth));
	float aperture = 1.0 - 0.85 * recess;
	ALBEDO = tint * mix(1.0, 0.35, recess);
	METALLIC = mix(metalness, body_metal, paint);
	ROUGHNESS = mix(mix(roughness, body_roughness, paint), 0.78, recess);
	SPECULAR = mix(mix(0.5, body_specular, paint), 0.12, recess);
	CLEARCOAT = path_tracing ? 0.0 : paint * coat;
	CLEARCOAT_ROUGHNESS = coat_roughness;
	AO = texture(occlusion_map, UV).b * aperture;
	AO_LIGHT_AFFECT = 0.85;
	RADIANCE = vec4(vec3(0.0), 1.0 - aperture);
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale * mix(1.0, 0.25, paint);
	}
}
