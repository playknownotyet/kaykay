"""Ana karakter (kaykaycı çocuk) + kaykay modelini koddan üretir.

Referans: assets/reference/karakter_referans.webp
Stil: köşeli low-poly yüzeyler (düz gölgeleme), düz renkler, kalın kıvırcık saç,
kırmızı bol tişört, bol mavi kot, siyah-beyaz kaykay ayakkabısı, sarı sırt çantası.

Çalıştırma (Blender arka planda):
  blender --background --factory-startup --python tools/blender/karakter_model.py -- art/karakter/karakter.blend

Koordinatlar: metre, Z yukarı, karakter -Y yönüne bakar (Blender önden görünüm),
karakterin sol tarafı +X. Ayak tabanı z = 0.
"""
import math
import random
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


# ---------------------------------------------------------------------------
# Renk paleti (sRGB, referanstan)
# ---------------------------------------------------------------------------
PALETTE = {
    "sac": (0.07, 0.065, 0.075),
    "ten": (0.95, 0.79, 0.65),
    "ten_koyu": (0.86, 0.67, 0.53),
    "tisort": (0.66, 0.13, 0.15),
    "kot": (0.24, 0.36, 0.62),
    "canta": (0.86, 0.69, 0.20),
    "siyah": (0.09, 0.09, 0.10),
    "beyaz": (0.92, 0.91, 0.88),
    "goz": (0.08, 0.06, 0.06),
    "agiz": (0.38, 0.16, 0.13),
    "grip": (0.12, 0.12, 0.13),
    "tahta": (0.85, 0.30, 0.20),
    "metal": (0.55, 0.56, 0.60),
    "teker": (0.95, 0.90, 0.75),
}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


_materials = {}


def material(name):
    if name in _materials:
        return _materials[name]
    srgb = PALETTE[name]
    lin = tuple(srgb_to_linear(c) for c in srgb)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*lin, 1.0)
    if mat.node_tree is None:
        try:
            mat.use_nodes = True
        except Exception:
            pass
    if mat.node_tree:
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.85
    _materials[name] = mat
    return mat


# ---------------------------------------------------------------------------
# Geometri yardımcıları
# ---------------------------------------------------------------------------
rng = random.Random(7)


def ring_basis(axis):
    axis = axis.normalized()
    ref = Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))
    u = ref.cross(axis).normalized()
    v = axis.cross(u).normalized()
    return u, v


def loft(bm, rings, segs, cap_start=True, cap_end=True, jitter=0.0, phase=0.0):
    """Halkalardan tüp örer. ring = (merkez, eksen, rx, ry)."""
    ring_verts = []
    for (c, axis, rx, ry) in rings:
        u, v = ring_basis(axis)
        vs = []
        for i in range(segs):
            t = phase + math.tau * i / segs
            p = c + u * (math.cos(t) * rx) + v * (math.sin(t) * ry)
            if jitter > 0:
                p += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * jitter * max(rx, ry)
            vs.append(bm.verts.new(p))
        ring_verts.append(vs)
    faces = []
    for a, b in zip(ring_verts[:-1], ring_verts[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            faces.append(bm.faces.new((a[i], a[j], b[j], b[i])))
    if cap_start:
        faces.append(bm.faces.new(list(reversed(ring_verts[0]))))
    if cap_end:
        faces.append(bm.faces.new(ring_verts[-1]))
    return faces


def make_object(name, build, mat_name, parent=None, face_mat=None):
    """build(bm) bmesh'e geometri ekler. face_mat(normal) -> 'malzeme' verilirse
    yüzler normaline göre ikinci malzemeye atanır (örn. kaykayın üst yüzü)."""
    bm = bmesh.new()
    build(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(material(mat_name))
    if face_mat:
        names = [mat_name]
        for poly in mesh.polygons:
            m = face_mat(poly.normal) or mat_name
            if m not in names:
                names.append(m)
                obj.data.materials.append(material(m))
            poly.material_index = names.index(m)
    bpy.context.collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj


def box(bm, center, size, bevel=0.0):
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    for v in verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + center
    if bevel > 0:
        edges = list({e for v in verts for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect='EDGES', profile=0.5)
    return verts


def ribbon(bm, points, width, thickness, up_hint=Vector((0, 0, 1))):
    """Bir yol boyunca yassı şerit (çanta askısı vb.)."""
    rings = []
    for i, p in enumerate(points):
        a = points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]
        rings.append((p, a.normalized(), width * 0.5, thickness * 0.5))
    loft(bm, rings, 4, phase=math.pi / 4)


def cone(bm, base, tip, radius, sides=5, bend=Vector(), twist=0.0):
    """Saç tutamı: tabandan uca, ortadan bükülen köşeli koni."""
    axis = (tip - base)
    mid = base + axis * 0.5 + bend
    rings = [
        (base, axis, radius, radius * 0.85),
        (mid, (tip - base), radius * 0.62, radius * 0.5),
    ]
    vs = []
    u, v = ring_basis(axis)
    ring_verts = []
    for (c, ax, rx, ry) in rings:
        uu, vv = ring_basis(ax)
        ring = []
        for i in range(sides):
            t = twist + math.tau * i / sides
            ring.append(bm.verts.new(c + uu * math.cos(t) * rx + vv * math.sin(t) * ry))
        ring_verts.append(ring)
    tip_v = bm.verts.new(tip)
    a, b = ring_verts
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((a[i], a[j], b[j], b[i]))
        bm.faces.new((b[i], b[j], tip_v))
    bm.faces.new(list(reversed(a)))


# ---------------------------------------------------------------------------
# Ölçüler
# ---------------------------------------------------------------------------
HEAD_C = Vector((0, 0, 1.29))
HEAD_S = Vector((0.105, 0.112, 0.132))
SHOULDER = 0.165
ARM_DIR_L = Vector((math.sin(math.radians(40)), 0, -math.cos(math.radians(40))))
UPPER_ARM = 0.25
FOREARM = 0.22
HAND = 0.085
FOOT_X = 0.11


def arm_points(side):
    d = Vector((ARM_DIR_L.x * side, 0, ARM_DIR_L.z))
    shoulder = Vector((SHOULDER * side, 0.0, 1.075))
    elbow = shoulder + d * UPPER_ARM
    wrist = elbow + d * FOREARM
    hand = wrist + d * HAND
    return shoulder, elbow, wrist, hand, d


# ---------------------------------------------------------------------------
# Parçalar
# ---------------------------------------------------------------------------
def build_head(bm):
    res = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=8, radius=1.0)
    for v in res["verts"]:
        x, y, z = v.co
        # Çene: alt yarıda daralt, hafif öne çıkar
        if z < 0:
            k = 1.0 - 0.32 * (-z) ** 1.3
            x *= k
            y *= k
            y -= 0.08 * (-z)
        # Arka kafa biraz dolgun
        if y > 0:
            y *= 1.05
        v.co = Vector((x * HEAD_S.x, y * HEAD_S.y, z * HEAD_S.z)) + HEAD_C
    # Kulaklar
    for side in (-1, 1):
        box(bm, HEAD_C + Vector((side * 0.103, 0.01, -0.01)), (0.025, 0.04, 0.05), bevel=0.008)


def head_bvh():
    bm = bmesh.new()
    build_head(bm)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return tree


def face_point(tree, x, z):
    hit = tree.ray_cast(Vector((x, -0.6, z)), Vector((0, 1, 0)))
    return hit[0], hit[1]


def flat_feature(bm, tree, x, z, w, h, depth=0.006, sides=6, tilt=0.0, offset=0.0015):
    """Yüze yapışık yassı oval parça (göz, kaş vb.)."""
    p, n = face_point(tree, x, z)
    n = n.normalized()
    up = Vector((0, 0, 1))
    right = up.cross(n).normalized()
    up = n.cross(right).normalized()
    ca, sa = math.cos(tilt), math.sin(tilt)
    r2 = right * ca + up * sa
    u2 = up * ca - right * sa
    front, back = [], []
    for i in range(sides):
        t = math.tau * i / sides
        q = p + r2 * math.cos(t) * w * 0.5 + u2 * math.sin(t) * h * 0.5
        front.append(bm.verts.new(q + n * (offset + depth * 0.5)))
        back.append(bm.verts.new(q - n * depth))
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((back[i], back[j], front[j], front[i]))


def build_eyes(bm, tree):
    for side in (-1, 1):
        flat_feature(bm, tree, side * 0.041, 1.283, 0.034, 0.042, sides=7)
        # Üst göz kapağı çizgisi
        flat_feature(bm, tree, side * 0.043, 1.305, 0.046, 0.012, sides=4, tilt=side * -0.12, offset=0.003)


def build_eye_highlights(bm, tree):
    for side in (-1, 1):
        flat_feature(bm, tree, side * 0.036, 1.29, 0.011, 0.012, sides=5, offset=0.006)


def build_brows(bm, tree):
    for side in (-1, 1):
        flat_feature(bm, tree, side * 0.046, 1.332, 0.05, 0.013, sides=4, tilt=side * -0.08, offset=0.004)


def build_mouth(bm, tree):
    # Hafif gülümseme: üç küçük parça
    for x, z, tilt in ((-0.0105, 1.2125, -0.28), (0.0105, 1.2125, 0.28)):
        flat_feature(bm, tree, x, z, 0.023, 0.0035, depth=0.002, sides=4, tilt=tilt, offset=0.0008)


def build_nose(bm, tree):
    p, n = face_point(tree, 0.0, 1.252)
    a = bm.verts.new(p + Vector((-0.011, 0.004, 0.0)))
    b = bm.verts.new(p + Vector((0.011, 0.004, 0.0)))
    c = bm.verts.new(p + Vector((0.0, -0.016, -0.004)))
    d = bm.verts.new(p + Vector((0.0, 0.006, 0.03)))
    bm.faces.new((a, c, b))
    bm.faces.new((a, d, c))
    bm.faces.new((b, c, d))
    bm.faces.new((a, b, d))


def build_neck(bm):
    loft(bm, [
        (Vector((0, 0.008, 1.10)), Vector((0, 0, 1)), 0.048, 0.044),
        (Vector((0, 0.012, 1.19)), Vector((0, 0, 1)), 0.043, 0.04),
    ], 8)


def build_hair(bm):
    """Dolgun, kıvırcık, aşağı dökülen saç: kafatası tabanı + katmanlı kalın tutamlar."""
    cap_c = HEAD_C + Vector((0, 0.01, 0.015))
    cap_s = Vector((0.12, 0.13, 0.134))
    res = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=1.0)
    kill = []
    for v in res["verts"]:
        x, y, z = v.co
        # Önde alın çizgisi yüksek, yanlarda kulak hizası, arkada enseye iner
        cut = 0.25 * max(-y, 0) ** 0.7 - 0.6 * max(y, 0) - 0.15
        if z < cut:
            kill.append(v)
            continue
        v.co = Vector((x * cap_s.x, y * cap_s.y, z * cap_s.z)) + cap_c
    bmesh.ops.delete(bm, geom=kill, context='VERTS')

    def surface(ang, elev):
        d = Vector((math.cos(ang) * math.cos(elev), math.sin(ang) * math.cos(elev), math.sin(elev)))
        p = cap_c + Vector((d.x * cap_s.x, d.y * cap_s.y, d.z * cap_s.z)) * 0.93
        n = Vector((d.x / cap_s.x, d.y / cap_s.y, d.z / cap_s.z)).normalized()
        return p, n

    # (yükseklik açısı, tutam sayısı, uzunluk, kalınlık, aşağı sarkma)
    layers = [
        (80, 5, 0.03, 0.055, 0.6),
        (58, 11, 0.05, 0.055, 0.7),
        (34, 14, 0.075, 0.052, 0.85),
        (10, 15, 0.085, 0.05, 1.2),
        (-14, 13, 0.08, 0.047, 1.5),
        (-34, 9, 0.065, 0.042, 1.8),
    ]
    for li, (elev_deg, count, length, radius, droop) in enumerate(layers):
        elev = math.radians(elev_deg)
        for i in range(count):
            ang = math.tau * (i + 0.5 * (li % 2)) / count + rng.uniform(-0.12, 0.12)
            # 'ang' 0 = +X (karakterin solu), -pi/2 = -Y (yüz). Alçak katmanlarda yüzü boş bırak.
            face = -math.sin(ang)  # 1 = tam önde
            if elev_deg <= 34 and face > 0.55:
                continue
            if elev_deg < 0 and face > 0.25:
                continue
            p, n = surface(ang, elev)
            tip_dir = (n + Vector((0, 0, -droop))).normalized()
            L = length * rng.uniform(0.85, 1.2)
            tip = p + tip_dir * L
            side = n.cross(Vector((0, 0, 1)))
            if side.length > 0.01:
                side.normalize()
            bend = n * L * 0.35 + side * rng.uniform(-0.02, 0.02)
            cone(bm, p, tip, radius * rng.uniform(0.85, 1.15), sides=5, bend=bend,
                 twist=rng.uniform(0, math.tau))

    # Ön perçem: ortadan ayrılıp yanlara süpürülen, yüzü çerçeveleyen kıvrımlar
    for side in (-1, 1):
        for k, (x0, z0, x1, z1, r) in enumerate((
            (0.012, 1.41, 0.05, 1.345, 0.034),
            (0.045, 1.40, 0.085, 1.32, 0.036),
            (0.078, 1.37, 0.108, 1.27, 0.034),
            (0.098, 1.32, 0.12, 1.215, 0.032),
        )):
            base = Vector((side * x0, -0.1 + k * 0.014, z0))
            tip = Vector((side * x1, -0.118 + k * 0.024, z1))
            cone(bm, base, tip, r, sides=5, bend=Vector((side * 0.014, -0.014, 0.0)),
                 twist=rng.uniform(0, math.tau))


def build_shirt(bm):
    up = Vector((0, 0, 1))
    loft(bm, [
        # (merkez, eksen, yarı genişlik, yarı derinlik): önden arkaya yassı gövde
        (Vector((0, 0.006, 0.695)), up, 0.172, 0.112),   # etek: hafif bol
        (Vector((0, 0.004, 0.80)), up, 0.162, 0.104),    # bel
        (Vector((0, -0.004, 0.93)), up, 0.168, 0.106),   # göğüs (önde hafif dolgun)
        (Vector((0, 0.0, 1.03)), up, 0.178, 0.1),        # göğüs üstü
        (Vector((0, 0.004, 1.085)), up, 0.168, 0.088),   # omuz hattı
        (Vector((0, 0.006, 1.12)), up, 0.11, 0.072),     # eğimli omuz üstü
        (Vector((0, 0.008, 1.14)), up, 0.062, 0.056),    # yaka
    ], 14, cap_start=False, cap_end=False, jitter=0.015, phase=math.pi / 14)
    # Bol, dirseğe doğru inen kısa kollar (omuzdan düşük dikiş)
    for side in (-1, 1):
        shoulder, elbow, _, _, d = arm_points(side)
        start = shoulder - d * 0.035
        loft(bm, [
            (start, d, 0.066, 0.06),
            (shoulder + d * 0.09, d, 0.07, 0.064),
            (shoulder + d * 0.19, d, 0.072, 0.066),
        ], 8, cap_start=False, cap_end=False, jitter=0.02)


def build_arms(bm):
    for side in (-1, 1):
        shoulder, elbow, wrist, hand_end, d = arm_points(side)
        loft(bm, [
            (shoulder + d * 0.04, d, 0.05, 0.048),     # omuz / kol üstü
            (shoulder + d * 0.15, d, 0.047, 0.046),    # pazı
            (elbow, d, 0.038, 0.037),                   # dirsek
            (elbow + d * 0.06, d, 0.042, 0.038),       # önkol kası
            (wrist, d, 0.029, 0.024),                   # bilek
        ], 8)


def build_hands(bm):
    """Hafif kapalı avuç + başparmak. Avuç içi vücuda bakar, başparmak öne."""
    for side in (-1, 1):
        _, _, wrist, hand_end, d = arm_points(side)
        fwd = Vector((0, -1, 0))
        loft(bm, [
            (wrist - d * 0.004, d, 0.03, 0.022),
            (wrist + d * 0.04, d, 0.038, 0.024),      # avuç
            (wrist + d * 0.075, d, 0.036, 0.021),     # parmak kökü
            (wrist + d * 0.1, d, 0.028, 0.018),       # parmak uçları
        ], 6, phase=math.pi / 6)
        base = wrist + d * 0.025 + fwd * 0.022
        tip = base + d * 0.03 + fwd * 0.018
        cone(bm, base, tip, 0.013, sides=5)


def build_pants(bm):
    up = Vector((0, 0, 1))
    loft(bm, [
        (Vector((0, 0.005, 0.62)), up, 0.145, 0.092),
        (Vector((0, 0.005, 0.72)), up, 0.15, 0.093),
        (Vector((0, 0.005, 0.79)), up, 0.138, 0.088),
    ], 12, cap_start=True, cap_end=True, jitter=0.02)
    for side in (-1, 1):
        x = FOOT_X * side
        loft(bm, [
            (Vector((side * 0.075, 0.005, 0.68)), up, 0.078, 0.09),
            (Vector((side * 0.098, 0.0, 0.45)), up, 0.088, 0.1),
            (Vector((x + side * 0.004, 0.005, 0.22)), up, 0.092, 0.11),
            (Vector((x + side * 0.006, 0.012, 0.14)), up, 0.096, 0.118),
            (Vector((x + side * 0.006, 0.02, 0.105)), up, 0.1, 0.122),
        ], 10, cap_start=True, cap_end=True, jitter=0.06)


SHOE_OUTLINE = [
    (0.0, -0.19), (0.034, -0.18), (0.052, -0.14), (0.057, -0.06), (0.054, 0.03),
    (0.045, 0.075), (0.0, 0.09), (-0.045, 0.075), (-0.054, 0.03), (-0.057, -0.06),
    (-0.052, -0.14), (-0.034, -0.18),
]


def build_soles(bm):
    for side in (-1, 1):
        x0 = FOOT_X * side
        pts = [Vector((x0 + x, y, 0.0)) for (x, y) in SHOE_OUTLINE]
        bot = [bm.verts.new(p) for p in pts]
        top = [bm.verts.new(p + Vector((0, 0, 0.032))) for p in pts]
        bm.faces.new(list(reversed(bot)))
        bm.faces.new(top)
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((bot[i], bot[j], top[j], top[i]))


def build_uppers(bm):
    for side in (-1, 1):
        x0 = FOOT_X * side
        n = len(SHOE_OUTLINE)
        low = [bm.verts.new(Vector((x0 + x * 0.96, y * 0.97, 0.03))) for (x, y) in SHOE_OUTLINE]
        high = []
        for (x, y) in SHOE_OUTLINE:
            # Burun alçak, bilek yüksek
            h = 0.065 if y < -0.07 else 0.1
            k = 0.82 if y < -0.06 else 0.9
            high.append(bm.verts.new(Vector((x0 + x * k, y * 0.95 + (0.01 if y < -0.06 else 0.0), h))))
        bm.faces.new(high)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((low[i], low[j], high[j], high[i]))
        bm.faces.new(list(reversed(low)))


def build_shoe_stripes(bm):
    # Dış yanda beyaz "dalga" çizgisi
    for side in (-1, 1):
        x = FOOT_X * side + side * 0.056
        pts = [Vector((x, -0.1, 0.045)), Vector((x + side * 0.002, -0.03, 0.072)), Vector((x, 0.04, 0.055))]
        ribbon(bm, pts, 0.014, 0.006)


def build_backpack(bm):
    c = Vector((0, 0.18, 0.96))
    verts = box(bm, c, (0.25, 0.11, 0.30), bevel=0.025)
    for v in verts:
        pass
    # Üst kenarı yuvarlat
    for v in bm.verts:
        if (v.co - c).length < 0.3 and v.co.z > c.z + 0.12 and abs(v.co.y - c.y) < 0.07:
            v.co.x *= 0.9


def build_pocket(bm):
    box(bm, Vector((0, 0.254, 0.89)), (0.19, 0.05, 0.13), bevel=0.015)


def build_patch(bm):
    box(bm, Vector((0, 0.282, 0.935)), (0.05, 0.006, 0.022))


def build_straps(bm):
    for side in (-1, 1):
        x = 0.1 * side
        pts = [
            Vector((x * 0.9, 0.14, 1.09)),
            Vector((x, 0.05, 1.135)),
            Vector((x * 1.05, -0.05, 1.12)),
            Vector((x * 1.1, -0.116, 1.03)),
            Vector((x * 1.15, -0.12, 0.92)),
            Vector((x * 1.45, -0.1, 0.85)),
            Vector((x * 1.8, 0.0, 0.83)),
            Vector((x * 1.25, 0.13, 0.84)),
        ]
        ribbon(bm, pts, 0.038, 0.012)
    # Tutma kulpu
    ribbon(bm, [Vector((-0.04, 0.17, 1.12)), Vector((0, 0.17, 1.15)), Vector((0.04, 0.17, 1.12))], 0.02, 0.01)


# ---------------------------------------------------------------------------
# Kaykay (ayrı obje): uzunluk Y boyunca, ucu -Y
# ---------------------------------------------------------------------------
DECK_TOP = 0.09


def deck_outline():
    pts = []
    L, W = 0.40, 0.105
    for i in range(8):
        t = math.pi * i / 7
        pts.append((math.cos(t) * W, -(L - W) - math.sin(t) * W))
    for i in range(8):
        t = math.pi * i / 7
        pts.append((-math.cos(t) * W, (L - W) + math.sin(t) * W))
    return pts


def kick(y):
    return max(abs(y) - 0.27, 0.0) * 0.45


def build_deck(bm):
    """Tek parça tahta; üst yüzleri siyah grip olur (ayrı katman yok, titremez)."""
    pts = deck_outline()
    z0 = DECK_TOP - 0.016
    z1 = DECK_TOP
    bot = [bm.verts.new(Vector((x, y, z0 + kick(y)))) for (x, y) in pts]
    top = [bm.verts.new(Vector((x, y, z1 + kick(y)))) for (x, y) in pts]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((bot[i], bot[j], top[j], top[i]))


def build_trucks(bm):
    for y in (-0.24, 0.24):
        box(bm, Vector((0, y, 0.062)), (0.05, 0.05, 0.022))
        box(bm, Vector((0, y, 0.045)), (0.17, 0.022, 0.018))


def build_wheels(bm):
    for y in (-0.24, 0.24):
        for x in (-0.085, 0.085):
            c = Vector((x, y, 0.028))
            loft(bm, [
                (c - Vector((0.017, 0, 0)), Vector((1, 0, 0)), 0.028, 0.028),
                (c + Vector((0.017, 0, 0)), Vector((1, 0, 0)), 0.028, 0.028),
            ], 8)


# ---------------------------------------------------------------------------
def main():
    out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "karakter.blend"

    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    tree = head_bvh()
    root = bpy.data.objects.new("Karakter", None)
    bpy.context.collection.objects.link(root)

    make_object("Kafa", build_head, "ten", root)
    make_object("Boyun", build_neck, "ten", root)
    make_object("Burun", lambda bm: build_nose(bm, tree), "ten_koyu", root)
    make_object("Gozler", lambda bm: build_eyes(bm, tree), "goz", root)
    make_object("GozParlak", lambda bm: build_eye_highlights(bm, tree), "beyaz", root)
    make_object("Kaslar", lambda bm: build_brows(bm, tree), "sac", root)
    make_object("Agiz", lambda bm: build_mouth(bm, tree), "agiz", root)
    make_object("Sac", build_hair, "sac", root)
    make_object("Tisort", build_shirt, "tisort", root)
    make_object("Kollar", build_arms, "ten", root)
    make_object("Eller", build_hands, "ten", root)
    make_object("Pantolon", build_pants, "kot", root)
    make_object("Taban", build_soles, "beyaz", root)
    make_object("Ayakkabi", build_uppers, "siyah", root)
    make_object("AyakkabiSerit", build_shoe_stripes, "beyaz", root)
    make_object("Canta", build_backpack, "canta", root)
    make_object("CantaCep", build_pocket, "canta", root)
    make_object("CantaEtiket", build_patch, "siyah", root)
    make_object("Askilar", build_straps, "canta", root)

    board = bpy.data.objects.new("Kaykay", None)
    bpy.context.collection.objects.link(board)
    make_object("Tahta", build_deck, "tahta", board, face_mat=lambda n: "grip" if n.z > 0.5 else None)
    make_object("Truck", build_trucks, "metal", board)
    make_object("Tekerler", build_wheels, "teker", board)
    board.location = (0.6, 0, 0)

    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("KAYDEDILDI", out)


main()
