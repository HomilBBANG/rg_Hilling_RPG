shader_type spatial;
// Stylized foliage: toon light, hue variation, leaf-clump highlights on the lit/top side,
// darker underside. `fade` < 1 uses screen-door dithering (stays opaque, pixel-art friendly).
// shadows_disabled: canopies don't receive shadows (blobs shadowing each other aliased into
// hatching once pixelated); they still cast shadows on the ground. Shape reads from cel light.
render_mode specular_disabled, shadows_disabled;

#include "res://shaders/stylized_common.gdshaderinc"
#include "res://shaders/cel_light.gdshaderinc"

uniform sampler2D noise_detail : filter_linear, repeat_enable;
uniform vec3 leaf_dark : source_color = vec3(0.16, 0.36, 0.22);
uniform vec3 leaf_base : source_color = vec3(0.30, 0.55, 0.25);
uniform vec3 leaf_light : source_color = vec3(0.58, 0.76, 0.32);
uniform float hue_shift = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float stylized = 1.0;
uniform float detail = 1.0;

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Triplanar sample so the pattern doesn't streak on steep blob sides.
float triplanar(vec3 p, vec3 nrm) {
	vec3 w = pow(abs(nrm), vec3(3.0));
	w /= (w.x + w.y + w.z);
	return texture(noise_detail, p.yz).r * w.x + texture(noise_detail, p.xz).r * w.y + texture(noise_detail, p.xy).r * w.z;
}

void fragment() {
	if (fade < 0.999 && bayer4(FRAGCOORD.xy) > fade) {
		discard;
	}
	float up = wnormal.y;
	float n = triplanar(wpos * 0.35, wnormal);
	float clump = triplanar(wpos * 0.5 + vec3(0.3, 0.1, 0.6), wnormal);
	vec3 col = mix(leaf_dark, leaf_base, smoothstep(-0.55, 0.35, up));
	col = mix(col, leaf_light, smoothstep(0.56, 0.66, clump) * smoothstep(0.0, 0.7, up) * 0.6 * stylized);
	col = mix(col, leaf_dark, smoothstep(0.34, 0.26, clump) * 0.22 * stylized);
	col *= 1.0 + (n - 0.5) * 0.18 * stylized;
	if (detail < 0.5) {
		col = leaf_base;  // single flat colour; light/shadow comes only from cel lighting
	}
	col.r += hue_shift * 0.06;
	col.b -= hue_shift * 0.04;
	ALBEDO = col;
	ROUGHNESS = 0.93;
}
