"""Müzik çalar (2000'lerin cep müzik çaları, iPod'dan esinli; marka / logo yok) ve kulaklık. Tek .glb.

  blender --background --factory-startup --python tools/blender/muzikcalar_build.py -- [cikti.glb] [onizleme_klasoru]

Ölçü gerçek boyut (metre): 62 x 104 x 11 mm. Ön yüz Blender -Y (Godot +Z), üst kenar +Z (Godot +Y).
Godot düğümleri adlarıyla bulur:
  "Govde"     ön yüz (beyaz parlak), arka ve yanlar (krom), üstte kulaklık girişi ve kilit düğmesi
              (çıkartma yok: oyunda katman olarak eklenir)
  "Ekran"     ekran camı: UV 0..1 (320 x 240 oranında), oyunda canlı görüntü dokusu basılır
  "Tekerlek"  tıklama tekerleği ve üstündeki işaretler (MENU, geri, ileri, oynat / durdur)
  "OrtaTus"   ortadaki düğme (tekrar / döngü)
  "GucTus"    sağ alt köşede güç düğmesi (aç / kapat)
  "Kulaklik"  kulak içi kulaklık (tek; ikisi de bununla çizilir), kablo bağlantısı +Z
  "Fis"       3.5 mm kulaklık fişi
Renk köşe renginde (shaders/toon_vc ile); Ekran'ın kendi malzemesi var.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0]) if args else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "muzikcalar", "muzikcalar.glb")
PREVIEW = os.path.abspath(args[1]) if len(args) > 1 else None

for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)

MM = 0.001
W, H, T = 62 * MM, 104 * MM, 11 * MM
FRONT_Y = -T * 0.5

WHITE = (0.96, 0.96, 0.95)
CHROME_A = (0.93, 0.94, 0.97)
CHROME_B = (0.34, 0.36, 0.42)
WHEEL = (0.84, 0.84, 0.85)
WHEEL_RIM = (0.72, 0.72, 0.74)
MARK = (0.4, 0.41, 0.44)
BEZEL = (0.1, 0.1, 0.12)


def mesh_obj(name, bm, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if "Col" in me.color_attributes:
        me.color_attributes.active_color = me.color_attributes["Col"]
    return ob


def paint(bm, faces, fn):
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in faces:
        for l in f.loops:
            c = fn(f, l.vert)
            l[col] = (c[0], c[1], c[2], 1.0)


def rounded_rect(cx, cz, w, h, r, seg=6):
    """XZ düzleminde yuvarlak köşeli dikdörtgen çevresi (saat yönü tersine)."""
    pts = []
    for (sx, sz, a0) in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        ccx, ccz = cx + sx * (w * 0.5 - r), cz + sz * (h * 0.5 - r)
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((ccx + math.cos(a) * r, ccz + math.sin(a) * r))
    return pts


def prism(bm, outline, y0, y1, color_front, color_side=None):
    """Çevre çizgisinden Y boyunca kalınlık: ön yüzü y0'da (öne bakar, -Y)."""
    v0 = [bm.verts.new((x, y0, z)) for (x, z) in outline]
    v1 = [bm.verts.new((x, y1, z)) for (x, z) in outline]
    front = bm.faces.new(v0)
    front.normal_update()
    if front.normal.y > 0.0:          # ön yüz öne (-Y) baksın
        front.normal_flip()
    faces = [front]
    n = len(outline)
    sides = []
    cx = sum(p[0] for p in outline) / n
    cz = sum(p[1] for p in outline) / n
    for i in range(n):
        j = (i + 1) % n
        sf = bm.faces.new((v0[i], v0[j], v1[j], v1[i]))
        sf.normal_update()
        mid = (v0[i].co + v0[j].co) * 0.5
        if sf.normal.dot(Vector((mid.x - cx, 0.0, mid.z - cz))) < 0.0:   # yan yüz dışa baksın
            sf.normal_flip()
        sides.append(sf)
    paint(bm, faces, lambda f, v: color_front)
    paint(bm, sides, lambda f, v: color_side or color_front)
    return faces + sides


# ---------- Gövde ----------
bm = bmesh.new()
res = bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * W, v.co.y * T, v.co.z * H))
# Dikey kenarlar yuvarlak (köşe yarıçapı ~8 mm), sonra her kenara ince pah
vert_edges = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > H * 0.5]
bmesh.ops.bevel(bm, geom=vert_edges, offset=8 * MM, segments=5, affect='EDGES', profile=0.5)
# Sonra ön ve arka çevre kenarları: arka geniş yuvarlak (krom kabuk), ön ince pah
front_edges = [e for e in bm.edges if all(abs(v.co.y - FRONT_Y) < 1e-6 for v in e.verts)]
back_edges = [e for e in bm.edges if all(abs(v.co.y + FRONT_Y) < 1e-6 for v in e.verts)]
bmesh.ops.bevel(bm, geom=back_edges, offset=3.2 * MM, segments=3, affect='EDGES', profile=0.5)
front_edges = [e for e in bm.edges if e.is_valid and all(abs(v.co.y - FRONT_Y) < 1e-6 for v in e.verts)]
# Ön çevre: ince pah
bmesh.ops.bevel(bm, geom=front_edges, offset=0.9 * MM, segments=1, affect='EDGES')
bm.normal_update()


def body_color(f, v):
    n = f.normal
    if n.y < -0.9:
        return WHITE
    # Krom: yansıma şeritleri (yükseklik ve yana göre açık / koyu)
    # Ayna krom: keskin açık / koyu bantlar (eğik), aralarında yumuşak geçiş
    u = v.co.z / H * 2.2 + v.co.x / W * 1.3
    t = 0.5 + 0.5 * math.sin(u * math.tau)
    t = t ** 3 if t < 0.5 else 1.0 - (1.0 - t) ** 0.6 * 0.5
    base = tuple(CHROME_B[i] + (CHROME_A[i] - CHROME_B[i]) * t for i in range(3))
    if n.y < -0.3:
        return tuple(0.5 * (base[i] + WHITE[i]) for i in range(3))
    return base


paint(bm, list(bm.faces), body_color)

# Üst kenar: kulaklık girişi (koyu halka) ve kilit düğmesi
top = H * 0.5
jack = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=2.2 * MM, radius2=2.2 * MM, depth=0.6 * MM,
                             matrix=Matrix.Translation((W * 0.28, 0, top + 0.1 * MM)))
paint(bm, list({f for v in jack["verts"] for f in v.link_faces}), lambda f, v: (0.12, 0.12, 0.13))
hold = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((-W * 0.3, 0, top + 0.5 * MM)) @ Matrix.Diagonal((7 * MM, 3 * MM, 1.2 * MM, 1)))
paint(bm, list({f for v in hold["verts"] for f in v.link_faces}), lambda f, v: (0.75, 0.76, 0.78))
hold_tab = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((-W * 0.3 - 1.8 * MM, 0, top + 1.2 * MM)) @ Matrix.Diagonal((2.5 * MM, 2 * MM, 0.8 * MM, 1)))
paint(bm, list({f for v in hold_tab["verts"] for f in v.link_faces}), lambda f, v: (0.95, 0.5, 0.15))

# Ekran çerçevesi (koyu, ön yüzden çok az çıkık)
SCR_W, SCR_H = 50 * MM, 37.5 * MM
SCR_CZ = 23 * MM
prism(bm, rounded_rect(0, SCR_CZ, SCR_W + 3 * MM, SCR_H + 3 * MM, 2.0 * MM, 4), FRONT_Y - 0.15 * MM, FRONT_Y + 0.05 * MM, BEZEL)

# Çıkartmalar modelde değil: oyunda katman olarak eklenir (scripts/ui/cihaz_sticker.gd)

mesh_obj("Govde", bm)

# ---------- Ekran (canlı görüntü) ----------
bm = bmesh.new()
uv = bm.loops.layers.uv.new("UVMap")
yv = FRONT_Y - 0.2 * MM
q = [bm.verts.new((x, yv, z)) for (x, z) in ((-SCR_W / 2, SCR_CZ - SCR_H / 2), (SCR_W / 2, SCR_CZ - SCR_H / 2),
                                            (SCR_W / 2, SCR_CZ + SCR_H / 2), (-SCR_W / 2, SCR_CZ + SCR_H / 2))]
f = bm.faces.new((q[0], q[1], q[2], q[3]))       # öne (-Y) bakar
for l in f.loops:
    co = l.vert.co
    l[uv].uv = ((co.x + SCR_W / 2) / SCR_W, (co.z - (SCR_CZ - SCR_H / 2)) / SCR_H)
ob = mesh_obj("Ekran", bm)
mat = bpy.data.materials.new("ekran")
ob.data.materials.append(mat)

# ---------- Tıklama tekerleği ----------
WCZ = -21 * MM
WR = 19.5 * MM
bm = bmesh.new()
ring = [(math.cos(a) * WR, WCZ + math.sin(a) * WR) for a in [k / 48 * math.tau for k in range(48)]]
prism(bm, ring, FRONT_Y - 0.35 * MM, FRONT_Y + 0.01 * MM, WHEEL, WHEEL_RIM)
y_mark = FRONT_Y - 0.4 * MM


def mark(pts):
    prism(bm, pts, y_mark, FRONT_Y - 0.34 * MM, MARK)


# MENU: dört küçük harf yerine çizgili sembol (3 yatay çizgi) — marka yazısı yok, okunur
for k in range(3):
    zc = WCZ + WR * 0.72 + (k - 1) * 1.5 * MM
    mark([(-3.0 * MM, zc - 0.4 * MM), (3.0 * MM, zc - 0.4 * MM), (3.0 * MM, zc + 0.4 * MM), (-3.0 * MM, zc + 0.4 * MM)])
# İleri (sağ): iki üçgen ve çubuk
xr = WR * 0.72
for off in (-1.6, 0.6):
    x0 = xr + off * MM - 1.1 * MM
    mark([(x0, WCZ - 1.6 * MM), (x0 + 2.2 * MM, WCZ), (x0, WCZ + 1.6 * MM)])
mark([(xr + 1.9 * MM, WCZ - 1.6 * MM), (xr + 2.5 * MM, WCZ - 1.6 * MM), (xr + 2.5 * MM, WCZ + 1.6 * MM), (xr + 1.9 * MM, WCZ + 1.6 * MM)])
# Geri (sol): ayna
xl = -WR * 0.72
for off in (-0.6, 1.6):
    x0 = xl + off * MM + 1.1 * MM
    mark([(x0, WCZ - 1.6 * MM), (x0, WCZ + 1.6 * MM), (x0 - 2.2 * MM, WCZ)])
mark([(xl - 2.5 * MM, WCZ - 1.6 * MM), (xl - 1.9 * MM, WCZ - 1.6 * MM), (xl - 1.9 * MM, WCZ + 1.6 * MM), (xl - 2.5 * MM, WCZ + 1.6 * MM)])
# Oynat / durdur (alt): üçgen ve iki çubuk
zb = WCZ - WR * 0.72
mark([(-3.2 * MM, zb - 1.5 * MM), (-0.6 * MM, zb), (-3.2 * MM, zb + 1.5 * MM)])
for x0 in (0.6, 2.2):
    mark([(x0 * MM, zb - 1.5 * MM), ((x0 + 0.9) * MM, zb - 1.5 * MM), ((x0 + 0.9) * MM, zb + 1.5 * MM), (x0 * MM, zb + 1.5 * MM)])
mesh_obj("Tekerlek", bm)

# Orta düğme: hafif kubbe, üstünde döngü işareti (halka ve ok)
bm = bmesh.new()
CR = 7.2 * MM
disc = [(math.cos(a) * CR, WCZ + math.sin(a) * CR) for a in [k / 32 * math.tau for k in range(32)]]
prism(bm, disc, FRONT_Y - 0.55 * MM, FRONT_Y - 0.3 * MM, (0.97, 0.97, 0.96), (0.85, 0.85, 0.84))
y_c = FRONT_Y - 0.6 * MM
segs = 20
for k in range(segs - 4):
    a0 = math.radians(60 + k * 300 / (segs - 4))
    a1 = math.radians(60 + (k + 1) * 300 / (segs - 4))
    ri, ro = 2.4 * MM, 3.1 * MM
    pts = [(math.cos(a0) * ri, WCZ + math.sin(a0) * ri), (math.cos(a1) * ri, WCZ + math.sin(a1) * ri),
           (math.cos(a1) * ro, WCZ + math.sin(a1) * ro), (math.cos(a0) * ro, WCZ + math.sin(a0) * ro)]
    prism(bm, pts, y_c, FRONT_Y - 0.54 * MM, (0.7, 0.71, 0.73))
a = math.radians(60)
tip = (math.cos(a) * 2.75 * MM, WCZ + math.sin(a) * 2.75 * MM)
prism(bm, [(tip[0] - 1.3 * MM, tip[1] + 0.3 * MM), (tip[0] + 0.9 * MM, tip[1] + 1.2 * MM), (tip[0] + 0.5 * MM, tip[1] - 1.2 * MM)],
      y_c, FRONT_Y - 0.54 * MM, (0.7, 0.71, 0.73))
mesh_obj("OrtaTus", bm)

# Güç düğmesi: sağ alt köşe (çıkartmanın karşısı), gri yuvarlak, üstünde güç işareti (halka + çizgi)
GX, GZ, GR = 21.5 * MM, -45.0 * MM, 3.6 * MM
bm = bmesh.new()
disc = [(GX + math.cos(a) * GR, GZ + math.sin(a) * GR) for a in [k / 24 * math.tau for k in range(24)]]
prism(bm, disc, FRONT_Y - 0.5 * MM, FRONT_Y + 0.01 * MM, (0.8, 0.81, 0.83), (0.62, 0.63, 0.66))
y_g = FRONT_Y - 0.56 * MM
for k in range(14):
    a0 = math.radians(125 + k * 290 / 14)
    a1 = math.radians(125 + (k + 1) * 290 / 14)
    ri, ro = 1.5 * MM, 2.1 * MM
    pts = [(GX + math.cos(a0) * ri, GZ + math.sin(a0) * ri), (GX + math.cos(a1) * ri, GZ + math.sin(a1) * ri),
           (GX + math.cos(a1) * ro, GZ + math.sin(a1) * ro), (GX + math.cos(a0) * ro, GZ + math.sin(a0) * ro)]
    prism(bm, pts, y_g, FRONT_Y - 0.49 * MM, (0.85, 0.2, 0.18))
prism(bm, [(GX - 0.3 * MM, GZ + 0.2 * MM), (GX + 0.3 * MM, GZ + 0.2 * MM), (GX + 0.3 * MM, GZ + 2.4 * MM), (GX - 0.3 * MM, GZ + 2.4 * MM)],
      y_g, FRONT_Y - 0.49 * MM, (0.85, 0.2, 0.18))
mesh_obj("GucTus", bm)

# ---------- Kulaklık ve fiş ----------
bm = bmesh.new()
bud = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=8 * MM)
for v in bud["verts"]:
    v.co.z *= 0.75
neck = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=2.6 * MM, radius2=1.6 * MM, depth=12 * MM,
                             matrix=Matrix.Translation((0, 0, 9 * MM)))
grill = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=5.4 * MM, radius2=5.4 * MM, depth=0.8 * MM,
                              matrix=Matrix.Translation((0, -5.9 * MM, 0)) @ Matrix.Rotation(math.radians(90), 4, 'X'))
paint(bm, list(bm.faces), lambda f, v: (0.97, 0.97, 0.96))
paint(bm, list({f for v in grill["verts"] for f in v.link_faces}), lambda f, v: (0.62, 0.63, 0.66))
mesh_obj("Kulaklik", bm, smooth=True)

# Fiş: kulaklık girişine takılı (ucu gövdenin içinde), üstünde kablo koruyucusu
JACK = Vector((W * 0.28, 0, top))
bm = bmesh.new()
plug = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=2.8 * MM, radius2=2.5 * MM, depth=13 * MM,
                             matrix=Matrix.Translation(JACK + Vector((0, 0, 7.1 * MM))))
relief = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=2.0 * MM, radius2=1.25 * MM, depth=9 * MM,
                               matrix=Matrix.Translation(JACK + Vector((0, 0, 18 * MM))))
pin = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=1.75 * MM, radius2=1.4 * MM, depth=12 * MM,
                            matrix=Matrix.Translation(JACK + Vector((0, 0, -5.4 * MM))))
paint(bm, list(bm.faces), lambda f, v: (0.97, 0.97, 0.96))
paint(bm, list({f for v in pin["verts"] for f in v.link_faces}), lambda f, v: (0.8, 0.8, 0.82))
mesh_obj("Fis", bm, smooth=True)

# Kablo: fişten biraz yükselir, arkaya kıvrılıp cihazın arkasından aşağı iner. Ucu saydamlaşır
# (köşe renginin alfası; oyunda ayrı saydam malzeme): cihazın altından kesik görünmesin
bm = bmesh.new()
col = bm.loops.layers.color.new("Col")
# Kısa yükselip arkaya kıvrılır ve cihazın arkasından aşağı iner (ekranda az yer kaplar)
path = [Vector(p) * MM for p in ((0, 0, 0), (0, 0, 5), (0, 1.8, 11), (0, 6, 16), (0, 12, 17.5), (0, 18, 14),
                                 (0, 21.5, 6), (0, 23, -8), (0, 23.5, -30), (0, 23.5, -55), (0, 23.5, -80))]
start = JACK + Vector((0, 0, 22.5 * MM))
pts = [start + p for p in path]
# Ara noktalar (yumuşak eğri)
fine = []
for i in range(len(pts) - 1):
    for k in range(4):
        t = k / 4
        p0, p1 = pts[max(i - 1, 0)], pts[i]
        p2, p3 = pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        tt = t * t
        fine.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * tt + (-p0 + 3 * p1 - 3 * p2 + p3) * tt * t))
fine.append(pts[-1])
SIDES = 7
R_C = 1.05 * MM
rings = []
for i, p in enumerate(fine):
    tdir = (fine[min(i + 1, len(fine) - 1)] - fine[max(i - 1, 0)]).normalized()
    u = Vector((1, 0, 0))              # yol YZ düzleminde: halka ekseni sabit (burulmaz)
    v2 = tdir.cross(u).normalized()
    rings.append([bm.verts.new(p + (u * math.cos(a) + v2 * math.sin(a)) * R_C) for a in [k / SIDES * math.tau for k in range(SIDES)]])
n = len(rings)
for i in range(n - 1):
    a_ = 1.0 if i < n * 0.7 else max(0.0, 1.0 - (i - n * 0.7) / (n * 0.28))
    b_ = 1.0 if i + 1 < n * 0.7 else max(0.0, 1.0 - (i + 1 - n * 0.7) / (n * 0.28))
    for k in range(SIDES):
        f = bm.faces.new((rings[i][k], rings[i][(k + 1) % SIDES], rings[i + 1][(k + 1) % SIDES], rings[i + 1][k]))
        f.normal_update()
        mid = (rings[i][k].co + rings[i + 1][(k + 1) % SIDES].co) * 0.5
        if f.normal.dot(mid - fine[i]) < 0:
            f.normal_flip()
        for l in f.loops:
            al = a_ if l.vert in rings[i] else b_
            l[col] = (0.96, 0.96, 0.95, al)
mesh_obj("Kablo", bm, smooth=True)

for o in bpy.data.objects:
    print("MUZIKCALAR %-10s %d yüz" % (o.name, len(o.data.polygons)))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
kw = dict(filepath=OUT, export_format='GLB', export_yup=True, export_apply=True)
try:
    bpy.ops.export_scene.gltf(**kw, export_vertex_color='ACTIVE')
except TypeError:
    bpy.ops.export_scene.gltf(**kw)
print("GLB", OUT)
