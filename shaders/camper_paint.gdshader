shader_type spatial;
// Two-tone camper livery painted in local space: cream body, teal skirt, coral + mustard
// stripes, alcove swoosh, wheel arches, panel seams, light roof.
render_mode specular_disabled;

#include "res://shaders/cel_light.gdshaderinc"

uniform vec3 body : source_color = vec3(0.96, 0.93, 0.85);
uniform vec3 skirt : source_color = vec3(0.32, 0.6, 0.58);
uniform vec3 stripe_a : source_color = vec3(0.95, 0.52, 0.4);
uniform vec3 stripe_b : source_color = vec3(0.97, 0.79, 0.36);
uniform vec3 roof : source_color = vec3(0.86, 0.85, 0.8);
uniform vec3 arch : source_color = vec3(0.2, 0.2, 0.23);
uniform vec2 wheel_a = vec2(2.5, 0.42);
uniform vec2 wheel_b = vec2(-2.0, 0.42);
uniform float stylized = 1.0;
uniform float detail = 1.0;

varying vec3 lpos;
varying vec3 lnormal;

void vertex() {
	lpos = VERTEX;
	lnormal = NORMAL;
}

void fragment() {
	vec3 col = body;
	float side = step(0.5, abs(lnormal.z));
	float y = lpos.y;
	col = mix(col, skirt, step(y, 1.02));
	col = mix(col, stripe_a, step(1.08, y) * step(y, 1.17));
	col = mix(col, stripe_b, step(1.21, y) * step(y, 1.25) * stylized * detail);
	// alcove swoosh on the sides
	float swoosh = side * step(1.3, lpos.x) * step(2.42 + (lpos.x - 1.3) * 0.08, y) * step(y, 2.58 + (lpos.x - 1.3) * 0.08);
	col = mix(col, skirt, swoosh);
	// panel seams (sides)
	float seam = side * (1.0 - step(0.025, abs(lpos.x + 1.6))) + side * (1.0 - step(0.025, abs(lpos.x - 1.9)));
	col = mix(col, col * 0.84, seam * step(1.25, y) * stylized * detail);
	// roof + underside
	col = mix(col, roof, step(0.75, lnormal.y));
	col = mix(col, arch, step(lnormal.y, -0.6));
	// wheel arches
	float arch_mask = side * (step(distance(lpos.xy, wheel_a), 0.6) + step(distance(lpos.xy, wheel_b), 0.6));
	col = mix(col, arch, clamp(arch_mask, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.45;
}
