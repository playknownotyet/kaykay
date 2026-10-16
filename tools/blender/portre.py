"""Reklam panoları için tür portresi: kaydedilmiş NPC .blend'inden (npc_build.py üretir)
tişörtlü, kafa-omuz yakın çekim, saydam arka plan.

  blender --background art/npc/<tur>.blend --python tools/blender/portre.py -- <cikti.png>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_ortak as O  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0]) if args else "portre.png"

outfit = ["ust_tisort"]
show = set(O.visible_skin(outfit)) | set(outfit)
parts = [o for o in bpy.data.objects if o.type == 'MESH']
for o in parts:
    o.hide_render = not (o.name.startswith("tur_") or o.name in show)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
arm.animation_data.action = bpy.data.actions["idle"]
bpy.context.scene.frame_set(0)

# Kafanın kapladığı alan (değerlendirilmiş mesh: iskelet pozuyla)
dg = bpy.context.evaluated_depsgraph_get()
head = next(o for o in parts if o.name == "tur_bas")
ev = head.evaluated_get(dg)
zs = [(ev.matrix_world @ v.co).z for v in ev.data.vertices]
top, bot = max(zs), min(zs)
size = top - bot
target = Vector((0, 0, top - size * 0.62))

scene = O.setup_render((320, 320))
scene.render.film_transparent = True
scene.render.image_settings.color_mode = 'RGBA'
cd = bpy.data.cameras.new("PortreKamera")
cd.type = 'ORTHO'
cd.ortho_scale = size * 1.55 + 0.12
cam = bpy.data.objects.new("PortreKamera", cd)
scene.collection.objects.link(cam)
scene.camera = cam
a, e = math.radians(-24), math.radians(4)
cam.location = target + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * 8.0
cam.rotation_euler = (math.radians(90) - e, 0, a)
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("PORTRE", OUT)
