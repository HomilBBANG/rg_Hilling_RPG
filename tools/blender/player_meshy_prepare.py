"""Prepares the Meshy AI protagonist model for the game (Blender 4.2+ / bpy 5.x).

Input: the Meshy export (static textured mesh, ~475k triangles, 2K PBR textures, no rig).
Output <out>/player.glb (bones: hips, spine, chest, head, upper_arm_L/R, forearm_L/R, hand_L/R,
thigh_L/R, shin_L/R, foot_L/R; _L = the character's left): the same character
  - scaled to the game height (1.74 m, feet at 0, centred), facing -Y in Blender (+Z in glTF)
  - decimated for the sprite baker (it renders ~200 posed copies at once) and smoothed
  - coloured per face with flat palette colours (vertex colours) taken from the Meshy texture;
    no texture / UVs in the game model: the Meshy atlas is hundreds of tiny islands, and after
    decimation faces straddle them, which made the sprites speckled
  - the shirt split into its own mesh ("Shirt") so the game can give it big plaid checks
  - skinned to a simple humanoid armature (hips, spine, chest, head, arms, hands, legs, feet)
    so PlayerRig can pose walk / attack / use motions from code, like the old procedural rig.
Also writes <out>/player.blend and <out>/renders/rig_test_*.png (rest + a test pose).

Run (from the project folder):
  blender -b -P tools/blender/player_meshy_prepare.py -- art_src/player_meshy/meshy_source.glb art_src/player_meshy assets/characters/player/player.glb
  python tools/blender/player_meshy_prepare.py <same three arguments>        (pip install bpy)
The optional third argument is where the game GLB goes (default <out_dir>/player.glb).
"""

import math
import os
import sys

import bpy  # noqa: I001 - bpy before bmesh / mathutils
from mathutils import Euler, Vector

HEIGHT = 1.74          # same height as the previous in-game model (scene scale unchanged)
TARGET_TRIS = 16000
TEXTURE_PX = 512       # working size for reading the colour regions

# Joint landmarks measured from the Meshy mesh (height slices): z as a fraction of the height,
# x / y in metres after scaling. Character faces -Y, so its right side is -X.
JOINTS = {
    "hips": (0.0, 0.03, 0.40), "spine": (0.0, 0.03, 0.52), "chest": (0.0, 0.03, 0.64),
    "neck": (0.0, 0.03, 0.755), "head_top": (0.0, 0.0, 1.0),
    "shoulder": (0.27, 0.03, 0.665), "elbow": (0.385, 0.03, 0.50), "wrist": (0.41, 0.0, 0.375),
    "hand_end": (0.425, -0.01, 0.28),
    "hip": (0.155, 0.04, 0.36), "knee": (0.155, 0.04, 0.175), "ankle": (0.155, 0.05, 0.06),
    "toe": (0.155, -0.14, 0.02),
}


def joint(name, side=1):
    x, y, f = JOINTS[name]
    return Vector((x * side, y, f * HEIGHT))


# Palette the texture is snapped to (sRGB). The Meshy texture is mostly flat colour islands; the fine
# buffalo plaid and small shading flecks turn into noise at sprite size.
PALETTE_SEED = {
    "skin": (0.96, 0.66, 0.5), "beard": (0.33, 0.22, 0.15), "jeans": (0.15, 0.22, 0.42),
    "boots": (0.75, 0.55, 0.22), "tee": (0.9, 0.9, 0.9), "nose": (0.85, 0.45, 0.2),
    "shirt_red": (0.75, 0.12, 0.12), "shirt_dark": (0.25, 0.06, 0.07), "black": (0.05, 0.05, 0.05),
}


def _box(a, r):
    """Mean over a (2r+1)^2 window (edge-clamped), via cumulative sums."""
    import numpy as np
    p = np.pad(a, r, mode="edge")
    c = np.cumsum(np.cumsum(p, 0), 1)
    c = np.pad(c, ((1, 0), (1, 0)))
    n = 2 * r + 1
    return (c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]) / (n * n)


def texture_labels(img):
    """Reads the Meshy colour texture as palette regions: every texel snapped to the nearest of a
    few outfit colours (k-means seeded with them), the buffalo plaid merged into one "shirt" region,
    stray texels cleaned. Returns (names, sRGB centres, label image [row 0 = bottom])."""
    import numpy as np
    w, h = img.size
    rgb = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[:, :, :3]  # sRGB values
    names = list(PALETTE_SEED)
    centers = np.array([PALETTE_SEED[n] for n in names], dtype=np.float32)
    flat = rgb.reshape(-1, 3)
    for _ in range(8):
        lab = np.argmin(((flat[:, None, :] - centers[None, :, :]) ** 2).sum(2), 1)
        for k in range(len(names)):
            sel = flat[lab == k]
            if len(sel):
                centers[k] = sel.mean(0)
    lab = lab.reshape(h, w)
    # shirt = connected islands of plaid colours (red / dark red / near-black) that contain a fair
    # share of bright red; the eyes and other small dark islands have none and stay as they are
    plaid = np.isin(lab, [names.index(n) for n in ("shirt_red", "shirt_dark", "black")])
    comp = np.where(plaid, np.arange(h * w).reshape(h, w), h * w)
    while True:  # connected components by min-label propagation
        nxt = comp.copy()
        for axis in (0, 1):
            for shift in (1, -1):
                nb = np.roll(comp, shift, axis)
                nxt = np.where(plaid, np.minimum(nxt, nb), nxt)
        nxt[~plaid] = h * w
        if np.array_equal(nxt, comp):
            break
        comp = nxt
    _ids, inv, sizes = np.unique(comp[plaid], return_inverse=True, return_counts=True)
    red_counts = np.bincount(inv, weights=(lab[plaid] == names.index("shirt_red")).astype(np.float64))
    is_shirt = (red_counts / sizes > 0.15) & (sizes > 20)
    shirt = np.zeros((h, w), dtype=bool)
    shirt[plaid] = is_shirt[inv]
    lab[shirt] = names.index("shirt_red")
    # majority filter (3x3, twice): removes isolated flecks, keeps small islands like the eyes
    for _ in range(2):
        counts = np.stack([_box((lab == k).astype(np.float32), 1) for k in range(len(names))])
        lab = np.argmax(counts, 0)
    print("[prepare] palette:", {n: tuple(round(float(v), 2) for v in centers[i]) for i, n in enumerate(names)})
    return names, centers, lab


def face_labels_from_uv(mesh, lab):
    """Palette region of every face, read from the label image at the face's UV centre."""
    import numpy as np
    h, w = lab.shape
    uv = np.zeros(len(mesh.loops) * 2, dtype=np.float32)
    mesh.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    starts = np.zeros(len(mesh.polygons), dtype=np.int32)
    counts = np.zeros(len(mesh.polygons), dtype=np.int32)
    mesh.polygons.foreach_get("loop_start", starts)
    mesh.polygons.foreach_get("loop_total", counts)
    centre = np.add.reduceat(uv, starts, axis=0) / counts[:, None]
    col = np.clip((centre[:, 0] % 1.0 * w).astype(int), 0, w - 1)
    row = np.clip((centre[:, 1] % 1.0 * h).astype(int), 0, h - 1)
    return lab[row, col]


def paint_faces(body, hi_mesh, hi_labels, names, centers):
    """Colours each decimated face with the region of the nearest original face, cleans single
    odd faces (majority with the edge neighbours) and returns the per-face labels."""
    import numpy as np
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromPolygons([v.co.copy() for v in hi_mesh.vertices], [p.vertices[:] for p in hi_mesh.polygons])
    me = body.data
    labels = np.array([hi_labels[bvh.find_nearest(p.center)[2]] for p in me.polygons])
    edge_faces = {}
    for p in me.polygons:
        for ek in p.edge_keys:
            edge_faces.setdefault(ek, []).append(p.index)
    for _ in range(2):
        new = labels.copy()
        for p in me.polygons:
            nb = [f for ek in p.edge_keys for f in edge_faces[ek] if f != p.index]
            votes = np.bincount(labels[nb + [p.index]], minlength=len(names))
            if votes.max() >= 2 and votes[labels[p.index]] < votes.max():
                new[p.index] = int(np.argmax(votes))
        labels = new
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for p in me.polygons:
        c = centers[labels[p.index]]
        for li in p.loop_indices:
            attr.data[li].color_srgb = (float(c[0]), float(c[1]), float(c[2]), 1.0)
    me.color_attributes.active_color = attr
    return labels


def vertex_colour_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 1.0
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    src, out = os.path.abspath(args[0]), os.path.abspath(args[1])
    glb = os.path.abspath(args[2]) if len(args) > 2 else os.path.join(out, "player.glb")
    os.makedirs(os.path.join(out, "renders"), exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    body = [o for o in bpy.data.objects if o.type == "MESH"][0]
    body.name = body.data.name = "Body"
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # --- scale to the game height, feet on the ground, centred
    vs = [v.co for v in body.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    s = HEIGHT / (hi.z - lo.z)
    c = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
    for v in body.data.vertices:
        v.co = (v.co - c) * s

    # --- weld: the export splits vertices along every UV seam (UVs live per face corner in
    # Blender, so welding keeps them); split vertices would get different weights and tear apart
    before = len(body.data.vertices)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0004)
    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"[prepare] welded {before} -> {len(body.data.vertices)} vertices")

    # --- colour regions from the texture, on the full-resolution mesh
    tex = next(n.image for n in body.data.materials[0].node_tree.nodes if n.type == "TEX_IMAGE"
               and any(l.to_socket.name == "Base Color" for l in n.outputs["Color"].links))
    tex.scale(TEXTURE_PX, TEXTURE_PX)
    names, centers, lab = texture_labels(tex)
    hi_mesh = body.data.copy()
    hi_labels = face_labels_from_uv(hi_mesh, lab)

    # --- decimate
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    mod = body.modifiers.new("decimate", "DECIMATE")
    mod.ratio = min(1.0, TARGET_TRIS / tris)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in body.data.polygons:
        p.use_smooth = True
    # Iron out the sculpted micro detail (beard strands, cloth wrinkles): at sprite size it only
    # turns into speckled lighting. Volume-preserving, so the silhouette stays.
    mod = body.modifiers.new("smooth", "LAPLACIANSMOOTH")
    mod.iterations = 6
    mod.lambda_factor = 0.8
    bpy.ops.object.modifier_apply(modifier=mod.name)

    # --- flat palette colour per face, no texture / UVs
    labels = paint_faces(body, hi_mesh, hi_labels, names, centers)
    bpy.data.meshes.remove(hi_mesh)
    while body.data.uv_layers:
        body.data.uv_layers.remove(body.data.uv_layers[0])
    body.data.materials.clear()
    body.data.materials.append(vertex_colour_material("Body"))
    shirt_mat = bpy.data.materials.new("Shirt")
    shirt_mat.use_nodes = True
    shirt_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = tuple(
        float(c) ** 2.2 for c in centers[names.index("shirt_red")]) + (1.0,)
    body.data.materials.append(shirt_mat)
    shirt_id = names.index("shirt_red")
    for p in body.data.polygons:
        p.material_index = 1 if labels[p.index] == shirt_id else 0
    for img in list(bpy.data.images):
        bpy.data.images.remove(img)
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)

    # --- armature
    arm_data = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, head, tail, parent=None, connect=False):
        b = eb.new(name)
        b.head, b.tail = head, tail
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        return b

    bone("hips", joint("hips") - Vector((0, 0, 0.12)), joint("spine"))
    bone("spine", joint("spine"), joint("chest"), "hips", True)
    bone("chest", joint("chest"), joint("neck"), "spine", True)
    bone("head", joint("neck"), joint("head_top"), "chest", True)
    for side, sx in (("L", 1), ("R", -1)):
        bone(f"upper_arm_{side}", joint("shoulder", sx), joint("elbow", sx), "chest")
        bone(f"forearm_{side}", joint("elbow", sx), joint("wrist", sx), f"upper_arm_{side}", True)
        bone(f"hand_{side}", joint("wrist", sx), joint("hand_end", sx), f"forearm_{side}", True)
        bone(f"thigh_{side}", joint("hip", sx), joint("knee", sx), "hips")
        bone(f"shin_{side}", joint("knee", sx), joint("ankle", sx), f"thigh_{side}", True)
        bone(f"foot_{side}", joint("ankle", sx), joint("toe", sx), f"shin_{side}", True)
    bpy.ops.object.mode_set(mode="OBJECT")

    # --- skin with automatic (heat) weights
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    empty_groups = [g.name for g in body.vertex_groups
                    if not any(g.index in [x.group for x in v.groups] for v in body.data.vertices)]
    print("[prepare] groups without vertices:", empty_groups)
    # the shirt becomes its own mesh (same weights, so it moves exactly with the body)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    body.active_material_index = 1
    bpy.ops.object.material_slot_select()
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    shirt = next(o for o in bpy.data.objects if o.type == "MESH" and o is not body)
    shirt.name = shirt.data.name = "Shirt"
    for o, keep in ((body, "Body"), (shirt, "Shirt")):
        idx = o.data.materials.find(keep)
        mat = o.data.materials[idx]
        o.data.materials.clear()
        o.data.materials.append(mat)

    for o in (body, shirt):
        o.data.validate(clean_customdata=False)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True,
                              export_apply=False, export_skins=True, export_animations=False,
                              export_cameras=False, export_lights=False, export_vertex_color="ACTIVE")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "player.blend"), compress=True)
    tris = sum(len(p.vertices) - 2 for o in (body, shirt) for p in o.data.polygons)
    print(f"[prepare] {tris} triangles (shirt {len(shirt.data.polygons)}), {len(arm_data.bones)} bones, written to {out}")
    test_renders(rig, os.path.join(out, "renders"))


def test_renders(rig, out_dir):
    """Rest pose and a stress pose (sword arm raised forward, legs mid-stride) to check the weights."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 16
    sc.render.resolution_x, sc.render.resolution_y = 700, 800
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.8, 0.8, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 2.5
    sun.rotation_euler = Euler((math.radians(50), 0, math.radians(-35)))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.2
    sc.collection.objects.link(cam)
    sc.camera = cam
    poses = {
        "rest": {},
        "pose": {"upper_arm_R": (-75, 0, 0), "forearm_R": (-20, 0, 0), "upper_arm_L": (30, 0, 0),
                 "thigh_L": (-30, 0, 0), "thigh_R": (25, 0, 0), "shin_R": (30, 0, 0), "head": (0, 0, 15)},
    }
    for pname, rots in poses.items():
        for pb in rig.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (0, 0, 0)
        for bname, r in rots.items():
            # rotation about world axes at the joint: convert into the bone's local frame
            pb = rig.pose.bones[bname]
            world_rot = Euler([math.radians(a) for a in r]).to_matrix()
            rest = pb.bone.matrix_local.to_3x3()
            pb.rotation_euler = (rest.inverted() @ world_rot @ rest).to_euler()
        bpy.context.view_layer.update()
        for view, yaw in (("front", 0), ("side", -90)):
            y = math.radians(yaw)
            d = Vector((math.sin(y), -math.cos(y), 0.15)).normalized()
            cam.location = Vector((0, 0, 0.87)) + d * 10
            cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = os.path.join(out_dir, f"rig_test_{pname}_{view}.png")
            bpy.ops.render.render(write_still=True)


main()
