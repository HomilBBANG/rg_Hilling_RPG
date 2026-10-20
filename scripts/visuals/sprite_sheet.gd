class_name SpriteSheet
extends RefCounted
## Result of a SpriteBaker run: atlas textures (cols x rows cells) + metadata.

var cols := 1
var rows := 1
var cell_px := Vector2i.ONE
## Size of one cell in world metres (= cell_px * texel).
var cell_m := Vector2.ONE
var texel := 0.04
var pitch := 40.0
## Pixel size of the game's render viewport the sheet was baked for (for pixel-grid alignment).
var screen_px := Vector2i(429, 242)
var albedo: Texture2D
var normal: Texture2D
var depth: Texture2D
## Emission maps by variant name (e.g. "default", "lights_on").
var emission := {}
## Raw images, kept for export/inspection.
var images := {}


func frame_rect(col: int, row: int) -> Vector4:
	return Vector4(float(col) / cols, float(row) / rows, 1.0 / cols, 1.0 / rows)
