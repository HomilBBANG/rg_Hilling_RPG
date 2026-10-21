// Map-wide wind shared by grass, bushes and tree canopies. scripts/world/wind.gd mirrors it for
// scripted things (flame, smoke, embers, laundry, flags, leaves) so everything follows one gust.
// Gust waves roll across the map along one direction, so neighbouring plants lean together
// (a wave passing over the field) instead of each one flickering on its own: independent fast
// sway of 1-texel blades read as ground sparkle once pixelated. Frequencies stay under ~0.3 Hz.

uniform float wind_scale = 1.0;  // global on/off (StylizedMaterials.set_wind)

const vec2 WIND_DIR = vec2(0.94, 0.34);

// Horizontal offset (metres per unit strength) for a point at world position p. Range ~0..1.3.
vec2 wind_offset(vec3 p, float t) {
	float along = dot(p.xz, WIND_DIR);
	float wave = sin(along * 0.16 - t * 1.05);              // gust front travelling downwind
	float gust = 0.55 + 0.45 * wave * (0.55 + 0.45 * sin(along * 0.05 - t * 0.27));
	float flutter = 0.2 * sin(t * 1.5 + p.x * 0.6 + p.z * 0.45);  // small local variation
	return WIND_DIR * (gust + flutter) * wind_scale;
}
