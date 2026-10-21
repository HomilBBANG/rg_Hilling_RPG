"""Player character v3 - static model following the user's character sheet (front / side / back).

Built from metaballs so the big masses flow into each other like clay (shoulders into sleeves,
sleeves around the arms, forearms into the fists, legs into the hips) instead of separate spheres
pushed together. Each colour region is one connected mesh:
  Skin (head + ears + jaw, arms + fists), Beard, Brows, Shirt (body + sleeves), Tee, Jeans, Boots
plus a few small pieces (nose, eyes, collar, rolled cuffs, shirt front panels, soles).

Writes into <out>:  player_v3.blend, player_v3.glb, renders/*.png (front, side, back, 3-4,
game camera) and renders/silhouette_sheet.png.

Run (Blender 4.2+):   blender -b -P tools/blender/player_v3_build.py -- art_src/player_v3
Run (bpy from PyPI):  python tools/blender/player_v3_build.py art_src/player_v3

Blender axes: Z up, the character faces -Y, 1 unit = 1 m, height 1.72 m.
Reference: bald head with big ears, thick flat brows, small dot eyes, big round orange nose,
full brown moustache + pointed beard, grey tee over a big round belly, open red buffalo plaid shirt
with rolled short sleeves and a collar, thick arms with big fists, navy jeans, tan round-toe boots.
"""

import math
import os
import sys

import bpy  # noqa: I001 - bpy must be imported before bmesh
import bmesh
from mathutils import Euler, Quaternion, Vector

COLORS = {
    "skin": "f2a47c", "ear_in": "e08a68", "nose": "d2693c", "hair": "5b3a22", "eye": "141010",
    "tee": "acacaa", "jeans": "2f3b7d", "boot": "c78a3a", "sole": "6e4423",
    "plaid_red": "c8352e", "plaid_mid": "8e2422", "plaid_dark": "5a1717",
}
PLAID_CYCLE = 0.09        # metres per check repeat (the sheet shows ~7 repeats across the body)
META_K = 0.5732           # metaball half-extent per unit radius at stiffness 2 / threshold 0.6


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(h):
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)


MATS = {}


def material(name, rough=0.85):
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = rgba(COLORS[name])
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = 0.0
        m.diffuse_color = rgba(COLORS[name])
        MATS[name] = m
    return MATS[name]


def plaid_material():
    if "plaid" not in MATS:
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
        b = nt.nodes["Principled BSDF"]
        b.inputs["Roughness"].default_value = 0.85
        b.inputs["Metallic"].default_value = 0.0
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.interpolation = "Closest"
        nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
        m.diffuse_color = rgba(COLORS["plaid_red"])
        MATS["plaid"] = m
    return MATS["plaid"]


ROOT = None


def finish(obj, name, mat, uv_box=False):
    obj.name = name
    obj.data.name = name
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    if uv_box:
        box_uv(obj)
    obj.parent = ROOT
    return obj


def front_uv(obj):
    """Projection from the front (panels lying on the belly)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for loop in f.loops:
            c = obj.matrix_world @ loop.vert.co
            loop[uv].uv = (c.x / PLAID_CYCLE, c.z / PLAID_CYCLE)
    bm.to_mesh(obj.data)
    bm.free()


def box_uv(obj):
    """Box mapping in world metres (axis-aligned plaid reads straight on front, sides and back)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.verify()
    mw = obj.matrix_world
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            c = mw @ loop.vert.co
            u, v = ((c.y, c.z), (c.x, c.z), (c.x, c.y))[ax]
            loop[uv].uv = (u / PLAID_CYCLE, v / PLAID_CYCLE)
    bm.to_mesh(obj.data)
    bm.free()


# ---------------------------------------------------------------- metaball masses

def meta(name, balls, resolution=0.014):
    """balls: (center, half_extents, rotation_euler_degrees). Returns one connected mesh."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = 0.6
    for b in balls:
        c, h = b[0], b[1]
        rot = b[2] if len(b) > 2 else (0, 0, 0)
        e = mb.elements.new(type="ELLIPSOID")
        e.co = c
        e.radius = 1.0 / META_K
        e.size_x, e.size_y, e.size_z = h
        e.stiffness = 2.0
        e.rotation = Euler([math.radians(a) for a in rot]).to_quaternion()
    obj = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return bpy.context.active_object


def mirror(balls):
    """Right-side balls -> both sides (x and the Y/Z rotations mirrored)."""
    out = []
    for b in balls:
        c, h = b[0], b[1]
        rot = b[2] if len(b) > 2 else (0, 0, 0)
        out.append((c, h, rot))
        out.append(((-c[0], c[1], c[2]), h, (rot[0], -rot[1], -rot[2])))
    return out


def cut(obj, co, no):
    """Planar cut, removing everything on the negative side of the normal (clean hems)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no, clear_inner=True)
    bm.to_mesh(obj.data)
    bm.free()


def primitive_blob(name, center, half, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=center)
    obj = bpy.context.active_object
    obj.scale = half
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(obj, name, mat)


def rounded_box(name, center, size, mat, bevel=0.015):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = bevel
    mod.segments = 4
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, mat)


def ring(name, center, major, minor, mat, uv_box=False):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=40,
                                     minor_segments=12, location=center)
    return finish(bpy.context.active_object, name, mat, uv_box=uv_box)


def face_hit(skin, x, z):
    """Point + normal on the front of the skin mesh at (x, z) (ray from the front)."""
    ok, loc, nrm, _ = skin.ray_cast(Vector((x, -2.0, z)), Vector((0, 1, 0)))
    if not ok:
        raise RuntimeError(f"no face at x={x} z={z}")
    return loc, nrm.normalized()


# ---------------------------------------------------------------- the character

def build():
    global ROOT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ROOT = bpy.data.objects.new("PlayerV3", None)
    bpy.context.scene.collection.objects.link(ROOT)
    plaid = plaid_material()

    # --- skin: bald head with full jaw/cheeks, big ears; thick arms ending in big fists
    head = [((0, 0.0, 1.5), (0.205, 0.19, 0.22)),               # round dome, not an egg
            ((0, -0.03, 1.31), (0.195, 0.165, 0.13))]          # full jaw / cheeks
    arm = mirror([
        ((0.315, 0.02, 0.95), (0.09, 0.09, 0.12), (0, -8, 0)),     # upper arm (inside the sleeve)
        ((0.35, 0.005, 0.76), (0.088, 0.085, 0.13), (0, -6, 0)),   # thick forearm
        ((0.365, 0.0, 0.63), (0.075, 0.072, 0.05)),                # wrist
        ((0.375, -0.005, 0.52), (0.1, 0.09, 0.095)),               # big fist
    ])
    skin = finish(meta("Skin", head + arm, 0.012), "Skin", material("skin"))
    # inner ear + finger segments as separate lumps so their creases stay visible
    for s in (-1, 1):
        side = "L" if s > 0 else "R"
        # big flat ears standing out from the head, turned a little forward, with an inner hollow
        primitive_blob(f"Ear.{side}", (0.212 * s, 0.025, 1.37), (0.026, 0.08, 0.102), material("skin"), rot=(0, 0, -16 * s))
        primitive_blob(f"Ear.Inner.{side}", (0.228 * s, 0.018, 1.37), (0.012, 0.05, 0.066), material("ear_in"), rot=(0, 0, -16 * s))
        for i, z in enumerate((0.565, 0.528, 0.491, 0.456)):
            primitive_blob(f"Finger{i}.{side}", (0.352 * s, -0.07, z), (0.05, 0.034, 0.02), material("skin"), rot=(0, 0, 18 * s))
        # thumb wrapped across the front of the curled fingers
        primitive_blob(f"Thumb.{side}", (0.365 * s, -0.093, 0.578), (0.048, 0.027, 0.026), material("skin"), rot=(0, -12 * s, 20 * s))

    # --- face, placed on the skin surface
    p, n = face_hit(skin, 0.0, 1.262)
    primitive_blob("Nose", p + n * 0.035 + Vector((0, -0.012, 0)), (0.074, 0.062, 0.064), material("nose", 0.6))
    for s in (-1, 1):
        p, n = face_hit(skin, 0.074 * s, 1.35)
        eye = primitive_blob(f"Eye.{'L' if s > 0 else 'R'}", p, (0.017, 0.008, 0.021), material("eye", 0.4))
        eye.rotation_mode = "QUATERNION"
        eye.rotation_quaternion = (-n).to_track_quat("Y", "Z")
    # thick flat brows: a row of lumps sitting on the brow, outer end a little lower
    brow_balls = []
    for s in (-1, 1):
        for i in range(4):
            x = (0.052 + i * 0.033) * s       # gap in the middle: two separate brows
            p, n = face_hit(skin, x, 1.402 + 0.0015 * i)   # near-flat, heavy brows
            brow_balls.append((tuple(p + n * 0.004), (0.042, 0.02, 0.03)))
    finish(meta("Brows", brow_balls, 0.008), "Brows", material("hair", 0.9))

    # --- beard: full moustache under the nose flowing into the cheeks and a pointed beard
    # V-shaped: wide over the cheeks, narrowing to a point on the chest
    beard = [((0, -0.215, 1.235), (0.15, 0.055, 0.05)),
             ((0, -0.19, 1.15), (0.16, 0.09, 0.1)),
             ((0, -0.2, 1.06), (0.1, 0.07, 0.07)),
             ((0, -0.205, 0.995), (0.045, 0.045, 0.045)),
             ((0, -0.205, 0.965), (0.02, 0.025, 0.025))]
    beard += mirror([((0.14, -0.14, 1.22), (0.075, 0.08, 0.09)),
                     ((0.08, -0.19, 1.07), (0.06, 0.06, 0.06)),
                     ((0.19, -0.05, 1.3), (0.032, 0.05, 0.08))])       # sideburns up to the ears
    beard_obj = meta("Beard", beard, 0.01)
    for v in beard_obj.data.vertices:   # ragged lower edge: a few soft points
        t = max(0.0, min(1.0, (1.14 - v.co.z) / 0.1))
        v.co.z -= t * 0.028 * (0.5 + 0.5 * math.cos(2 * math.pi * v.co.x / 0.075))
    finish(beard_obj, "Beard", material("hair", 0.9))

    # --- grey tee over the big round belly (tucked into the jeans)
    tee_balls = [((0, -0.1, 0.77), (0.265, 0.255, 0.215)),
                 ((0, -0.05, 0.975), (0.2, 0.16, 0.13)),
                 ((0, -0.03, 0.6), (0.245, 0.2, 0.08))]
    tee = meta("Tee", tee_balls, 0.012)
    cut(tee, (0, 0, 0.52), (0, 0, 1))
    finish(tee, "Tee", material("tee"))

    # --- red plaid shirt: body + shoulders + short sleeves in one piece, open at the front
    shirt_balls = [((0, 0.03, 0.99), (0.28, 0.19, 0.17)),
                   ((0, -0.01, 0.77), (0.315, 0.24, 0.2)),
                   ((0, 0.02, 0.63), (0.29, 0.22, 0.09))]
    shirt_balls += mirror([((0.235, 0.03, 1.075), (0.1, 0.1, 0.08)),
                           ((0.315, 0.02, 0.975), (0.105, 0.105, 0.11), (0, -10, 0))])
    shirt = meta("Shirt", shirt_balls, 0.012)
    cut(shirt, (0, 0, 0.565), (0, 0, 1))                # straight hem
    finish(shirt, "Shirt", plaid, uv_box=True)
    # front panels: cut from a slightly larger copy of the tee so they lie on the belly
    for s in (-1, 1):
        panel = meta(f"Shirt.Front.{'L' if s > 0 else 'R'}",
                     [(c, tuple(v * 1.04 for v in h)) for c, h in tee_balls], 0.012)
        for co, no in (((0.185 * s, 0, 0), (s, 0, 0)), ((0, -0.02, 0), (0, -1, 0)),
                       ((0, 0, 0.565), (0, 0, 1)), ((0, 0, 1.1), (0, 0, -1))):
            cut(panel, co, no)
        mod = panel.modifiers.new("thick", "SOLIDIFY")
        mod.thickness = 0.012
        bpy.context.view_layer.objects.active = panel
        bpy.ops.object.modifier_apply(modifier=mod.name)
        finish(panel, panel.name, plaid)
        front_uv(panel)
    # collar points either side of the neck, rolled sleeve cuffs
    for s in (-1, 1):
        side = "L" if s > 0 else "R"
        p, n = face_hit(shirt, 0.15 * s, 1.1)
        collar = primitive_blob(f"Shirt.Collar.{side}", p + n * 0.012, (0.085, 0.016, 0.06), plaid)
        collar.rotation_mode = "QUATERNION"
        collar.rotation_quaternion = (-n).to_track_quat("Y", "Z") @ Quaternion((0, 1, 0), math.radians(-28 * s))
        bpy.context.view_layer.objects.active = collar
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        front_uv(collar)
        ring(f"Shirt.Cuff.{side}", (0.33 * s, 0.02, 0.88), 0.088, 0.03, plaid, uv_box=True)

    # --- navy jeans: hips, seat and straight thick legs
    jeans = [((0, 0.02, 0.55), (0.28, 0.21, 0.1)), ((0, 0.05, 0.5), (0.24, 0.16, 0.09))]
    jeans += mirror([((0.145, 0.02, 0.4), (0.12, 0.125, 0.12)),
                     ((0.152, 0.0, 0.26), (0.105, 0.11, 0.1)),
                     ((0.156, 0.0, 0.15), (0.1, 0.1, 0.075))])
    finish(meta("Jeans", jeans, 0.012), "Jeans", material("jeans"))

    # --- tan round-toe boots on dark soles
    boots = mirror([((0.16, -0.055, 0.085), (0.12, 0.175, 0.08)),
                    ((0.16, 0.0, 0.13), (0.105, 0.105, 0.065)),
                    ((0.16, -0.155, 0.088), (0.108, 0.085, 0.072))])
    finish(meta("Boots", boots, 0.012), "Boots", material("boot"))
    soles = mirror([((0.16, -0.06, 0.024), (0.119, 0.18, 0.026)),
                    ((0.16, -0.16, 0.026), (0.106, 0.086, 0.026))])
    finish(meta("Soles", soles, 0.01), "Soles", material("sole"))


# ---------------------------------------------------------------- rendering

def setup_render(res):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.82, 0.82, 0.8, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.75
    for name, rot, energy in (("Key", (50, 0, -35), 2.4), ("Rim", (60, 0, 160), 1.2)):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.angle = math.radians(14)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = Euler([math.radians(a) for a in rot])
        sc.collection.objects.link(lo)


def add_camera(name, pitch_deg, yaw_deg, ortho, target_z):
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


VIEWS = [("front", 0, 0, 2.1), ("side", 0, -90, 2.1), ("back", 0, 180, 2.1),
         ("three_quarter", 10, 35, 2.1), ("game_camera", 40, 30, 2.2)]


def render_views(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    for name, pitch, yaw, ortho in VIEWS:
        sc.camera = add_camera("Cam." + name, pitch, yaw, ortho, 0.86)
        sc.render.filepath = os.path.join(out_dir, f"player_v3_{name}.png")
        bpy.ops.render.render(write_still=True)


def render_silhouettes(out_dir):
    sc = bpy.context.scene
    black = bpy.data.materials.new("silhouette")
    black.use_nodes = True
    nt = black.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0, 0, 0, 1)
    nt.links.new(em.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs[0])
    bpy.context.view_layer.material_override = black
    sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.cycles.samples = 8
    paths = []
    for name, *_ in VIEWS:
        sc.camera = bpy.data.objects["Cam." + name]
        sc.render.filepath = os.path.join(out_dir, f"silhouette_{name}.png")
        bpy.ops.render.render(write_still=True)
        paths.append(sc.render.filepath)
    bpy.context.view_layer.material_override = None
    try:
        from PIL import Image, ImageDraw, ImageFont
        tiles = [Image.open(p).convert("RGB") for p in paths]
        w, h = tiles[0].size
        sheet = Image.new("RGB", (w * len(tiles), h + 44), "white")
        draw = ImageDraw.Draw(sheet)
        try:
            font = ImageFont.load_default(size=28)
        except TypeError:
            font = None
        for i, t in enumerate(tiles):
            sheet.paste(t, (i * w, 44))
            draw.text((i * w + 12, 6), VIEWS[i][0], fill="black", font=font)
        sheet.save(os.path.join(out_dir, "silhouette_sheet.png"))
        for p in paths:
            os.remove(p)
    except ImportError:
        print("Pillow not available: silhouettes left as separate images")


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    out = os.path.abspath(args[0] if args else "art_src/player_v3")
    os.makedirs(out, exist_ok=True)
    build()
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "player_v3.glb"), export_format="GLB",
                              export_yup=True, export_apply=True, export_cameras=False, export_lights=False)
    setup_render((900, 1000))
    render_views(os.path.join(out, "renders"))
    render_silhouettes(os.path.join(out, "renders"))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "player_v3.blend"), compress=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    zs = [(o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices]
    tris = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    print(f"[player_v3] {len(meshes)} meshes, {tris} triangles, height {max(zs) - min(zs):.3f} m, written to {out}")


main()
