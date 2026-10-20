shader_type spatial;
// Stylized stone: soft colour bands, speckles and moss on upward faces.
render_mode specular_disabled;

#include "res://shaders/stylized_common.gdshaderinc"
#include "res://shaders/cel_light.gdshaderinc"

uniform sampler2D noise_detail : filter_linear, repeat_enable;
uniform vec3 stone_dark : source_color = vec3(0.42, 0.42, 0.46);
uniform vec3 stone_base : source_color = vec3(0.62, 0.61, 0.60);
uniform vec3 stone_light : source_color = vec3(0.80, 0.78, 0.72);
uniform vec3 moss : source_color = vec3(0.42, 0.58, 0.27);
uniform float moss_amount = 0.5;
uniform float stylized = 1.0;
uniform float detail = 1.0;

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = texture(noise_detail, wpos.xz * 0.9 + vec2(wpos.y * 0.6)).r;
	vec3 col = mix(stone_dark, stone_base, smoothstep(-0.6, 0.3, wnormal.y));
	col = mix(col, stone_light, smoothstep(0.55, 0.75, n) * 0.6 * stylized);
	float sp = hash13(floor(wpos * 14.0));
	col = mix(col, stone_dark * 0.85, step(0.9, sp) * 0.7 * stylized);
	float m = smoothstep(0.45, 0.75, wnormal.y + (n - 0.5) * 0.6) * moss_amount * stylized;
	col = mix(col, moss, m);
	if (detail < 0.5) {
		col = mix(stone_base, moss, step(0.68, wnormal.y) * step(0.01, moss_amount));
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
