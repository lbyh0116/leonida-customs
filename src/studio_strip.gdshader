shader_type spatial;
render_mode unshaded;

uniform vec4 light_color : source_color = vec4(0.93, 0.96, 1.0, 1.0);
uniform float brightness = 2.4;

void fragment() {
	ALBEDO = light_color.rgb * brightness;
}
