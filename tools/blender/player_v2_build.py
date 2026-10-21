"""Player character v2 - static model blockout (Blender 4.2+ / bpy 5.x).

Builds the protagonist as separate, simply shaded parts, then writes:
  <out>/player_v2.blend            Blender source
  <glb> (default <out>/player_v2.glb)  for Godot (Y-up; the model faces +Z after import)
  <out>/renders/*.png              front / side / 3-4 / game camera renders
  <out>/renders/silhouette_sheet.png  flat black silhouettes of the same four views

Run (Blender installed):   blender -b -P tools/blender/player_v2_build.py -- art_src/player_v2 assets/characters/player_v2/player_v2.glb
Run (bpy from PyPI):       python tools/blender/player_v2_build.py art_src/player_v2 assets/characters/player_v2/player_v2.glb
(the optional second argument is where the .glb goes; default <out>/player_v2.glb)

Design brief: Healing_RPG_Player_Character_Blender_Brief_v1 - bald, big bushy moustache (no beard),
chubby middle-aged man, white tank top, open red plaid shirt, cargo pants, work boots; 2.4-2.8 heads
tall SD proportions; shape first, flat base colours, no metal / skin noise. Static model only.
Blender axes: Z up, the character faces -Y. 1 unit = 1 m, total height about 1.72 m
(the same size as the current in-game model so the scene scale doesn't change).
"""

import math
import os
import sys

import bpy
from mathutils import Euler, Vector

# ---------------------------------------------------------------- proportions (metres)
TOTAL_H = 1.72
HEAD_C = Vector((0.0, 0.0, 1.385))
HEAD_R = Vector((0.35, 0.33, 0.335))   # wide and round, not an egg
BODY_C = Vector((0.0, 0.0, 0.74))
BODY_R = Vector((0.335, 0.295, 0.335))
BELLY_C = Vector((0.0, -0.1, 0.7))
BELLY_R = Vector((0.29, 0.27, 0.33))
BELLY_TAPER = 0.3   # the top narrows into the tank top's neckline
HIP_Z = 0.42

# sRGB colours (converted to linear for Blender)
COLORS = {
    "skin": "f2b48c", "skin_nose": "eb9a7c", "blush": "f28a86", "ear_in": "d98a72",
    "hair": "5c3622",       # moustache + brows
    "eye": "2a1a14", "mouth": "9c3a34", "tongue": "e0776b",
    "tank": "f4f1ea",
    "plaid_red": "d63a2e", "plaid_mid": "b0302c", "plaid_dark": "7c2224", "shirt_edge": "8e1e22",
    "pants": "7c8146", "pants_dark": "656a38",
    "belt": "5a3820", "buckle": "cfc8b4",
    "boot": "8c5530", "boot_dark": "4a2e1c", "lace": "d8c49a",
}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(hexstr):
    return tuple(srgb_to_linear(int(hexstr[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)


# ---------------------------------------------------------------- scene helpers

MATS = {}


def material(name, rough=0.8):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba(COLORS[name])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.0
    m.diffuse_color = rgba(COLORS[name])
    MATS[name] = m
    return m


def plaid_material():
    """Buffalo plaid: big 3-tone checks (survive pixelation). Nearest filtering."""
    if "plaid" in MATS:
        return MATS["plaid"]
    n = 8
    img = bpy.data.images.new("plaid", n, n, alpha=False)
    red, mid, dark = rgba(COLORS["plaid_red"]), rgba(COLORS["plaid_mid"]), rgba(COLORS["plaid_dark"])
    px = []
    for y in range(n):
        for x in range(n):
            a, b = x < n // 2, y < n // 2
            px.extend(dark if a and b else (mid if a or b else red))
    img.pixels = px
    img.pack()
    m = bpy.data.materials.new("plaid")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    m.diffuse_color = rgba(COLORS["plaid_red"])
    MATS["plaid"] = m
    return m


ROOT = None


def finish(obj, name, mat, smooth=True, uv_scale=None):
    obj.name = name
    obj.data.name = name
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    if uv_scale and obj.data.uv_layers:
        for d in obj.data.uv_layers.active.data:
            d.uv = (d.uv[0] * uv_scale[0], d.uv[1] * uv_scale[1])
    obj.parent = ROOT
    return obj


def apply_xform(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def blob(name, center, radii, mat, rot=(0, 0, 0), segs=32, rings=16, uv_scale=None, taper=0.0):
    """Ellipsoid: the basic clay lump everything is made of. taper > 0 narrows the upper half
    (pear / egg shape) smoothly, without a seam."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=1.0, location=center)
    obj = bpy.context.active_object
    obj.scale = radii
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    apply_xform(obj)
    if taper > 0.0:
        for v in obj.data.vertices:
            t = max(0.0, v.co.z / radii[2])
            v.co.x *= 1.0 - taper * t * t
            v.co.y *= 1.0 - taper * 0.5 * t * t
    return finish(obj, name, mat, uv_scale=uv_scale)


def belly_band(name, side, mat, lo=0.72, hi=2.0, grow=1.03, uv_scale=None):
    """Open-shirt front edge: a strip cut (clean planar cuts) from a slightly larger copy of the
    tank-top belly, so it lies exactly on the belly's curve from the opening (|x| >= lo on the unit
    sphere) round to where the belly disappears into the shirt."""
    import bmesh
    bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=1.0, location=(0, 0, 0))
    obj = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for co, no in (((side * lo, 0, 0), (side, 0, 0)), ((side * hi, 0, 0), (-side, 0, 0)), ((0, -0.05, 0), (0, -1, 0)),
                   ((0, 0, 0.97), (0, 0, -1)), ((0, 0, -0.8), (0, 0, 1))):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_inner=True)
    bm.to_mesh(obj.data)
    bm.free()
    r = BELLY_R * grow
    for v in obj.data.vertices:
        c = Vector((v.co.x * r.x, v.co.y * r.y, v.co.z * r.z))
        t = max(0.0, c.z / r.z)
        c.x *= 1.0 - BELLY_TAPER * t * t
        c.y *= 1.0 - BELLY_TAPER * 0.5 * t * t
        v.co = c
    obj.location = BELLY_C
    mod = obj.modifiers.new("thick", "SOLIDIFY")
    mod.thickness = 0.012
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, mat, uv_scale=uv_scale)


def ring(name, center, major, minor, mat, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=40,
                                     minor_segments=12, location=center)
    obj = bpy.context.active_object
    obj.scale = scale
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    apply_xform(obj)
    return finish(obj, name, mat)


def rounded_box(name, center, size, mat, rot=(0, 0, 0), bevel=0.02):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.active_object
    obj.scale = size
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    apply_xform(obj)
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = bevel
    mod.segments = 3
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, mat)


def head_surface(az_deg, el_deg, lift=0.0):
    """Point / normal on the head ellipsoid. az 0 = straight forward (-Y), + = character's left
    side seen from the front (screen right), el + = up."""
    az, el = math.radians(az_deg), math.radians(el_deg)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    p = HEAD_C + Vector((d.x * HEAD_R.x, d.y * HEAD_R.y, d.z * HEAD_R.z))
    n = Vector((d.x / HEAD_R.x, d.y / HEAD_R.y, d.z / HEAD_R.z)).normalized()
    return p + n * lift, n


def face_blob(name, az, el, radii, mat, lift=0.0, sink=0.0, roll=0.0, segs=24, rings=12):
    """Flattened lump lying on the face: local X = across, Y = depth (along the normal), Z = up."""
    p, n = head_surface(az, el, lift)
    p = p - n * sink
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=1.0, location=p)
    obj = bpy.context.active_object
    obj.scale = radii
    q = (-n).to_track_quat("Y", "Z")
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = q @ Euler((0, math.radians(roll), 0)).to_quaternion()
    apply_xform(obj)
    return finish(obj, name, mat)


# ---------------------------------------------------------------- the character

def build():
    global ROOT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ROOT = bpy.data.objects.new("PlayerV2", None)
    bpy.context.scene.collection.objects.link(ROOT)

    skin, nose_m, blush, ear_in = material("skin"), material("skin_nose"), material("blush"), material("ear_in")
    hair, eye, mouth, tongue = material("hair", 0.9), material("eye", 0.4), material("mouth"), material("tongue")
    tank, plaid, edge = material("tank"), plaid_material(), material("shirt_edge")
    pants, pants_dark = material("pants"), material("pants_dark")
    belt, buckle = material("belt"), material("buckle", 0.5)
    boot, boot_dark, lace = material("boot"), material("boot_dark"), material("lace")

    # --- boots: big, round, toes forward
    for s, side in ((-1, "R"), (1, "L")):
        x = 0.155 * s
        blob(f"Boot.{side}", (x, -0.05, 0.095), (0.125, 0.175, 0.095), boot)
        blob(f"BootSole.{side}", (x, -0.05, 0.03), (0.122, 0.172, 0.035), boot_dark)
        ring(f"BootCuff.{side}", (x, -0.01, 0.165), 0.085, 0.03, boot_dark)
        rounded_box(f"BootLace.{side}", (x, -0.17, 0.135), (0.07, 0.03, 0.05), lace, rot=(-35, 0, 0), bevel=0.012)

    # --- cargo pants: short thick legs + hip, side pockets
    blob("Pants.Hip", (0, 0.0, HIP_Z), (0.305, 0.27, 0.14), pants)
    for s, side in ((-1, "R"), (1, "L")):
        x = 0.155 * s
        blob(f"Pants.Leg.{side}", (x, 0.0, 0.28), (0.13, 0.135, 0.15), pants)
        rounded_box(f"Pants.Pocket.{side}", (0.27 * s, 0.0, 0.3), (0.05, 0.13, 0.12), pants_dark, bevel=0.025)
        rounded_box(f"Pants.Flap.{side}", (0.285 * s, 0.0, 0.365), (0.035, 0.14, 0.035), pants_dark, bevel=0.012)

    # --- belt peeks out at the sides / back under the belly
    ring("Belt", (0, 0.0, 0.47), 0.29, 0.035, belt, scale=(1.0, 0.92, 1.0))
    rounded_box("Belt.Buckle", (0, -0.31, 0.47), (0.09, 0.03, 0.06), buckle, bevel=0.01)

    # --- torso: round body in the open red plaid shirt, white tank top over the round belly
    blob("Shirt.Body", BODY_C, BODY_R, plaid, uv_scale=(3.0, 2.0))
    # one smooth piece from the neckline down over the round belly
    blob("TankTop", BELLY_C, BELLY_R, tank, taper=BELLY_TAPER)
    for s, side in ((-1, "R"), (1, "L")):
        # open shirt: flat front edges lying on the body along the tank top, and the collar points
        belly_band(f"Shirt.Front.{side}", s, plaid, lo=0.74, uv_scale=(3.0, 2.0))
        belly_band(f"Shirt.Edge.{side}", s, edge, lo=0.71, hi=0.77, grow=1.036)
        blob(f"Shirt.Collar.{side}", (0.16 * s, -0.16, 1.01), (0.1, 0.06, 0.04), edge, rot=(24, 0, -28 * s))

    # --- arms: round shoulders, short thick arms, sleeves rolled to the elbow, simple mitten hands
    for s, side in ((-1, "R"), (1, "L")):
        blob(f"Shirt.Shoulder.{side}", (0.33 * s, 0.0, 0.92), (0.135, 0.135, 0.13), plaid, uv_scale=(2.0, 1.5))
        blob(f"Shirt.Sleeve.{side}", (0.405 * s, 0.0, 0.8), (0.115, 0.115, 0.14), plaid, rot=(0, -16 * s, 0), uv_scale=(2.0, 1.5))
        ring(f"Shirt.Cuff.{side}", (0.44 * s, -0.005, 0.69), 0.085, 0.035, edge, rot=(0, -16 * s, 0))
        blob(f"Arm.{side}", (0.46 * s, -0.01, 0.6), (0.085, 0.085, 0.11), skin, rot=(0, -12 * s, 0))
        blob(f"Hand.{side}", (0.475 * s, -0.02, 0.48), (0.09, 0.085, 0.095), skin)

    # --- head: big round bald head, no hair at all
    blob("Head", HEAD_C, HEAD_R, skin, segs=40, rings=20)
    for s, side in ((-1, "R"), (1, "L")):
        p, n = head_surface(88 * s, -2)
        blob(f"Ear.{side}", p + Vector((0.01 * s, 0.02, 0)), (0.05, 0.075, 0.09), skin)
        blob(f"Ear.Inner.{side}", p + Vector((0.035 * s, 0.015, 0)), (0.025, 0.045, 0.055), ear_in)
        # soft cheeks: a little extra volume low on the face (볼살) with a pink blush on top
        face_blob(f"Cheek.{side}", 36 * s, -14, (0.105, 0.07, 0.085), skin, sink=0.035)
        face_blob(f"Blush.{side}", 38 * s, -9, (0.06, 0.012, 0.035), blush, lift=0.022)

    # --- face: small smiling eyes, thick soft brows, big round nose, moustache in 4 round lumps
    for s, side in ((-1, "R"), (1, "L")):
        # smiling eyes (^ ^): a dark oval whose lower half is covered by a skin-coloured lid
        face_blob(f"Eye.{side}", 21 * s, 4, (0.046, 0.012, 0.038), eye, lift=0.002)
        face_blob(f"Eye.Lid.{side}", 21 * s, -0.5, (0.058, 0.012, 0.032), skin, lift=0.005)
        face_blob(f"Brow.{side}", 23 * s, 19, (0.075, 0.03, 0.028), hair, lift=0.008, roll=10 * s)
        # moustache: two big lobes under the nose + two smaller curled tips, clear of eyes and nose
        face_blob(f"Moustache.Lobe.{side}", 14 * s, -19, (0.135, 0.095, 0.078), hair, lift=0.035, roll=14 * s)
        face_blob(f"Moustache.Tip.{side}", 33 * s, -24, (0.08, 0.072, 0.056), hair, lift=0.022, roll=35 * s)
    face_blob("Nose", 0, -5, (0.08, 0.085, 0.075), nose_m, lift=0.045)
    face_blob("Mouth", 0, -35, (0.06, 0.015, 0.028), mouth, lift=0.0)
    face_blob("Mouth.Tongue", 0, -37, (0.03, 0.012, 0.012), tongue, lift=0.004)


# ---------------------------------------------------------------- rendering

def setup_render(res):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.resolution_x = res[0]
    sc.render.resolution_y = res[1]
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.66, 0.72, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    # soft key from the upper front-left + rim from behind (like the game's sun)
    for name, rot, energy in (("Key", (50, 0, -35), 3.2), ("Rim", (60, 0, 160), 1.6)):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.angle = math.radians(12)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = Euler([math.radians(a) for a in rot])
        sc.collection.objects.link(lo)


def add_camera(name, pitch_deg, yaw_deg, ortho, target_z):
    """Orthographic camera looking at the character. yaw 0 = from the front (-Y)."""
    cd = bpy.data.cameras.new(name)
    cd.type = "ORTHO"
    cd.ortho_scale = ortho
    co = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(co)
    pitch, yaw = math.radians(pitch_deg), math.radians(yaw_deg)
    d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    co.location = Vector((0, 0, target_z)) + d * 10.0
    co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    return co


VIEWS = [
    # name, pitch, yaw, ortho scale
    ("front", 0, 0, 2.15),
    ("side", 0, 90, 2.15),
    ("three_quarter", 12, 35, 2.15),
    # GDD camera style D: fixed 40 degree pitch, no rotation; the character turned 3/4 towards it
    ("game_camera", 40, 30, 2.3),
]


def render_views(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    paths = []
    for name, pitch, yaw, ortho in VIEWS:
        sc.camera = add_camera("Cam." + name, pitch, yaw, ortho, TOTAL_H * 0.5)
        sc.render.filepath = os.path.join(out_dir, f"player_v2_{name}.png")
        bpy.ops.render.render(write_still=True)
        paths.append(sc.render.filepath)
    return paths


def render_silhouettes(out_dir):
    """Same views, every part flat black on white - the shape test of the brief (step 02)."""
    sc = bpy.context.scene
    black = bpy.data.materials.new("silhouette")
    black.use_nodes = True
    nt = black.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0, 0, 0, 1)
    outn = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], outn.inputs[0])
    bpy.context.view_layer.material_override = black
    sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.cycles.samples = 8
    paths = []
    for name, _pitch, _yaw, _ortho in VIEWS:
        sc.camera = bpy.data.objects["Cam." + name]
        sc.render.filepath = os.path.join(out_dir, f"silhouette_{name}.png")
        bpy.ops.render.render(write_still=True)
        paths.append(sc.render.filepath)
    bpy.context.view_layer.material_override = None
    try:
        from PIL import Image, ImageDraw
        tiles = [Image.open(p).convert("RGB") for p in paths]
        w, h = tiles[0].size
        sheet = Image.new("RGB", (w * len(tiles), h + 40), "white")
        draw = ImageDraw.Draw(sheet)
        try:
            from PIL import ImageFont
            font = ImageFont.load_default(size=28)
        except (ImportError, TypeError):
            font = None
        for i, t in enumerate(tiles):
            sheet.paste(t, (i * w, 40))
            draw.text((i * w + 12, 6), VIEWS[i][0], fill="black", font=font)
        sheet.save(os.path.join(out_dir, "silhouette_sheet.png"))
        for p in paths:
            os.remove(p)
    except ImportError:
        print("Pillow not available: silhouettes left as separate images")


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out = os.path.abspath(args[0] if args else "art_src/player_v2")
    glb = os.path.abspath(args[1]) if len(args) > 1 else os.path.join(out, "player_v2.glb")
    os.makedirs(out, exist_ok=True)
    os.makedirs(os.path.dirname(glb), exist_ok=True)
    build()
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB",
                              export_yup=True, export_apply=True, export_cameras=False, export_lights=False)
    setup_render((900, 1000))
    render_views(os.path.join(out, "renders"))
    render_silhouettes(os.path.join(out, "renders"))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "player_v2.blend"), compress=True)
    parts = [o.name for o in bpy.data.objects if o.parent and o.parent.name == "PlayerV2"]
    zs = [(o.matrix_world @ v.co).z for o in bpy.data.objects if o.type == "MESH" for v in o.data.vertices]
    lo, hi = min(zs), max(zs)
    print(f"[player_v2] {len(parts)} parts, height {hi - lo:.3f} m (z {lo:.3f}..{hi:.3f}), written to {out}")


main()
