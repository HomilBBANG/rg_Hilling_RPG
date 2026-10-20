shader_type spatial;
// Bake pass: writes view-space depth relative to the sprite's anchor plane (metres, HDR viewport).
// Positive = closer to the camera than the plane through the model origin.
render_mode unshaded, fog_disabled, cull_back;

uniform float anchor_view_z = -50.0;

void fragment() {
	ALBEDO = vec3(VERTEX.z - anchor_view_z, 0.0, 0.0);
}
