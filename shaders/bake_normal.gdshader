shader_type spatial;
// Bake pass: writes the view-space normal (raw floats, HDR viewport).
render_mode unshaded, fog_disabled, cull_back;

void fragment() {
	ALBEDO = NORMAL * 0.5 + 0.5;
}
