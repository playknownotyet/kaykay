"""Bir animasyonu yandan kare kare render alır (adım / kol kontrolü için).

  blender --background art/karakter/karakter_rig.blend --python tools/blender/adim_onizleme.py -- <klasor> walk,run [kare_sayisi] [aci]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out_dir = args[0]
names = args[1].split(",")
count = int(args[2]) if len(args) > 2 else 6
angle = float(args[3]) if len(args) > 3 else 90.0
os.makedirs(out_dir, exist_ok=True)

scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 300
scene.render.resolution_y = 420
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'MATERIAL'
if scene.world is None:
    scene.world = bpy.data.worlds.new("World")
scene.world.color = (0.18, 0.18, 0.19)
cam_data = bpy.data.cameras.new("Kamera")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 1.9
cam = bpy.data.objects.new("Kamera", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
a = math.radians(angle)
d = Vector((math.sin(a), -math.cos(a), 0.0))
cam.location = Vector((0, 0, 0.75)) + d * 4.0
cam.rotation_euler = (math.radians(90), 0, a)

arm = bpy.data.objects["KarakterIskelet"]
for name in names:
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    f0, f1 = act.frame_range
    for i in range(count):
        f = f0 + (f1 - f0) * i / count
        scene.frame_set(int(round(f)))
        scene.render.filepath = os.path.join(out_dir, f"adim_{name}_{i}.png")
        bpy.ops.render.render(write_still=True)
