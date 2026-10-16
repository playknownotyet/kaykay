"""Poly Haven nesnesini (glTF) oyuna hazırlar: tek mesh, üçgen sayısı düşürülmüş, yalnız renk
dokusu (küçültülmüş; retro görünüm), kökü taban ortasında. Karakteristik olmayan sokak eşyaları
için (bank, çöp kovası, lamba...). Kaynak: https://polyhaven.com (CC0).

  blender --background --factory-startup --python tools/blender/prop_hazirla.py -- <girdi.gltf> <cikti.glb> <hedef_ucgen> <doku_px>
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
TARGET = int(args[2]) if len(args) > 2 else 800
TEX = int(args[3]) if len(args) > 3 else 128
## "tek": modelde yan yana birkaç kopya varsa (çift yangın musluğu, iki çöp kovası) yalnız soldakini tut
SINGLE = len(args) > 4 and args[4] == "tek"

for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
# Ebeveynlerden kurtar, dönüşümleri uygula, birleştir
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
for o in list(bpy.data.objects):
    if o != ob:
        bpy.data.objects.remove(o, do_unlink=True)

if SINGLE:
    # Kopuk parçaları ayır; ağırlık merkezi en soldaki kopyaya ait olanları tut
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    parts, seen = [], set()
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, part = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            part.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        parts.append(part)
    xs = [v.co.x for v in bm.verts]
    mid = (min(xs) + max(xs)) / 2
    kill = []
    for part in parts:
        cx = sum(sum(v.co.x for v in f.verts) / len(f.verts) for f in part) / len(part)
        if cx > mid:
            kill.extend(part)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(ob.data)
    bm.free()

tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
if tris > TARGET:
    mod = ob.modifiers.new("Azalt", 'DECIMATE')
    mod.ratio = max(TARGET / tris, 0.005)
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
after = sum(len(p.vertices) - 2 for p in ob.data.polygons)

# Kök: taban ortası
bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
shift = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
for v in ob.data.vertices:
    v.co -= shift
ob.location = (0, 0, 0)

# Malzemeler: yalnız renk dokusu, küçültülmüş ve gömülü
for mat in ob.data.materials:
    if not mat or not mat.use_nodes:
        continue
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    keep = None
    if bsdf and bsdf.inputs["Base Color"].is_linked:
        keep = bsdf.inputs["Base Color"].links[0].from_node
        # Araya karıştırıcı girmişse ilk görüntü düğümüne in
        seen = 0
        while keep is not None and keep.type != 'TEX_IMAGE' and seen < 6:
            seen += 1
            ins = [i for i in keep.inputs if i.is_linked]
            keep = ins[0].links[0].from_node if ins else None
        if keep is not None and keep.type == 'TEX_IMAGE':
            bsdf_link_from = keep
            for l in list(bsdf.inputs["Base Color"].links):
                nt.links.remove(l)
            nt.links.new(keep.outputs["Color"], bsdf.inputs["Base Color"])
    for n in list(nt.nodes):
        if n.type == 'TEX_IMAGE' and n != keep:
            nt.nodes.remove(n)
    if bsdf:
        for name in ("Normal", "Roughness", "Metallic"):
            if name in bsdf.inputs:
                for l in list(bsdf.inputs[name].links):
                    nt.links.remove(l)
        bsdf.inputs["Roughness"].default_value = 0.8
        bsdf.inputs["Metallic"].default_value = 0.0
    if keep is not None and getattr(keep, "image", None):
        img = keep.image
        w, h = img.size
        s = TEX / max(w, h)
        if s < 1.0:
            img.scale(max(int(w * s), 4), max(int(h * s), 4))
        img.pack()

# Lamba gibi nesnelerin kol yönü: üst bölgenin ağırlık merkezinin eksenden kayması (bilgi)
top = [v.co for v in ob.data.vertices if v.co.z > (mx.z - mn.z) * 0.75]
arm = Vector((0, 0, 0))
if top:
    arm = sum(top, Vector()) / len(top)
print("PROP", os.path.basename(OUT), "UCGEN", tris, "->", after, "BOYUT %.2f x %.2f x %.2f" % (mx.x - mn.x, mx.y - mn.y, mx.z - mn.z),
      "UST_KAYMA %.2f %.2f" % (arm.x, arm.y))

bpy.ops.object.select_all(action='DESELECT')
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True,
                          export_animations=False, export_image_format='AUTO')
