shader_type canvas_item;
// Final pass on the upscaled pixel image: warm/cool split toning, saturation, soft vignette,
// optional limited colour levels + 4x4 ordered dither (mode 3, toggle P). All per render texel.

uniform float grade_strength : hint_range(0.0, 1.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.05;
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.88, 1.04);
uniform vec3 highlight_tint : source_color = vec3(1.02, 0.98, 0.92);
uniform float vignette : hint_range(0.0, 1.0) = 0.22;
uniform bool dither_enabled = false;
uniform float levels : hint_range(2.0, 32.0, 1.0) = 10.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.35;
// Screen pixels per render texel when the texture is already upscaled (SCALING_3D pipeline).
uniform float block_size = 1.0;

float bayer4(ivec2 p) {
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[(p.y & 3) * 4 + (p.x & 3)]) + 0.5) / 16.0;
}

void fragment() {
	vec2 tex_px = UV / TEXTURE_PIXEL_SIZE;
	ivec2 cell = ivec2(floor(tex_px / block_size));
	vec2 sample_uv = (vec2(cell) + 0.5) * block_size * TEXTURE_PIXEL_SIZE;
	vec3 c = texture(TEXTURE, sample_uv).rgb;

	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 graded = mix(vec3(l), c, saturation);
	graded *= mix(shadow_tint, highlight_tint, smoothstep(0.15, 0.75, l));
	vec2 v = UV - 0.5;
	graded *= 1.0 - vignette * smoothstep(0.25, 0.75, dot(v, v) * 2.2);
	c = mix(c, graded, grade_strength);

	if (dither_enabled) {
		float t = (bayer4(cell) - 0.5) * dither_strength;
		c = floor(c * (levels - 1.0) + 0.5 + t) / (levels - 1.0);
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
