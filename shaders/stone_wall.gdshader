shader_type spatial;
// Dressed stone walls (pixel-art reference): brick courses with darker mortar, a per-brick tone
// variation, light top bevels, a few cracks, and moss creeping up from the ground and over top
// faces. Mapped in world space, so the courses stay level on any box or round tower.
render_mode specular_disabled;

#include "res://shaders/stylized_common.gdshaderinc"
#include "res://shaders/cel_light.gdshaderinc"

uniform sampler2D noise_detail : filter_linear, repeat_enable;
uniform vec3 stone_dark : source_color = vec3(0.46, 0.45, 0.44);
uniform vec3 stone_base : source_color = vec3(0.64, 0.62, 0.58);
uniform vec3 stone_light : source_color = vec3(0.78, 0.76, 0.7);
uniform vec3 mortar : source_color = vec3(0.34, 0.33, 0.33);
uniform vec3 moss : source_color = vec3(0.27, 0.44, 0.21);
uniform float moss_amount = 0.6;   // 0 = none, 1 = heavy
uniform float moss_height = 1.6;   // metres above y = 0 that the ground moss climbs
uniform float brick_w = 0.9;
uniform float brick_h = 0.42;
uniform float stylized = 1.0;
uniform float detail = 1.0;

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnormal);
	bool top = n.y > 0.5;
	// wall faces: u along the wall, v = height; top faces: square flagstones in x / z
	vec2 uv;
	if (top) {
		uv = wpos.xz;
	} else {
		vec2 t = normalize(vec2(-n.z, n.x) + vec2(1e-4, 0.0));
		uv = vec2(dot(wpos.xz, t), wpos.y);
	}
	float bh = top ? brick_w : brick_h;
	float row = floor(uv.y / bh);
	float offs = top ? 0.0 : mod(row, 2.0) * 0.5 * brick_w;  // running bond
	vec2 b = vec2((uv.x + offs) / brick_w, uv.y / bh);
	vec2 bid = floor(b);
	vec2 f = fract(b);
	float mw = 0.05 / brick_w;
	float mh = 0.05 / bh;
	float in_mortar = clamp(step(f.x, mw) + step(f.y, mh), 0.0, 1.0);
	// per-brick tone (three steps) and a light bevel along each brick's top edge
	float h1 = hash12(bid + vec2(3.1, 7.7) + floor(n.xz * 2.0) * 13.0);
	vec3 col = stone_base;
	col = mix(col, stone_light, step(0.74, h1) * 0.55);
	col = mix(col, stone_dark, step(h1, 0.2) * 0.6);
	col = mix(col, stone_dark, smoothstep(0.3, -0.4, n.y) * 0.3);
	col = mix(col, stone_light, step(1.0 - mh * 1.3, f.y) * (1.0 - in_mortar) * 0.55 * stylized);
	// cracks: one brick in ten carries a dark jagged line
	float nz = texture(noise_detail, uv * 0.9 + bid * 0.37).r;
	float crack = step(0.9, hash12(bid + 11.0)) * (1.0 - smoothstep(0.012, 0.03, abs(nz - 0.5)));
	col = mix(col, mortar * 0.85, crack * stylized);
	// moss: patches low on the wall (climbing from the ground) and on top faces
	// coherent patches (low-frequency noise), bigger and lower on the wall with moss_amount
	float nm = texture(noise_detail, uv * 0.22 + vec2(7.0, 3.0)).r;
	float low = top ? 0.4 : smoothstep(moss_height, 0.1, wpos.y);
	float m = step(0.74 - moss_amount * 0.14, nm + low * 0.26) * step(0.01, moss_amount) * stylized;
	col = mix(col, moss, m);
	col = mix(col, mix(mortar, moss * 0.8, m), in_mortar * stylized);
	ALBEDO = col;
	ROUGHNESS = 0.95;  // outlined and bevel-highlighted by the pixel outline pass
}
