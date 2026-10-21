"""Prepares the Meshy AI protagonist model for the game (Blender 4.2+ / bpy 5.x).

Input: the Meshy export (static textured mesh, ~475k triangles, 2K PBR textures, no rig).
Output <out>/player.glb (bones: hips, spine, chest, head, upper_arm_L/R, forearm_L/R, hand_L/R,
thigh_L/R, shin_L/R, foot_L/R; _L = the character's left): the same character
  - scaled to the game height (1.74 m, feet at 0, centred), facing -Y in Blender (+Z in glTF)
  - decimated for the sprite baker (it renders ~200 posed copies at once)
  - base colour only (1024 px); metal/roughness/normal maps dropped (the game uses flat toon shading)
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
TEXTURE_PX = 1024

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

    # --- decimate
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    mod = body.modifiers.new("decimate", "DECIMATE")
    mod.ratio = min(1.0, TARGET_TRIS / tris)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in body.data.polygons:
        p.use_smooth = True

    # --- material: base colour only, smaller texture, no metal
    mat = body.data.materials[0]
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    base_img = None
    for link in list(nt.links):
        if link.to_node == bsdf and link.to_socket.name == "Base Color":
            base_img = link.from_node.image
    for n in list(nt.nodes):
        if n.type in ("TEX_IMAGE", "NORMAL_MAP", "SEPRGB", "SEPARATE_COLOR") and getattr(n, "image", None) is not base_img:
            nt.nodes.remove(n)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    base_img.scale(TEXTURE_PX, TEXTURE_PX)
    base_img.file_format = "JPEG"
    base_img.pack()
    for img in list(bpy.data.images):
        if img is not base_img:
            bpy.data.images.remove(img)

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

    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True,
                              export_apply=False, export_skins=True, export_animations=False,
                              export_cameras=False, export_lights=False, export_image_format="JPEG")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "player.blend"), compress=True)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print(f"[prepare] {tris} triangles, {len(arm_data.bones)} bones, texture {base_img.size[0]} px, written to {out}")
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
