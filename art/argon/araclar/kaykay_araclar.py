"""Kaykay eşya araçları (Blender 5.2). Argon bunları Blender MCP'nin execute_blender_code aracıyla yükler:

    exec(open("/Users/kerem/Projects/kaykay/art/argon/araclar/kaykay_araclar.py").read())

Sonra:
    yeni_sahne("bank")              # boş sahne, birim metre, kayıt: cikti/bank/bank.blend
    renk(obj, "#2f7d6d")            # nesnenin tüm yüzlerini bir renge boyar (köşe rengi "Col")
    renk_yuz(obj, [0, 3, 4], "#f2c14e")   # yalnız bu yüzleri boyar
    birlestir("bank")               # bütün mesh'leri tek nesnede toplar (adı: bank), kökü tabanın ortasına alır
    rapor = kontrol("bank")         # kuralları denetler; rapor["gecti"] True olmalı
    disa_aktar("bank")              # cikti/bank/bank.glb + onizleme_on.png / _yan.png / _ust.png / _oyun.png

Kurallar için: art/argon/README.md
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector

KOK = "/Users/kerem/Projects/kaykay/art/argon"
CIKTI = os.path.join(KOK, "cikti")
RENK_ATTR = "Col"


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def yeni_sahne(ad):
    """Boş sahne: varsayılan küp / ışık / kamera silinir, birim metre. .blend dosyası kaydedilir."""
    # Dosya yeniden yüklenmez (MCP bağlantısı kopmasın): sahne temizlenir
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.cameras, bpy.data.lights, bpy.data.materials, bpy.data.curves):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    sc.unit_settings.scale_length = 1.0
    klasor = os.path.join(CIKTI, ad)
    os.makedirs(klasor, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(klasor, ad + ".blend"))
    # Görünüm: köşe renkleri görünsün
    for area in bpy.context.screen.areas if bpy.context.screen else []:
        if area.type == 'VIEW_3D':
            sh = area.spaces[0].shading
            sh.type = 'SOLID'
            sh.color_type = 'VERTEX'
    return klasor


def _renk_katmani(me):
    ca = me.color_attributes.get(RENK_ATTR)
    if ca is None:
        ca = me.color_attributes.new(RENK_ATTR, 'BYTE_COLOR', 'CORNER')
    me.color_attributes.active_color = ca
    me.color_attributes.render_color_index = me.color_attributes.find(RENK_ATTR)
    return ca


def renk(obj, hex_renk, alfa=1.0):
    """Nesnenin bütün yüzlerini tek renge boyar. alfa < 1: o yüzler oyunda kendiliğinden parlar
    (ampul, neon, ekran). Normal yüzeyler her zaman alfa 1."""
    renk_yuz(obj, None, hex_renk, alfa)


def renk_yuz(obj, yuzler, hex_renk, alfa=1.0):
    """Belirli yüzleri (indeks listesi; None = hepsi) boyar."""
    me = obj.data
    ca = _renk_katmani(me)
    r, g, b = _hex(hex_renk)
    secili = None if yuzler is None else set(yuzler)
    for poly in me.polygons:
        if secili is not None and poly.index not in secili:
            continue
        for li in poly.loop_indices:
            ca.data[li].color_srgb = (r, g, b, alfa)
    me.update()


def birlestir(ad):
    """Sahnedeki bütün mesh nesnelerini tek nesnede birleştirir, dönüşümleri uygular."""
    meshler = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if not meshler:
        raise RuntimeError("Sahnede mesh yok")
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshler:
        o.select_set(True)
        _renk_katmani(o.data)
    bpy.context.view_layer.objects.active = meshler[0]
    if len(meshler) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = ad
    obj.data.name = ad
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    kok_tabana(obj)
    return obj


def kok_tabana(obj):
    """Kökü (origin) tabanın ortasına alır ve nesneyi (0,0,0)'a koyar: model zemine oturur."""
    mn, mx = _bbox(obj)
    kayma = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))
    for v in obj.data.vertices:
        v.co = obj.matrix_world.inverted() @ (obj.matrix_world @ v.co - kayma)
    obj.location = (0.0, 0.0, 0.0)
    obj.data.update()


def _bbox(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def kontrol(ad, ucgen_sinir=None, olcu=None, tolerans=0.12):
    """Kuralları denetler. ucgen_sinir: görev kartındaki en çok üçgen; olcu: (en x, derinlik y,
    yükseklik z) metre, tolerans oranı. Dönen rapor["gecti"] False ise rapor["sorunlar"]ı düzelt."""
    sorunlar = []
    meshler = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if len(meshler) != 1:
        sorunlar.append("Sahnede tam 1 mesh nesnesi olmalı (şu an %d). birlestir(ad) kullan." % len(meshler))
    obj = bpy.data.objects.get(ad)
    if obj is None or obj.type != 'MESH':
        sorunlar.append("'%s' adında mesh nesnesi yok." % ad)
        return {"gecti": False, "sorunlar": sorunlar}
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    ucgen = sum(len(f.verts) - 2 for f in bm.faces)
    bm.free()
    mn, mx = _bbox(obj)
    boyut = mx - mn
    if ucgen_sinir and ucgen > ucgen_sinir:
        sorunlar.append("Üçgen sayısı %d, sınır %d." % (ucgen, ucgen_sinir))
    if obj.location.length > 1e-4:
        sorunlar.append("Nesnenin konumu (0,0,0) olmalı; kökü taban ortasına taşı (şu an %s)." % (tuple(round(v, 3) for v in obj.location),))
    if any(abs(r) > 1e-4 for r in obj.rotation_euler) or any(abs(s - 1.0) > 1e-4 for s in obj.scale):
        sorunlar.append("Dönüş ve ölçek uygulanmamış (Ctrl+A).")
    if abs(mn.z) > 0.01:
        sorunlar.append("Taban z=0'da olmalı (en alt nokta z=%.3f)." % mn.z)
    cx, cy = (mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5
    if abs(cx) > 0.03 + boyut.x * 0.05 or abs(cy) > 0.03 + boyut.y * 0.05:
        sorunlar.append("Kök tabanın ortasında değil (kutu ortası x=%.3f y=%.3f)." % (cx, cy))
    if olcu:
        for ad_e, gercek, hedef in zip(("en (x)", "derinlik (y)", "yükseklik (z)"), boyut, olcu):
            if hedef and abs(gercek - hedef) > hedef * tolerans:
                sorunlar.append("%s %.2f m, hedef %.2f m." % (ad_e, gercek, hedef))
    if me.color_attributes.get(RENK_ATTR) is None:
        sorunlar.append("Köşe rengi '%s' yok: renk() / renk_yuz() ile boya." % RENK_ATTR)
    for mat in me.materials:
        if mat and mat.use_nodes and any(n.type == 'TEX_IMAGE' for n in mat.node_tree.nodes):
            sorunlar.append("Malzemede resim dokusu var ('%s'); doku kullanma, köşe rengiyle boya." % mat.name)
    # Ters dönmüş yüzler: normaller dışa bakmalı (kabaca: ortadan dışa)
    ters = 0
    merkez = (mn + mx) * 0.5
    for poly in me.polygons:
        c = obj.matrix_world @ poly.center
        n = obj.matrix_world.to_3x3() @ poly.normal
        if (c - merkez).length > 0.05 and n.dot(c - merkez) < -0.5 * (c - merkez).length:
            ters += 1
    if ters > len(me.polygons) * 0.25:
        sorunlar.append("Yüzlerin çoğu içe bakıyor olabilir (%d / %d); normalleri düzelt (Shift+N)." % (ters, len(me.polygons)))
    return {"gecti": not sorunlar, "sorunlar": sorunlar, "ucgen": ucgen,
            "boyut_m": tuple(round(v, 3) for v in boyut)}


def _kamera(ad, yon, yukari, uzaklik_k=1.0, lens=50.0):
    obj = bpy.data.objects[ad]
    mn, mx = _bbox(obj)
    merkez = (mn + mx) * 0.5
    r = max((mx - mn).length * 0.5, 0.2)
    cam_data = bpy.data.cameras.new("onizleme")
    cam_data.lens = lens
    cam = bpy.data.objects.new("onizleme", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    d = Vector(yon).normalized()
    uzak = r / math.tan(cam_data.angle * 0.5) * 1.15 * uzaklik_k
    cam.location = merkez + d * uzak + Vector((0, 0, yukari))
    cam.rotation_euler = (merkez - cam.location).to_track_quat('-Z', 'Y').to_euler()
    return cam


def _render(ad, cam, yol):
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'VERTEX'
    sc.display.shading.show_object_outline = False
    sc.display.shading.background_type = 'VIEWPORT'
    sc.display.shading.background_color = (0.78, 0.86, 0.95)
    sc.render.resolution_x = 768
    sc.render.resolution_y = 768
    sc.render.film_transparent = False
    sc.render.filepath = yol
    bpy.ops.render.render(write_still=True)


def disa_aktar(ad):
    """GLB ve önizlemeler: cikti/<ad>/<ad>.glb, onizleme_on/yan/ust/oyun.png. Önce kontrol() geçmeli."""
    r = kontrol(ad)
    if not r["gecti"]:
        raise RuntimeError("Kontrol geçmedi: " + " | ".join(r["sorunlar"]))
    klasor = os.path.join(CIKTI, ad)
    os.makedirs(klasor, exist_ok=True)
    obj = bpy.data.objects[ad]
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    glb = os.path.join(klasor, ad + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=glb,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_vertex_color='ACTIVE',
    )
    # Önizlemeler: önden (3/4), yandan, üstten ve oyun kamerası (göz hizası, birkaç metre uzaktan)
    goruntuler = {
        "on": ((0.55, -1.0, 0.35), 0.0, 1.0, 50.0),
        "yan": ((1.0, 0.0, 0.1), 0.0, 1.0, 50.0),
        "ust": ((0.3, -0.4, 1.0), 0.0, 1.0, 50.0),
    }
    for isim, (yon, yukari, k, lens) in goruntuler.items():
        cam = _kamera(ad, yon, yukari, k, lens)
        _render(ad, cam, os.path.join(klasor, "onizleme_%s.png" % isim))
        bpy.data.objects.remove(cam, do_unlink=True)
    # Oyun kamerası: 1,6 m göz hizası, nesneden ~4 m uzakta, hafif yukarıdan
    mn, mx = _bbox(obj)
    cam_data = bpy.data.cameras.new("oyun")
    cam_data.lens = 24.0
    cam = bpy.data.objects.new("oyun", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    hedef = Vector((0, 0, (mx.z - mn.z) * 0.45))
    cam.location = Vector((2.2, -3.4, 1.6)) * max(1.0, (mx.z - mn.z) / 1.5)
    cam.rotation_euler = (hedef - cam.location).to_track_quat('-Z', 'Y').to_euler()
    _render(ad, cam, os.path.join(klasor, "onizleme_oyun.png"))
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.ops.wm.save_mainfile()
    return {"glb": glb, "klasor": klasor, "ucgen": r["ucgen"], "boyut_m": r["boyut_m"]}
