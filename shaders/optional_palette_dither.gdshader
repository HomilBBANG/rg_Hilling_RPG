shader_type canvas_item;
// Mode 3 (optional): limited colour levels + 4x4 ordered (Bayer) dither, applied per render texel.
// Toggle with P. Purely experimental post effect, not a decided art direction.

uniform float levels : hint_range(2.0, 16.0, 1.0) = 8.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.35;
// Screen pixels per render texel when the texture is already upscaled (SCALING_3D pipeline).
uniform float block_size = 1.0;
// Slight saturation boost so limited levels don't wash out.
uniform float saturation : hint_range(0.0, 2.0) = 1.1;

float bayer4(ivec2 p) {
	int x = p.x & 3;
	int y = p.y & 3;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

void fragment() {
	vec2 tex_px = UV / TEXTURE_PIXEL_SIZE;
	ivec2 cell = ivec2(floor(tex_px / block_size));
	// Sample at the centre of the block so the whole block shares one value.
	vec2 sample_uv = (vec2(cell) + 0.5) * block_size * TEXTURE_PIXEL_SIZE;
	vec3 c = texture(TEXTURE, sample_uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	float t = (bayer4(cell) - 0.5) * dither_strength;
	vec3 q = floor(c * (levels - 1.0) + 0.5 + t) / (levels - 1.0);
	COLOR = vec4(clamp(q, 0.0, 1.0), 1.0);
}
