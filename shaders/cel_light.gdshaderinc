// Two-tone cel lighting (lit / shadow) with no wrap, as in Dead Cells-style flat shading.
// Shadow colour comes from the ambient light; direct light adds a hard lit band.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.05, ndl);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
