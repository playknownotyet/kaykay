"""Hazırlanan sokak eşyalarının ön izlemesi (hepsi yan yana, ölçekli).
  blender --background --factory-startup --python tools/blender/prop_onizleme.py -- <klasor> <cikti.png>
"""
import os, sys, math
import bpy
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
D, OUT = args[0], args[1]
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
x = 0.0
for f in sorted(os.listdir(D)):
    if not f.endswith(".glb"):
        continue
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(D, f))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location.x += x
    x += 2.2
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'TEXTURE'
scene.render.resolution_x, scene.render.resolution_y = 1600, 500
cd = bpy.data.cameras.new("K"); cd.type = 'ORTHO'; cd.ortho_scale = x + 1
cam = bpy.data.objects.new("K", cd); scene.collection.objects.link(cam); scene.camera = cam
cam.location = (x / 2 - 1.1, -20, 2.0); cam.rotation_euler = (math.radians(86), 0, 0)
if scene.world is None:
    scene.world = bpy.data.worlds.new("W")
scene.world.color = (0.5, 0.55, 0.6)
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
