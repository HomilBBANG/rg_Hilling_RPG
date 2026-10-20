shader_type spatial;
// Pixel-art outline pass for the low-res 3D render (Forward+ only).
// Drawn as a full-screen quad parented to the camera:
//  - depth edge  -> the nearer object's border texel is darkened (coloured outline)
//  - normal edge -> convex creases get a light highlight texel
// Surfaces with roughness >= 0.97 (terrain, grass) never receive an outline themselves;
// crease highlights only go on hard props (roughness < 0.8), not on foliage/rocks.
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform float depth_threshold = 0.28;
uniform float outline_darkness : hint_range(0.0, 1.0) = 0.42;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.28;
uniform float normal_threshold = 0.5;
uniform vec3 normal_edge_bias = vec3(1.0, 1.0, 1.0);
// Rim light on silhouette texels whose normal faces `rim_dir` (view space); others get the dark outline.
uniform bool rim_enabled = false;
uniform vec3 rim_dir = vec3(0.75, 0.55, 0.0);
uniform vec3 rim_color : source_color = vec3(1.0, 0.82, 0.62);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.65;
uniform vec3 outline_tint : source_color = vec3(0.08, 0.04, 0.12);
uniform float outline_tint_amount : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec4 normal_rough(vec2 uv) {
	vec4 nr = texture(normal_tex, uv);
	// Godot 4.7 (verified empirically): alpha holds roughness directly.
	return vec4(normalize(nr.xyz * 2.0 - 1.0), nr.w);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	vec4 c_nr = normal_rough(uv);
	if (c_nr.w >= 0.97) {
		discard;
	}
	float c_d = lin_depth(uv, INV_PROJECTION_MATRIX);
	vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
	float depth_edge = 0.0;
	float normal_edge = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 nuv = uv + offs[i];
		float nd = lin_depth(nuv, INV_PROJECTION_MATRIX);
		depth_edge += clamp(nd - c_d, 0.0, 1.0);
		vec3 nn = normal_rough(nuv).xyz;
		vec3 diff = c_nr.xyz - nn;
		float along = dot(diff, normalize(normal_edge_bias));
		float same_surface = 1.0 - smoothstep(0.05, 0.2, abs(nd - c_d));
		normal_edge += max(0.0, along) * same_surface * step(normal_threshold, length(diff));
	}
	vec3 base = texture(screen_tex, uv).rgb;
	if (depth_edge > depth_threshold) {
		if (rim_enabled && dot(c_nr.xyz, normalize(rim_dir)) > 0.25) {
			ALBEDO = mix(base, max(base, rim_color), rim_strength);
		} else {
			vec3 dark = base * (1.0 - outline_darkness);
			dark = mix(dark, dark * vec3(0.85, 0.8, 1.0), 0.5);
			ALBEDO = mix(dark, outline_tint, outline_tint_amount);
		}
	} else if (normal_edge > 0.2 && c_nr.w < 0.8) {
		ALBEDO = base + (vec3(1.0, 0.97, 0.88) - base) * highlight_strength;
	} else {
		discard;
	}
}
