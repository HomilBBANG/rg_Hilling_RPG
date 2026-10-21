// Gentle map-wide wind shared by grass, bushes and tree canopies.
// Slow gust waves roll across the map along one direction, so neighbouring plants lean together
// (a wave passing over the field) instead of each one flickering on its own: independent fast
// sway of 1-texel blades read as ground sparkle once pixelated. Frequencies stay well under 1 Hz.

uniform float wind_scale = 1.0;  // global on/off (StylizedMaterials.set_wind)

const vec2 WIND_DIR = vec2(0.94, 0.34);

// Horizontal offset (metres per unit strength) for a point at world position p.
vec2 wind_offset(vec3 p, float t) {
	float along = dot(p.xz, WIND_DIR);
	float wave = sin(along * 0.16 - t * 0.85);              // gust front travelling downwind
	float gust = 0.5 + 0.5 * wave * (0.6 + 0.4 * sin(along * 0.05 - t * 0.23));
	float flutter = 0.18 * sin(t * 1.1 + p.x * 0.6 + p.z * 0.45);  // small local variation
	return WIND_DIR * (gust + flutter) * wind_scale;
}
