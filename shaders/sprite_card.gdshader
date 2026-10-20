shader_type spatial;
// Pre-rendered pixel sprite drawn on a camera-facing card (Dead Cells-style pipeline):
// baked albedo + view-space normal give dynamic toon lighting (sun, lantern, campfire),
// baked depth is written so the sprite sorts/occludes like the 3D model it came from.
render_mode cull_disabled, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : filter_nearest, repeat_disable;
uniform sampler2D depth_tex : filter_nearest, repeat_disable;
uniform sampler2D emission_tex : filter_nearest, repeat_disable;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);  // uv offset (xy) and size (zw) in the atlas
uniform float emission_energy = 1.0;
uniform float roughness_value = 0.7;
uniform float light_offset = 0.04;
// Lighting point is also pulled toward the camera (which faces the sun side) so the sprite's
// own shadow-only 3D model doesn't shade small protruding parts (moustache top looked blue).
uniform float self_shadow_escape = 0.35;
// Classic pixel-sprite outline: the sprite's own border texels are drawn in a dark colour.
uniform bool sprite_outline = true;
uniform vec3 outline_color : source_color = vec3(0.13, 0.08, 0.12);

void fragment() {
	vec2 uv = frame_rect.xy + UV * frame_rect.zw;
	vec4 a = texture(albedo_tex, uv);
	if (a.a < 0.5) {
		discard;
	}
	ALBEDO = a.rgb;
	bool border = false;
	if (sprite_outline) {
		vec2 px = 1.0 / vec2(textureSize(albedo_tex, 0));
		border = texture(albedo_tex, uv + vec2(px.x, 0.0)).a < 0.5 || texture(albedo_tex, uv - vec2(px.x, 0.0)).a < 0.5
			|| texture(albedo_tex, uv + vec2(0.0, px.y)).a < 0.5 || texture(albedo_tex, uv - vec2(0.0, px.y)).a < 0.5;
		if (border) {
			ALBEDO = outline_color;
		}
	}
	NORMAL = normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
	float d = texture(depth_tex, uv).r;
	vec3 surface = VERTEX + vec3(0.0, 0.0, d);
	vec4 clip = PROJECTION_MATRIX * vec4(surface, 1.0);
	DEPTH = clip.z / clip.w;
	// Light and shadow are evaluated at the reconstructed surface, not on the flat card,
	// so the shadow-only 3D model doesn't darken its own sprite.
	// Small push along the normal: the reconstructed surface can sit a hair inside the
	// shadow-only mesh, which otherwise shows up as shadow-acne rings.
	LIGHT_VERTEX = surface + NORMAL * light_offset + vec3(0.0, 0.0, self_shadow_escape);
	EMISSION = border ? vec3(0.0) : texture(emission_tex, uv).rgb * emission_energy;
	ROUGHNESS = roughness_value;
}

// Hard cel lighting without wrap: lights behind a surface contribute nothing (the default toon
// wrap leaked light through thin parts such as the awning). Same 1/PI scale as Godot's BRDF.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.06, ndl);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
