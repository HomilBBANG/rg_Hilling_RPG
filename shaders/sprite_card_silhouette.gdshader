shader_type spatial;
// X-ray pass for baked sprites: only where something else is in front of the sprite.
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : filter_nearest, repeat_disable;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 color : source_color = vec4(1.0, 0.95, 0.8, 0.45);
uniform float self_bias = 0.8;

void fragment() {
	vec2 uv = frame_rect.xy + UV * frame_rect.zw;
	if (texture(albedo_tex, uv).a < 0.5) {
		discard;
	}
	float d = texture(depth_tex, uv).r + self_bias;
	vec4 clip = PROJECTION_MATRIX * vec4(VERTEX + vec3(0.0, 0.0, d), 1.0);
	DEPTH = clip.z / clip.w;
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
