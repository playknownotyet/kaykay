"""Bir .blend dosyasının ön izleme render'larını alır (Workbench, düz renk).

  blender --background <dosya.blend> --python tools/blender/onizleme.py -- <cikti_klasoru> [on,yan,arka,ucdort,yuz]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out_dir = args[0]
views = args[1].split(",") if len(args) > 1 else ["on", "ucdort", "yan", "arka", "yuz"]
os.makedirs(out_dir, exist_ok=True)

scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 520
scene.render.resolution_y = 760
scene.render.film_transparent = False
shading = scene.display.shading
shading.light = 'STUDIO'
shading.color_type = 'MATERIAL'
shading.show_shadows = True
shading.show_cavity = False
if scene.world is None:
    scene.world = bpy.data.worlds.new("World")
scene.world.color = (0.18, 0.18, 0.19)

cam_data = bpy.data.cameras.new("OnizlemeKamera")
cam_data.type = 'ORTHO'
cam = bpy.data.objects.new("OnizlemeKamera", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

# (yön açısı derece: 0 = önden, karakter -Y'ye bakar), hedef yükseklik, ortho ölçek
VIEWS = {
    "on": (0, 0.74, 1.65),
    "ucdort": (35, 0.74, 1.65),
    "yan": (90, 0.74, 1.65),
    "arka": (180, 0.74, 1.65),
    "yuz": (20, 1.29, 0.42),
    "yuz_on": (0, 1.29, 0.42),
}

for name in views:
    ang, h, scale = VIEWS[name]
    a = math.radians(ang)
    d = Vector((math.sin(a), -math.cos(a), 0.0))
    cam.location = Vector((0, 0, h)) + d * 4.0
    cam.rotation_euler = (math.radians(90), 0, a)
    cam_data.ortho_scale = scale
    scene.render.filepath = os.path.join(out_dir, f"karakter_{name}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDER", scene.render.filepath)
