shader_type spatial;
// "X-ray" silhouette pass: drawn only where the character is hidden behind OTHER geometry.
// The pass is pulled towards the camera by `self_bias` metres so the character's own
// limbs/backpack (closer than that) don't trigger it.
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.95, 0.8, 0.45);
uniform float self_bias = 0.8;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_pos.z += self_bias;
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
