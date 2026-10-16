"""Oyunun arabaları: kompakt hatchback, dolmuş (minibüs) ve kamyonet. Her biri ayrı .glb.

  blender --background --factory-startup --python tools/blender/araba_build.py -- <cikti_klasoru> [onizleme_klasoru]

Gövde, kesitlerden örülür (loft): her kesit aracın o noktadaki enine profili (taban, bel
çizgisi, tavan). Camlar aynı yüzeyin bel çizgisi üstündeki parçaları; direkler (A/B/C)
kesit bantlarıyla ayrılır. Tekerlekler ayrı düğümler (Godot döndürür, ön tekerlekler direksiyonla
yön alır). "Koltuk" ve "Direksiyon" boş düğümleri sürücünün kalçası ve direksiyon merkezi.

Malzeme adları renk yuvaları: govde (Godot boyar), serit (ikinci renk), cam, lastik, jant,
tampon, far, stop (fren yakınca parlar), sinyal, plaka, ic, koltuk, direksiyon, kasa.
Araç -Y'ye bakar (karakterlerle aynı); solu +X. Sürücü solda (sağdan trafik).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_ortak as O  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(args[0]) if args else os.path.join(HERE, "..", "..", "assets", "araba")
PREVIEW_DIR = os.path.abspath(args[1]) if len(args) > 1 else None

COLORS = {
    "govde": (0.8, 0.2, 0.15), "serit": (0.1, 0.1, 0.1), "cam": (0.16, 0.22, 0.28),
    "lastik": (0.07, 0.07, 0.08), "jant": (0.72, 0.72, 0.7), "tampon": (0.2, 0.2, 0.21),
    "far": (1.0, 0.96, 0.82), "stop": (0.55, 0.06, 0.05), "sinyal": (1.0, 0.55, 0.1),
    "plaka": (0.95, 0.95, 0.92), "ic": (0.12, 0.12, 0.13), "koltuk": (0.3, 0.22, 0.17),
    "direksiyon": (0.08, 0.08, 0.08), "kasa": (0.25, 0.22, 0.2), "krom": (0.82, 0.82, 0.84),
}


def mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        c = COLORS[name]
        m.diffuse_color = (*c, 1.0)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*c, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.6
    return m


def new_obj(name, bm, mats, parent=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(mat(m))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    for p in me.polygons:
        p.use_smooth = False
    return ob


# ---------------------------------------------------------------------------
# Kesitlerden gövde
# ---------------------------------------------------------------------------
def half_profile(w, zb, zbelt, wc, ztop, r=0.1):
    """Enine yarım profil (x >= 0), alttan üste: taban ortası .. tavan ortası."""
    return [
        (0.0, zb), (w - r * 0.6, zb), (w, zb + r), (w, zbelt),
        (wc, ztop - min(0.06, (ztop - zbelt) * 0.3)), (wc - r * 0.8, ztop), (0.0, ztop),
    ]


def loft(sections, face_mat):
    """sections: [(y, yarım profil)]. face_mat(yi, seg, center) -> malzeme indeksi.
    seg: profil parçası (0 taban, 1 alt köşe, 2 yan alt, 3 yan (bel->üst), 4 üst köşe, 5 tavan)."""
    bm = bmesh.new()
    rings = []
    for y, hp in sections:
        pts = hp + [(-x, z) for x, z in reversed(hp[1:-1])]
        rings.append([bm.verts.new((x, y, z)) for x, z in pts])
    n = len(rings[0])
    half = len(sections[0][1])
    for i in range(len(rings) - 1):
        for k in range(n):
            a, b = rings[i][k], rings[i][(k + 1) % n]
            c, d = rings[i + 1][(k + 1) % n], rings[i + 1][k]
            f = bm.faces.new((a, b, c, d))
            seg = k if k < half - 1 else n - 1 - k
            f.material_index = face_mat(i, seg, f.calc_center_median())
    # Uç kapakları
    for ring, rev in ((rings[0], False), (rings[-1], True)):
        f = bm.faces.new(list(reversed(ring)) if rev else ring)
        f.material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def box(bm, c, s, mi=0):
    r = bmesh.ops.create_cube(bm, size=1.0)
    for v in r["verts"]:
        v.co = Vector((c[0] + v.co.x * s[0], c[1] + v.co.y * s[1], c[2] + v.co.z * s[2]))
    for f in bm.faces:
        if f.verts[0] in r["verts"]:
            f.material_index = mi
    return r["verts"]


def cyl(bm, c, r, depth, axis="x", seg=12, mi=0, cap_mi=None):
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=depth)
    vs = res["verts"]
    for v in vs:
        x, y, z = v.co
        if axis == "x":
            v.co = Vector((c[0] + z, c[1] + x, c[2] + y))
        elif axis == "y":
            v.co = Vector((c[0] + x, c[1] + z, c[2] + y))
        else:
            v.co = Vector((c[0] + x, c[1] + y, c[2] + z))
    vset = set(vs)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            big = len(f.verts) > 4
            f.material_index = cap_mi if (big and cap_mi is not None) else mi
    return vs


def wheel(name, c, r, width, parent):
    """Lastik + jant + bijon; Godot döndürür (yerel X ekseni etrafında)."""
    bm = bmesh.new()
    cyl(bm, (0, 0, 0), r, width, "x", 14, 0, 0)
    side = 1 if c[0] > 0 else -1
    cyl(bm, (side * width * 0.32, 0, 0), r * 0.62, width * 0.45, "x", 10, 1, 1)
    cyl(bm, (side * width * 0.52, 0, 0), r * 0.18, width * 0.12, "x", 6, 2, 2)
    ob = new_obj(name, bm, ["lastik", "jant", "tampon"], parent)
    ob.location = c
    return ob


def lights_front(bm, y, z, xs, r, round_lamps=True):
    for x in xs:
        if round_lamps:
            cyl(bm, (x, y - 0.012, z), r, 0.04, "y", 10, 0)
        else:
            box(bm, (x, y - 0.012, z), (r * 2.2, 0.04, r * 1.2), 0)


def empty(name, loc, parent):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    e.parent = parent
    bpy.context.scene.collection.objects.link(e)
    return e


def interior(root, seat, wheel_c, floor_z, width, y0, y1):
    """Taban, koltuklar, direksiyon (sürücü solda, +X)."""
    bm = bmesh.new()
    box(bm, (0, (y0 + y1) / 2, floor_z), (width * 1.9, y1 - y0, 0.04), 0)
    for x in (seat[0], -seat[0]):
        box(bm, (x, seat[1] + 0.05, seat[2] - 0.08), (0.46, 0.46, 0.12), 1)
        box(bm, (x, seat[1] + 0.3, seat[2] + 0.25), (0.46, 0.1, 0.62), 1)
    # Gösterge paneli
    box(bm, (0, wheel_c[1] - 0.25, wheel_c[2] - 0.12), (width * 1.85, 0.3, 0.16), 0)
    ob = new_obj("Ic", bm, ["ic", "koltuk"], root)
    bm = bmesh.new()
    res = bmesh.ops.create_circle(bm, cap_ends=False, segments=12, radius=0.17)
    ring = res["verts"]
    bmesh.ops.extrude_edge_only(bm, edges=bm.edges[:])
    for i, v in enumerate(bm.verts):
        v.co.z += 0.03 if v not in ring else 0.0
    bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.04, radius2=0.025, depth=0.25)
    for v in bm.verts:
        v.co = Vector((v.co.x, v.co.z * 0.5 + (0.12 if v not in ring else 0.0), v.co.y))
    w = new_obj("Direksiyon", bm, ["direksiyon"], root)
    w.location = wheel_c
    w.rotation_euler = (math.radians(-25), 0, 0)
    empty("Koltuk", seat, root)
    empty("DireksiyonMerkez", wheel_c, root)
    return ob


# ---------------------------------------------------------------------------
# 1) Kompakt hatchback: yuvarlak hatlı, kısa burunlu, büyük camlı 80'ler şehir arabası
# ---------------------------------------------------------------------------
def build_hatchback():
    root = empty("Hatchback", (0, 0, 0), None)
    W = 0.8
    S = [
        (-1.86, half_profile(0.74, 0.3, 0.6, 0.7, 0.66, 0.09)),
        (-1.8, half_profile(W, 0.24, 0.72, 0.78, 0.76, 0.1)),
        (-1.62, half_profile(W, 0.22, 0.78, 0.79, 0.82, 0.1)),
        (-1.08, half_profile(W, 0.22, 0.83, 0.77, 0.88, 0.1)),     # cam altı
        (-0.98, half_profile(W, 0.22, 0.84, 0.75, 0.97, 0.1)),     # A direği
        (-0.42, half_profile(W, 0.22, 0.86, 0.66, 1.37, 0.12)),    # tavan başı
        (0.0, half_profile(W, 0.22, 0.86, 0.66, 1.39, 0.12)),
        (0.1, half_profile(W, 0.22, 0.86, 0.66, 1.39, 0.12)),      # B direği
        (0.86, half_profile(W, 0.22, 0.86, 0.66, 1.37, 0.12)),     # tavan sonu
        (0.98, half_profile(W, 0.22, 0.86, 0.67, 1.33, 0.12)),     # C direği
        (1.7, half_profile(W, 0.23, 0.86, 0.72, 0.98, 0.1)),       # bagaj camı altı
        (1.84, half_profile(0.78, 0.27, 0.82, 0.74, 0.9, 0.09)),
    ]
    # Bant i: kesit i -> i+1. 4 ön cam (eğik), 5 ön yan cam, 6 B direği, 7 arka yan cam,
    # 8 C direği, 9 bagaj camı (yanları kalın C direği)
    def fm(i, seg, c):
        if seg < 3:
            return 0
        if i == 4:
            return 1
        if i in (5, 7):
            return 1 if seg == 3 else 0
        if i == 9:
            return 1 if seg in (4, 5) else 0
        return 0

    body = new_obj("Govde", loft(S, fm), ["govde", "cam"], root)
    bm = bmesh.new()
    box(bm, (0, -1.9, 0.36), (1.62, 0.12, 0.16), 0)            # ön tampon
    box(bm, (0, 1.88, 0.36), (1.6, 0.12, 0.16), 0)             # arka tampon
    box(bm, (0, -1.87, 0.6), (0.7, 0.03, 0.14), 0)             # ızgara
    box(bm, (0, -1.97, 0.37), (0.42, 0.02, 0.11), 1)           # plaka
    box(bm, (0, 1.95, 0.37), (0.42, 0.02, 0.11), 1)
    for x in (0.81, -0.81):
        box(bm, (x * 1.0 + 0.02 * (1 if x > 0 else -1), -0.88, 0.95), (0.06, 0.12, 0.08), 0)   # ayna
        box(bm, (x * 1.003, 0.0, 0.52), (0.012, 2.6, 0.05), 2)                                # yan şerit
    new_obj("Tampon", bm, ["tampon", "plaka", "serit"], root)
    bm = bmesh.new()
    lights_front(bm, -1.87, 0.62, (0.52, -0.52), 0.1, True)
    new_obj("Far", bm, ["far"], root)
    bm = bmesh.new()
    for x in (0.6, -0.6):
        box(bm, (x, 1.86, 0.66), (0.24, 0.04, 0.14), 0)
    new_obj("Stop", bm, ["stop"], root)
    for nm, c in (("Teker_OnSol", (0.74, -1.18, 0.29)), ("Teker_OnSag", (-0.74, -1.18, 0.29)),
                  ("Teker_ArkaSol", (0.74, 1.2, 0.29)), ("Teker_ArkaSag", (-0.74, 1.2, 0.29))):
        wheel(nm, c, 0.29, 0.2, root)
    interior(root, (0.36, 0.25, 0.48), (0.36, -0.38, 0.92), 0.3, W, -1.0, 1.6)
    return root, body


# ---------------------------------------------------------------------------
# 2) Dolmuş: kutu gibi, kısa burunlu, yanda sıra sıra cam, tavanda tabela kutusu, şeritli
# ---------------------------------------------------------------------------
def build_minibus():
    root = empty("Minibus", (0, 0, 0), None)
    W = 0.95
    S = [
        (-2.5, half_profile(0.9, 0.34, 0.8, 0.88, 0.96, 0.1)),
        (-2.44, half_profile(W, 0.3, 0.9, 0.92, 1.04, 0.1)),
        (-2.05, half_profile(W, 0.3, 1.04, 0.92, 1.12, 0.1)),      # cam altı
        (-1.98, half_profile(W, 0.3, 1.06, 0.9, 1.25, 0.1)),       # A direği
        (-1.55, half_profile(W, 0.3, 1.1, 0.88, 2.1, 0.12)),       # tavan başı
    ]
    ys = [-1.4, -0.75, -0.68, -0.02, 0.05, 0.72, 0.79, 1.46, 1.53, 2.38]
    for y in ys:
        S.append((y, half_profile(W, 0.3, 1.1, 0.88, 2.12, 0.12)))
    S.append((2.5, half_profile(W, 0.32, 1.06, 0.87, 2.08, 0.1)))
    # Camlı bantlar: ön cam (2, 3), yan camlar (direkler arası)
    side_glass = {5, 7, 9, 11}

    def fm(i, seg, c):
        if i in (2, 3) and seg >= 3:
            return 1
        if i == 4 and seg == 3:
            return 1                          # sürücü yan camı
        if i in side_glass and seg == 3 and 1.18 < c.z < 1.95:
            return 1
        if i == len(S) - 2 and seg >= 3 and c.z < 1.95:
            return 1 if abs(c.x) < 0.7 else 0  # arka cam
        return 0

    body = new_obj("Govde", loft(S, fm), ["govde", "cam"], root)
    bm = bmesh.new()
    box(bm, (0, -2.55, 0.42), (1.92, 0.14, 0.2), 0)
    box(bm, (0, 2.55, 0.42), (1.9, 0.14, 0.2), 0)
    box(bm, (0, -2.53, 0.72), (1.0, 0.03, 0.2), 0)              # ızgara
    box(bm, (0, -2.63, 0.42), (0.46, 0.02, 0.12), 1)
    box(bm, (0, 2.63, 0.42), (0.46, 0.02, 0.12), 1)
    box(bm, (0, -0.9, 2.2), (0.9, 0.3, 0.16), 3)                # tavan tabelası (dolmuş)
    for x in (W + 0.006, -W - 0.006):
        box(bm, (x, 0.0, 0.98), (0.012, 4.9, 0.12), 3)          # yan şerit
    box(bm, (0, 1.0, 2.15), (1.5, 2.2, 0.05), 0)                # port bagaj tabanı
    for x in (0.75, -0.75):
        box(bm, (x, 1.0, 2.24), (0.04, 2.2, 0.04), 0)
    for x in (0.97, -0.97):
        box(bm, (x + 0.04 * (1 if x > 0 else -1), -1.85, 1.3), (0.06, 0.14, 0.12), 0)
    new_obj("Tampon", bm, ["tampon", "plaka", "krom", "serit"], root)
    bm = bmesh.new()
    lights_front(bm, -2.53, 0.78, (0.66, -0.66), 0.12, False)
    new_obj("Far", bm, ["far"], root)
    bm = bmesh.new()
    for x in (0.8, -0.8):
        box(bm, (x, 2.52, 0.95), (0.14, 0.04, 0.4), 0)
    new_obj("Stop", bm, ["stop"], root)
    for nm, c in (("Teker_OnSol", (0.86, -1.72, 0.33)), ("Teker_OnSag", (-0.86, -1.72, 0.33)),
                  ("Teker_ArkaSol", (0.86, 1.62, 0.33)), ("Teker_ArkaSag", (-0.86, 1.62, 0.33))):
        wheel(nm, c, 0.33, 0.22, root)
    interior(root, (0.45, -1.35, 0.72), (0.45, -1.95, 1.2), 0.42, W, -2.2, 2.3)
    return root, body


# ---------------------------------------------------------------------------
# 3) Kamyonet: uzun burun, tek sıra kabin, arkası açık kasa (kenarları grind yüzeyi olabilir)
# ---------------------------------------------------------------------------
def build_pickup():
    root = empty("Kamyonet", (0, 0, 0), None)
    W = 0.88
    S = [
        (-2.36, half_profile(0.84, 0.34, 0.78, 0.82, 0.84, 0.08)),
        (-2.3, half_profile(W, 0.3, 0.86, 0.86, 0.92, 0.08)),
        (-1.0, half_profile(W, 0.3, 0.98, 0.84, 1.04, 0.08)),       # cam altı
        (-0.92, half_profile(W, 0.3, 1.0, 0.82, 1.14, 0.08)),       # A direği
        (-0.45, half_profile(W, 0.3, 1.02, 0.76, 1.72, 0.1)),       # tavan başı
        (0.25, half_profile(W, 0.3, 1.02, 0.76, 1.72, 0.1)),
        (0.36, half_profile(W, 0.3, 1.02, 0.78, 1.66, 0.1)),        # kabin arkası
    ]

    def fm(i, seg, c):
        if i in (2, 3) and seg >= 3:
            return 1
        if i == 4 and seg == 3:
            return 1
        return 0

    body = new_obj("Govde", loft(S, fm), ["govde", "cam"], root)
    # Kasa: taban, iki yan, ön duvar, kapak (dış: gövde rengi, iç: kasa rengi)
    bm = bmesh.new()
    y0, y1, zf, zt = 0.4, 2.36, 0.72, 1.18
    box(bm, (0, (y0 + y1) / 2, zf - 0.2), (W * 2, y1 - y0, 0.4), 0)
    for x in (W - 0.04, -(W - 0.04)):
        box(bm, (x, (y0 + y1) / 2, (zf + zt) / 2), (0.08, y1 - y0, zt - zf), 0)
    box(bm, (0, y1 - 0.04, (zf + zt) / 2), (W * 2, 0.08, zt - zf), 0)
    box(bm, (0, (y0 + y1) / 2, zf + 0.005), (W * 2 - 0.16, y1 - y0 - 0.1, 0.01), 1)
    new_obj("Kasa", bm, ["govde", "kasa"], root)
    bm = bmesh.new()
    box(bm, (0, -2.42, 0.42), (1.8, 0.14, 0.18), 1)
    box(bm, (0, 2.44, 0.42), (1.78, 0.12, 0.16), 0)
    box(bm, (0, -2.39, 0.66), (1.0, 0.03, 0.18), 1)
    box(bm, (0, -2.5, 0.42), (0.44, 0.02, 0.11), 2)
    box(bm, (0, 2.51, 0.42), (0.44, 0.02, 0.11), 2)
    for x in (0.9, -0.9):
        box(bm, (x + 0.04 * (1 if x > 0 else -1), -0.75, 1.16), (0.06, 0.13, 0.1), 0)
    new_obj("Tampon", bm, ["tampon", "krom", "plaka"], root)
    bm = bmesh.new()
    lights_front(bm, -2.39, 0.68, (0.62, -0.62), 0.11, True)
    new_obj("Far", bm, ["far"], root)
    bm = bmesh.new()
    for x in (0.78, -0.78):
        box(bm, (x, 2.41, 0.9), (0.18, 0.04, 0.2), 0)
    new_obj("Stop", bm, ["stop"], root)
    for nm, c in (("Teker_OnSol", (0.8, -1.55, 0.33)), ("Teker_OnSag", (-0.8, -1.55, 0.33)),
                  ("Teker_ArkaSol", (0.8, 1.5, 0.33)), ("Teker_ArkaSag", (-0.8, 1.5, 0.33))):
        wheel(nm, c, 0.33, 0.22, root)
    interior(root, (0.4, -0.05, 0.66), (0.4, -0.66, 1.08), 0.4, W, -0.9, 0.34)
    return root, body


BUILDERS = {"hatchback": build_hatchback, "minibus": build_minibus, "kamyonet": build_pickup}


def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


def export(root, path):
    bpy.ops.object.select_all(action='DESELECT')
    stack = [root]
    while stack:
        o = stack.pop()
        o.select_set(True)
        stack.extend(o.children)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_animations=False)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    shots = []
    for name, fn in BUILDERS.items():
        clear()
        root, body = fn()
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == 'MESH')
        export(root, os.path.join(OUT_DIR, f"{name}.glb"))
        print("ARABA", name, "UCGEN", tris)
        if PREVIEW_DIR:
            os.makedirs(os.path.join(PREVIEW_DIR, "_tmp"), exist_ok=True)
            for ang in (-35, -100, 150):
                shots.append(O.render_view(os.path.join(PREVIEW_DIR, "_tmp", f"{name}{ang}.png"), 1.0, 4.2, ang,
                                           dist=14.0, elev_deg=18.0, res=(460, 300)))
    if PREVIEW_DIR:
        O.stitch(shots, os.path.join(PREVIEW_DIR, "arabalar.png"), cols=3)


main()
