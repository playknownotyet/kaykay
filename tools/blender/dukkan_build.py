"""Zürafa Bakkal: bina (iç ve dış), mobilyalar ve market ürünleri. Tek .glb.

  blender --background --factory-startup --python tools/blender/dukkan_build.py -- <cikti.glb> [onizleme_klasoru]

Koordinatlar (Blender): Z yukarı, kapı y = 0'da, dükkânın içi +Y (Godot'ta -Z), +X sağ (içeri bakınca).
Godot (scripts/soygun/dukkan.gd) düğümleri adlarıyla bulur:
  - "Bina": duvarlar, vitrinler, kapı, tente, tabela, zemin (yerinde)
  - "Cati": çatı ve tavan lambaları (kuş bakışı keşifte gizlenir)
  - Şablonlar (kökte, yerleşimi Godot yapar): "Raf" (iki yüzlü ada), "DuvarRaf", "Tezgah",
    "YazarKasa", "Buzdolabi", "MeyveKasasi", "Sepetler", "Kamera", "MeyveTezgahi", "GazeteStandi",
    "TabelaA"
  - Ürünler "urun_<ad>": kökü tabanın ortası (rafa oturur)
Malzeme adları renk yuvaları; "cam" saydam, "isik" kendiliğinden parlar (Godot).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0]) if args else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "dukkan", "dukkan.glb")
PREVIEW_DIR = os.path.abspath(args[1]) if len(args) > 1 else None

W, D, H = 10.0, 8.0, 3.6        # iç genişlik, derinlik, yükseklik (dukkan.gd ile aynı)
T = 0.2                         # duvar kalınlığı
DOOR_W, DOOR_H = 2.0, 2.3
WIN_X0, WIN_X1, WIN_Z0, WIN_Z1 = 1.5, 4.3, 0.6, 2.3

COLORS = {
    # bina
    "duvar": (0.93, 0.83, 0.62), "duvar_ic": (0.95, 0.93, 0.86), "lambri": (0.55, 0.72, 0.62),
    "tas": (0.62, 0.58, 0.54), "tas_koyu": (0.45, 0.42, 0.4), "korniz": (0.98, 0.95, 0.88),
    "cerceve": (0.17, 0.36, 0.3), "cam": (0.55, 0.75, 0.85), "kapi_kol": (0.85, 0.75, 0.4),
    "tente_a": (0.82, 0.16, 0.18), "tente_b": (0.97, 0.95, 0.9), "tabela": (0.17, 0.36, 0.3),
    "tabela_yazi": (1.0, 0.85, 0.3), "zemin_a": (0.9, 0.88, 0.82), "zemin_b": (0.6, 0.66, 0.68),
    "cati": (0.42, 0.4, 0.4), "metal": (0.55, 0.56, 0.58), "metal_koyu": (0.25, 0.26, 0.28),
    "isik": (1.0, 0.97, 0.85), "lamba": (0.95, 0.8, 0.45), "paspas": (0.3, 0.22, 0.18),
    "acik": (0.2, 0.62, 0.3),
    # mobilya
    "raf": (0.86, 0.87, 0.88), "raf_koyu": (0.36, 0.4, 0.46), "fiyat": (0.98, 0.93, 0.5),
    "raf_ust": (0.17, 0.36, 0.3), "ahsap": (0.58, 0.4, 0.24), "ahsap_koyu": (0.36, 0.23, 0.14),
    "tezgah_ust": (0.82, 0.8, 0.76), "kasa": (0.2, 0.21, 0.24), "kasa_acik": (0.78, 0.78, 0.76),
    "ekran": (0.25, 0.65, 0.55), "tus": (0.9, 0.9, 0.88), "tus_kirmizi": (0.85, 0.2, 0.15),
    "kagit": (0.98, 0.98, 0.95), "dolap": (0.92, 0.92, 0.9), "dolap_kirmizi": (0.8, 0.12, 0.14),
    "sepet": (0.85, 0.15, 0.15), "kamera": (0.88, 0.88, 0.86), "lens": (0.08, 0.08, 0.1),
    "led": (1.0, 0.1, 0.1), "kara_tahta": (0.12, 0.18, 0.15), "tebesir": (0.95, 0.95, 0.9),
    "gazete": (0.92, 0.9, 0.84), "gazete_b": (0.75, 0.3, 0.25), "gazete_c": (0.3, 0.45, 0.7),
    # ürünler
    "kola": (0.85, 0.1, 0.12), "gumus": (0.78, 0.78, 0.8), "beyaz": (0.97, 0.97, 0.95),
    "su": (0.62, 0.82, 0.95), "su_etiket": (0.15, 0.4, 0.8), "kapak_mavi": (0.1, 0.25, 0.65),
    "sut_mavi": (0.2, 0.45, 0.85), "gevrek": (0.98, 0.78, 0.15), "gevrek_b": (0.85, 0.25, 0.15),
    "gevrek_c": (0.6, 0.35, 0.15), "cips": (0.98, 0.55, 0.1), "cips_b": (0.55, 0.2, 0.55),
    "cikolata": (0.45, 0.2, 0.55), "altin": (0.95, 0.75, 0.25), "bal": (0.9, 0.55, 0.1),
    "ekmek": (0.8, 0.55, 0.25), "ekmek_ust": (0.62, 0.38, 0.15), "elma": (0.82, 0.12, 0.1),
    "yaprak": (0.3, 0.6, 0.2), "sap": (0.35, 0.22, 0.12), "kurabiye": (0.7, 0.45, 0.25),
    "kurabiye_b": (0.95, 0.85, 0.6), "macun": (0.15, 0.4, 0.85), "sampuan": (0.3, 0.7, 0.45),
    "konserve": (0.3, 0.55, 0.25), "yumurta": (0.75, 0.72, 0.68), "yumurta_b": (0.95, 0.9, 0.8),
    "portakal": (0.98, 0.55, 0.1), "limon": (0.98, 0.88, 0.25),
    # yeni ürünler: etiketli yüzler "etiket" (doku atlası assets/dukkan/urun_etiket.png)
    "etiket": (1.0, 1.0, 1.0), "su_govde": (0.72, 0.88, 0.97), "kola_ust": (0.83, 0.84, 0.86),
    "karton": (0.78, 0.66, 0.48), "karton_koyu": (0.6, 0.5, 0.36), "yumurta_kabuk": (0.97, 0.9, 0.78),
    "yumurta_beyaz": (0.98, 0.97, 0.94), "ekmek_acik": (0.93, 0.74, 0.42), "ekmek_alt": (0.6, 0.38, 0.18),
    "bal_cam": (0.93, 0.6, 0.12), "bez_kirmizi": (0.85, 0.18, 0.18), "elma_acik": (0.95, 0.35, 0.25),
    "macun_govde": (0.95, 0.96, 0.98), "macun_kapak": (0.15, 0.4, 0.85), "sampuan_kapak": (0.95, 0.95, 0.95),
    "gevrek_kenar": (0.98, 0.78, 0.15), "cips_folyo": (0.95, 0.5, 0.1), "kurabiye_kutu": (0.16, 0.38, 0.72),
    "sut_tepe": (0.97, 0.97, 0.95),
}
ETIKET_PNG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "dukkan", "urun_etiket.png")
# Etiket atlası hücreleri (tools/blender/urun_etiket.py CELLS ile aynı sıra), 8 sütun x 2 satır
LABELS = {n: i for i, n in enumerate(["kola", "su", "sut_on", "sut_yan", "gevrek_on", "gevrek_yan", "cips_on", "cikolata",
                                      "bal", "kurabiye", "macun", "sampuan", "konserve", "yumurta_kapak"])}


def cell_uv(name, u, v):
    """Hücre içi (u, v) (0..1, v yukarı) -> atlas UV (Blender: v yukarı)."""
    i = LABELS[name]
    col, row = i % 8, i // 8
    return ((col + u) / 8.0, 1.0 - (row + 1.0 - v) / 2.0)


def mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        c = COLORS[name]
        m.diffuse_color = (*c, 1.0)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*c, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.7
        if name == "etiket" and os.path.exists(ETIKET_PNG):
            tex = m.node_tree.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(ETIKET_PNG)
            tex.interpolation = 'Closest'
            m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


class Part:
    """Bir nesnenin geometrisi: malzeme adı -> yüz listesi (tek bmesh, malzeme indeksli)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _faces(self, verts, faces, m, uvs=None):
        """uvs: köşe başına UV listesi (verts ile aynı sıra) ya da None."""
        idx = self.mi(m)
        vs = [self.bm.verts.new(v) for v in verts]
        for f in faces:
            try:
                face = self.bm.faces.new([vs[i] for i in f])
                face.material_index = idx
                if uvs is not None:
                    for loop, vi in zip(face.loops, f):
                        loop[self.uv].uv = uvs[vi]
            except ValueError:
                pass
        return vs

    def quad_uv(self, pts, m, label, rect=(0.0, 0.0, 1.0, 1.0)):
        """Dörtgen pts (dışarıdan bakınca sol alt, sağ alt, sağ üst, sol üst), etiket hücresinin
        rect (u0, v0, u1, v1) kısmı."""
        u0, v0, u1, v1 = rect
        uvs = [cell_uv(label, u0, v0), cell_uv(label, u1, v0), cell_uv(label, u1, v1), cell_uv(label, u0, v1)]
        self._faces([Vector(p) for p in pts], [(0, 1, 2, 3)], m, uvs)

    def label_box(self, c, s, faces):
        """Kutu; faces: yön ('-y' ön, '+y' arka, '+x', '-x', '+z', '-z') -> (malzeme, etiket ya da None)."""
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        P = lambda x, y, z: (cx + x * hx, cy + y * hy, cz + z * hz)
        quads = {
            "-y": [P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)],
            "+y": [P(1, 1, -1), P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1)],
            "+x": [P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1)],
            "-x": [P(-1, 1, -1), P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1)],
            "+z": [P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)],
            "-z": [P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1), P(-1, -1, -1)],
        }
        for k, pts in quads.items():
            m, lab = faces.get(k, faces.get("*", ("beyaz", None)))
            if lab:
                self.quad_uv(pts, m, lab[0] if isinstance(lab, tuple) else lab, lab[1] if isinstance(lab, tuple) else (0, 0, 1, 1))
            else:
                self._faces([Vector(p) for p in pts], [(0, 1, 2, 3)], m)

    def lathe(self, prof, m, seg=12, label=None, band=None, sy=1.0, cap_top=None, cap_bot=None, c=(0, 0, 0)):
        """Dönel yüzey: prof [(r, z)] alttan üste; label: etiket (u çevre, ön -Y'de u = 0,5),
        band: (z0, z1) etiketin sardığı aralık (o dilimler etiketli). sy: Y'de basıklık (oval)."""
        rings = []
        for (r, z) in prof:
            ring = []
            for k in range(seg + 1):
                a = math.radians(-270.0 + 360.0 * k / seg)
                ring.append(Vector((c[0] + math.cos(a) * r, c[1] + math.sin(a) * r * sy, c[2] + z)))
            rings.append(ring)
        for i in range(len(prof) - 1):
            za, zb = prof[i][1], prof[i + 1][1]
            labeled = label and band and za >= band[0] - 1e-6 and zb <= band[1] + 1e-6
            for k in range(seg):
                pts = [rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]]
                if labeled:
                    # Etiket önde ve arkada birer kez (gerçek kutulardaki gibi): yarım çevre bir etiket.
                    # seg 4'ün katı olmalı (dikiş köşeye denk gelsin)
                    va = (za - band[0]) / (band[1] - band[0])
                    vb = (zb - band[0]) / (band[1] - band[0])
                    u0 = (2.0 * k / seg + 0.5) % 1.0
                    u1 = u0 + 2.0 / seg
                    uvs = [cell_uv(label, u0, va), cell_uv(label, u1, va), cell_uv(label, u1, vb), cell_uv(label, u0, vb)]
                    self._faces(pts, [(0, 1, 2, 3)], "etiket", uvs)
                else:
                    self._faces(pts, [(0, 1, 2, 3)], m)
        if cap_bot:
            self._faces(rings[0][:seg], [tuple(reversed(range(seg)))], cap_bot)
        if cap_top:
            self._faces(rings[-1][:seg], [tuple(range(seg))], cap_top)

    def box(self, c, s, m, rot=0.0):
        """c: merkez, s: boyut; rot: Z ekseninde döndürme (derece)."""
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        R = Matrix.Rotation(math.radians(rot), 3, 'Z')
        pts = []
        for z in (-hz, hz):
            for (x, y) in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)):
                pts.append(Vector(c) + R @ Vector((x, y, z)))
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self._faces(pts, f, m)

    def box2(self, a, b, m):
        """İki köşeden kutu."""
        c = [(a[i] + b[i]) / 2 for i in range(3)]
        s = [abs(b[i] - a[i]) for i in range(3)]
        self.box(c, s, m)

    def cyl(self, c, r, h, m, seg=10, r2=None, cap_m=None, axis="z", cap=True):
        """Taban merkezi c, yarıçap r (üstte r2), boy h; axis yönünde."""
        r2 = r if r2 is None else r2
        ax = {"z": Matrix.Identity(3), "x": Matrix.Rotation(math.radians(90), 3, 'Y'),
              "y": Matrix.Rotation(math.radians(-90), 3, 'X')}[axis]
        pts = []
        for k in range(seg):
            a = math.tau * k / seg
            pts.append(Vector(c) + ax @ Vector((math.cos(a) * r, math.sin(a) * r, 0)))
        for k in range(seg):
            a = math.tau * k / seg
            pts.append(Vector(c) + ax @ Vector((math.cos(a) * r2, math.sin(a) * r2, h)))
        faces = [(k, (k + 1) % seg, seg + (k + 1) % seg, seg + k) for k in range(seg)]
        self._faces(pts, faces, m)
        if cap:
            cm = cap_m or m
            self._faces(pts[:seg], [tuple(reversed(range(seg)))], cm)
            self._faces(pts[seg:], [tuple(range(seg))], cm)

    def sphere(self, c, r, m, seg=8, rings=5, sz=1.0):
        pts = []
        for i in range(1, rings):
            phi = math.pi * i / rings
            for k in range(seg):
                a = math.tau * k / seg
                pts.append(Vector(c) + Vector((math.sin(phi) * math.cos(a) * r, math.sin(phi) * math.sin(a) * r, -math.cos(phi) * r * sz)))
        bot = len(pts)
        pts.append(Vector(c) + Vector((0, 0, -r * sz)))
        top = len(pts)
        pts.append(Vector(c) + Vector((0, 0, r * sz)))
        faces = []
        for i in range(rings - 2):
            for k in range(seg):
                a0, a1 = i * seg + k, i * seg + (k + 1) % seg
                faces.append((a0, a1, a1 + seg, a0 + seg))
        for k in range(seg):
            faces.append((bot, (k + 1) % seg, k))
            last = (rings - 2) * seg
            faces.append((top, last + k, last + (k + 1) % seg))
        self._faces(pts, faces, m)

    def poly(self, pts, m):
        self._faces([Vector(p) for p in pts], [tuple(range(len(pts)))], m)

    def prism(self, profile, y0, y1, m, cap_m=None):
        """XZ düzleminde profil (kapalı çokgen), y0..y1 boyunca uzatılır."""
        n = len(profile)
        pts = [Vector((x, y0, z)) for x, z in profile] + [Vector((x, y1, z)) for x, z in profile]
        faces = [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
        self._faces(pts, faces, m)
        cm = cap_m or m
        self._faces(pts[:n], [tuple(range(n))], cm)
        self._faces(pts[n:], [tuple(reversed(range(n)))], cm)

    def build(self, loc=(0, 0, 0)):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(mat(m))
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        ob.location = loc
        bpy.context.scene.collection.objects.link(ob)
        return ob


# ---------------------------------------------------------------------------
# Bina
# ---------------------------------------------------------------------------
def build_shell():
    P = Part("Bina")
    hw = W / 2
    # Zemin karoları (50 cm, iki renk) ve kapı önü basamak
    n_x, n_y = int(W / 0.5), int(D / 0.5)
    for i in range(n_x):
        for j in range(n_y):
            x0, y0 = -hw + i * 0.5, j * 0.5
            P.box2((x0, y0, -0.12), (x0 + 0.5, y0 + 0.5, 0.0), "zemin_a" if (i + j) % 2 == 0 else "zemin_b")
    P.box2((-hw - T, -0.9, -0.3), (hw + T, -T, 0.0), "tas")
    P.box2((-1.3, -0.85, 0.0), (1.3, -0.25, 0.012), "paspas")
    # Arka ve yan duvarlar (dış yüz rengi, iç yüze ince kaplama)
    P.box2((-hw - T, D, 0), (hw + T, D + T, H), "duvar")
    P.box2((-hw - T, -T, 0), (-hw, D, H), "duvar")
    P.box2((hw, -T, 0), (hw + T, D, H), "duvar")
    for (a, b) in (((-hw, D - 0.01, 0), (hw, D, H)), ((-hw, 0, 0), (-hw + 0.01, D, H)), ((hw - 0.01, 0, 0), (hw, D, H))):
        P.box2(a, b, "duvar_ic")
    # İç lambri (alt bant) ve süpürgelik
    P.box2((-hw, D - 0.03, 0), (hw, D - 0.01, 1.0), "lambri")
    P.box2((-hw + 0.01, 0, 0), (-hw + 0.03, D, 1.0), "lambri")
    P.box2((hw - 0.03, 0, 0), (hw - 0.01, D, 1.0), "lambri")
    P.box2((-hw, D - 0.05, 0), (hw, D - 0.03, 0.1), "ahsap_koyu")
    # Ön duvar: kapı ve iki vitrin boşluğu
    fy0, fy1 = -T, 0.0
    P.box2((-hw - T, fy0, 0), (-WIN_X1, fy1, H), "duvar")
    P.box2((WIN_X1, fy0, 0), (hw + T, fy1, H), "duvar")
    P.box2((-WIN_X0, fy0, 0), (-DOOR_W / 2, fy1, H), "duvar")
    P.box2((DOOR_W / 2, fy0, 0), (WIN_X0, fy1, H), "duvar")
    for s in (-1, 1):
        x0, x1 = sorted((s * WIN_X0, s * WIN_X1))
        P.box2((x0, fy0, 0), (x1, fy1, WIN_Z0), "duvar")             # vitrin altı
        P.box2((x0, fy0, WIN_Z1), (x1, fy1, H), "duvar")             # vitrin üstü
    P.box2((-DOOR_W / 2, fy0, DOOR_H), (DOOR_W / 2, fy1, H), "duvar")
    # Taş kaide (dışta, ön ve yanlar)
    for s in (-1, 1):                                   # kapı boşluğunda kaide yok
        x0, x1 = sorted((s * (hw + T + 0.04), s * (DOOR_W / 2 + 0.09)))
        P.box2((x0, -T - 0.04, 0), (x1, -T + 0.02, 0.45), "tas")
    P.box2((-hw - T - 0.04, -T, 0), (-hw - T + 0.02, D + T, 0.45), "tas")
    P.box2((hw + T - 0.02, -T, 0), (hw + T + 0.04, D + T, 0.45), "tas")
    P.box2((-hw - T - 0.04, D + T - 0.02, 0), (hw + T + 0.04, D + T + 0.04, 0.45), "tas")
    # Köşe pilastrları ve korniş
    for s in (-1, 1):
        x = s * (hw + T - 0.15)
        P.box((x, -T - 0.05, H / 2), (0.36, 0.1, H), "korniz")
    # Korniş: duvarların üstünde çerçeve (ortası boş: kuş bakışında çatı kalkınca içerisi görünsün)
    cz0, cz1, ox = H - 0.05, H + 0.12, 0.1
    P.box2((-hw - T - ox, -T - 0.18, cz0), (hw + T + ox, -T + 0.2, cz1), "korniz")
    P.box2((-hw - T - ox, D - 0.2, cz0), (hw + T + ox, D + T + ox, cz1), "korniz")
    P.box2((-hw - T - ox, -T, cz0), (-hw + 0.0, D + T, cz1), "korniz")
    P.box2((hw - 0.0, -T, cz0), (hw + T + ox, D + T, cz1), "korniz")
    P.box2((-hw - T - 0.06, -T - 0.12, H - 0.16), (hw + T + 0.06, -T, H - 0.05), "korniz")
    # Vitrinler: çerçeve, orta kayıt, denizlik, cam
    for s in (-1, 1):
        x0, x1 = sorted((s * WIN_X0, s * WIN_X1))
        cx, wdt = (x0 + x1) / 2, x1 - x0
        fw = 0.07
        P.box((cx, -T / 2, WIN_Z0 + fw / 2), (wdt, T + 0.04, fw), "cerceve")
        P.box((cx, -T / 2, WIN_Z1 - fw / 2), (wdt, T + 0.04, fw), "cerceve")
        P.box((x0 + fw / 2, -T / 2, (WIN_Z0 + WIN_Z1) / 2), (fw, T + 0.04, WIN_Z1 - WIN_Z0), "cerceve")
        P.box((x1 - fw / 2, -T / 2, (WIN_Z0 + WIN_Z1) / 2), (fw, T + 0.04, WIN_Z1 - WIN_Z0), "cerceve")
        P.box((cx, -T / 2, (WIN_Z0 + WIN_Z1) / 2), (0.05, T + 0.02, WIN_Z1 - WIN_Z0), "cerceve")
        P.box((cx, -T / 2, WIN_Z1 - 0.45), (wdt, T + 0.02, 0.04), "cerceve")
        P.box((cx, -T - 0.08, WIN_Z0 - 0.03), (wdt + 0.16, 0.2, 0.06), "korniz")      # denizlik
        P.box((cx, -T / 2, (WIN_Z0 + WIN_Z1) / 2), (wdt - 0.1, 0.02, WIN_Z1 - WIN_Z0 - 0.1), "cam")
        # Vitrin içi: alçak sergi tablası
        P.box((cx, 0.35, WIN_Z0 - 0.05), (wdt - 0.1, 0.6, 0.06), "ahsap")
    # Kapı: çerçeve, iki cam kanat, kollar, "AÇIK" levhası
    fw = 0.09
    P.box((0, -T / 2, DOOR_H + fw / 2), (DOOR_W + 2 * fw, T + 0.06, fw), "cerceve")
    for s in (-1, 1):
        P.box((s * (DOOR_W / 2 + fw / 2), -T / 2, DOOR_H / 2), (fw, T + 0.06, DOOR_H), "cerceve")
        # Kanatlar açık (içe dönük, duvara yaslı): kapı boşluğu geçilebilir
        hinge = Vector((s * DOOR_W / 2, 0.0, 0))
        leaf_w = DOOR_W / 2 - 0.04
        ang = math.radians(-82 * s)
        R = Matrix.Rotation(ang, 3, 'Z')
        def lp(x, y, z, hinge=hinge, R=R):
            return hinge + R @ Vector((x, y, z))
        c = lp(-s * leaf_w / 2, 0.05, DOOR_H / 2)
        P.box(c, (leaf_w, 0.05, DOOR_H - 0.04), "cerceve", rot=math.degrees(ang))
        P.box(lp(-s * leaf_w / 2, 0.05, DOOR_H / 2 + 0.05), (leaf_w - 0.16, 0.06, DOOR_H - 0.45), "cam", rot=math.degrees(ang))
        P.box(lp(-s * (leaf_w - 0.12), 0.0, 1.05), (0.04, 0.12, 0.45), "kapi_kol", rot=math.degrees(ang))
    P.box((0, -T - 0.02, DOOR_H + 0.25), (0.62, 0.03, 0.22), "acik")
    P.box((0, -T - 0.035, DOOR_H + 0.25), (0.5, 0.01, 0.12), "beyaz")
    # Tente: çizgili, eğimli, önü dilimli saçak
    aw_y0, aw_y1, aw_z0, aw_z1 = -T, -T - 1.25, 2.95, 2.5
    stripes = 20
    x_l, x_r = -hw - 0.05, hw + 0.05
    for k in range(stripes):
        xa = x_l + (x_r - x_l) * k / stripes
        xb = x_l + (x_r - x_l) * (k + 1) / stripes
        m = "tente_a" if k % 2 == 0 else "tente_b"
        P.poly([(xa, aw_y0, aw_z0), (xb, aw_y0, aw_z0), (xb, aw_y1, aw_z1), (xa, aw_y1, aw_z1)], m)
        P.poly([(xa, aw_y1, aw_z1), (xb, aw_y1, aw_z1), (xb, aw_y0, aw_z0), (xa, aw_y0, aw_z0)], m)
        # Saçak: aşağı sarkan dilim
        xm = (xa + xb) / 2
        for side in (0, 1):
            pts = [(xa, aw_y1, aw_z1), (xb, aw_y1, aw_z1), (xb, aw_y1, aw_z1 - 0.14), (xm, aw_y1, aw_z1 - 0.24), (xa, aw_y1, aw_z1 - 0.14)]
            P.poly(pts if side else list(reversed(pts)), m)
    for s in (-1, 1):
        x = s * (hw + 0.05)
        pts = [(x, aw_y0, aw_z0), (x, aw_y1, aw_z1), (x, aw_y1, aw_z1 - 0.14), (x, aw_y0, aw_z0 - 0.3)]
        P.poly(pts, "tente_a")
        P.poly(list(reversed(pts)), "tente_a")
    for s in (-1, 1):                                   # taşıyıcı demir
        P.box((s * (hw - 0.3), (aw_y0 + aw_y1) / 2, (aw_z0 + aw_z1) / 2 - 0.08), (0.03, 1.3, 0.03), "metal_koyu")
    # Tabela levhası (yazı Godot'ta Label3D ile)
    P.box((0, -T - 0.06, 3.25), (6.2, 0.1, 0.6), "tabela")
    P.box((0, -T - 0.075, 3.25), (6.36, 0.06, 0.72), "altin")
    P.box((0, -T - 0.09, 3.25), (6.2, 0.04, 0.6), "tabela")
    # Duvar lambaları (kapının iki yanı)
    for s in (-1, 1):
        x = s * (DOOR_W / 2 + 0.3)
        P.box((x, -T - 0.05, 2.05), (0.1, 0.1, 0.16), "metal_koyu")
        P.box((x, -T - 0.2, 2.12), (0.04, 0.3, 0.04), "metal_koyu")
        P.cyl((x, -T - 0.33, 1.88), 0.07, 0.18, "lamba", seg=8, r2=0.04)
        P.cyl((x, -T - 0.33, 2.06), 0.1, 0.05, "metal_koyu", seg=8, r2=0.02)
    # Yağmur borusu (ön köşeler) ve yan duvarda klima
    for s in (-1, 1):
        x = s * (hw + T + 0.08)
        P.cyl((x, -T + 0.15, 0.1), 0.05, H + 0.02, "metal", seg=8)
        P.box((x - s * 0.04, -T + 0.15, H + 0.05), (0.16, 0.16, 0.1), "metal")
    P.box((hw + T + 0.22, D * 0.55, 2.3), (0.4, 0.8, 0.55), "beyaz")
    for k in range(5):
        P.box((hw + T + 0.43, D * 0.55, 2.12 + k * 0.08), (0.02, 0.7, 0.02), "metal_koyu")
    # Arka kapı (dışarıdan)
    P.box((-2.5, D + T + 0.02, 1.05), (0.95, 0.04, 2.1), "cerceve")
    P.box((-2.2, D + T + 0.05, 1.0), (0.08, 0.04, 0.08), "kapi_kol")
    return P.build()


def build_roof():
    P = Part("Cati")
    hw = W / 2
    P.box2((-hw - T, -T, H), (hw + T, D + T, H + 0.15), "cati")
    # Parapet
    P.box2((-hw - T, -T, H + 0.15), (hw + T, -T + 0.15, H + 0.45), "korniz")
    P.box2((-hw - T, D + T - 0.15, H + 0.15), (hw + T, D + T, H + 0.4), "korniz")
    P.box2((-hw - T, -T, H + 0.15), (-hw - T + 0.15, D + T, H + 0.4), "korniz")
    P.box2((hw + T - 0.15, -T, H + 0.15), (hw + T, D + T, H + 0.4), "korniz")
    # Çatı üstü: havalandırma ve su deposu
    P.box((-2.5, D * 0.6, H + 0.4), (0.6, 0.6, 0.5), "metal")
    P.cyl((2.8, D * 0.7, H + 0.15), 0.5, 0.9, "beyaz", seg=12)
    P.cyl((2.8, D * 0.7, H + 1.05), 0.5, 0.08, "metal", seg=12, r2=0.15)
    # Tavan (içten) ve flüoresan lambalar
    P.box2((-hw, 0, H - 0.02), (hw, D, H), "duvar_ic")
    for x in (-2.6, 0.0, 2.6):
        for y in (2.2, 5.6):
            P.box((x, y, H - 0.06), (0.35, 1.3, 0.06), "metal")
            P.box((x, y, H - 0.1), (0.25, 1.2, 0.03), "isik")
    return P.build()


# ---------------------------------------------------------------------------
# Mobilyalar (kökte; Godot yerleştirir). Ön yüz -Y (müşteriye bakan), içe bakınca.
# ---------------------------------------------------------------------------
SHELF_Z = (0.14, 0.5, 0.86, 1.22)       # raf üst yüzleri (dukkan.gd ile aynı)
GONDOLA_L, GONDOLA_D, GONDOLA_H = 2.8, 0.9, 1.55
WALL_L, WALL_D, WALL_H = 2.8, 0.45, 1.95
WALL_Z = (0.14, 0.52, 0.9, 1.28, 1.66)


def build_gondola():
    P = Part("Raf")
    L, Dd, Hh = GONDOLA_L, GONDOLA_D, GONDOLA_H
    P.box((0, 0, 0.06), (L, Dd - 0.04, 0.12), "raf_koyu")                    # taban
    P.box((0, 0, Hh / 2 + 0.06), (L, 0.05, Hh - 0.12), "raf")                 # sırt panosu
    for x in (-L / 2 + 0.02, 0.0, L / 2 - 0.02):
        P.box((x, 0, Hh / 2), (0.04, 0.08, Hh), "raf_koyu")                   # dikmeler
    for s in (-1, 1):
        for z in SHELF_Z:
            y = s * (0.03 + 0.2)
            P.box((0, y, z - 0.015), (L - 0.04, 0.4, 0.03), "raf")
            P.box((0, s * (0.03 + 0.4), z - 0.035), (L - 0.04, 0.012, 0.05), "fiyat")
            # Fiyat etiketleri (koyu küçük kareler)
            for k in range(6):
                P.box((-L / 2 + 0.3 + k * 0.45, s * (0.03 + 0.407), z - 0.035), (0.08, 0.004, 0.03), "raf_koyu")
    # Uç paneller (renkli) ve üstte başlık bandı
    for s in (-1, 1):
        P.box((s * (L / 2 + 0.02), 0, Hh / 2), (0.04, Dd, Hh), "raf_ust")
    P.box((0, 0, Hh + 0.08), (L + 0.08, 0.1, 0.16), "raf_ust")
    P.box((0, 0, Hh + 0.08), (L * 0.5, 0.12, 0.08), "fiyat")
    return P.build()


def build_wall_shelf():
    P = Part("DuvarRaf")
    L, Dd, Hh = WALL_L, WALL_D, WALL_H
    # Sırt +Y'de (duvara yaslı), raflar -Y'ye bakar; kök arka-orta değil ön-orta değil: gövde ortası
    P.box((0, Dd / 2 - 0.02, Hh / 2), (L, 0.04, Hh), "raf")
    P.box((0, 0, 0.06), (L, Dd, 0.12), "raf_koyu")
    for x in (-L / 2 + 0.02, 0.0, L / 2 - 0.02):
        P.box((x, Dd / 2 - 0.06, Hh / 2), (0.04, 0.06, Hh), "raf_koyu")
    for z in WALL_Z:
        P.box((0, 0, z - 0.015), (L - 0.04, Dd - 0.04, 0.03), "raf")
        P.box((0, -Dd / 2 + 0.01, z - 0.035), (L - 0.04, 0.012, 0.05), "fiyat")
    for s in (-1, 1):
        P.box((s * (L / 2 + 0.02), 0, Hh / 2), (0.04, Dd, Hh), "raf_ust")
    P.box((0, 0, Hh + 0.1), (L + 0.08, Dd, 0.2), "raf_ust")
    P.box((0, -Dd / 2 - 0.005, Hh + 0.1), (L * 0.6, 0.01, 0.1), "fiyat")
    return P.build()


def build_counter():
    """Tezgâh: 2,4 x 0,7 x 1,0; müşteri tarafı -Y, kasiyer +Y."""
    P = Part("Tezgah")
    L, Dd, Hh = 2.4, 0.7, 1.0
    P.box((0, 0.03, (Hh - 0.05) / 2), (L, Dd - 0.06, Hh - 0.05), "ahsap")
    for k in range(12):                                         # ön yüz çıtaları
        x = -L / 2 + 0.1 + k * (L - 0.2) / 11
        P.box((x, -Dd / 2 + 0.02, (Hh - 0.05) / 2), (0.05, 0.02, Hh - 0.15), "ahsap_koyu")
    P.box((0, -Dd / 2 + 0.03, 0.05), (L, 0.04, 0.1), "ahsap_koyu")
    P.box((0, 0, Hh - 0.025), (L + 0.1, Dd + 0.1, 0.05), "tezgah_ust")
    # Kasiyer tarafı: raf boşluğu ve çekmece
    P.box((0.6, Dd / 2 + 0.005, 0.55), (0.8, 0.01, 0.25), "ahsap_koyu")
    P.box((0.6, Dd / 2 + 0.02, 0.55), (0.15, 0.03, 0.03), "metal")
    # Tezgâh üstü şeker standı (basamaklı)
    for k in range(3):
        P.box((-0.75, -0.12 + k * 0.08, Hh + 0.04 + k * 0.06), (0.6, 0.12, 0.08 + k * 0.12), "raf_ust")
    return P.build()


def build_register():
    """Yazar kasa: kasiyer +Y tarafında; tuş takımı ona dönük, müşteri ekranı -Y'ye."""
    P = Part("YazarKasa")
    P.box((0, 0, 0.06), (0.44, 0.4, 0.12), "kasa")                       # çekmece gövdesi
    P.box((0, 0.201, 0.06), (0.38, 0.004, 0.07), "kasa_acik")            # çekmece ön yüzü
    P.box((0, 0.205, 0.06), (0.1, 0.01, 0.015), "metal")
    # Eğimli tuş takımı
    tilt = math.radians(18)
    base = Vector((0, 0.05, 0.12))
    R = Matrix.Rotation(tilt, 3, 'X')
    P.box(base + R @ Vector((0, 0, 0.02)), (0.36, 0.26, 0.04), "kasa", rot=0)
    for i in range(4):
        for j in range(4):
            c = base + R @ Vector((-0.12 + i * 0.06, -0.08 + j * 0.055, 0.045))
            P.box(c, (0.045, 0.04, 0.015), "tus_kirmizi" if (i == 3 and j == 0) else "tus")
    # Ekran (kasiyere dönük) ve direk
    P.box((0, -0.14, 0.2), (0.04, 0.04, 0.16), "kasa")
    scr_c = Vector((0, -0.12, 0.33))
    P.box(scr_c, (0.3, 0.04, 0.2), "kasa")
    P.box(scr_c + Vector((0, 0.021, 0)), (0.26, 0.004, 0.16), "ekran")
    # Müşteri ekranı (arkada küçük)
    P.box((0, -0.15, 0.44), (0.16, 0.03, 0.06), "ekran")
    # Fiş yazıcı ve kâğıt
    P.box((0.27, 0.0, 0.07), (0.12, 0.16, 0.14), "kasa")
    P.box((0.27, 0.06, 0.16), (0.07, 0.002, 0.08), "kagit")
    return P.build()


def build_fridge():
    """İçecek dolabı: 1,0 x 0,75 x 2,0; cam kapı -Y'de."""
    P = Part("Buzdolabi")
    Ww, Dd, Hh = 1.0, 0.75, 2.0
    P.box((0, 0.02, Hh / 2), (Ww, Dd - 0.04, Hh), "dolap")
    P.box((0, 0, 0.06), (Ww + 0.01, Dd + 0.01, 0.12), "metal_koyu")
    P.box((0, -Dd / 2 + 0.03, Hh - 0.15), (Ww + 0.02, 0.08, 0.3), "dolap_kirmizi")      # başlık
    P.box((0, -Dd / 2 - 0.012, Hh - 0.15), (Ww * 0.6, 0.01, 0.14), "beyaz")
    # İç boşluk (koyu) ve raflar
    P.box((0, -Dd / 2 + 0.06, 1.0), (Ww - 0.12, 0.01, 1.6), "metal_koyu")
    # Kapı çerçevesi ve cam
    fz0, fz1 = 0.14, Hh - 0.32
    P.box((0, -Dd / 2 - 0.01, fz0), (Ww, 0.05, 0.05), "dolap")
    P.box((0, -Dd / 2 - 0.01, fz1), (Ww, 0.05, 0.05), "dolap")
    for s in (-1, 1):
        P.box((s * (Ww / 2 - 0.03), -Dd / 2 - 0.01, (fz0 + fz1) / 2), (0.06, 0.05, fz1 - fz0), "dolap")
    P.box((Ww / 2 - 0.12, -Dd / 2 - 0.05, (fz0 + fz1) / 2), (0.03, 0.04, 0.5), "metal")
    P.box((0, -Dd / 2 - 0.012, (fz0 + fz1) / 2), (Ww - 0.12, 0.01, fz1 - fz0 - 0.05), "cam")
    return P.build()


FRIDGE_Z = (0.2, 0.62, 1.04, 1.42)      # dolap içi raflar (ürün tabanı)


def build_fridge_shelves():
    P = Part("DolapRaflari")
    for z in FRIDGE_Z:
        P.box((0, 0.0, z - 0.01), (0.86, 0.55, 0.02), "metal")
    return P.build()


def build_produce():
    """Meyve kasası standı (içeride): eğimli, üç tahta kasa. Elmalar Godot'ta (çalınabilir)."""
    P = Part("MeyveKasasi")
    for s in (-1, 1):
        P.box((s * 0.6, 0, 0.35), (0.05, 0.6, 0.7), "ahsap_koyu")
    for k, x in enumerate((-0.4, 0.0, 0.4)):
        c = Vector((x, 0, 0.55))
        P.box(c + Vector((0, 0, -0.08)), (0.38, 0.5, 0.02), "ahsap")
        for s in (-1, 1):
            P.box(c + Vector((s * 0.19, 0, 0)), (0.02, 0.5, 0.16), "ahsap")
            P.box(c + Vector((0, s * 0.25, 0)), (0.38, 0.02, 0.16), "ahsap")
    P.box((0, 0, 0.2), (1.2, 0.55, 0.03), "ahsap")
    return P.build()


def build_fruit_stand():
    """Dışarıdaki meyve-sebze tezgâhı (dekor): eğimli üç kasa, tabelası."""
    P = Part("MeyveTezgahi")
    for s in (-1, 1):
        for y in (-0.3, 0.3):
            P.box((s * 0.7, y, 0.4), (0.05, 0.05, 0.8), "ahsap_koyu")
    tilt = math.radians(-18)
    R = Matrix.Rotation(tilt, 3, 'X')
    for k, (x, kind) in enumerate(((-0.47, "elma"), (0.0, "portakal"), (0.47, "limon"))):
        c = Vector((x, 0, 0.82))
        P.box(c + R @ Vector((0, 0, -0.06)), (0.44, 0.62, 0.02), "ahsap", rot=0)
        for s in (-1, 1):
            P.box(c + R @ Vector((s * 0.22, 0, 0.02)), (0.02, 0.62, 0.14), "ahsap")
            P.box(c + R @ Vector((0, s * 0.31, 0.02)), (0.44, 0.02, 0.14), "ahsap")
        r = 0.045
        for i in range(4):
            for j in range(6):
                q = c + R @ Vector((-0.15 + i * 0.1, -0.25 + j * 0.1, -0.05 + r))
                P.sphere(q, r, kind, seg=6, rings=4)
    P.box((0, 0.36, 1.12), (1.5, 0.04, 0.2), "tabela")
    P.box((0, 0.338, 1.12), (0.9, 0.005, 0.08), "tabela_yazi")
    return P.build()


def build_newsstand():
    P = Part("GazeteStandi")
    P.box((0, 0, 0.5), (0.7, 0.3, 1.0), "metal_koyu")
    for k, m in enumerate(("gazete", "gazete_b", "gazete_c", "gazete")):
        z = 0.25 + k * 0.22
        P.box((0, -0.16 - k * 0.01, z), (0.6, 0.02, 0.2), m)
        P.box((0, -0.175 - k * 0.01, z + 0.04), (0.4, 0.004, 0.04), "lens")
    P.box((0, 0, 1.05), (0.75, 0.32, 0.08), "dolap_kirmizi")
    return P.build()


def build_aboard():
    """A tipi kara tahta tabela."""
    P = Part("TabelaA")
    ang = math.radians(15)
    for s in (-1, 1):
        R = Matrix.Rotation(s * ang, 3, 'X')
        c = Vector((0, s * 0.2, 0.0))
        P.box(c + R @ Vector((0, 0, 0.5)), (0.6, 0.04, 1.0), "ahsap", rot=0)
        P.box(c + R @ Vector((0, s * 0.022, 0.55)), (0.5, 0.005, 0.7), "kara_tahta")
        for k in range(4):
            P.box(c + R @ Vector((-0.05 + (k % 2) * 0.08, s * 0.026, 0.75 - k * 0.12)), (0.3 - k * 0.04, 0.003, 0.025), "tebesir")
    return P.build()


def build_baskets():
    P = Part("Sepetler")
    for k in range(5):
        z = k * 0.06
        c = Vector((0, 0, z))
        P.box(c + Vector((0, 0, 0.005)), (0.42, 0.3, 0.01), "sepet")
        for s in (-1, 1):
            P.box(c + Vector((s * 0.21, 0, 0.11)), (0.012, 0.3, 0.22), "sepet")
            P.box(c + Vector((0, s * 0.15, 0.11)), (0.42, 0.012, 0.22), "sepet")
    for s in (-1, 1):
        P.box((s * 0.1, 0, 0.5), (0.02, 0.32, 0.02), "metal_koyu")
    return P.build()


def build_camera():
    """Tavan güvenlik kamerası: kök tavana bağlantı; gövde -Y'ye bakar."""
    P = Part("Kamera")
    P.box((0, 0, -0.02), (0.12, 0.12, 0.04), "kamera")
    P.box((0, 0, -0.1), (0.04, 0.04, 0.14), "kamera")
    return P.build()


def build_camera_head():
    P = Part("KameraKafa")
    P.box((0, -0.05, 0), (0.14, 0.32, 0.13), "kamera")
    P.box((0, -0.12, 0.075), (0.16, 0.26, 0.02), "kamera")       # güneşlik
    P.cyl((0, -0.21, 0), 0.045, 0.02, "lens", seg=10, axis="y")
    P.box((0.045, -0.21, 0.045), (0.02, 0.01, 0.02), "led")
    return P.build()


# ---------------------------------------------------------------------------
# Ürünler: kök tabanın ortası; boyutlar metre (biraz iri: küçük ekranda okunsun)
# ---------------------------------------------------------------------------
def product(name):
    return Part("urun_" + name)


def build_products():
    """Her ürün kendi biçiminde; ön yüz -Y (rafın önü). Etiketler piksel-art doku atlasından."""
    out = []

    # --- Kola kutusu: alt / üst daralan alüminyum, saran etiket, kapakta açma halkası ---
    P = product("kola")
    P.lathe([(0.029, 0.0), (0.034, 0.008), (0.034, 0.008)], "gumus", seg=16, cap_bot="gumus")
    P.lathe([(0.034, 0.008), (0.034, 0.11)], "kola", seg=16, label="kola", band=(0.008, 0.11))
    P.lathe([(0.034, 0.11), (0.028, 0.121), (0.029, 0.124)], "gumus", seg=16, cap_top="kola_ust")
    P.box((0.0, 0.006, 0.1245), (0.012, 0.022, 0.002), "gumus")
    P.box((0.0, -0.008, 0.1245), (0.006, 0.006, 0.0025), "metal_koyu")
    out.append(P.build())

    # --- Su şişesi: halkalı gövde, saran etiket, omuz, boyun, mavi kapak ---
    P = product("su")
    prof = [(0.03, 0.0), (0.034, 0.006), (0.034, 0.03), (0.032, 0.036), (0.034, 0.042), (0.034, 0.05)]
    P.lathe(prof, "su_govde", seg=16, cap_bot="su_govde")
    P.lathe([(0.034, 0.05), (0.034, 0.12)], "su_govde", seg=16, label="su", band=(0.05, 0.12))
    P.lathe([(0.034, 0.12), (0.032, 0.14), (0.026, 0.16), (0.017, 0.178), (0.014, 0.186), (0.014, 0.196)], "su_govde", seg=16)
    P.lathe([(0.017, 0.196), (0.017, 0.218), (0.014, 0.222)], "kapak_mavi", seg=12, cap_top="kapak_mavi", cap_bot="kapak_mavi")
    out.append(P.build())

    # --- Süt kutusu: üçgen tepeli karton, önde / arkada süt etiketi, yanlarda damla ---
    P = product("sut")
    hw, hd, hb = 0.0375, 0.0375, 0.17
    P.label_box((0, 0, hb / 2), (hw * 2, hd * 2, hb), {"-y": ("etiket", "sut_on"), "+y": ("etiket", "sut_on"),
                                                         "+x": ("etiket", "sut_yan"), "-x": ("etiket", "sut_yan"),
                                                         "-z": ("sut_tepe", None), "+z": ("sut_tepe", None)})
    for sy in (-1, 1):
        P.poly([(-hw, sy * hd, hb), (hw, sy * hd, hb), (hw, 0.0, hb + 0.04), (-hw, 0.0, hb + 0.04)][::(1 if sy < 0 else -1)], "sut_tepe")
    for sx in (-1, 1):
        P.poly([(sx * hw, -hd, hb), (sx * hw, hd, hb), (sx * hw, 0.0, hb + 0.04)][::(1 if sx > 0 else -1)], "sut_mavi")
    P.box((0, 0, hb + 0.046), (hw * 2 + 0.002, 0.006, 0.014), "sut_tepe")
    out.append(P.build())

    # --- Mısır gevreği kutusu: önde kase resmi ve logo, yanlarda besin tablosu ---
    P = product("gevrek")
    P.label_box((0, 0, 0.14), (0.2, 0.07, 0.28), {"-y": ("etiket", "gevrek_on"), "+y": ("etiket", "gevrek_yan"),
                                                   "+x": ("etiket", ("gevrek_yan", (0.0, 0.0, 0.4, 1.0))),
                                                   "-x": ("etiket", ("gevrek_yan", (0.6, 0.0, 1.0, 1.0))),
                                                   "+z": ("gevrek_kenar", None), "-z": ("gevrek_kenar", None)})
    out.append(P.build())

    # --- Cips paketi: şişkin yastık, üstte ve altta dişli kıvrık kenar ---
    P = product("cips")
    W, H, T = 0.16, 0.24, 0.036
    nx, nz = 6, 6
    crimp = 0.022

    def bulge(x, z):
        u = (x / (W / 2)) ** 2
        v = ((z - H / 2) / (H / 2 - crimp)) ** 2
        return T * max(0.0, 1.0 - u ** 2) ** 0.5 * max(0.0, 1.0 - v ** 3) ** 0.5 + 0.002

    for side in (-1, 1):
        grid = []
        for jz in range(nz + 1):
            z = crimp + (H - 2 * crimp) * jz / nz
            row = []
            for ix in range(nx + 1):
                x = -W / 2 + W * ix / nx
                row.append(Vector((x, side * bulge(x * 0.98, z), z)))
            grid.append(row)
        for jz in range(nz):
            for ix in range(nx):
                pts = [grid[jz][ix], grid[jz][ix + 1], grid[jz + 1][ix + 1], grid[jz + 1][ix]]
                if side > 0:
                    pts = [pts[1], pts[0], pts[3], pts[2]]
                    P._faces(pts, [(0, 1, 2, 3)], "cips_folyo")
                else:
                    u0, u1 = ix / nx, (ix + 1) / nx
                    v0, v1 = jz / nz, (jz + 1) / nz
                    P._faces(pts, [(0, 1, 2, 3)], "etiket",
                             [cell_uv("cips_on", u0, v0), cell_uv("cips_on", u1, v0), cell_uv("cips_on", u1, v1), cell_uv("cips_on", u0, v1)])
    # Yan kenarlar (ince)
    for sx in (-1, 1):
        P.box((sx * W / 2, 0, H / 2), (0.004, 0.006, H - 2 * crimp), "cips_folyo")
    # Kıvrık kenarlar: düz şerit ve dişler
    for zc in (crimp / 2, H - crimp / 2):
        P.box((0, 0, zc), (W, 0.006, crimp), "cips_b")
        for k in range(10):
            x = -W / 2 + W * (k + 0.5) / 10
            P.box((x, 0, zc + (crimp / 2 if zc > H / 2 else -crimp / 2)), (0.008, 0.004, 0.004), "cips_b")
    out.append(P.build())

    # --- Çikolata: yatık tablet, üstte ambalaj, uçlarda kıvrık yaldız ---
    P = product("cikolata")
    L, Wd, Ht = 0.15, 0.075, 0.022
    P.label_box((0, 0, Ht / 2), (L, Wd, Ht), {"+z": ("etiket", ("cikolata", (0.14, 0.0, 0.86, 1.0))),
                                              "-y": ("cikolata", None), "+y": ("cikolata", None), "*": ("cikolata", None)})
    for sx in (-1, 1):
        P.box((sx * (L / 2 + 0.012), 0, Ht / 2), (0.024, Wd + 0.004, Ht * 0.7), "altin")
        P.box((sx * (L / 2 + 0.026), 0, Ht / 2), (0.006, Wd + 0.008, Ht * 0.25), "altin")
    out.append(P.build())

    # --- Bal kavanozu: altıgen amber cam, saran etiket, altın kapak ve kırmızı bez ---
    P = product("bal")
    P.lathe([(0.042, 0.0), (0.046, 0.008)], "bal_cam", seg=8, cap_bot="bal_cam")
    P.lathe([(0.046, 0.008), (0.046, 0.085)], "bal_cam", seg=8, label="bal", band=(0.008, 0.085))
    P.lathe([(0.046, 0.085), (0.04, 0.095), (0.036, 0.1)], "bal_cam", seg=8)
    P.lathe([(0.04, 0.1), (0.04, 0.115), (0.034, 0.12)], "altin", seg=12, cap_top="altin", cap_bot="altin")
    P.lathe([(0.05, 0.1), (0.043, 0.122), (0.02, 0.128), (0.0, 0.129)], "bez_kirmizi", seg=10)
    P.lathe([(0.0415, 0.103), (0.0415, 0.108)], "beyaz", seg=12)
    out.append(P.build())

    # --- Ekmek: yuvarlak uçlu somun, üstte çizik yarıklar, alt koyu ---
    P = product("ekmek")
    prof = [(-0.05, 0.0), (0.05, 0.0), (0.058, 0.025), (0.055, 0.055), (0.042, 0.08), (0.022, 0.095), (0.0, 0.1),
            (-0.022, 0.095), (-0.042, 0.08), (-0.055, 0.055), (-0.058, 0.025)]
    secs = 10
    L = 0.13
    rings = []
    for k in range(secs + 1):
        y = -L + 2 * L * k / secs
        f = max(0.0, 1.0 - (abs(y) / (L + 0.006)) ** 4) ** 0.5
        rings.append([Vector((y, x * f, z * (0.35 + 0.65 * f))) for (x, z) in prof])
    n = len(prof)
    for k in range(secs):
        for p in range(n):
            q = (p + 1) % n
            m = "ekmek_alt" if p == 0 else ("ekmek_ust" if 3 <= p <= 7 else "ekmek")
            P._faces([rings[k][p], rings[k][q], rings[k + 1][q], rings[k + 1][p]], [(0, 1, 2, 3)], m)
    P._faces(rings[0], [tuple(range(n))], "ekmek")
    P._faces(rings[-1], [tuple(reversed(range(n)))], "ekmek")
    for k in range(4):
        x = -0.075 + k * 0.05
        P.box((x, 0, 0.097), (0.012, 0.07, 0.008), "ekmek_acik", rot=25)
    out.append(P.build())

    # --- Elma: yukarıda çukur, altta yuvarlak; sap ve yaprak; bir yanı açık kırmızı ---
    P = product("elma")
    prof = [(0.0, 0.004), (0.02, 0.0), (0.036, 0.008), (0.046, 0.025), (0.049, 0.045), (0.045, 0.065), (0.033, 0.08),
            (0.016, 0.083), (0.006, 0.076), (0.0, 0.072)]
    P.lathe(prof, "elma", seg=12)
    P.box((0.002, 0, 0.085), (0.005, 0.005, 0.024), "sap", rot=0)
    P.poly([(0.004, 0.0, 0.092), (0.022, -0.006, 0.098), (0.034, 0.0, 0.094), (0.02, 0.006, 0.088)], "yaprak")
    P.poly([(0.02, 0.006, 0.088), (0.034, 0.0, 0.094), (0.022, -0.006, 0.098), (0.004, 0.0, 0.092)], "yaprak")
    out.append(P.build())

    # --- Kurabiye kutusu: önde kurabiye resmi ---
    P = product("kurabiye")
    P.label_box((0, 0, 0.055), (0.17, 0.05, 0.11), {"-y": ("etiket", "kurabiye"), "+y": ("etiket", "kurabiye"),
                                                    "*": ("kurabiye_kutu", None)})
    out.append(P.build())

    # --- Diş macunu tüpü: yatık; bir ucu düz kıvrık, öbür ucunda omuz ve mavi kapak ---
    P = product("macun")
    L = 0.17
    n_s = 8
    secs = 12
    rings = []
    for k in range(secs + 1):
        t = k / secs                       # 0 kıvrık uç, 1 omuz
        x = -L / 2 + L * t
        flat = max(0.0, 1.0 - t * 1.6)     # kıvrık uçta yassı
        r = 0.024 * (0.85 + 0.15 * min(t * 3, 1.0))
        ring = []
        for p in range(n_s + 1):
            a = math.tau * p / n_s - math.pi / 2
            ry = r * (1.0 + flat * 0.6)
            rz = r * (1.0 - flat * 0.92)
            ring.append(Vector((x, math.cos(a) * ry, 0.025 + math.sin(a) * rz)))
        rings.append(ring)
    for k in range(secs):
        for p in range(n_s):
            pts = [rings[k][p], rings[k + 1][p], rings[k + 1][p + 1], rings[k][p + 1]]
            top = math.sin(math.tau * (p + 0.5) / n_s - math.pi / 2) > -0.2
            if top:
                P._faces(pts, [(0, 1, 2, 3)], "etiket",
                         [cell_uv("macun", k / secs, p / n_s), cell_uv("macun", (k + 1) / secs, p / n_s),
                          cell_uv("macun", (k + 1) / secs, (p + 1) / n_s), cell_uv("macun", k / secs, (p + 1) / n_s)])
            else:
                P._faces(pts, [(0, 1, 2, 3)], "macun_govde")
    P._faces(rings[0][:n_s], [tuple(range(n_s))], "macun_govde")
    P.box((-L / 2 - 0.006, 0, 0.025), (0.012, 0.062, 0.006), "macun_govde")
    for k in range(5):
        P.box((-L / 2 - 0.006, -0.024 + k * 0.012, 0.0285), (0.012, 0.004, 0.001), "macun_kapak")
    P.cyl((L / 2, 0, 0.025), 0.02, 0.01, "macun_govde", seg=10, r2=0.011, axis="x")
    P.cyl((L / 2 + 0.01, 0, 0.025), 0.014, 0.024, "macun_kapak", seg=10, axis="x")
    out.append(P.build())

    # --- Şampuan: basık oval şişe, saran etiket, beyaz kapaklı kapak ---
    P = product("sampuan")
    P.lathe([(0.026, 0.0), (0.034, 0.008)], "sampuan", seg=16, sy=0.6, cap_bot="sampuan")
    P.lathe([(0.034, 0.008), (0.034, 0.13)], "sampuan", seg=16, sy=0.6, label="sampuan", band=(0.008, 0.13))
    P.lathe([(0.034, 0.13), (0.03, 0.15), (0.02, 0.162), (0.014, 0.166)], "sampuan", seg=16, sy=0.6)
    P.lathe([(0.018, 0.166), (0.018, 0.19), (0.014, 0.194)], "sampuan_kapak", seg=12, sy=0.8, cap_top="sampuan_kapak", cap_bot="sampuan_kapak")
    P.box((0.0, -0.012, 0.192), (0.012, 0.006, 0.006), "sampuan_kapak")
    out.append(P.build())

    # --- Konserve: gümüş kenarlı teneke, saran etiket, kapakta halka ---
    P = product("konserve")
    P.lathe([(0.038, 0.0), (0.04, 0.004), (0.039, 0.008), (0.04, 0.012)], "gumus", seg=16, cap_bot="gumus")
    P.lathe([(0.0405, 0.012), (0.0405, 0.078)], "gumus", seg=16, label="konserve", band=(0.012, 0.078))
    P.lathe([(0.04, 0.078), (0.039, 0.082), (0.04, 0.086), (0.038, 0.09)], "gumus", seg=16, cap_top="kola_ust")
    P.lathe([(0.014, 0.0905), (0.018, 0.0905), (0.018, 0.093), (0.014, 0.093)], "metal_koyu", seg=10, c=(0.0, -0.012, 0.0))
    out.append(P.build())

    # --- Yumurta kolisi: altı gözlü karton, altı yumurta, arkaya açılmış kapak (içinde etiket) ---
    P = product("yumurta")
    W, Dp, Hb = 0.16, 0.1, 0.035
    P.label_box((0, 0, Hb / 2), (W, Dp, Hb), {"*": ("karton", None), "+z": ("karton_koyu", None)})
    for i in range(3):
        for j in range(2):
            x, y = -0.05 + i * 0.05, -0.025 + j * 0.05
            P.lathe([(0.0, 0.0), (0.012, 0.004), (0.019, 0.016), (0.02, 0.028), (0.017, 0.042), (0.01, 0.052), (0.0, 0.056)],
                    "yumurta_kabuk" if (i + j) % 2 == 0 else "yumurta_beyaz", seg=8, c=(x, y, Hb - 0.012))
    # Kapak: arka kenardan menteşeli, 70° açık; iç yüzünde etiket
    ang = math.radians(70.0)
    hy = Dp / 2
    pts_in = []
    for (x, d) in ((-W / 2, 0.0), (W / 2, 0.0), (W / 2, Dp), (-W / 2, Dp)):
        pts_in.append((x, hy + d * math.cos(math.pi - ang), Hb + d * math.sin(math.pi - ang)))
    P.quad_uv([pts_in[1], pts_in[0], pts_in[3], pts_in[2]], "etiket", "yumurta_kapak", (1.0, 0.0, 0.0, 1.0))
    P._faces([Vector(p) + Vector((0, 0.004, 0.0)) for p in pts_in], [(0, 1, 2, 3)], "karton")
    out.append(P.build())
    return out


# ---------------------------------------------------------------------------
def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)


def preview(objs, path_dir):
    os.makedirs(path_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x, scene.render.resolution_y = 1280, 800
    sh = scene.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'TEXTURE'
    sh.show_object_outline = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.5, 0.55, 0.6)
    cam_d = bpy.data.cameras.new("Kam")
    cam = bpy.data.objects.new("Kam", cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam

    def shot(name, loc, target, lens=35, ortho=None, only=None):
        for ob in bpy.data.objects:
            if ob.type == 'MESH':
                ob.hide_render = only is not None and ob not in only
        cam.location = loc
        d = Vector(target) - Vector(loc)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        if ortho:
            cam_d.type = 'ORTHO'
            cam_d.ortho_scale = ortho
        else:
            cam_d.type = 'PERSP'
            cam_d.lens = lens
        scene.render.filepath = os.path.join(path_dir, name + ".png")
        bpy.ops.render.render(write_still=True)

    bina = [bpy.data.objects["Bina"], bpy.data.objects["Cati"]]
    shot("dis", (6.5, -9.5, 3.2), (0, 0, 1.6), lens=28, only=bina)
    # Mobilya ve ürünler yan yana
    furn = ["Raf", "DuvarRaf", "Tezgah", "YazarKasa", "Buzdolabi", "MeyveKasasi", "MeyveTezgahi", "GazeteStandi", "TabelaA", "Sepetler"]
    x = 0.0
    lay = []
    for n in furn:
        ob = bpy.data.objects[n]
        ob.location = (x, 30, 0)
        lay.append(ob)
        x += ob.dimensions.x + 0.5
    shot("mobilya", (x / 2, 30 - 13, 4.0), (x / 2, 30, 0.8), lens=22, only=lay)
    for ob in lay:
        ob.location = (0, 0, 0)
    prods = [ob for ob in bpy.data.objects if ob.name.startswith("urun_")]
    x = 0.0
    for ob in prods:
        ob.location = (x, 40, 0)
        x += 0.25
    shot("urunler", (x / 2, 40 - 2.4, 0.75), (x / 2, 40, 0.08), lens=35, only=prods)
    for ob in prods:
        c = ob.location
        h = max(ob.dimensions.z, 0.08)
        shot("u_" + ob.name, (c.x + 0.25, c.y - 0.42, h * 0.9 + 0.14), (c.x, c.y, h * 0.45), lens=50, only=[ob])
    for ob in prods:
        ob.location = (0, 0, 0)
    cam_d.type = 'PERSP'


def main():
    clear()
    build_shell()
    build_roof()
    build_gondola()
    build_wall_shelf()
    build_counter()
    build_register()
    build_fridge()
    build_fridge_shelves()
    build_produce()
    build_fruit_stand()
    build_newsstand()
    build_aboard()
    build_baskets()
    build_camera()
    build_camera_head()
    build_products()
    if PREVIEW_DIR:
        preview(None, PREVIEW_DIR)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_apply=True)
    print("DUKKAN GLB", OUT)


main()
