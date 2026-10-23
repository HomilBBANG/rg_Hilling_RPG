shader_type spatial;
// Stylised pixel-art water (lakes, ponds and the sea around a region), after the 3D-pixel-art
// water look (davidhol.land "3D Pixel Art Rendering"): bright turquoise surface whose colour comes
// from the water depth under it (depth texture), a little refraction of the bottom in the shallows,
// shadows that turn the water a saturated blue instead of dark, screen-space reflections of what
// stands in / beside the water, crisp white foam lines where anything meets the surface, and
// short white wave dashes that blink and drift. Everything is evaluated per render texel.
// Sea mode: no bottom under the plane, so depth comes from the distance to the land rectangle.
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled, ambient_light_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;

uniform vec3 shallow_color : source_color = vec3(0.42, 0.86, 0.84);
uniform vec3 water_color : source_color = vec3(0.22, 0.73, 0.82);
uniform vec3 deep_color : source_color = vec3(0.15, 0.6, 0.78);
uniform vec3 foam_color : source_color = vec3(0.94, 1.0, 1.0);
// Lit water is multiplied by this inside shadows: a clear blue, not grey (reference look).
uniform vec3 shadow_tint : source_color = vec3(0.5, 0.56, 1.0);
uniform float depth_range = 1.3;      // metres of water until it reads fully deep
uniform float clarity : hint_range(0.0, 1.0) = 0.22;  // how much of the bottom shows in the shallows
uniform float refraction = 0.6;       // wobble of the bottom, in texels
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.42;
uniform vec3 reflection_tint : source_color = vec3(0.55, 0.88, 0.95);
uniform float foam_width = 0.07;      // metres of shallow water that turn into the white edge line
uniform float wave_density : hint_range(0.0, 1.0) = 0.16;
uniform float glint_density : hint_range(0.0, 1.0) = 0.05;
uniform float light_gain = 0.85;
uniform float night_floor = 0.07;     // keeps the water readable when the sun is gone
uniform bool sea = false;
uniform vec4 land_rect = vec4(-100.0, -100.0, 100.0, 100.0);  // xz min, xz max (sea mode)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

// Signed distance from p to the land rectangle (negative inside).
float land_sdf(vec2 p) {
	vec2 c = (land_rect.xy + land_rect.zw) * 0.5;
	vec2 h = (land_rect.zw - land_rect.xy) * 0.5;
	vec2 q = abs(p - c) - h;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

void fragment() {
	vec2 p = wpos.xz;
	// world size of one render texel (the low-res pixel) along x / z on the water plane
	float tx = max(fwidth(p.x), 0.0001);
	float tz = max(fwidth(p.y), 0.0001);
	float n1 = texture(noise_tex, p * 0.09 + vec2(TIME * 0.012, 0.0)).r;
	float n2 = texture(noise_tex, p * 0.31 - vec2(0.0, TIME * 0.02)).r;

	// --- water depth under this texel
	vec3 bottom_v = view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 bottom_w = (INV_VIEW_MATRIX * vec4(bottom_v, 1.0)).xyz;
	bool has_bottom = texture(depth_tex, SCREEN_UV).r > 0.00001;  // reversed Z: 0 = nothing behind
	float depth = has_bottom ? max(wpos.y - bottom_w.y, 0.0) : 99.0;
	float coast = 99.0;
	if (sea) {
		coast = land_sdf(p) + (n1 - 0.5) * 0.9 + (n2 - 0.5) * 0.2;
		depth = min(depth, max(coast, 0.0) * 0.22);
	}

	// --- body colour: shallow -> water -> deep in hard pixel-art bands
	float t = clamp(depth / depth_range, 0.0, 1.0);
	float band = t < 0.05 ? 0.0 : (t < 0.6 ? 0.5 : 1.0);
	vec3 body = band < 0.25 ? shallow_color : (band < 0.75 ? water_color : deep_color);

	// --- the bottom seen through the shallows (refracted)
	vec2 wobble = vec2(sin(p.y * 3.1 + TIME * 1.6), cos(p.x * 2.7 + TIME * 1.3)) * refraction / VIEWPORT_SIZE;
	vec2 ruv = SCREEN_UV + wobble * (1.0 - t);
	vec3 rb = view_pos(ruv, INV_PROJECTION_MATRIX);
	if (rb.z > VERTEX.z) {  // refracted sample is in front of the water: don't pull it in
		ruv = SCREEN_UV;
	}
	vec3 under = texture(screen_tex, ruv).rgb;
	float see = has_bottom ? clarity * (1.0 - smoothstep(0.0, 0.6, t)) : 0.0;
	vec3 col = mix(body, under * mix(vec3(1.0), shallow_color * 1.25, 0.6), see);

	// --- screen-space reflection of what stands above the water (trees, rocks, people, piers)
	vec3 n_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 dir_in = PROJECTION_MATRIX[3][3] > 0.5 ? vec3(0.0, 0.0, -1.0) : normalize(VERTEX);  // orthographic: parallel rays
	vec3 r = reflect(dir_in, n_view);
	float hit = 0.0;
	vec3 refl = vec3(0.0);
	float stepl = 0.25;
	vec3 rp = VERTEX;
	for (int i = 0; i < 28; i++) {
		rp += r * stepl;
		stepl *= 1.12;
		vec4 clip = PROJECTION_MATRIX * vec4(rp, 1.0);
		vec2 suv = clip.xy / clip.w * 0.5 + 0.5;
		if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
			break;
		}
		vec3 sv = view_pos(suv, INV_PROJECTION_MATRIX);
		float diff = sv.z - rp.z;  // > 0: the scene surface is in front of the ray point
		if (diff > 0.0 && diff < 1.2 + stepl) {
			vec3 sw = (INV_VIEW_MATRIX * vec4(sv, 1.0)).xyz;
			if (sw.y > wpos.y + 0.05) {
				suv.x += sin(p.y * 6.0 + TIME * 2.0) * 0.8 / VIEWPORT_SIZE.x;
				refl = texture(screen_tex, suv).rgb;
				hit = 1.0 - float(i) / 28.0;
			}
			break;
		}
	}
	col = mix(col, refl * reflection_tint, hit > 0.0 ? reflection_strength * (0.6 + 0.4 * hit) : 0.0);

	// --- foam: a crisp white line where the surface meets anything, a lighter ring further out
	float foam_d = sea ? max(coast, 0.0) : depth;
	float edge_n = (n2 - 0.5) * 0.04;
	float foam = step(foam_d + edge_n, foam_width);
	float ring_at = foam_width * (2.0 + 0.5 * sin(TIME * 1.1));
	float ring = step(abs(foam_d - ring_at), foam_width * 0.3) * step(foam_width * 1.4, foam_d) * 0.6;
	if (sea) {
		foam = step(foam_d + edge_n * 3.0, 0.28);
		ring = step(abs(foam_d - (1.1 + 0.35 * sin(TIME * 0.9))), 0.09) * step(0.5, foam_d);
	}
	col = mix(col, mix(col, foam_color, 0.5), ring);
	col = mix(col, foam_color, foam);

	// --- wave dashes: short one-texel white lines, blinking and drifting with the current
	vec2 cell_size = vec2(1.9, 0.62);
	vec2 q = (p + vec2(TIME * 0.18, 0.0)) / cell_size;
	q.x += floor(q.y) * 0.37;
	vec2 ci = floor(q);
	float h = hash12(ci);
	if (h < wave_density && foam < 0.5) {
		vec2 f = fract(q);
		float len = 0.35 + 0.4 * hash12(ci + 7.3);
		float x0 = hash12(ci + 3.1) * (1.0 - len);
		float life = fract(TIME * 0.22 + h * 13.0);
		float on = step(life, 0.62) * step(x0, f.x) * step(f.x, x0 + len * (0.6 + 0.4 * sin(life * 3.14159)));
		on *= step(abs((f.y - 0.5) * cell_size.y), tz * 0.55);
		col = mix(col, foam_color, on * 0.9);
	}
	// --- glints: tiny three-texel sparkles, mostly in deeper water
	vec2 gq = p / 2.6;
	vec2 gi = floor(gq);
	float gh = hash12(gi + 41.0);
	if (gh < glint_density * band && foam < 0.5) {
		vec2 gc = (gi + vec2(0.3 + 0.4 * hash12(gi + 2.0), 0.3 + 0.4 * hash12(gi + 5.0))) * 2.6;
		vec2 o = vec2((p.x - gc.x) / tx, (p.y - gc.y) / tz);
		vec2 oi = floor(o + 0.5);
		bool px = (oi == vec2(0.0, 0.0)) || (oi == vec2(-1.0, 1.0)) || (oi == vec2(1.0, 1.0));
		float blink = step(0.5, fract(TIME * 0.35 + gh * 9.0));
		col = mix(col, foam_color, (px ? 1.0 : 0.0) * blink * 0.85);
	}

	ALBEDO = col;
	EMISSION = col * night_floor;
	ROUGHNESS = 1.0;
	ALPHA = 1.0;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// shadow = blue tint of the lit colour, not darkness (reference)
		vec3 lc = LIGHT_COLOR / PI;
		lc = mix(lc, vec3(dot(lc, vec3(0.3, 0.59, 0.11))), 0.6);  // keep the turquoise, not the sun's warmth
		DIFFUSE_LIGHT += mix(shadow_tint, vec3(1.0), ATTENUATION) * lc * light_gain;
	} else {
		DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR / PI * 0.6;
	}
}
