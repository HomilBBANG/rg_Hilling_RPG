shader_type spatial;
// MultiMesh grass tufts and flowers. Lit like the ground (up normal) so they blend in,
// gentle wind sway, roughness 1.0 so the outline pass ignores them.
render_mode diffuse_toon, specular_disabled, cull_disabled;

uniform vec3 root_color : source_color = vec3(0.34, 0.56, 0.26);
uniform vec3 tip_color : source_color = vec3(0.58, 0.76, 0.33);
uniform float wind_strength = 0.05;
uniform bool is_flower = false;

varying float tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + world.x * 0.45 + world.z * 0.32) + 0.4 * sin(TIME * 2.9 + world.z);
	VERTEX.x += sway * wind_strength * UV.y;
	VERTEX.z += sway * wind_strength * 0.5 * UV.y;
	NORMAL = vec3(0.0, 1.0, 0.0);
	tint = UV.y;
}

void fragment() {
	vec3 col;
	if (is_flower) {
		// UV.x > 1.5 marks petals, UV.x in (0.5,1.5) marks the centre, else stem.
		col = UV.x > 1.5 ? COLOR.rgb : (UV.x > 0.5 ? vec3(0.98, 0.85, 0.3) : root_color);
	} else {
		col = mix(root_color, tip_color, smoothstep(0.0, 1.0, tint)) * COLOR.rgb;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
