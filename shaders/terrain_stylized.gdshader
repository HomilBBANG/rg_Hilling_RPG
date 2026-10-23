shader_type spatial;
// Hand-painted style ground: multi-hue grass patches, brush specks, tiny flowers,
// a dirt path with irregular noisy edges, pebbles and a darker rim, sandy pond shore.
// Vertex COLOR carries masks: r = path, g = shore, b = forest shade, a = camp wear.
render_mode specular_disabled;

#include "res://shaders/stylized_common.gdshaderinc"
#include "res://shaders/cel_light.gdshaderinc"

uniform sampler2D noise_large : filter_linear, repeat_enable;
uniform sampler2D noise_detail : filter_linear, repeat_enable;

uniform vec3 grass_dark : source_color = vec3(0.24, 0.45, 0.24);
uniform vec3 grass_mid : source_color = vec3(0.39, 0.61, 0.27);
uniform vec3 grass_light : source_color = vec3(0.56, 0.74, 0.33);
uniform vec3 grass_warm : source_color = vec3(0.70, 0.73, 0.36);
uniform vec3 grass_cool : source_color = vec3(0.27, 0.55, 0.42);
uniform vec3 dirt_dark : source_color = vec3(0.50, 0.34, 0.22);
uniform vec3 dirt_mid : source_color = vec3(0.66, 0.56, 0.4);
uniform vec3 dirt_light : source_color = vec3(0.80, 0.64, 0.43);
uniform vec3 sand : source_color = vec3(0.78, 0.72, 0.54);
uniform vec3 pebble : source_color = vec3(0.78, 0.74, 0.68);
uniform float stylized = 1.0;  // 0 = flat legacy colours (camera style A)
// 0 = flat cel colours: one colour per ground type, no specks/flowers/strokes (style D).
uniform float detail = 1.0;

varying vec3 wpos;
varying vec4 masks;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	masks = COLOR;
}

// Two-tone border with a 2-texel checker dither band (pixel-art soft edge): 1 above the edge,
// 0 below, the checker only within ~1.5 texels of it (fwidth = change per screen texel).
float dither_step(float edge, float v, vec2 cell) {
	float d = (v - edge) / max(fwidth(v), 1e-5);
	float checker = mod(cell.x + cell.y, 2.0);
	return abs(d) < 1.5 ? checker : step(0.0, d);
}

void fragment() {
	vec2 p = wpos.xz;
	float n_large = texture(noise_large, p * 0.011).r;
	float n_mid = texture(noise_detail, p * 0.055).r;
	float n_small = texture(noise_detail, p * 0.21 + vec2(0.37, 0.11)).r;
	float n_tiny = texture(noise_detail, p * 0.73 + vec2(0.71, 0.29)).r;

	// --- grass: big hue patches, mid clumps, small brush strokes
	vec3 g = mix(grass_dark, grass_mid, smoothstep(0.28, 0.62, n_large));
	g = mix(g, grass_cool, smoothstep(0.62, 0.3, n_mid) * 0.35);
	g = mix(g, grass_light, smoothstep(0.55, 0.78, n_mid) * 0.75);
	g = mix(g, grass_warm, smoothstep(0.68, 0.88, n_large) * 0.55);
	float stroke = step(0.56, n_small) * 0.07 - step(n_small, 0.36) * 0.07;
	g *= 1.0 + stroke * stylized;
	// pixel-sized specks: light blades / dark gaps
	vec2 cell = floor(p * 9.0);
	float h = hash12(cell);
	g = mix(g, grass_light * 1.08, step(0.93, h) * 0.6 * stylized);
	g = mix(g, grass_dark * 0.85, step(h, 0.05) * 0.6 * stylized);
	// tiny flowers (2-3 texels), clustered by noise
	vec2 fcell = floor(p * 6.0);
	float fh = hash12(fcell + 17.0);
	float flower_zone = smoothstep(0.55, 0.75, n_mid);
	if (stylized > 0.5 && fh > 0.975 - flower_zone * 0.03) {
		float pick = hash12(fcell + 5.0);
		vec3 petal = pick < 0.4 ? vec3(0.98, 0.95, 0.86) : (pick < 0.7 ? vec3(0.99, 0.82, 0.35) : vec3(0.93, 0.6, 0.78));
		vec2 local = fract(p * 6.0);
		if (distance(local, vec2(0.5)) < 0.32) {
			g = petal;
		}
	}
	// forest floor shade
	g = mix(g, mix(grass_dark, grass_cool, 0.4) * 0.82, masks.b * 0.65);
	// trampled camp grass
	g = mix(g, mix(g, grass_warm, 0.5) * 0.95, masks.a * 0.5 * stylized);

	// --- dirt path with irregular edges
	float edge_noise = ((n_mid - 0.5) * 0.55 + (n_small - 0.5) * 0.35 + (n_tiny - 0.5) * 0.12) * mix(0.0, 1.0, stylized);
	float pm = masks.r + edge_noise;
	float path = step(0.5, pm);
	vec3 d = mix(dirt_mid, dirt_light, smoothstep(0.45, 0.72, n_small));
	d = mix(d, dirt_dark, smoothstep(0.42, 0.25, n_tiny) * 0.45);
	d = mix(d, dirt_light, smoothstep(0.85, 1.05, pm) * 0.35);  // worn, lighter centre
	float ph = hash12(floor(p * 8.0) + 3.0);
	d = mix(d, pebble, step(0.94, ph) * stylized);
	d = mix(d, dirt_dark * 0.8, step(ph, 0.04) * stylized);
	float rim = path * (1.0 - step(0.58, pm));
	d = mix(d, dirt_dark * 0.9, rim * 0.7 * stylized);
	// grass edge just outside the path is a bit lighter / drier
	float halo = (1.0 - path) * step(0.4, pm);
	g = mix(g, grass_warm, halo * 0.35 * stylized);

	// --- sandy shore
	float shore = step(0.5, masks.g + edge_noise * 0.7);
	vec3 s = mix(sand, sand * 0.9, step(0.5, n_small));
	s = mix(s, pebble * 0.95, step(0.95, hash12(floor(p * 10.0) + 9.0)) * stylized);

	vec3 col = mix(g, d, path);
	col = mix(col, s, shore * (1.0 - path));
	if (detail < 0.5) {
		// Flat cel (pixel-art reference): grass in three broad tones whose borders are dithered
		// texel by texel, a few light blades / dark gaps, forest floor a shade darker, the dirt
		// path with a darker rim and pebble specks, flat sand.
		vec2 scell = floor(SCREEN_UV * VIEWPORT_SIZE);  // render texels: the checker stays 1 texel
		vec3 fg = mix(grass_mid, grass_dark, dither_step(0.62, n_large, scell) * 0.55);
		fg = mix(fg, grass_light, dither_step(0.74, n_mid, scell) * 0.5);
		fg = mix(fg, grass_light * 1.06, step(0.985, h) * 0.5);
		fg = mix(fg, grass_dark * 0.82, step(h, 0.012) * 0.6);
		fg = mix(fg, grass_dark * 0.9, dither_step(0.5, masks.b, scell));
		vec3 fd = dirt_mid;
		fd = mix(fd, dirt_dark * 0.9, rim * 0.6);
		fd = mix(fd, pebble, step(0.978, ph) * 0.7);
		fd = mix(fd, dirt_dark * 0.85, step(ph, 0.012) * 0.7);
		vec3 flat_col = mix(fg, fd, path);
		flat_col = mix(flat_col, sand, shore * (1.0 - path));
		col = flat_col;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;  // 1.0 marks "no outline" for the pixel outline pass
}
