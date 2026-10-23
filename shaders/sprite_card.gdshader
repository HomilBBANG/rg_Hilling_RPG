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
// Written as the roughness tag the screen-space outline pass skips (>= 0.97, like terrain):
// a sprite already carries its own border outline (sprite_outline below), and the post pass
// used to darken depth steps *inside* the sprite too - the sword hand held in front of the body
// became a stray dark dot in the middle of the hero when walking sideways. Specular is off, so
// the value changes nothing else.
uniform float roughness_value = 1.0;
uniform float light_offset = 0.04;
// Lighting point is also pulled toward the camera (which faces the sun side) so the sprite's
// own shadow-only 3D model doesn't shade small protruding parts (moustache top looked blue).
uniform float self_shadow_escape = 0.35;
// Classic pixel-sprite outline: the sprite's own border texels are drawn in a dark colour.
uniform bool sprite_outline = true;
uniform vec3 outline_color : source_color = vec3(0.13, 0.08, 0.12);
// Pixel-art inner lines (per sprite): darken texels at baked creases (normal change) and on
// the near side of depth steps inside the sprite (awning over body, windows, wheels).
uniform bool inner_lines = false;
uniform float crease_threshold = 0.93;
uniform float depth_step = 0.18;
uniform float line_darkness : hint_range(0.0, 1.0) = 0.42;
// Hit reaction flash (P1): rgb = colour, a = strength. 0 = no change.
uniform vec4 flash_color = vec4(1.0, 1.0, 1.0, 0.0);

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
			// a deeper shade of the texel's own colour, lightly tinted (no black outlines)
			vec3 deep = a.rgb * 0.5;
			deep = mix(deep, deep * vec3(0.85, 0.9, 1.12), 0.5);
			ALBEDO = mix(deep, outline_color, 0.22);
		}
	}
	if (inner_lines && !border) {
		vec2 px = 1.0 / vec2(textureSize(albedo_tex, 0));
		vec3 n0 = texture(normal_tex, uv).xyz * 2.0 - 1.0;
		float d0 = texture(depth_tex, uv).r;
		bool line = false;
		bool shine = false;
		// creases: compare with right and lower neighbours only -> single-pixel lines
		for (int i = 0; i < 2; i++) {
			vec2 o = i == 0 ? vec2(px.x, 0.0) : vec2(0.0, px.y);
			if (texture(albedo_tex, uv + o).a > 0.5) {
				vec3 n1 = texture(normal_tex, uv + o).xyz * 2.0 - 1.0;
				if (dot(normalize(n0), normalize(n1)) < crease_threshold) {
					// top edges (this texel faces up more than its neighbour) get a light
					// highlight pixel, other creases a dark line - classic pixel-art edges
					if (n0.y > n1.y + 0.25) {
						shine = true;
					} else {
						line = true;
					}
				}
			}
		}
		// the texel just below a top edge gets the dark line (highlight above, line below)
		vec2 up = vec2(0.0, -px.y);
		if (!line && texture(albedo_tex, uv + up).a > 0.5) {
			vec3 nu = texture(normal_tex, uv + up).xyz * 2.0 - 1.0;
			if (dot(normalize(n0), normalize(nu)) < crease_threshold && nu.y > n0.y + 0.25) {
				line = true;
				shine = false;
			}
		}
		// depth steps: mark the nearer texel
		vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
		for (int i = 0; i < 4; i++) {
			if (texture(albedo_tex, uv + offs[i]).a > 0.5 && texture(depth_tex, uv + offs[i]).r < d0 - depth_step) {
				line = true;
			}
		}
		if (line) {
			ALBEDO = mix(ALBEDO * (1.0 - line_darkness), outline_color, 0.25);
		} else if (shine) {
			ALBEDO = mix(ALBEDO, vec3(1.0, 0.98, 0.9), 0.45);
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
	if (flash_color.a > 0.0) {
		ALBEDO = mix(ALBEDO, flash_color.rgb, flash_color.a);
		EMISSION += flash_color.rgb * flash_color.a * 0.8;
	}
	ROUGHNESS = roughness_value;
}

// Hard cel lighting without wrap: lights behind a surface contribute nothing (the default toon
// wrap leaked light through thin parts such as the awning). Same 1/PI scale as Godot's BRDF.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit;
	if (LIGHT_IS_DIRECTIONAL) {
		lit = smoothstep(0.0, 0.06, ndl);  // sun/moon: hard two-tone cel edge
	} else {
		// Local lights (campfire, porch, headlights) wrap around the small sprite: two of
		// them from opposite sides left an unlit violet band across the head at night.
		// Wrapped and kept smooth: stepped levels from two overlapping lights drew stripes.
		float w = clamp((ndl + 0.7) / 1.7, 0.0, 1.0);
		lit = 0.35 + 0.65 * w;
	}
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
