"""Hayvan NPC'leri için ortak altyapı. Her tür tools/blender/npc_turler/<tur>.py içinde
kendi anatomisini, kafasını/boynunu, ellerini, ek kemik zincirlerini ve hareket
karakterini tanımlar; bu dosya hepsinin kullandığı araçları verir:

- Geometri: yumuşak (Catmull-Rom) kesitli loft, kesit profilinden organik form
  (kafa, gaga, hortum), göz (göz akı / iris / göz bebeği / parlama / kapak), el.
- Mesh: çok malzemeli parça; yüz boyama (benek, desen) ve kemik grubu ipuçları.
- Body: türün anatomik profili. Gövde, omuzlar, kıyafetler ve iskelet bundan
  türetilir; kıyafetler her türün gövdesine ayrı biçilir.
- İskelet + deri ağırlıkları, animasyon çatısı (yürüyüş, bekleme, bakınma, affallama).
- Ön izleme görüntüsü (Workbench) ve yan yana birleştirme.

Koordinatlar: metre, Z yukarı, karakter -Y'ye bakar, solu +X, ayak tabanı z = 0.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

UP = Vector((0, 0, 1))
FWD = Vector((0, -1, 0))

# Varsayılan renkler. Godot NPC başına boyar (yuva adları: npc_catalog.gd)
PALETTE = {
    "kumas_ust": (0.3, 0.45, 0.4), "kumas_ic": (0.92, 0.9, 0.85), "kumas_alt": (0.3, 0.35, 0.45),
    "ayakkabi": (0.25, 0.25, 0.3), "ayakkabi_taban": (0.92, 0.91, 0.88), "sapka": (0.6, 0.15, 0.15),
    "aksesuar": (0.15, 0.12, 0.1), "kravat": (0.6, 0.1, 0.12), "yelek": (0.95, 0.45, 0.1),
    "serit": (0.85, 0.85, 0.8),
    # Türün kendi renkleri (tür dosyası PALETTE'i günceller; Godot tür paletinden boyar)
    "ten": (0.6, 0.6, 0.6), "ten2": (0.9, 0.9, 0.9), "ten3": (0.3, 0.25, 0.2), "iris": (0.45, 0.3, 0.12),
    "tirnak": (0.2, 0.18, 0.16), "tasma": (0.75, 0.15, 0.12), "dil": (0.88, 0.45, 0.5),
    "kanat": (0.8, 0.85, 0.9), "damar": (0.32, 0.34, 0.38),
    # Sabit
    "goz": (0.03, 0.025, 0.025), "goz_ak": (0.95, 0.94, 0.9), "parlak": (1.0, 1.0, 1.0),
    "beyaz": (0.95, 0.93, 0.88), "gaga": (0.95, 0.6, 0.15), "siyah": (0.07, 0.07, 0.08),
    "bej": (0.88, 0.82, 0.7), "pembe": (0.9, 0.58, 0.6), "agiz": (0.35, 0.12, 0.12),
}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


_materials = {}


def material(name):
    if name in _materials:
        return _materials[name]
    lin = tuple(srgb_to_linear(c) for c in PALETTE[name])
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


rng = random.Random(11)


def reseed(seed):
    rng.seed(seed)


def V(*a):
    return Vector(a[0]) if len(a) == 1 else Vector(a)


# ---------------------------------------------------------------------------
# Eğri yardımcıları
# ---------------------------------------------------------------------------
def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def resample(seq, sub, lerp_idx=()):
    """Değer dizilerini (tuple) Catmull-Rom ile sıklaştır. lerp_idx: doğrusal karışacak alanlar."""
    if sub <= 1 or len(seq) < 2:
        return list(seq)
    out = []
    n = len(seq)
    for i in range(n - 1):
        a, b, c, d = seq[max(i - 1, 0)], seq[i], seq[i + 1], seq[min(i + 2, n - 1)]
        for k in range(sub):
            t = k / sub
            row = []
            for j in range(len(b)):
                if b[j] is None:
                    row.append(None)
                elif j in lerp_idx:
                    x = b[j].lerp(c[j], t) if isinstance(b[j], Vector) else b[j] + (c[j] - b[j]) * t
                    row.append(x)
                else:
                    row.append(catmull(a[j], b[j], c[j], d[j], t))
            out.append(tuple(row))
    out.append(seq[-1])
    return out


def ring_basis(axis, u=None):
    axis = Vector(axis).normalized()
    if u is None:
        ref = Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))
        u = ref.cross(axis)
    u = Vector(u)
    u = (u - axis * u.dot(axis)).normalized()
    v = axis.cross(u).normalized()
    return u, v


def _se(c, p):
    """Süperelips bileşeni: p = 2 elips, > 2 köşeli, < 2 sivri."""
    return math.copysign(abs(c) ** (2.0 / p), c)


# ---------------------------------------------------------------------------
# Geometri
# ---------------------------------------------------------------------------
def loft(bm, rings, segs, cap_start=True, cap_end=True, jitter=0.0, phase=0.0, sq=2.0, sub=1):
    """rings: (merkez, eksen, rx, ry[, u]). u verilirse kesitin x ekseni odur.
    sub > 1: kesitler arası Catmull-Rom ile yumuşatılır. sq: süperelips (köşelilik)."""
    rings = [tuple(r) + (None,) * (5 - len(r)) for r in rings]
    rings = [(Vector(c), Vector(a), rx, ry, None if u is None else Vector(u)) for (c, a, rx, ry, u) in rings]
    if sub > 1:
        rings = resample(rings, sub, lerp_idx=(1, 4))
    ring_verts = []
    for (c, axis, rx, ry, u0) in rings:
        u, v = ring_basis(axis, u0)
        vs = []
        for i in range(segs):
            t = phase + math.tau * i / segs
            off = u * (_se(math.cos(t), sq) * rx) + v * (_se(math.sin(t), sq) * ry)
            if jitter > 0 and off.length > 1e-6:
                # Kumaş kırışıklığı: yalnız dışa doğru (içteki katmanın içine girmez)
                off += off.normalized() * rng.uniform(0.0, 1.0) * jitter * max(rx, ry)
            vs.append(bm.verts.new(c + off))
        ring_verts.append(vs)
    for a, b in zip(ring_verts[:-1], ring_verts[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap_start:
        bm.faces.new(list(reversed(ring_verts[0])))
    if cap_end:
        bm.faces.new(ring_verts[-1])
    return ring_verts


def path_loft(bm, pts, radii, segs, flatten=1.0, cap_start=True, cap_end=True, jitter=0.0, sub=1, u=None, sq=2.0):
    """Bir yol boyunca değişken yarıçaplı tüp (kuyruk, hortum, boyun, parmak)."""
    pts = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        a = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        r = radii[i] if isinstance(radii, (list, tuple)) else radii
        fl = flatten[i] if isinstance(flatten, (list, tuple)) else flatten
        rings.append((p, a.normalized(), r, r * fl, u))
    return loft(bm, rings, segs, cap_start, cap_end, jitter, sub=sub, sq=sq)


def organic(bm, origin, fwd, up, sections, segs=14, sub=3, jitter=0.0):
    """Ön eksen boyunca kesit profilinden kapalı form (kafa, ağız, gaga, kafatası).
    sections: (öne mesafe, yukarı kayma, yarı genişlik, üst yarı yükseklik, alt yarı yükseklik, köşelilik)
    Uç kesitler küçük tutulursa form yuvarlak kapanır. Halka köşe listelerini döndürür."""
    fwd = Vector(fwd).normalized()
    up = Vector(up)
    up = (up - fwd * up.dot(fwd)).normalized()
    side = up.cross(fwd).normalized()
    secs = resample([tuple(float(x) for x in s) for s in sections], sub)
    rings = []
    for (d, dz, w, ht, hb, sq) in secs:
        c = Vector(origin) + fwd * d + up * dz
        vs = []
        for i in range(segs):
            t = math.tau * i / segs
            ct, st = math.cos(t), math.sin(t)
            h = ht if st >= 0 else hb
            p = c + side * (_se(ct, sq) * w) + up * (_se(st, sq) * h)
            if jitter > 0:
                p += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * jitter * max(w, h)
            vs.append(bm.verts.new(p))
        rings.append(vs)
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return rings


class Frame:
    """Yerel çerçeve: x yan (sol +), y ön, z üst. Kafa gibi eğik parçaları
    kendi eksenlerinde modellemek için: F.p(x, y, z) dünya noktası, F.d(...) yön."""

    def __init__(self, origin, fwd, up):
        self.o = Vector(origin)
        self.f = Vector(fwd).normalized()
        u = Vector(up)
        self.u = (u - self.f * u.dot(self.f)).normalized()
        self.s = self.u.cross(self.f).normalized()      # karakterin solu (+X), çünkü f ≈ -Y

    def p(self, x, y, z):
        return self.o + self.s * x + self.f * y + self.u * z

    def d(self, x, y, z):
        return (self.s * x + self.f * y + self.u * z).normalized()

    def mat(self):
        return Matrix((self.s, self.f, self.u)).transposed()


def box(bm, center, size, bevel=0.0, rot=None):
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    for v in verts:
        p = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if rot is not None:
            p = rot @ p
        v.co = p + Vector(center)
    if bevel > 0:
        edges = list({e for v in verts for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect='EDGES', profile=0.5)


def ellipsoid(bm, center, radii, u=12, v=8, rot=None, deform=None):
    res = bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    for vert in res["verts"]:
        p = Vector(vert.co)
        if deform:
            p = deform(p)
        p = Vector((p.x * radii[0], p.y * radii[1], p.z * radii[2]))
        if rot is not None:
            p = rot @ p
        vert.co = p + Vector(center)
    return res["verts"]


def axis_rot(z_axis, x_hint=None):
    """Yerel z'yi z_axis'e çeviren dönüş matrisi (elipsoid / kubbe yönlendirmek için)."""
    z = Vector(z_axis).normalized()
    x = Vector(x_hint) if x_hint is not None else (Vector((1, 0, 0)) if abs(z.x) < 0.9 else Vector((0, 1, 0)))
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


def cone(bm, base, tip, radius, sides=5, tip_radius=0.0, flatten=1.0, u=None):
    base, tip = Vector(base), Vector(tip)
    uu, v = ring_basis(tip - base, u)
    a = [bm.verts.new(base + uu * math.cos(math.tau * i / sides) * radius + v * math.sin(math.tau * i / sides) * radius * flatten)
         for i in range(sides)]
    if tip_radius > 0:
        b = [bm.verts.new(tip + uu * math.cos(math.tau * i / sides) * tip_radius + v * math.sin(math.tau * i / sides) * tip_radius * flatten)
             for i in range(sides)]
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((a[i], a[j], b[j], b[i]))
        bm.faces.new(b)
    else:
        t = bm.verts.new(tip)
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((a[i], a[j], t))
    bm.faces.new(list(reversed(a)))


def ribbon(bm, points, width, thickness, u=None):
    """Şerit (kemer, askı, yaka). u: genişlik yönü (verilmezse rastgele dik)."""
    rings = []
    for i, p in enumerate(points):
        a = points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]
        rings.append((Vector(p), a.normalized(), width * 0.5, thickness * 0.5, u))
    loft(bm, rings, 4, phase=math.pi / 4)


def patch(bm, center, normal, w, h, depth=0.004, sides=6, rot=0.0, irregular=0.0):
    """Yüzeye yapışık küçük yassı parça (burun deliği, ağız çizgisi). Büyük desenler
    için kullanılmaz: onlar yüz boyamayla yapılır (üst üste yüzey titremesin)."""
    n = Vector(normal).normalized()
    up = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((0, 1, 0))
    r = up.cross(n).normalized()
    u = n.cross(r).normalized()
    cr, sr = math.cos(rot), math.sin(rot)
    r, u = r * cr + u * sr, u * cr - r * sr
    front, back = [], []
    for i in range(sides):
        t = math.tau * i / sides
        k = 1.0 + rng.uniform(-irregular, irregular)
        q = Vector(center) + r * math.cos(t) * w * 0.5 * k + u * math.sin(t) * h * 0.5 * k
        front.append(bm.verts.new(q + n * depth * 0.5))
        back.append(bm.verts.new(q - n * depth))
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((back[i], back[j], front[j], front[i]))


def tufts(bm, base, direction, count, length, radius, spread=0.6, sides=4, area=1.2):
    """Tüy tutamı kümesi: köşeli küçük konilerden kabarık tüy."""
    d = Vector(direction).normalized()
    u, v = ring_basis(d)
    for i in range(count):
        off = (u * rng.uniform(-1, 1) + v * rng.uniform(-1, 1)) * radius * area
        dd = (d + (u * rng.uniform(-1, 1) + v * rng.uniform(-1, 1)) * spread * 0.5).normalized()
        b = Vector(base) + off
        cone(bm, b, b + dd * length * rng.uniform(0.7, 1.2), radius * rng.uniform(0.7, 1.1), sides=sides)


# ---------------------------------------------------------------------------
# Desen (yüz boyama)
# ---------------------------------------------------------------------------
class Voronoi:
    """3B Voronoi deseni: hücre içi bir renk, sınırlar başka renk (zürafa benekleri,
    kaplumbağa kabuğu vb.). Sınır kalınlığı metre cinsinden."""

    def __init__(self, lo, hi, spacing, jitter=0.45, seed=3):
        r = random.Random(seed)
        self.pts = []
        lo, hi = Vector(lo), Vector(hi)
        nx = max(1, int((hi.x - lo.x) / spacing) + 1)
        ny = max(1, int((hi.y - lo.y) / spacing) + 1)
        nz = max(1, int((hi.z - lo.z) / spacing) + 1)
        for i in range(nx + 1):
            for j in range(ny + 1):
                for k in range(nz + 1):
                    self.pts.append(lo + Vector((i, j, k)) * spacing +
                                    Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-1, 1))) * spacing * jitter)

    @classmethod
    def on_surface(cls, points, spacing, seed=3):
        """Tohumları yüzeyin kendisinden, aralarında en az 'spacing' olacak şekilde seç
        (eşit boyda hücreler; 3B ızgaranın kesitindeki gibi minik / dev hücre olmaz)."""
        self = cls.__new__(cls)
        r = random.Random(seed)
        pts = list(points)
        r.shuffle(pts)
        self.pts = []
        s2 = spacing * spacing
        for p in pts:
            if all((p - q).length_squared >= s2 for q in self.pts):
                self.pts.append(p)
        return self

    def edge(self, p):
        """Hücre sınırına (en yakın iki tohumun orta düzlemine) gerçek uzaklık."""
        d1 = d2 = 1e9
        q1 = q2 = None
        for q in self.pts:
            d = (q - p).length_squared
            if d < d1:
                d1, d2, q2, q1 = d, d1, q1, q
            elif d < d2:
                d2, q2 = d, q
        return (d2 - d1) / (2.0 * max((q2 - q1).length, 1e-6))


def hash01(p, seed=0):
    """Konumdan tekrarlanabilir 0..1 sayı (yüz boyamada doku gürültüsü)."""
    h = math.sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7 + seed * 19.3) * 43758.5453
    return h - math.floor(h)


def noise_paint(base, alt, frac, seed=0, region=None):
    """Rastgele yüzleri ikinci tona boyar (deri / kumaş dokusu hissi)."""
    def f(c, n, src):
        if src != base or (region and not region(c)):
            return None
        return alt if hash01(c, seed) < frac else None
    return f


def band_paint(path, period, width, base, alt, radius=0.2):
    """Bir yol boyunca halka çizgiler (hortum / boyun kırışıkları, kuyruk halkaları).
    path: nokta listesi; period: çizgi aralığı (m); width: 0..1 çizgi oranı."""
    path = [Vector(p) for p in path]
    lens = [0.0]
    for a, b in zip(path[:-1], path[1:]):
        lens.append(lens[-1] + (b - a).length)

    def along(c):
        best = (1e9, 0.0)
        for i, (a, b) in enumerate(zip(path[:-1], path[1:])):
            ab = b - a
            t = max(0.0, min(1.0, (c - a).dot(ab) / max(ab.length_squared, 1e-9)))
            d = (a + ab * t - c).length
            if d < best[0]:
                best = (d, lens[i] + ab.length * t)
        return best

    def f(c, n, src):
        if src != base:
            return None
        d, s = along(c)
        if d > radius:
            return None
        return alt if (s / period) % 1.0 < width else None
    return f


def combine(*fns):
    """Boyama işlevlerini sırayla dene; ilk dönen yeni malzeme kazanır."""
    def f(c, n, src):
        for fn in fns:
            r = fn(c, n, src)
            if r:
                return r
        return None
    return f


# ---------------------------------------------------------------------------
# Çok malzemeli parça
# ---------------------------------------------------------------------------
class Mesh:
    """Malzeme (+ kemik grubu) kovalarına geometri toplar, tek nesneye çevirir.
    m.bm("ten") -> o malzemenin bmesh'i; m.bm("ten", "ear.L") -> o kemik zincirine
    bağlanacak geometri (deri ağırlığı yalnız o zincirden alınır)."""

    def __init__(self):
        self.buckets = {}

    def bm(self, mat, grp=None):
        key = (mat, grp)
        if key not in self.buckets:
            self.buckets[key] = bmesh.new()
        return self.buckets[key]

    def build(self, name, parts, paint=None):
        """paint(merkez, normal, malzeme_adı) -> yeni malzeme adı ya da None."""
        objs = []
        for (mat, grp), bm in self.buckets.items():
            if not bm.faces:
                bm.free()
                continue
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            me = bpy.data.meshes.new(f"{name}_{mat}")
            bm.to_mesh(me)
            bm.free()
            o = bpy.data.objects.new(f"{name}_{mat}", me)
            o.data.materials.append(material(mat))
            bpy.context.collection.objects.link(o)
            if grp:
                vg = o.vertex_groups.new(name="g:" + grp)
                vg.add([v.index for v in me.vertices], 1.0, 'REPLACE')
            objs.append(o)
        if len(objs) > 1:
            bpy.ops.object.select_all(action='DESELECT')
            for o in objs:
                o.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            bpy.ops.object.join()
            obj = bpy.context.view_layer.objects.active
        else:
            obj = objs[0]
        obj.name = name
        me = obj.data
        if paint:
            # Üçgenle: desen sınırları dörtgenin yarısı çözünürlükte (GPU için maliyetsiz)
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='SHORT_EDGE')
            bm.to_mesh(me)
            bm.free()
            if hasattr(paint, "prepare"):
                paint.prepare([(Vector(p.center), me.materials[p.material_index].name) for p in me.polygons])
            slots = {m.name: i for i, m in enumerate(me.materials)}
            for poly in me.polygons:
                src = me.materials[poly.material_index].name
                new = paint(Vector(poly.center), Vector(poly.normal), src)
                if new and new != src:
                    if new not in slots:
                        me.materials.append(material(new))
                        slots[new] = len(me.materials) - 1
                    poly.material_index = slots[new]
        for poly in me.polygons:
            poly.use_smooth = False
        parts.append(obj)
        return obj


# ---------------------------------------------------------------------------
# Anatomi profili
# ---------------------------------------------------------------------------
class Body:
    """Türün gövde profili. Ölçüler metre; kesitler (yarı genişlik, yarı derinlik)."""

    def __init__(self, **kw):
        self.hip_z = 0.93          # kasık / bacak kökü
        self.shoulder_z = 1.42     # omuz eklemi
        self.shoulder_w = 0.2      # omuz eklemi x
        self.chest = (0.19, 0.12)
        self.chest_cy = 0.0        # göğüs öne (-) / arkaya (+)
        self.waist = (0.16, 0.1)
        self.belly = (0.17, 0.11)
        self.belly_cy = 0.0        # göbek öne (-)
        self.hip = (0.17, 0.105)
        self.butt = 0.0            # kalça arkaya taşma
        self.trap = 0.66           # trapez: boyun dibinde gövde genişliği / omuz
        self.neck_r = 0.055
        self.arm = (0.3, 0.27, 0.1)            # üst kol, ön kol, el
        self.arm_r = (0.05, 0.048, 0.038, 0.044, 0.03)   # omuz, pazı, dirsek, önkol, bilek
        self.arm_flat = 1.0
        self.leg_r = (0.085, 0.06, 0.06, 0.04)  # uyluk, diz, baldır, bilek
        self.foot_x = 0.11
        self.foot_len = 1.0
        self.foot_w = 1.0
        self.hand_scale = 1.0
        self.arm_angle = 26.0      # dinlenme pozunda kolun dikeyle açısı (az deformasyon için küçük)
        self.spine_lean = 0.0      # duruş: öne eğik (derece)
        self.neck_pts = None       # boyun kemik noktaları (alt -> üst)
        self.head_c = Vector((0, 0.0, 1.63))
        self.head_r = (0.11, 0.11, 0.1)        # şapka yerleşimi
        self.head_top = 1.75
        self.hat_tilt = 0.0        # şapka öne eğimi (derece)
        self.hats = True
        for k, v in kw.items():
            setattr(self, k, v)
        if self.neck_pts is None:
            self.neck_pts = [Vector((0, 0.005, self.shoulder_z)), Vector((0, 0.012, self.head_c.z - self.head_r[2] * 0.6))]
        self.neck_pts = [Vector(p) for p in self.neck_pts]
        self.head_c = Vector(self.head_c)

    @property
    def knee_z(self):
        return 0.085 + (self.hip_z - 0.085) * 0.49

    @property
    def deltoid(self):
        return self.arm_r[0] * 1.22

    def arm_points(self, side):
        a = math.radians(self.arm_angle)
        d = Vector((math.sin(a) * side, 0, -math.cos(a)))
        s = Vector((self.shoulder_w * side, 0.0, self.shoulder_z))
        up, fo, ha = self.arm
        e = s + d * up + Vector((0, 0.015, 0))   # hafif dirsek bükümü (IK için şart)
        w = s + d * (up + fo)
        h = w + d * ha * self.hand_scale
        return s, e, w, h, d

    def leg_points(self, side):
        hx = max(self.hip[0] * 0.55, 0.075) * side
        hip = Vector((hx, 0.005, self.hip_z))
        knee = Vector((hx * 1.05, -0.014, self.knee_z))
        ankle = Vector((self.foot_x * side, 0.01, 0.085))
        toe = Vector((self.foot_x * side, -0.15 * self.foot_len, 0.03))
        return hip, knee, ankle, toe

    def torso_sections(self):
        """(z, yarı genişlik, yarı derinlik, ön/arka kayma) kasıktan boyun dibine."""
        hz, sz = self.hip_z, self.shoulder_z
        L = sz - hz                       # gövde boyu: kesitler buna oranlı (kısa gövdede basamak olmaz)
        sw = self.shoulder_w
        r0 = self.arm_r[0]
        return [
            (hz - 0.035, self.hip[0] * 0.8, self.hip[1] * 0.88, 0.005 + self.butt * 0.5),
            (hz + 0.1 * L, self.hip[0], self.hip[1], 0.005 + self.butt),
            (hz + 0.31 * L, self.waist[0], self.waist[1], 0.003),
            (hz + 0.5 * L, self.belly[0], self.belly[1], self.belly_cy),
            (hz + 0.7 * L, self.chest[0], self.chest[1], self.chest_cy),
            # Koltuk altı hizası: kol kökü gövdenin içinden çıkar
            (sz - 0.09, max(self.chest[0], sw + r0 * 0.25), self.chest[1] * 0.97, self.chest_cy * 0.7),
            # Omuz başı: deltoid gövde hattının parçası (kol ayrı boru gibi durmaz)
            (sz - 0.03, sw + r0 * 0.55, self.chest[1] * 0.86, self.chest_cy * 0.3),
            # Trapez eğimi: omuzdan boyna
            (sz + 0.02, sw * (self.trap + 1.0) * 0.5 + r0 * 0.15, self.chest[1] * 0.72, 0.006),
            (sz + 0.06, sw * self.trap * 0.75 + self.neck_r * 0.4, self.chest[1] * 0.58, 0.008),
        ]

    def torso_rings(self, loose=0.0, from_z=-1.0, to_z=99.0):
        out = []
        for (z, rx, ry, cy) in self.torso_sections():
            if z < from_z - 1e-4 or z > to_z + 1e-4:
                continue
            out.append((Vector((0, cy, z)), UP, rx + loose, ry + loose))
        return out

    def section_at(self, z):
        """Verilen yükseklikte gövde kesiti (yarı genişlik, yarı derinlik, kayma); doğrusal ara değer."""
        secs = self.torso_sections()
        if z <= secs[0][0]:
            return secs[0][1:]
        for a, b in zip(secs[:-1], secs[1:]):
            if z <= b[0]:
                k = (z - a[0]) / max(b[0] - a[0], 1e-6)
                return tuple(a[i] + (b[i] - a[i]) * k for i in (1, 2, 3))
        return secs[-1][1:]

    def front_at(self, z, loose=0.0):
        """Verilen yükseklikte gövdenin ön yüzü (y)."""
        rx, ry, cy = self.section_at(z)
        return cy - ry - loose

    def top_z_at(self, x, loose=0.0):
        """Omuz / trapez hattında, verilen |x| için gövdenin üst yüzeyi (askı, çanta kayışı)."""
        secs = [s for s in self.torso_sections() if s[0] >= self.shoulder_z - 0.1]
        x = abs(x)
        for a, b in zip(secs[::-1][:-1], secs[::-1][1:]):      # yukarıdan aşağı
            if x <= b[1] + loose:
                ra, rb = a[1] + loose, b[1] + loose
                k = 0.0 if x <= ra else (x - ra) / max(rb - ra, 1e-6)
                return a[0] + (b[0] - a[0]) * k
        return secs[0][0]

    def surface_at(self, z, ang, loose=0.0):
        """Gövde yüzeyinde nokta: ang = önden açı (radyan, + sol)."""
        rx, ry, cy = self.section_at(z)
        return Vector((math.sin(ang) * (rx + loose), cy - math.cos(ang) * (ry + loose), z))


# ---------------------------------------------------------------------------
# Deri: gövde (omuz/deltoid dahil), üst kol, ön kol
# ---------------------------------------------------------------------------
def arm_rings(B, side, start, end, loose=0.0, end_loose=None, step=0.045):
    """Kol boyunca (omuz ekleminden t metre) kesitler: kas profiliyle (pazı, ön kol şişkinliği)."""
    s, e, w, h, d = B.arm_points(side)
    up, fo = B.arm[0], B.arm[1]
    r = B.arm_r
    prof = [(-0.05, r[0] * 0.45), (-0.025, r[0] * 0.8), (0.0, r[0] * 0.95), (up * 0.3, r[1] * 1.02), (up * 0.6, r[1]), (up, r[2]),
            (up + fo * 0.22, r[3]), (up + fo * 0.6, (r[3] + r[4]) * 0.5), (up + fo, r[4])]
    end_loose = loose if end_loose is None else end_loose

    def radius(t):
        for (t0, r0), (t1, r1) in zip(prof[:-1], prof[1:]):
            if t <= t1:
                k = max(0.0, (t - t0) / max(t1 - t0, 1e-6))
                k = k * k * (3 - 2 * k)
                return r0 + (r1 - r0) * k
        return prof[-1][1]

    rings = []
    n = max(2, int((end - start) / step) + 1)
    for i in range(n + 1):
        t = start + (end - start) * i / n
        lo = loose + (end_loose - loose) * (i / n)
        c = s + d * t + (Vector((0, 0.015 * max(0.0, min(1.0, t / up)), 0)))
        rr = radius(t) + lo
        rings.append((c, d, rr, rr * B.arm_flat, Vector((0, -1, 0))))
    return rings


def arm_tag(side):
    return "arm." + ("L" if side > 0 else "R")


def build_body_skin(B, parts, mat="ten", paint=None, arm_extra=None):
    """Görünebilen deri: deri_govde (omuz başları dahil), deri_kol_ust, deri_kol_alt.
    Kıyafet bir parçayı tamamen örttüğünde Godot onu gizler (içten taşma olmasın)."""
    m = Mesh()
    loft(m.bm(mat), B.torso_rings(), 16, cap_start=True, cap_end=True, sq=2.2, sub=2, phase=math.pi / 16)
    m.build("deri_govde", parts, paint)
    up, fo = B.arm[0], B.arm[1]
    m = Mesh()
    for side in (-1, 1):
        loft(m.bm(mat, arm_tag(side)), arm_rings(B, side, -0.05, up + 0.02, step=0.03), 10, cap_start=True, cap_end=False)
    m.build("deri_kol_ust", parts, paint)
    m = Mesh()
    for side in (-1, 1):
        loft(m.bm(mat, arm_tag(side)), arm_rings(B, side, up - 0.03, up + fo + 0.01), 10, cap_start=False, cap_end=True)
        if arm_extra:
            arm_extra(m, side)
    m.build("deri_kol_alt", parts, paint)


def neck_skin(m, B, radii, mat="ten", flare=1.9, grp="neck", flatten=1.0, sub=2, segs=12, into=None):
    """Boyun: boyun kemik noktaları boyunca, dipte gövdeye/yakaya oturan geniş kökle.
    radii: neck_pts başına yarıçap (x); flatten: derinlik / genişlik."""
    pts = B.neck_pts
    base = pts[0]
    rings = [(base + Vector((0, 0.01, -0.1)), UP, radii[0] * flare, radii[0] * flare * 0.8 * flatten),
             (base + Vector((0, 0.005, -0.03)), UP, radii[0] * (1 + flare) * 0.5, radii[0] * (1 + flare) * 0.45 * flatten)]
    for i, p in enumerate(pts):
        a = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        rings.append((p, a.normalized(), radii[i], radii[i] * flatten))
    if into is not None:
        # Boyun kafanın içine kadar sürer: birleşim yerinde kesik / boşluk görünmez
        into = Vector(into)
        a = (into - pts[-1]).normalized()
        rings.append((pts[-1].lerp(into, 0.5), a, radii[-1] * 0.95, radii[-1] * 0.95 * flatten))
        rings.append((into, a, radii[-1] * 0.7, radii[-1] * 0.7 * flatten))
    return loft(m.bm(mat, grp), rings, segs, cap_start=True, cap_end=True, sub=sub)


# ---------------------------------------------------------------------------
# El
# ---------------------------------------------------------------------------
def whiskers(m, F, side, x, y, z, n=3, length=0.09, mat="beyaz", grp="head", thick=0.0022, fan=0.2, droop=0.06, back=0.15):
    """Bıyıklar: burun yastığından yana ve hafif geriye yelpaze."""
    for i in range(n):
        k = i - (n - 1) / 2
        base = F.p(side * x, y, z + k * 0.008)
        d = F.d(side * 1.0, -back, k * fan - droop)
        cone(m.bm(mat, grp), base - d * 0.004, base + d * length * (1 - abs(k) * 0.12), thick, sides=3)


def eye_ring(m, mat, center, normal, radius, tube, grp="head", up_hint=UP, n=10):
    """Göz çevresinde halka (güvercin / penguen göz halkası)."""
    nn = Vector(normal).normalized()
    upv = Vector(up_hint)
    upv = (upv - nn * upv.dot(nn)).normalized()
    t1 = upv.cross(nn).normalized()
    pts = [Vector(center) + (t1 * math.cos(math.tau * i / n) + upv * math.sin(math.tau * i / n)) * radius for i in range(n + 1)]
    path_loft(m.bm(mat, grp), pts, tube, 5, cap_start=False, cap_end=False)


def hand(m, B, side, mat="ten", fingers=4, finger_len=0.05, finger_r=0.01, palm_w=0.042, palm_t=0.022,
         palm_len=0.06, thumb=True, nail_mat=None, curl=28, spread=1.0, tip_ball=0.0, pad_mat=None,
         claw_mat=None, finger_lens=None, grp="hand"):
    """İnsansı hayvan eli. Kol sarkarken avuç içi gövdeye bakar, parmaklar önden arkaya
    dizilir; başparmak önde. Parmak sayısı / kalınlığı / uç topu türe göre."""
    s, e, w, h, d = B.arm_points(side)
    sc = B.hand_scale
    a = Vector((0, -1, 0))                       # avuç genişliği yönü (öne)
    n = d.cross(a) * side                        # avuç içi normali (gövdeye doğru)
    n.normalize()
    g = f"{grp}.{'L' if side > 0 else 'R'}"
    bm = m.bm(mat, g)
    pw, pt, pl = palm_w * sc, palm_t * sc, palm_len * sc
    loft(bm, [(w - d * 0.012, d, pt * 0.75, pw * 0.7, n),
              (w + d * pl * 0.35, d, pt, pw, n),
              (w + d * pl * 0.8, d, pt * 0.95, pw * 1.02, n),
              (w + d * pl, d, pt * 0.75, pw * 0.92, n)], 8, sub=2, sq=2.4)
    if pad_mat:
        ellipsoid(m.bm(pad_mat, g), w + d * pl * 0.55 + n * pt * 0.7, (pw * 0.6, pt * 0.35, pl * 0.32),
                  8, 5, rot=axis_rot(n, d))
    knuckle = w + d * pl * 0.92
    lens = finger_lens or [finger_len * k for k in (0.92, 1.0, 0.96, 0.8, 0.75)[:fingers]]
    for i in range(fingers):
        k = 0.0 if fingers == 1 else (i / (fingers - 1)) * 2 - 1     # -1 arka ... +1 ön
        base = knuckle + a * (-k * pw * 0.72 * spread) + n * pt * 0.1
        L = lens[i] * sc
        c1 = math.radians(curl * 0.6)
        c2 = math.radians(curl * 1.4)
        d1 = (d * math.cos(c1) + n * math.sin(c1) - a * k * 0.12 * spread).normalized()
        p1 = base + d1 * L * 0.55
        d2 = (d * math.cos(c2) + n * math.sin(c2) - a * k * 0.1 * spread).normalized()
        p2 = p1 + d2 * L * 0.45
        fr = finger_r * sc
        path_loft(bm, [base - d * 0.006, p1, p2], [fr * 1.05, fr * 0.92, fr * 0.7], 6, u=a)
        if tip_ball:
            ellipsoid(bm, p2, (fr * tip_ball, fr * tip_ball, fr * tip_ball * 0.8), 6, 4)
        if nail_mat:
            ellipsoid(m.bm(nail_mat, g), p2 - n * fr * 0.45 + d2 * fr * 0.1, (fr * 0.75, fr * 0.9, fr * 0.35), 6, 4,
                      rot=axis_rot(-n, d2))
        if claw_mat:
            cone(m.bm(claw_mat, g), p2 - d2 * fr * 0.2, p2 + d2 * fr * 1.6 + n * fr * 0.8, fr * 0.45, sides=4)
    if thumb:
        tb = w + d * pl * 0.3 + a * pw * 0.75 + n * pt * 0.4
        td = (a * 0.55 + d * 0.65 + n * 0.45).normalized()
        tl = (lens[0] if lens else finger_len) * 0.85 * sc
        t1 = tb + td * tl * 0.5
        t2 = t1 + (td + n * 0.4).normalized() * tl * 0.45
        fr = finger_r * 1.1 * sc
        path_loft(bm, [tb - td * 0.01, t1, t2], [fr * 1.2, fr, fr * 0.75], 6)
        if tip_ball:
            ellipsoid(bm, t2, (fr * tip_ball, fr * tip_ball, fr * tip_ball * 0.8), 6, 4)
        if nail_mat:
            ellipsoid(m.bm(nail_mat, g), t2 - n * fr * 0.4, (fr * 0.7, fr * 0.85, fr * 0.33), 6, 4, rot=axis_rot(-n, td))
        if claw_mat:
            cone(m.bm(claw_mat, g), t2, t2 + td * fr * 1.5, fr * 0.45, sides=4)


# ---------------------------------------------------------------------------
# Göz
# ---------------------------------------------------------------------------
def on_surface(bm, guess, normal, sink=0.35, r=0.0):
    """Tahmini bir noktayı, verilen yönden ışın atarak bmesh yüzeyine oturtur
    (göz / burun gibi parçalar kafanın içinde kalmasın ya da havada durmasın).
    Dönüş: yüzey noktası - normal * (r * sink)."""
    from mathutils.bvhtree import BVHTree
    n = Vector(normal).normalized()
    tree = BVHTree.FromBMesh(bm)
    hit = tree.ray_cast(Vector(guess) + n * 0.3, -n, 0.6)
    p = hit[0] if hit[0] is not None else Vector(guess)
    return p - n * (r * sink)


def eye(m, center, normal, r, up_hint=UP, grp="head", iris_k=0.62, pupil="round", lid=0.25,
        lid_mat="ten", lid_tilt=0.0, lower_lid=0.0, lower_mat=None, ak=True, lashes=0, lash_mat="ten3"):
    """Katmanlı göz: göz akı küresi, öne taşan iris ve göz bebeği kapakları, parlama
    ve üst göz kapağı (kesişen elipsoidler; üst üste yassı yüzey yok, titremez).
    lid: 0 = kapak yok, 0.25 = hafif, 0.5 = uykulu. lid_tilt: + dış köşe aşağı (hüzünlü/sakin)."""
    n = Vector(normal).normalized()
    upv = Vector(up_hint)
    upv = (upv - n * upv.dot(n)).normalized()
    t1 = upv.cross(n).normalized()
    rot = Matrix((t1, upv, n)).transposed()
    c = Vector(center)
    if ak:
        ellipsoid(m.bm("goz_ak", grp), c, (r, r * 1.04, r * 0.82), 10, 7, rot=rot)
    ik = iris_k
    ellipsoid(m.bm("iris", grp), c + n * r * 0.52, (r * ik, r * ik * 1.05, r * 0.42), 10, 6, rot=rot)
    if pupil == "slit":
        pr = (r * 0.13, r * ik * 0.92, r * 0.36)
    elif pupil == "wide":
        pr = (r * ik * 0.85, r * 0.17, r * 0.36)
    elif pupil == "full":
        pr = (r * ik * 0.92, r * ik * 0.97, r * 0.36)
    else:
        pr = (r * ik * 0.52, r * ik * 0.55, r * 0.36)
    ellipsoid(m.bm("goz", grp), c + n * r * 0.63, pr, 8, 5, rot=rot)
    hl = c + n * r * 0.86 + upv * r * 0.3 - t1 * r * 0.22
    ellipsoid(m.bm("parlak", grp), hl, (r * 0.16, r * 0.16, r * 0.12), 6, 4, rot=rot)
    if lid > 0:
        # Üst kapak: göz merkezinin üstüne oturan, göz akını üstten örten elipsoid
        tilt = Matrix.Rotation(math.radians(lid_tilt), 3, n)
        lr = Matrix.Rotation(math.radians(-8), 3, t1)
        lc = c + upv * r * (1.05 - lid * 1.1) + n * r * 0.04
        ellipsoid(m.bm(lid_mat, grp), lc, (r * 1.12, r * 0.95, r * 0.98), 10, 6, rot=tilt @ lr @ rot)
        if lashes:
            for i in range(lashes):
                k = (i / max(lashes - 1, 1)) * 2 - 1
                side_k = k * 0.8
                base = c + (t1 * side_k * r * 0.95) + upv * r * (1.05 - lid * 1.1 - 0.62) + n * r * 0.86
                tip = base + (n * 0.6 + upv * 0.3 + t1 * side_k * 0.6).normalized() * r * 0.55
                cone(m.bm(lash_mat, grp), base, tip, r * 0.09, sides=3)
    if lower_lid > 0:
        lc = c - upv * r * (1.05 - lower_lid * 1.1) + n * r * 0.02
        ellipsoid(m.bm(lower_mat or lid_mat, grp), lc, (r * 1.08, r * 0.8, r * 0.92), 10, 6, rot=rot)


# ---------------------------------------------------------------------------
# Kıyafetler (profile göre biçilir)
#
# Katman düzeni (gövde yüzeyinden dışa pay, m): deri 0 < pantolon beli 0.008 <
# iç gömlek 0.012 < iş gömleği 0.018 < tişört 0.02 < ceket 0.024 < kapüşonlu 0.034 ~
# kısa ceket 0.036 ~ yelek 0.036. Kırışıklık yalnız dışa ve iki katman arasındaki
# boşluktan küçük; açık önlü giysiler gerçekten kesilir, altta tam bir iç katman olur.
# ---------------------------------------------------------------------------
def _sleeves(m, mat, B, length, loose, end_loose=None, jitter=0.02, start=-0.05):
    """Kol: baş kısmı kapalı ve yuvarlak (omuz başı), gövdenin içinden doğar."""
    up, fo = B.arm[0], B.arm[1]
    for side in (-1, 1):
        rings = arm_rings(B, side, start, min(length, up + fo), loose, end_loose, step=0.03)
        loft(m.bm(mat, arm_tag(side)), rings, 10, cap_start=True, cap_end=False, jitter=jitter)


def _torso(m, mat, B, loose, from_z, to_z=99.0, jitter=0.0, opening=None, cap_start=False, cap_end=False):
    """Gövde kılıfı. opening(z) -> önde kesilecek yarım açı (radyan): açık fermuar, V yaka.
    Kalça hizasında pantolonun kalçasını da örtecek kadar açılır (pantolon ceketi delmez)."""
    rings = []
    for (c, axis, rx, ry) in B.torso_rings(loose, from_z, to_z):
        if c.z < B.hip_z + 0.07:
            rx = max(rx, B.hip[0] + 0.016 + loose)
            ry = max(ry, B.hip[1] + 0.006 + loose)
        rings.append((c, axis, rx, ry))
    bm = m.bm(mat)
    before = set(bm.faces)
    loft(bm, rings, 18, cap_start=cap_start, cap_end=cap_end, jitter=jitter, phase=math.pi / 18, sq=2.2, sub=2)
    if opening:
        kill = []
        for f in bm.faces:
            if f in before:
                continue
            c = f.calc_center_median()
            _, _, cy = B.section_at(c.z)
            ang = math.atan2(c.x, -(c.y - cy))
            if abs(ang) < opening(c.z):
                kill.append(f)
        bmesh.ops.delete(bm, geom=kill, context='FACES')
    return rings


def _edge_strip(m, mat, B, opening, z0, z1, loose, width, thick, n=8):
    """Açıklığın iki kenarına şerit (fermuar bandı, yaka devriği): kesik kenarı örter."""
    for side in (-1, 1):
        pts = []
        for i in range(n + 1):
            z = z0 + (z1 - z0) * i / n
            pts.append(B.surface_at(z, side * opening(z), loose + thick * 0.3))
        ribbon(m.bm(mat), pts, width, thick, u=Vector((1, 0, 0)))


def collar(m, mat, B, loose, height=0.05, flare=0.012, jitter=0.0):
    """Boyun dibinde yaka (gövde açıklığını kapatır)."""
    secs = B.torso_sections()
    z, rx, ry, cy = secs[-1]
    loft(m.bm(mat), [(Vector((0, cy, z - 0.02)), UP, rx + loose, ry + loose),
                     (Vector((0, cy, z + height)), UP, B.neck_r * 1.05 + loose + flare, B.neck_r * 1.0 + loose + flare)],
         12, cap_start=False, cap_end=False, jitter=jitter)


def top(B, parts, kind):
    m = Mesh()
    hz, sz = B.hip_z, B.shoulder_z
    up, fo = B.arm[0], B.arm[1]
    if kind == "ust_takim":
        # Gömlek (içte, tam) + kravat; üstte oturan ceket: V yaka gerçekten açık, devrik yakalar
        _torso(m, "kumas_ic", B, 0.012, hz + 0.1, sz + 0.06, jitter=0.004)
        collar(m, "kumas_ic", B, 0.012, height=0.045, flare=0.006)
        button_z = hz + 0.2
        top_z = sz - 0.04

        def v_open(z):
            if z <= button_z:
                return 0.0
            return min(0.7, 0.62 * (z - button_z) / (top_z - button_z))

        _torso(m, "kumas_ust", B, 0.024, hz - 0.06, sz + 0.03, jitter=0.008, opening=v_open)
        _sleeves(m, "kumas_ust", B, up + fo - 0.025, 0.024, 0.016, jitter=0.01)
        for side in (-1, 1):
            s, e, w, h, d = B.arm_points(side)
            # Gömlek manşeti ceket kolundan taşar
            loft(m.bm("kumas_ic", arm_tag(side)), arm_rings(B, side, up + fo - 0.04, up + fo - 0.005, 0.012, 0.012), 10, cap_start=False, cap_end=False)
            # Revers: V kenarı boyunca, boyun arkasına dolanır
            pts = [B.surface_at(z, side * v_open(z), 0.03) for z in
                   (button_z + 0.01, button_z + (top_z - button_z) * 0.35, button_z + (top_z - button_z) * 0.7, top_z)]
            pts += [Vector((side * (B.neck_r + 0.035), -B.neck_r * 0.4, sz + 0.06)),
                    Vector((side * (B.neck_r + 0.02), B.neck_r * 0.7, sz + 0.08)), Vector((0, B.neck_r + 0.03, sz + 0.085))]
            ribbon(m.bm("kumas_ust"), pts, 0.05, 0.012)
            # Cep kapakları ve göğüs cebi mendili
            box(m.bm("kumas_ust"), B.surface_at(hz + 0.08, side * 0.75, 0.03), (0.075, 0.012, 0.016), rot=Matrix.Rotation(side * 0.75, 3, 'Z'))
            if side > 0:
                box(m.bm("kumas_ic"), B.surface_at(sz - 0.11, 0.62, 0.03), (0.03, 0.008, 0.014), rot=Matrix.Rotation(0.62, 3, 'Z'))
        # Kravat: gömleğin önünde, düğüm yakada
        tie = [Vector((0, B.front_at(z, 0.012) - 0.004, z)) for z in (sz + 0.02, sz - 0.08, sz - 0.18, hz + 0.24)]
        tie[0] = Vector((0, -B.neck_r - 0.022, sz + 0.035))
        ribbon(m.bm("kravat"), tie, 0.042, 0.008, u=Vector((1, 0, 0)))
        box(m.bm("kravat"), Vector((0, -B.neck_r - 0.026, sz + 0.035)), (0.032, 0.02, 0.028))
        for zz in (button_z, hz + 0.1):
            ellipsoid(m.bm("aksesuar"), (0, B.front_at(zz, 0.024) - 0.004, zz), (0.011, 0.006, 0.011), 6, 4)
    elif kind == "ust_kapusonlu":
        # İçte tişört (tam), üstte fermuarı açık bol kapüşonlu; yan cepler, ribanalar, ensede kapüşon
        _torso(m, "kumas_ic", B, 0.012, hz + 0.0, sz + 0.06, jitter=0.004)
        collar(m, "kumas_ic", B, 0.012, height=0.025)

        def zip_open(z):
            return 0.3 if z < sz - 0.03 else 0.0

        _torso(m, "kumas_ust", B, 0.034, hz + 0.03, sz + 0.03, jitter=0.03, opening=zip_open)
        _sleeves(m, "kumas_ust", B, up + fo - 0.03, 0.034, 0.03, jitter=0.03)
        _edge_strip(m, "kumas_ust", B, zip_open, hz + 0.03, sz - 0.04, 0.034, 0.03, 0.016)
        # Bel ribanası (açıklık dahil kesik)
        rb = []
        for (c, axis, rx, ry) in B.torso_rings(0.04, hz + 0.0, hz + 0.08)[:1]:
            rx = max(rx, B.hip[0] + 0.056)
            rb = [(c + Vector((0, 0, 0.02)), axis, rx, ry), (c + Vector((0, 0, 0.055)), axis, rx, ry)]
        bmr = m.bm("kumas_ust")
        before = set(bmr.faces)
        loft(bmr, rb, 18, cap_start=False, cap_end=False, phase=math.pi / 18)
        kill = [f for f in bmr.faces if f not in before and abs(math.atan2(f.calc_center_median().x, -f.calc_center_median().y)) < 0.3]
        bmesh.ops.delete(bmr, geom=kill, context='FACES')
        for side in (-1, 1):
            # Manşet ribanası
            loft(m.bm("kumas_ust", arm_tag(side)), arm_rings(B, side, up + fo - 0.06, up + fo - 0.01, 0.03, 0.022), 10, cap_start=False, cap_end=False)
            # Kapüşon ipleri: yakadan sarkar
            ribbon(m.bm("kumas_ic"), [Vector((side * (B.neck_r + 0.012), -B.neck_r - 0.03, sz + 0.05)),
                                      B.surface_at(sz - 0.08, side * 0.24, 0.036), B.surface_at(sz - 0.19, side * 0.25, 0.038)], 0.01, 0.008)
            # Yan cep ağzı
            box(m.bm("kumas_ust"), B.surface_at(hz + 0.13, side * 0.85, 0.044), (0.012, 0.09, 0.012),
                rot=Matrix.Rotation(side * 0.85, 3, 'Z') @ Matrix.Rotation(side * 0.5, 3, 'Y'))
        # Ensede toplanmış kapüşon
        bk = B.chest[1] * 0.62
        loft(m.bm("kumas_ust"), [(Vector((0, bk, sz + 0.02)), Vector((0, 0.5, 1)), B.neck_r * 1.9 + 0.035, 0.05),
                                 (Vector((0, bk + 0.05, sz + 0.08)), Vector((0, 0.7, 1)), B.neck_r * 1.8 + 0.035, 0.055),
                                 (Vector((0, bk + 0.07, sz + 0.13)), Vector((0, 0.9, 1)), B.neck_r * 1.3 + 0.02, 0.035)], 10, jitter=0.03, sub=2)
    elif kind == "ust_isci":
        # Kolları kıvrılmış iş gömleği (düğme patı, cepler) + önü açık reflektif yelek + kemer
        _torso(m, "kumas_ust", B, 0.018, hz + 0.04, sz + 0.03, jitter=0.02)
        roll = up + fo * 0.62
        _sleeves(m, "kumas_ust", B, roll, 0.018, 0.024, jitter=0.02)
        for side in (-1, 1):
            loft(m.bm("kumas_ust", arm_tag(side)), arm_rings(B, side, roll - 0.045, roll + 0.004, 0.032, 0.034), 10, jitter=0.02)
            cone(m.bm("kumas_ust"), Vector((side * (B.neck_r + 0.005), -B.neck_r * 0.8, sz + 0.08)),
                 Vector((side * (B.neck_r + 0.05), -B.neck_r - 0.04, sz + 0.02)), 0.026, sides=4)
            box(m.bm("kumas_ust"), B.surface_at(sz - 0.14, side * 0.5, 0.024), (0.065, 0.01, 0.07), bevel=0.006,
                rot=Matrix.Rotation(side * 0.5, 3, 'Z'))
        collar(m, "kumas_ust", B, 0.018, height=0.045)
        ribbon(m.bm("kumas_ust"), [Vector((0, B.front_at(z, 0.022), z)) for z in (hz + 0.06, hz + 0.25, sz - 0.12, sz + 0.02)],
               0.028, 0.006, u=Vector((1, 0, 0)))

        def vest_open(z):
            return 0.42

        vr = _torso(m, "yelek", B, 0.036, hz + 0.08, sz - 0.03, jitter=0.012, opening=vest_open)
        _edge_strip(m, "yelek", B, vest_open, hz + 0.08, sz - 0.04, 0.036, 0.024, 0.012)
        for side in (-1, 1):
            sx = side * (B.neck_r + 0.06)
            tz = B.top_z_at(sx, 0.03) + 0.008
            ribbon(m.bm("yelek"), [B.surface_at(sz - 0.07, side * 0.5, 0.04), B.surface_at(tz - 0.03, side * 0.35, 0.036),
                                   Vector((sx, 0, tz)), B.surface_at(tz - 0.03, side * (math.pi - 0.35), 0.036),
                                   B.surface_at(sz - 0.07, side * (math.pi - 0.5), 0.04)], 0.06, 0.012, u=Vector((1, 0, 0)))
        for z in (hz + 0.14, hz + 0.3):
            bms = m.bm("serit")
            before = set(bms.faces)
            rx, ry, cy = B.section_at(z)
            rx, ry = max(rx, B.hip[0] + 0.016) + 0.04, ry + 0.04
            loft(bms, [(Vector((0, cy, z)), UP, rx, ry), (Vector((0, cy, z + 0.035)), UP, rx, ry)], 18, cap_start=False, cap_end=False,
                 phase=math.pi / 18, sq=2.2)
            kill = [f for f in bms.faces if f not in before and abs(math.atan2(f.calc_center_median().x, -(f.calc_center_median().y - cy))) < 0.42]
            bmesh.ops.delete(bms, geom=kill, context='FACES')
        wr = B.torso_rings(loose=0.022, from_z=hz + 0.04)[0]
        rx, ry = max(wr[2], B.hip[0] + 0.03), wr[3]
        loft(m.bm("aksesuar"), [(Vector((0, wr[0].y, hz + 0.05)), UP, rx, ry), (Vector((0, wr[0].y, hz + 0.085)), UP, rx, ry)],
             18, cap_start=False, cap_end=False)
        box(m.bm("serit"), Vector((0, wr[0].y - ry - 0.004, hz + 0.068)), (0.05, 0.01, 0.035))
    elif kind == "ust_kisa":
        # Göbeği açık bluz (tam) + önü açık, bol kollu kısa ceket
        crop_z = hz + 0.27
        _torso(m, "kumas_ic", B, 0.012, crop_z, sz + 0.06, jitter=0.004)
        collar(m, "kumas_ic", B, 0.012, height=0.025)

        def jk_open(z):
            return 0.42 if z < sz - 0.03 else 0.0

        _torso(m, "kumas_ust", B, 0.036, crop_z + 0.04, sz + 0.03, jitter=0.025, opening=jk_open)
        _sleeves(m, "kumas_ust", B, up + fo - 0.015, 0.036, 0.04, jitter=0.03)
        _edge_strip(m, "kumas_ust", B, jk_open, crop_z + 0.04, sz - 0.04, 0.036, 0.03, 0.016)
    elif kind == "ust_tisort":
        _torso(m, "kumas_ust", B, 0.02, hz + 0.0, sz + 0.03, jitter=0.025)
        _sleeves(m, "kumas_ust", B, up * 0.6, 0.022, 0.03, jitter=0.03)
        collar(m, "kumas_ust", B, 0.02, height=0.018)
    return m.build(kind, parts)


def bottom(B, parts, kind):
    m = Mesh()
    hz = B.hip_z
    wide = {"alt_takim": 0.012, "alt_kargo": 0.045, "alt_kot": 0.03}[kind]
    hem = {"alt_takim": 0.05, "alt_kargo": 0.07, "alt_kot": 0.065}[kind]
    loft(m.bm("kumas_alt"), B.torso_rings(loose=0.008, to_z=hz + 0.17), 16, cap_start=True, cap_end=True, jitter=0.01, sub=2, sq=2.2,
         phase=math.pi / 16)
    for side in (-1, 1):
        hp, kn, an, _ = B.leg_points(side)
        lr = B.leg_r
        top_r = max(B.hip[0] + 0.01 - abs(hp.x), lr[0] + 0.012)    # kalçadan dışarı taşmaz
        bottom_r = lr[3] + (0.034 if kind == "alt_takim" else 0.05) + wide
        pts = [hp + Vector((side * -0.01, 0, 0.03)), hp.lerp(kn, 0.5), kn, kn.lerp(an, 0.55), Vector((an.x, an.y + 0.015, hem + 0.05)),
               Vector((an.x, an.y + 0.02, hem))]
        rad = [top_r, max(lr[0] * 0.92 + 0.02 + wide * 0.6, top_r * 0.9), lr[1] + 0.026 + wide * 0.8,
               lr[2] + 0.026 + wide, bottom_r, bottom_r * 1.05]
        leg = "leg." + ("L" if side > 0 else "R")      # paça hangi bacağa ait (deri ağırlığı karışmasın)
        path_loft(m.bm("kumas_alt", leg), pts, rad, 10, flatten=1.05, jitter=0.05 if wide > 0.02 else 0.015, sub=2)
        if kind == "alt_kargo":
            c = hp.lerp(kn, 0.7)
            off = lr[0] + 0.03 + wide * 0.6
            box(m.bm("kumas_alt", leg), Vector((c.x + side * off, c.y, c.z)), (0.035, 0.13, 0.15), bevel=0.012)
            box(m.bm("kumas_alt", leg), Vector((c.x + side * (off + 0.02), c.y, c.z + 0.06)), (0.012, 0.13, 0.03))
        if kind == "alt_kot":
            box(m.bm("kumas_alt"), Vector((side * B.hip[0] * 0.55, B.hip[1] + 0.014 + B.butt, hz + 0.05)), (0.06, 0.01, 0.07))
    if kind in ("alt_kot", "alt_takim"):
        wr = B.torso_rings(loose=0.012, from_z=hz + 0.1, to_z=hz + 0.17)[-1]
        loft(m.bm("aksesuar" if kind == "alt_kot" else "kumas_alt"), [(wr[0] + Vector((0, 0, -0.02)), UP, wr[2], wr[3]), (wr[0], UP, wr[2], wr[3])],
             16, cap_start=False, cap_end=False, phase=math.pi / 16)
    return m.build(kind, parts)


SHOE_OUTLINE = [(0.0, -0.21), (0.038, -0.2), (0.058, -0.155), (0.063, -0.065), (0.06, 0.035),
                (0.05, 0.085), (0.0, 0.1), (-0.05, 0.085), (-0.06, 0.035), (-0.063, -0.065),
                (-0.058, -0.155), (-0.038, -0.2)]


def shoes(B, parts, kind):
    m = Mesh()
    sc, sw = B.foot_len, B.foot_w
    outline = [(x * sw, y * sc) for (x, y) in SHOE_OUTLINE]
    if kind == "ayk_kundura":
        outline = [(x * 0.85, y * 1.02) for (x, y) in outline]
    sole_h = {"ayk_spor": 0.035, "ayk_bot": 0.04, "ayk_kundura": 0.018}[kind]
    hi_back = {"ayk_spor": 0.11, "ayk_bot": 0.19, "ayk_kundura": 0.085}[kind]
    hi_toe = {"ayk_spor": 0.07, "ayk_bot": 0.09, "ayk_kundura": 0.05}[kind]
    sole_mat = "siyah" if kind == "ayk_kundura" else "ayakkabi_taban"
    for side in (-1, 1):
        x0 = B.foot_x * side
        bs = m.bm(sole_mat)
        bot = [bs.verts.new(Vector((x0 + x, y, 0))) for (x, y) in outline]
        topv = [bs.verts.new(Vector((x0 + x, y, sole_h))) for (x, y) in outline]
        bs.faces.new(list(reversed(bot)))
        bs.faces.new(topv)
        for i in range(len(outline)):
            j = (i + 1) % len(outline)
            bs.faces.new((bot[i], bot[j], topv[j], topv[i]))
        # Üst kısım: üç katlı (taban, burun kavisi, bilek) yumuşak kubbe
        bu = m.bm("ayakkabi")
        layers = []
        for (k, z) in ((0.97, sole_h - 0.004), (0.93, (sole_h + hi_toe) * 0.55), (0.0, None)):
            ring = []
            for (x, y) in outline:
                toe = y < -0.06 * sc
                if z is None:
                    zz = hi_toe if toe else hi_back
                    if toe:
                        zz = hi_toe - (abs(y) - 0.06 * sc) * 0.25
                    ring.append(bu.verts.new(Vector((x0 + x * (0.72 if toe else 0.86), y * 0.93 + (0.012 if toe else 0.0), zz))))
                else:
                    ring.append(bu.verts.new(Vector((x0 + x * k, y * k, z))))
            layers.append(ring)
        bu.faces.new(list(reversed(layers[0])))
        bu.faces.new(layers[-1])
        for la, lb in zip(layers[:-1], layers[1:]):
            for i in range(len(outline)):
                j = (i + 1) % len(outline)
                bu.faces.new((la[i], la[j], lb[j], lb[i]))
        if kind == "ayk_spor":
            for s2 in (-1, 1):
                x = x0 + s2 * 0.06 * sw
                ribbon(m.bm("ayakkabi_taban"), [Vector((x, -0.11 * sc, 0.045)), Vector((x + s2 * 0.003, -0.03 * sc, 0.07)),
                                                 Vector((x + s2 * 0.002, 0.04 * sc, 0.05))], 0.016, 0.006)
            for k in range(3):
                box(m.bm("ayakkabi_taban"), Vector((x0, (-0.1 + k * 0.035) * sc, 0.072 + k * 0.01)), (0.045, 0.008, 0.006))
        if kind == "ayk_bot":
            loft(m.bm("ayakkabi_taban"), [(Vector((x0, 0.01, 0.17)), UP, 0.062 * sw, 0.072), (Vector((x0, 0.01, 0.192)), UP, 0.066 * sw, 0.076)], 10)
            for k in range(3):
                box(m.bm("siyah"), Vector((x0, -0.06 * sc + k * 0.0, 0.1 + k * 0.025)), (0.04, 0.01, 0.006))
        if kind == "ayk_kundura":
            box(m.bm("siyah"), Vector((x0, 0.075 * sc, 0.022)), (0.08 * sw, 0.06, 0.02))   # topuk
    return m.build(kind, parts)


def hats(B, parts):
    if not B.hats:
        return
    c = B.head_c
    rx, ry, rz = B.head_r
    top = B.head_top
    base_z = top - (top - c.z) * 0.95
    tilt = Matrix.Rotation(math.radians(B.hat_tilt), 3, 'X')
    piv = Vector((c.x, c.y, base_z))

    def place(bm):
        for v in bm.verts:
            v.co = piv + tilt @ (v.co - piv)

    def dome(bm, height_k, extra, squash=1.0):
        res = bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=8, radius=1.0)
        kill = [v for v in res["verts"] if v.co.z < -0.02]
        bmesh.ops.delete(bm, geom=kill, context='VERTS')
        h = (top - base_z) * height_k
        for v in bm.verts:
            v.co = Vector((v.co.x * (rx + extra), v.co.y * (ry + extra) * squash, v.co.z * (h + extra))) + piv
        bmesh.ops.holes_fill(bm, edges=bm.edges[:], sides=0)

    m = Mesh()
    dome(m.bm("sapka"), 1.02, 0.012)
    loft(m.bm("sapka"), [(Vector((0, c.y - ry * 0.95, base_z + 0.01)), Vector((0, 0.2, 1)), rx * 0.82, ry * 0.55),
                         (Vector((0, c.y - ry * 1.0, base_z + 0.02)), Vector((0, 0.2, 1)), rx * 0.82, ry * 0.55)], 12)
    box(m.bm("sapka"), Vector((0, c.y, top + 0.012)), (0.02, 0.02, 0.012))
    place(m.bm("sapka"))
    m.build("sapka_kasket", parts)

    m = Mesh()
    dome(m.bm("sapka"), 1.08, 0.022)
    loft(m.bm("sapka"), [(Vector((0, c.y, base_z)), UP, rx + 0.055, ry + 0.065), (Vector((0, c.y, base_z + 0.014)), UP, rx + 0.055, ry + 0.065)], 16)
    path_loft(m.bm("sapka"), [Vector((0, c.y - ry - 0.015, top - 0.02)), Vector((0, c.y, top + 0.03)), Vector((0, c.y + ry + 0.015, top - 0.02))],
              0.016, 6, flatten=0.7)
    place(m.bm("sapka"))
    m.build("sapka_baret", parts)

    m = Mesh()
    dome(m.bm("sapka"), 1.2, 0.016)
    loft(m.bm("sapka"), [(Vector((0, c.y, base_z - 0.012)), UP, rx + 0.025, ry + 0.025), (Vector((0, c.y, base_z + 0.04)), UP, rx + 0.027, ry + 0.027)],
         16, jitter=0.02)
    ellipsoid(m.bm("sapka"), (c.x, c.y, top + 0.05), (0.032, 0.032, 0.026), 7, 5)
    place(m.bm("sapka"))
    m.build("sapka_bere", parts)


def accessories(B, parts):
    # Evrak çantası: sağ elde, kol yönünde sarkar
    m = Mesh()
    _, _, w, h, d = B.arm_points(-1)
    grip = w + d * B.arm[2] * 0.6 * B.hand_scale
    box(m.bm("aksesuar"), grip + d * 0.19, (0.07, 0.36, 0.27), bevel=0.012, rot=axis_rot(-d, Vector((1, 0, 0))))
    path_loft(m.bm("siyah"), [grip + Vector((0, -0.05, 0.0)) + d * 0.04, grip + Vector((0, -0.03, 0.0)),
                               grip + Vector((0, 0.03, 0.0)), grip + Vector((0, 0.05, 0.0)) + d * 0.04], 0.008, 5)
    m.build("aks_evrak", parts)

    # Omuz çantası: sol omuzdan sağ kalçaya çapraz
    m = Mesh()
    sz, hz = B.shoulder_z, B.hip_z
    fr = -max(B.chest[1], B.belly[1]) - 0.045 + B.chest_cy
    bk = max(B.chest[1], B.belly[1]) + 0.04
    sw = B.shoulder_w * 0.62
    ribbon(m.bm("aksesuar"), [Vector((sw, -0.02, sz + 0.07)), Vector((sw * 0.4, fr, sz - 0.08)), Vector((-sw * 0.6, fr, hz + 0.25)),
                              Vector((-B.hip[0] - 0.04, -0.04, hz + 0.08))], 0.035, 0.008)
    ribbon(m.bm("aksesuar"), [Vector((sw, 0.03, sz + 0.07)), Vector((sw * 0.4, bk, sz - 0.08)), Vector((-sw * 0.7, bk, hz + 0.25)),
                              Vector((-B.hip[0] - 0.04, 0.04, hz + 0.08))], 0.035, 0.008)
    box(m.bm("aksesuar"), Vector((-B.hip[0] - 0.07, -0.01, hz - 0.01)), (0.06, 0.2, 0.2), bevel=0.015)
    box(m.bm("siyah"), Vector((-B.hip[0] - 0.103, -0.01, hz + 0.04)), (0.004, 0.12, 0.05))
    m.build("aks_omuz", parts)


# Üst kıyafetin tamamen örttüğü deri parçaları (Godot'taki kataloğun aynısı)
TOP_HIDES = {
    "ust_takim": {"deri_govde", "deri_kol_ust", "deri_kol_alt"},
    "ust_kapusonlu": {"deri_govde", "deri_kol_ust", "deri_kol_alt"},
    "ust_isci": {"deri_govde", "deri_kol_ust"},
    "ust_kisa": {"deri_kol_ust", "deri_kol_alt"},
    "ust_tisort": {"deri_govde"},
}


def visible_skin(outfit):
    hide = set()
    for p in outfit:
        hide |= TOP_HIDES.get(p, set())
    return [n for n in ("deri_govde", "deri_kol_ust", "deri_kol_alt") if n not in hide]


def build_clothes(B, parts, tops=None, bottoms=None, shoe_kinds=None):
    for k in tops or ("ust_takim", "ust_kapusonlu", "ust_isci", "ust_kisa", "ust_tisort"):
        top(B, parts, k)
    for k in bottoms or ("alt_takim", "alt_kargo", "alt_kot"):
        bottom(B, parts, k)
    for k in shoe_kinds or ("ayk_spor", "ayk_bot", "ayk_kundura"):
        shoes(B, parts, k)
    hats(B, parts)
    accessories(B, parts)


# ---------------------------------------------------------------------------
# İskelet
# ---------------------------------------------------------------------------
def build_armature(B, chains):
    """chains: [(önek, [nokta...], ebeveyn)] -> önek.0, önek.1 ... kemikleri"""
    arm_data = bpy.data.armatures.new("NpcIskelet")
    arm_obj = bpy.data.objects.new("NpcIskelet", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones

    def add(name, h, t, parent=None, deform=True, connect=False):
        b = eb.new(name)
        b.head, b.tail = Vector(h), Vector(t)
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        return b

    hz, sz = B.hip_z, B.shoulder_z
    add("hips", (0, 0.005, hz), (0, 0.005, hz + 0.12))
    add("spine", (0, 0.005, hz + 0.12), (0, 0.0, sz - 0.2), "hips", connect=True)
    add("chest", (0, 0.0, sz - 0.2), (0, 0.0, sz), "spine", connect=True)
    npts = B.neck_pts
    prev = "chest"
    for i in range(len(npts) - 1):
        name = "neck" if i == 0 else f"neck.{i}"
        add(name, npts[i], npts[i + 1], prev, connect=(i > 0))
        prev = name
    head_top = Vector((B.head_c.x, B.head_c.y, B.head_top))
    if (head_top - npts[-1]).length < 0.05:
        head_top = npts[-1] + Vector((0, 0, 0.15))
    add("head", npts[-1], head_top, prev, connect=True)
    for side, sfx in ((1, "L"), (-1, "R")):
        s, e, w, h, d = B.arm_points(side)
        add(f"upper_arm.{sfx}", s, e, "chest")
        add(f"forearm.{sfx}", e, w, f"upper_arm.{sfx}", connect=True)
        add(f"hand.{sfx}", w, h, f"forearm.{sfx}", connect=True)
        hp, kn, an, toe = B.leg_points(side)
        add(f"thigh.{sfx}", hp, kn, "hips")
        add(f"shin.{sfx}", kn, an, f"thigh.{sfx}", connect=True)
        add(f"foot.{sfx}", an, toe, f"shin.{sfx}", connect=True)
    for prefix, pts, parent in chains:
        prev = parent
        for i in range(len(pts) - 1):
            name = f"{prefix}.{i}"
            add(name, pts[i], pts[i + 1], prev, connect=(i > 0))
            prev = name
    for sfx, side in (("L", 1), ("R", -1)):
        f = eb[f"foot.{sfx}"]
        add(f"ik_foot.{sfx}", f.head, f.tail, deform=False)
        add(f"pole_knee.{sfx}", (0.1 * side, -0.6, B.knee_z), (0.1 * side, -0.65, B.knee_z), deform=False)
        hd = eb[f"hand.{sfx}"]
        add(f"ik_hand.{sfx}", hd.head, hd.tail, deform=False)
        e = eb[f"forearm.{sfx}"].head
        add(f"pole_elbow.{sfx}", (e.x, 0.5, e.z), (e.x, 0.55, e.z), deform=False)
    bpy.ops.object.mode_set(mode='POSE')
    pb = arm_obj.pose.bones
    for sfx in ("L", "R"):
        c = pb[f"shin.{sfx}"].constraints.new('IK')
        c.target, c.subtarget = arm_obj, f"ik_foot.{sfx}"
        c.pole_target, c.pole_subtarget = arm_obj, f"pole_knee.{sfx}"
        c.pole_angle = math.radians(-90)
        c.chain_count = 2
        cr = pb[f"foot.{sfx}"].constraints.new('COPY_ROTATION')
        cr.target, cr.subtarget = arm_obj, f"ik_foot.{sfx}"
        c = pb[f"forearm.{sfx}"].constraints.new('IK')
        c.target, c.subtarget = arm_obj, f"ik_hand.{sfx}"
        c.pole_target, c.pole_subtarget = arm_obj, f"pole_elbow.{sfx}"
        c.pole_angle = math.radians(129 if sfx == "L" else 51)   # ana karakterde kalibre edildi
        c.chain_count = 2
    for p in pb:
        p.rotation_mode = 'XYZ'
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm_obj


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def _match(bname, prefixes):
    return any(bname == p or bname.startswith(p + ".") for p in prefixes)


TORSO_BONES = ["hips", "spine", "chest", "neck"]
ARM_BONES = [f"{b}.{s}" for s in ("L", "R") for b in ("upper_arm", "forearm", "hand")]
LEG_BONES = [f"{b}.{s}" for s in ("L", "R") for b in ("thigh", "shin", "foot")]


def _dist_weights(p, cand, segs, power=4, keep=3):
    ws = []
    for bname in cand:
        if bname not in segs:
            continue
        d = seg_dist(p, *segs[bname]) + 0.01
        ws.append((1.0 / d ** power, bname))
    ws.sort(reverse=True)
    ws = ws[:keep]
    total = sum(w for w, _ in ws) or 1.0
    return {b: w / total for w, b in ws}


def _smooth(a, b, x):
    k = max(0.0, min(1.0, (x - a) / (b - a)))
    return k * k * (3 - 2 * k)


def arm_share(p, B, loose=0.015, tagged=False):
    """Bir noktanın kola ait olma payı (0 gövde ... 1 kol). Omuz ekleminden kol yönünde
    ilerledikçe ve kol ekseninden uzaklaşmadıkça artar: omuz başı yumuşak döner, koltuk
    altındaki gövde ve trapez kolla birlikte çökmez."""
    side = 1 if p.x > 0 else -1
    s, e, w, h, d = B.arm_points(side)
    q = p - s
    t = q.dot(d)
    radial = (q - d * t).length
    r = B.arm_r[0] + loose
    if tagged:
        # Kol / kolluk geometrisi: yalnız omuz ekleminde gövdeyle karışır
        return _smooth(-0.05, 0.05, t)
    # Gövde geometrisi: yalnız omuz başında, kol ekseninin hemen çevresinde
    return _smooth(-0.02, 0.08, t) * (1.0 - _smooth(r * 1.0, r * 1.45, radial))


def skin(obj, arm_obj, rule, bones=None, B=None):
    """rule: 'fixed' (tek kemik), 'dist' (kemiklere uzaklıkla), 'upper' (gövde + kollar, omuz
    payıyla), 'top' (upper + etek kalçaya), 'foot', 'pants'.
    'g:<önekler>' köşe grupları (Mesh.bm(mat, grp)) yalnız o kemiklerden ağırlık alır."""
    segs = {b.name: (Vector(b.head_local), Vector(b.tail_local)) for b in arm_obj.data.bones if b.use_deform}
    groups = {}
    grp_of = {}
    hint_groups = [vg for vg in obj.vertex_groups if vg.name.startswith("g:")]
    if hint_groups:
        idx_name = {vg.index: vg.name[2:].split("|") for vg in hint_groups}
        for v in obj.data.vertices:
            for g in v.groups:
                if g.group in idx_name and g.weight > 0.5:
                    grp_of[v.index] = idx_name[g.group]
        for vg in hint_groups:
            obj.vertex_groups.remove(vg)

    def add(bname, idx, w):
        if bname not in groups:
            groups[bname] = obj.vertex_groups.new(name=bname)
        groups[bname].add([idx], w, 'REPLACE')

    arm_b = [b for b in ARM_BONES if b in segs]
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        cand = bones
        tag = grp_of.get(v.index, [""])[0]
        if rule in ("upper", "top") and (tag.startswith("arm.") or not tag):
            k = arm_share(p, B, tagged=tag.startswith("arm."))
            body = [b for b in cand if b not in arm_b]
            if rule == "top" and p.z < B.hip_z + 0.12 and not tag:
                tw = {"hips": 1.0}
            else:
                tw = _dist_weights(p, body, segs)
            ws = {b: w * (1 - k) for b, w in tw.items()}
            if k > 0.001:
                side = tag[-1] if tag else ("L" if p.x > 0 else "R")
                for b, w in _dist_weights(p, [b for b in arm_b if b.endswith(side)], segs).items():
                    ws[b] = ws.get(b, 0.0) + w * k
        elif rule == "pants":
            if p.z > B.hip_z - 0.02:
                add("hips", v.index, 1.0)
                continue
            g = grp_of.get(v.index, [""])[0]
            if g.startswith("leg."):
                side = g[-1]
            else:
                side = "L" if seg_dist(p, *segs["thigh.L"]) < seg_dist(p, *segs["thigh.R"]) else "R"
            k = _smooth(B.hip_z - 0.14, B.hip_z - 0.02, p.z)
            ws = {b: w * (1 - k) for b, w in _dist_weights(p, [f"thigh.{side}", f"shin.{side}", f"foot.{side}"], segs).items()}
            ws["hips"] = ws.get("hips", 0.0) + k
        elif v.index in grp_of:
            cand = [b for b in segs if _match(b, grp_of[v.index])]
            if len(cand) == 1:
                add(cand[0], v.index, 1.0)
                continue
            ws = _dist_weights(p, cand, segs)
        elif rule == "fixed":
            add(bones, v.index, 1.0)
            continue
        elif rule == "foot":
            add("foot.L" if p.x > 0 else "foot.R", v.index, 1.0)
            continue
        else:
            ws = _dist_weights(p, [cand] if isinstance(cand, str) else cand, segs)
        for b, w in ws.items():
            if w > 0.002:
                add(b, v.index, w)
    obj.parent = arm_obj
    obj.matrix_parent_inverse.identity()
    mod = obj.modifiers.new("Iskelet", 'ARMATURE')
    mod.object = arm_obj


# ---------------------------------------------------------------------------
# Animasyon çatısı
# ---------------------------------------------------------------------------
class Animator:
    def __init__(self, arm_obj, B):
        self.arm = arm_obj
        self.B = B
        self.rest = {b.name: Vector(b.head_local) for b in arm_obj.data.bones}
        self.actions = []
        self.neck = [b.name for b in arm_obj.data.bones if b.name == "neck" or b.name.startswith("neck.")]
        self.scaled = set()            # ölçeği canlandırılan kemikler (gırtlak kesesi vb.)

    def to_local(self, bone, delta):
        b = self.arm.data.bones[bone]
        return b.matrix_local.to_3x3().inverted() @ Vector(delta)

    def apply(self, pose):
        pb = self.arm.pose.bones
        for p in pb:
            p.location = (0, 0, 0)
            p.rotation_euler = (0, 0, 0)
        pb["hips"].location = self.to_local("hips", pose.get("hips", (0, 0, 0)))
        quats = {}
        for bone, rot in pose.get("rot", {}).items():
            if bone in pb:
                quats[bone] = Euler([math.radians(a) for a in rot], 'XYZ').to_quaternion()
        # Dünya ekseni etrafında dönüşler (kulak, kuyruk, hortum gibi yan yatık kemikler için)
        for bone, lst in pose.get("wrot", {}).items():
            if bone not in pb:
                continue
            q = quats.get(bone, Quaternion())
            for axis, deg in lst:
                la = self.to_local(bone, Vector(axis)).normalized()
                q = q @ Quaternion(la, math.radians(deg))
            quats[bone] = q
        for bone, q in quats.items():
            pb[bone].rotation_euler = q.to_euler('XYZ')
        for p in pb:
            p.scale = (1, 1, 1)
        for bone, sc in pose.get("scale", {}).items():
            if bone in pb:
                pb[bone].scale = sc
        for sfx in ("L", "R"):
            for key, bone in ((f"foot.{sfx}", f"ik_foot.{sfx}"), (f"hand.{sfx}", f"ik_hand.{sfx}"),
                              (f"knee.{sfx}", f"pole_knee.{sfx}"), (f"elbow.{sfx}", f"pole_elbow.{sfx}")):
                if key in pose:
                    pb[bone].location = self.to_local(bone, Vector(pose[key]) - self.rest[bone])
            if f"foot_rot.{sfx}" in pose:
                pb[f"ik_foot.{sfx}"].rotation_euler = [math.radians(a) for a in pose[f"foot_rot.{sfx}"]]
            if f"hand_rot.{sfx}" in pose:
                pb[f"ik_hand.{sfx}"].rotation_euler = [math.radians(a) for a in pose[f"hand_rot.{sfx}"]]

    def key(self, frame, pose):
        self.apply(pose)
        for p in self.arm.pose.bones:
            p.keyframe_insert("location", frame=frame)
            p.keyframe_insert("rotation_euler", frame=frame)
            if p.name in self.scaled:
                p.keyframe_insert("scale", frame=frame)

    def action(self, name):
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        if self.arm.animation_data is None:
            self.arm.animation_data_create()
        self.arm.animation_data.action = act
        self.actions.append(name)

    @staticmethod
    def add_rot(pose, bone, rot):
        r = pose["rot"].get(bone, (0, 0, 0))
        pose["rot"][bone] = tuple(a + b for a, b in zip(r, rot))

    @staticmethod
    def add_wrot(pose, bone, axis, deg):
        pose.setdefault("wrot", {}).setdefault(bone, []).append((axis, deg))

    def spread_neck(self, pose, rot, head_share=0.35):
        """Bir baş hareketini (pitch, yaw, roll) boyun zinciri ve kafaya paylaştır."""
        n = len(self.neck)
        for b in self.neck:
            self.add_rot(pose, b, tuple(a * (1 - head_share) / n for a in rot))
        self.add_rot(pose, "head", tuple(a * head_share for a in rot))

    # --- Duruş ---
    def hand_rest(self, side, out=0.0, fwd=0.0, up=0.0):
        B = self.B
        reach = (B.arm[0] + B.arm[1]) * 0.955
        x = (B.shoulder_w + B.deltoid * 0.6 + 0.02 + out) * side
        dx = x - B.shoulder_w * side
        z = B.shoulder_z - math.sqrt(max(reach * reach - dx * dx, 0.01))
        return (x, 0.02 + fwd, z + up)

    def stand(self, **over):
        B = self.B
        p = {"hips": (0, 0, -0.012), "rot": {}}
        for sfx, side in (("L", 1), ("R", -1)):
            hp, kn, an, _ = B.leg_points(side)
            p[f"foot.{sfx}"] = (an.x, 0.01, 0.085)
            p[f"hand.{sfx}"] = self.hand_rest(side)
            p[f"knee.{sfx}"] = (0.15 * side, -0.7, B.knee_z)
            p[f"elbow.{sfx}"] = ((B.shoulder_w + 0.04) * side, 0.6, B.shoulder_z - B.arm[0] * 1.2)
            p[f"hand_rot.{sfx}"] = (-10, 0, 6 * side)
        if B.spine_lean:
            p["rot"]["spine"] = (B.spine_lean * 0.6, 0, 0)
            p["rot"]["chest"] = (B.spine_lean * 0.4, 0, 0)
            self.spread_neck(p, (-B.spine_lean * 0.8, 0, 0), 0.5)
        for k, v in over.items():
            if k == "rot":
                for b, r in v.items():
                    self.add_rot(p, b, r)
            else:
                p[k] = v
        return p

    @staticmethod
    def gait_foot(u, amp, duty, lift):
        u = u % 1.0
        if u < duty:
            k = u / duty
            y = -amp + 2 * amp * k
            z = 0.0
            pitch = -30 * (k - 0.8) / 0.2 if k > 0.8 else 0.0
        else:
            k = (u - duty) / (1 - duty)
            sm = k * k * (3 - 2 * k)
            y = amp - 2 * amp * sm
            z = math.sin(math.pi * k) * lift
            pitch = -30 * (1 - k) + 10 * math.sin(math.pi * k)
        return y, z, pitch


DEFAULT_STYLE = {
    "frames": 24, "amp": 0.32, "duty": 0.6, "lift": 0.09, "width": None,
    "bob": 0.014, "sway": 0.008, "roll": 2.0, "twist": 4.0, "lean": 3.0,
    "arm_swing": 0.13, "arm_out": 0.0, "arm_fwd": 0.0, "arm_lift": 0.0, "head_stab": 0.8,
    "toe_out": 6.0, "bounce": 0.0, "stiff": 0.0, "stumble_arms": 1.0,
}


def standard_actions(A, style=None, secondary=None):
    """Tüm türlerin ortak hareket seti; türün karakteri style ve secondary ile gelir.
    secondary(pose, kind, ph, f): kind = walk / idle / look / stumble; ph = 0..2π döngü evresi."""
    S = dict(DEFAULT_STYLE)
    S.update(style or {})
    B = A.B
    sec = secondary or (lambda pose, kind, ph, f: None)

    # --- Yürüyüş ---
    A.action("walk")
    n = S["frames"]
    for f in range(0, n + 1):
        u = f / n
        ph = math.tau * u
        bob = -S["bob"] * math.cos(2 * ph) - S["bounce"] * abs(math.sin(ph))
        pose = A.stand(hips=(S["sway"] * math.sin(ph), 0.0, -0.022 + bob))
        A.add_rot(pose, "hips", (0, S["twist"] * 0.5 * math.cos(ph), S["roll"] * math.sin(ph)))
        A.add_rot(pose, "spine", (S["lean"] * 0.6, -S["twist"] * math.cos(ph), -S["roll"] * 0.6 * math.sin(ph)))
        A.add_rot(pose, "chest", (S["lean"] * 0.4, -S["twist"] * 0.6 * math.cos(ph), -S["roll"] * 0.3 * math.sin(ph)))
        # Bakış sabit: gövde eğimi ve yalpasını boyun / kafa telafi eder
        A.spread_neck(pose, (-S["lean"] * S["head_stab"] + 1.5 * math.cos(2 * ph) * S["head_stab"],
                             S["twist"] * 1.2 * math.cos(ph) * S["head_stab"], 0), 0.5)
        for sfx, side, off in (("L", 1, 0.0), ("R", -1, 0.5)):
            y, z, pitch = A.gait_foot(u + off, S["amp"], S["duty"], S["lift"])
            fx = (S["width"] if S["width"] is not None else B.foot_x * 0.92) * side
            pose[f"foot.{sfx}"] = (fx, y, 0.085 + z)
            pose[f"foot_rot.{sfx}"] = (pitch, 0, S["toe_out"] * side)
        sw = S["arm_swing"]
        for sfx, side, sgn in (("L", 1, 1), ("R", -1, -1)):
            x, y0, z0 = A.hand_rest(side, S["arm_out"], S["arm_fwd"], S["arm_lift"])
            k = sgn * math.cos(ph)
            pose[f"hand.{sfx}"] = (x, y0 + sw * k, z0 + abs(k) * sw * 0.18 + (0.02 if k < 0 else 0) * sw / 0.13)
            pose[f"hand_rot.{sfx}"] = (-10 - 12 * k * sw / 0.13, 0, 6 * side)
        sec(pose, "walk", ph, f)
        A.key(f, pose)

    # --- Bekleme: nefes, ağırlık aktarma ---
    A.action("idle")
    n = 96
    for f in range(0, n + 1, 4):
        ph = math.tau * f / n
        br = math.sin(ph * 2)
        shift = math.sin(ph)
        pose = A.stand(hips=(0.012 * shift, 0, -0.012 - 0.004 * br))
        A.add_rot(pose, "hips", (0, 0, -2.0 * shift))
        A.add_rot(pose, "spine", (0, 0, 1.4 * shift))
        A.add_rot(pose, "chest", (-1.5 * br, 0, 0.6 * shift))
        A.spread_neck(pose, (1.2 * br, 2.5 * math.sin(ph + 1), 1.0 * shift), 0.5)
        pose["foot.L"] = (B.foot_x, 0.01, 0.085)
        pose["foot.R"] = (-B.foot_x, 0.03, 0.085)
        for sfx, side in (("L", 1), ("R", -1)):
            x, y0, z0 = A.hand_rest(side)
            pose[f"hand.{sfx}"] = (x, y0, z0 + 0.006 * br)
        sec(pose, "idle", ph, f)
        A.key(f, pose)

    # --- Etrafa bakınma ---
    A.action("idle_look")
    keys = [(0, 0, 0), (18, 38, -6), (44, 38, -6), (62, -32, 2), (90, -32, 2), (110, 0, 0)]
    for f, yaw, pitch in keys:
        ph = math.tau * f / 110
        pose = A.stand()
        A.add_rot(pose, "chest", (0, yaw * 0.15, 0))
        A.spread_neck(pose, (pitch, yaw * 0.85, 0), 0.45)
        sec(pose, "look", ph, f)
        A.key(f, pose)

    # --- Affallama: önden çarpılır, geri sendeler, kollar havaya, toparlanır, silkinir ---
    A.action("stumble")
    sz = B.shoulder_z
    keys = [
        # kare, kalça (y, z), gövde, kollar yukarı oranı, ayak L y, R y, kafa (pitch, roll)
        (0, (0.0, -0.012), 3, 0.0, 0.01, 0.01, (0, 0)),
        (3, (0.06, -0.02), -22, 0.8, 0.01, 0.01, (-24, 0)),
        (8, (0.16, -0.05), -18, 1.0, 0.01, 0.28, (-14, 6)),
        (14, (0.25, -0.06), -10, 0.8, 0.36, 0.28, (-6, -8)),
        (20, (0.22, -0.05), 8, 0.4, 0.3, 0.26, (10, 0)),
        (26, (0.12, -0.03), 4, 0.15, 0.14, 0.1, (4, 14)),
        (30, (0.06, -0.02), 2, 0.05, 0.05, 0.04, (2, -14)),
        (36, (0.0, -0.012), 3, 0.0, 0.01, 0.01, (0, 0)),
    ]
    for f, (hy, hz), spine, armk, fl, fr, (hp, hr) in keys:
        armk *= S["stumble_arms"]
        pose = A.stand(hips=(0.0, hy, hz))
        A.add_rot(pose, "spine", (spine, 0, 0))
        A.spread_neck(pose, (hp - spine * 0.5, 0, hr), 0.5)
        lift_l = 0.06 if f == 14 else 0.0
        lift_r = 0.06 if f == 8 else 0.0
        pose["foot.L"] = (B.foot_x, fl, 0.085 + lift_l)
        pose["foot.R"] = (-B.foot_x, fr, 0.085 + lift_r)
        for sfx, side in (("L", 1), ("R", -1)):
            x, y0, z0 = A.hand_rest(side)
            up_x = (B.shoulder_w + B.arm[0] * 0.8) * side
            up_z = sz + B.arm[1] * 0.4
            pose[f"hand.{sfx}"] = (x + (up_x - x) * armk, y0 - 0.1 * armk + (0.04 if side < 0 else 0), z0 + (up_z - z0) * armk)
            if armk > 0.5:
                pose[f"elbow.{sfx}"] = ((B.shoulder_w + 0.2) * side, 0.3, sz - 0.5)
                pose[f"hand_rot.{sfx}"] = (-30, 0, 30 * side)
        sec(pose, "stumble", f / 36.0, f)
        A.key(f, pose)


def walk_speed(style):
    S = dict(DEFAULT_STYLE)
    S.update(style or {})
    return 2 * S["amp"] / (S["duty"] * S["frames"] / 30.0)


# ---------------------------------------------------------------------------
# Ön izleme
# ---------------------------------------------------------------------------
def setup_render(res=(480, 760)):
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    sh = scene.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_cavity = True
    sh.cavity_type = 'BOTH'
    sh.show_object_outline = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.22, 0.22, 0.23)
    scene.render.film_transparent = False
    return scene


def render_view(path, target_z, height, angle_deg, dist=8.0, elev_deg=6.0, res=(480, 760)):
    scene = setup_render(res)
    cam = scene.camera
    if cam is None:
        cd = bpy.data.cameras.new("Kamera")
        cd.type = 'ORTHO'
        cam = bpy.data.objects.new("Kamera", cd)
        scene.collection.objects.link(cam)
        scene.camera = cam
    cam.data.ortho_scale = height
    a = math.radians(angle_deg)
    e = math.radians(elev_deg)
    tgt = Vector((0, 0, target_z))
    cam.location = tgt + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (math.radians(90) - e, 0, a)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def stitch(paths, out, cols=None):
    import numpy as np
    imgs = [bpy.data.images.load(p) for p in paths]
    w, h = imgs[0].size
    cols = cols or len(imgs)
    rows = (len(imgs) + cols - 1) // cols
    canvas = np.zeros((rows * h, cols * w, 4), dtype=np.float32)
    canvas[..., 3] = 1.0
    for i, im in enumerate(imgs):
        a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
        r = rows - 1 - i // cols
        c = i % cols
        canvas[r * h:(r + 1) * h, c * w:(c + 1) * w] = a
    o = bpy.data.images.new("birlesik", cols * w, rows * h)
    o.pixels.foreach_set(canvas.ravel())
    o.filepath_raw = out
    o.file_format = 'PNG'
    o.save()
    for im in imgs:
        bpy.data.images.remove(im)
    for p in paths:
        try:
            os.remove(p)
        except OSError:
            pass
    return out
