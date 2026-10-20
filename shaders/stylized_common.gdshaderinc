// Shared helpers for the stylized "diorama pixel" materials.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// 4x4 ordered dither threshold (0..1) for screen-door fading.
float bayer4(vec2 frag) {
	ivec2 p = ivec2(frag) & ivec2(3);
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[p.y * 4 + p.x]) + 0.5) / 16.0;
}
