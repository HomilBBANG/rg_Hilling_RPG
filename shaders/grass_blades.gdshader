shader_type spatial;
// MultiMesh grass tufts and flowers. Lit like the ground (up normal) so they blend in,
// gentle shared wind sway (wind.gdshaderinc), roughness 1.0 so the outline pass ignores them.
render_mode specular_disabled, cull_disabled;

#include "res://shaders/cel_light.gdshaderinc"
#include "res://shaders/wind.gdshaderinc"

uniform vec3 root_color : source_color = vec3(0.34, 0.56, 0.26);
uniform vec3 tip_color : source_color = vec3(0.58, 0.76, 0.33);
uniform float wind_strength = 0.045;  // tip offset in metres (~1.5 texels at the default zoom)
uniform bool is_flower = false;
uniform float detail = 1.0;
// Flat look: tufts in one colour just a bit darker than the grass ground.
uniform vec3 line_color : source_color = vec3(0.33, 0.53, 0.23);  // ~12% darker than the grass ground

varying float tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// Only the tips move; the whole tuft leans with the passing gust (instance transform is
	// rotated, so convert the world offset into the tuft's local space).
	vec2 w = wind_offset(world, TIME) * wind_strength * UV.y;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * vec3(w.x, 0.0, w.y));
	NORMAL = vec3(0.0, 1.0, 0.0);
	tint = UV.y;
}

void fragment() {
	// Blades are double-sided; keep the up normal on back faces too (otherwise they go dark).
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 col;
	if (is_flower) {
		// UV.x > 1.5 marks petals, UV.x in (0.5,1.5) marks the centre, else stem.
		col = UV.x > 1.5 ? COLOR.rgb : (UV.x > 0.5 ? vec3(0.98, 0.85, 0.3) : root_color);
	} else {
		col = mix(root_color, tip_color, smoothstep(0.0, 1.0, tint)) * COLOR.rgb;
		if (detail < 0.5) {
			col = line_color;
		}
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
