"""Peyzaj: ağaçlar, çalılar, çalı grupları, çit, ot öbekleri ve kayalar. Tek .glb.

  blender --background --factory-startup --python tools/blender/peyzaj_build.py -- [cikti.glb]

Her tür iki nesne: "<ad>" (yakın, ayrıntılı) ve "<ad>_uzak" (uzak, çok az üçgen). Köken gövdenin
dibi (zemin). Renk köşe renginde (tek malzeme, MultiMesh ile çizilir; shaders/peyzaj.gdshader):
  RGB: renk (yapraklarda üst yüzler açık, alt / iç yüzler koyu: ışık ve gölge hissi)
  A:   0..0.5 gövde / dal (0.5 ile çarpılmış rüzgâr payı), 0.5..1 yaprak (rüzgâr payı = (a-0.5)*2).
       Yapraklar oyunda örnek başına hafif renk kaydırması alır (aynı ağaç her yerde aynı durmasın).
Koordinat (Blender): Z yukarı; dışa aktarımda Godot'a Y yukarı.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0]) if args else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "peyzaj", "peyzaj.glb")

for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
for me in list(bpy.data.meshes):
    bpy.data.meshes.remove(me)

STATS = []


def srgb(c):
    return tuple(max(0.0, min(1.0, v)) for v in c)


def mul(c, k):
    return (c[0] * k, c[1] * k, c[2] * k)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


class Part:
    """Bir nesnenin bmesh'i ve renk katmanı; parçalar buna eklenir."""

    def __init__(self, name, height):
        self.name = name
        self.H = height
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")

    def paint(self, faces, fn):
        for f in faces:
            for l in f.loops:
                rgb, a = fn(f, l.vert)
                r, g, b = srgb(rgb)
                l[self.col] = (r, g, b, max(0.0, min(1.0, a)))

    # ---------- Gövde / dal ----------
    def tube(self, pts, radii, sides, bark, seed=0, cap=True, sway_k=1.0):
        rnd = random.Random(seed)
        rings = []
        n = len(pts)
        for i, p in enumerate(pts):
            if i < n - 1:
                t = (pts[i + 1] - p).normalized()
            else:
                t = (p - pts[i - 1]).normalized()
            if 0 < i < n - 1:
                t = ((pts[i + 1] - pts[i - 1])).normalized()
            up = Vector((0, 0, 1)) if abs(t.z) < 0.95 else Vector((1, 0, 0))
            u = t.cross(up).normalized()
            v = t.cross(u).normalized()
            ring = []
            for k in range(sides):
                a = k / sides * math.tau + i * 0.4
                rr = radii[i] * (1.0 + rnd.uniform(-0.06, 0.06))
                ring.append(self.bm.verts.new(p + (u * math.cos(a) + v * math.sin(a)) * rr))
            rings.append(ring)
        faces = []
        for i in range(n - 1):
            for k in range(sides):
                a, b = rings[i][k], rings[i][(k + 1) % sides]
                c, d = rings[i + 1][(k + 1) % sides], rings[i + 1][k]
                faces.append(self.bm.faces.new((a, b, c, d)))
        if cap:
            faces.append(self.bm.faces.new(list(reversed(rings[-1])) if False else rings[-1]))
        H = self.H

        def fn(f, v):
            z = v.co.z
            k = 0.75 + 0.25 * min(z / 2.0, 1.0)
            shade = 0.85 + 0.15 * (f.normal.x * 0.5 + 0.5)
            c = mul(bark, k * shade * (0.95 + 0.1 * noise.noise(v.co * 3.0)))
            return c, 0.5 * sway_k * min(max(z / H, 0.0), 1.0) ** 2
        self.paint(faces, fn)
        return faces

    # ---------- Yaprak öbeği ----------
    def blob(self, c, r, leaf, subdiv=1, squash=(1.0, 1.0, 1.0), rough=0.22, seed=0, top=None, under=0.62, freq=1.3):
        # bmesh: subdivisions=1 düz ikosahedron (20 yüz), 2 = 80 yüz
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv + 1, radius=1.0)
        verts = res["verts"]
        off = Vector((seed * 1.37, seed * 2.11, seed * 0.73))
        for v in verts:
            d = v.co.normalized()
            n = noise.noise(d * freq * 2.0 + off)
            v.co = Vector((d.x * squash[0], d.y * squash[1], d.z * squash[2])) * r * (1.0 + rough * n) + c
        faces = list({f for v in verts for f in v.link_faces})
        rnd = random.Random(seed)
        tint = {f: rnd.uniform(0.9, 1.08) for f in faces}
        H = self.H
        cz = c.z

        def fn(f, v):
            nz = f.normal.z
            # Üst yüzler açık, alt yüzler koyu; öbeğin alt yarısı ve ağacın alt kısmı biraz daha koyu
            k = under + (1.0 - under) * (0.5 + 0.5 * nz)
            k *= 0.88 + 0.12 * min(max((v.co.z - cz + r) / (2.0 * r), 0.0), 1.0)
            base = leaf if top is None else mix(leaf, top, max(nz, 0.0) ** 1.5)
            col = mul(base, k * tint[f])
            sway = min(max(v.co.z / H, 0.0), 1.0)
            return col, 0.5 + 0.5 * (0.35 + 0.65 * sway)
        self.paint(faces, fn)
        return faces

    # ---------- Küçük süs: çiçek / meyve ----------
    def dots(self, centers, r, color, seed=0):
        rnd = random.Random(seed)
        faces = []
        for c in centers:
            # Küçük sekiz yüzlü (çiçek, meyve)
            rr = r * rnd.uniform(0.8, 1.2)
            vs = [self.bm.verts.new(c + d * rr) for d in (Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, 1, 0)),
                                                         Vector((0, -1, 0)), Vector((0, 0, 1)), Vector((0, 0, -1)))]
            for a, b in ((0, 2), (2, 1), (1, 3), (3, 0)):
                faces.append(self.bm.faces.new((vs[a], vs[b], vs[4])))
                faces.append(self.bm.faces.new((vs[b], vs[a], vs[5])))
        H = self.H

        def fn(f, v):
            return mul(color, 0.8 + 0.25 * (0.5 + 0.5 * f.normal.z)), 0.5 + 0.5 * min(max(v.co.z / H, 0.0), 1.0)
        self.paint(faces, fn)

    # ---------- Ot yaprağı (ince üçgen, iki yüzlü) ----------
    def blades(self, base, count, h, spread, color, tip, seed=0, width=0.035):
        rnd = random.Random(seed)
        faces = []
        for _ in range(count):
            a = rnd.uniform(0, math.tau)
            p = base + Vector((math.cos(a), math.sin(a), 0)) * rnd.uniform(0, spread)
            hh = h * rnd.uniform(0.6, 1.15)
            lean = Vector((math.cos(a), math.sin(a), 0)) * hh * rnd.uniform(0.15, 0.45)
            side = Vector((-math.sin(a + 1.2), math.cos(a + 1.2), 0)) * width
            v1 = self.bm.verts.new(p - side)
            v2 = self.bm.verts.new(p + side)
            v3 = self.bm.verts.new(p + lean + Vector((0, 0, hh)))
            faces.append(self.bm.faces.new((v1, v2, v3)))
            w1 = self.bm.verts.new(p - side)
            w2 = self.bm.verts.new(p + side)
            w3 = self.bm.verts.new(p + lean + Vector((0, 0, hh)))
            faces.append(self.bm.faces.new((w3, w2, w1)))

        def fn(f, v):
            t = min(max((v.co.z - base.z) / h, 0.0), 1.0)
            return mix(color, tip, t), 0.5 + 0.5 * t
        self.paint(faces, fn)

    # ---------- Kaya ----------
    def rock(self, c, r, color, squash=(1.0, 0.8, 0.6), seed=0, subdiv=1):
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv + 1, radius=1.0)
        off = Vector((seed * 3.1, seed * 1.7, 0.5))
        for v in res["verts"]:
            d = v.co.normalized()
            n = noise.noise(d * 1.6 + off) * 0.35 + noise.noise(d * 4.0 + off) * 0.1
            p = Vector((d.x * squash[0], d.y * squash[1], d.z * squash[2])) * r * (1.0 + n)
            p.z = max(p.z, -0.15 * r)
            v.co = p + c
        faces = list({f for v in res["verts"] for f in v.link_faces})
        moss = (0.36, 0.5, 0.25)

        def fn(f, v):
            nz = f.normal.z
            k = 0.62 + 0.38 * (0.5 + 0.5 * nz)
            base = mix(color, moss, max(nz - 0.55, 0.0) * 1.4)
            return mul(base, k * (0.94 + 0.12 * noise.noise(v.co * 2.0))), 0.0
        self.paint(faces, fn)

    def finish(self, smooth=False):
        bmesh.ops.remove_doubles(self.bm, verts=[v for v in self.bm.verts], dist=0.0001) if False else None
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        for p in me.polygons:
            p.use_smooth = smooth
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.color_attributes.active_color = me.color_attributes["Col"]
        STATS.append((self.name, len(me.polygons)))
        self.bm.free()
        return ob


def rv(rnd, a, b):
    return rnd.uniform(a, b)


# ---------------- Ağaç türleri ----------------

BARK = (0.48, 0.35, 0.24)
BARK_GREY = (0.55, 0.52, 0.47)


def broadleaf(name, seed, H=7.0, R=2.6, leaf=(0.3, 0.55, 0.2), top=(0.5, 0.72, 0.28), branches=4, bark=BARK, blossom=None):
    """Yuvarlak taçlı yapraklı ağaç (çınar / ıhlamur / zeytin): kök genişlemesi olan gövde dallara
    ayrılır, dallardan ince sürgünler çıkar. Taç: içte birkaç büyük öbek, dışta çok sayıda küçük,
    tırtıklı yaprak kümesi (siluet tümsekli olur); dışa / üste bakan kümeler açık, içtekiler koyu."""
    rnd = random.Random(seed)
    near = Part(name, H)
    far = Part(name + "_uzak", H)
    k7 = H / 7.0
    split = H * rv(rnd, 0.32, 0.4)
    lean = Vector((rv(rnd, -0.25, 0.25), rv(rnd, -0.25, 0.25), 0))
    trunk_top = Vector((0, 0, split)) + lean
    # Gövde: dipte kök genişlemesi
    near.tube([Vector((0, 0, -0.2)), Vector((0, 0, 0.12)), Vector((0, 0, 0.5)), Vector((0, 0, split * 0.6)) + lean * 0.5, trunk_top],
              [0.36 * k7, 0.32 * k7, 0.22 * k7, 0.19 * k7, 0.16 * k7], 7, bark, seed)
    far.tube([Vector((0, 0, -0.2)), trunk_top], [0.22 * k7, 0.15 * k7], 4, bark, seed, cap=False)
    crown_c = Vector((0, 0, H - R * 0.9)) + lean
    ends = []
    a0 = rv(rnd, 0, math.tau)
    for i in range(branches):
        a = a0 + i / branches * math.tau + rv(rnd, -0.3, 0.3)
        out = Vector((math.cos(a), math.sin(a), 0))
        reach = R * rv(rnd, 0.5, 0.72)
        mid = trunk_top + out * reach * 0.45 + Vector((0, 0, H * 0.14))
        end = trunk_top + out * reach + Vector((0, 0, H * rv(rnd, 0.22, 0.34)))
        near.tube([trunk_top, mid, end], [0.12 * k7, 0.085 * k7, 0.05 * k7], 5, bark, seed + i, sway_k=1.2)
        # İnce sürgün
        side = Vector((-out.y, out.x, 0)) * (1 if i % 2 else -1)
        twig = mid + (side * 0.6 + out * 0.5).normalized() * reach * 0.45 + Vector((0, 0, H * 0.12))
        near.tube([mid, twig], [0.05 * k7, 0.03 * k7], 4, bark, seed + 50 + i, cap=False, sway_k=1.4)
        ends.append(end)
        ends.append(twig)
    ends.append(crown_c + Vector((0, 0, R * 0.35)))
    # İç öbek (büyük, koyu): tacın hacmi
    for j in range(1):
        d = Vector((rv(rnd, -1, 1), rv(rnd, -1, 1), rv(rnd, -0.3, 0.4)))
        c = crown_c + Vector((d.x * R * 0.35, d.y * R * 0.35, d.z * R * 0.4))
        near.blob(c, R * rv(rnd, 0.5, 0.6), mul(leaf, 0.82), 1, (1.0, 1.0, 0.8), 0.18, seed * 31 + j, mul(top, 0.85), under=0.55)
    # Dış kümeler (küçük, tırtıklı): dal uçlarının çevresinde ve tacın kabuğunda
    k = 0
    shell = []
    for e in ends:
        d = Vector((rv(rnd, -1, 1), rv(rnd, -1, 1), rv(rnd, -0.2, 1))).normalized()
        shell.append(e + d * R * rv(rnd, 0.1, 0.22))
    for j in range(5):
        th = rv(rnd, 0, math.tau)
        ph = rv(rnd, 0.15, 1.3)
        d = Vector((math.cos(th) * math.cos(ph - 0.4), math.sin(th) * math.cos(ph - 0.4), math.sin(ph)))
        shell.append(crown_c + Vector((d.x * R * 0.85, d.y * R * 0.85, d.z * R * 0.75)))
    for c in shell:
        rel = c - crown_c
        outk = min(max(rel.length / (R * 0.9), 0.0), 1.0)
        upk = min(max(rel.z / (R * 0.8) * 0.5 + 0.5, 0.0), 1.0)
        light = 0.82 + 0.28 * (0.55 * outk + 0.45 * upk)
        near.blob(c, R * rv(rnd, 0.34, 0.44), mul(leaf, light), 1, (1.0, 1.0, 0.82), 0.3, seed * 71 + k, mul(top, light), under=0.6)
        k += 1
    # Uzak: birkaç öbekle aynı siluet
    far.blob(crown_c, R * 0.95, leaf, 0, (1.0, 1.0, 0.82), 0.18, seed * 17, top)
    for j in range(3):
        a = a0 + j / 3 * math.tau
        far.blob(crown_c + Vector((math.cos(a) * R * 0.55, math.sin(a) * R * 0.55, R * 0.1)), R * 0.55, leaf, 0, (1.0, 1.0, 0.85), 0.15, seed * 19 + j, top)
    if blossom:
        pts = []
        for _ in range(20):
            e = shell[rnd.randrange(len(shell))]
            d = Vector((rv(rnd, -1, 1), rv(rnd, -1, 1), rv(rnd, 0.0, 1))).normalized()
            pts.append(e + d * R * 0.3)
        near.dots(pts, 0.1, blossom, seed)
    near.finish()
    far.finish()


def stone_pine(name, seed, H=9.0, R=3.4):
    """Fıstık çamı: uzun çıplak gövde, tepede yatay dallar ve yassı şemsiye taç."""
    rnd = random.Random(seed)
    near = Part(name, H)
    far = Part(name + "_uzak", H)
    bend = Vector((rv(rnd, -0.8, 0.8), rv(rnd, -0.8, 0.8), 0))
    top = Vector((0, 0, H * 0.72)) + bend
    pts = [Vector((0, 0, -0.2)), Vector((0, 0, H * 0.3)) + bend * 0.25, Vector((0, 0, H * 0.55)) + bend * 0.7, top]
    near.tube(pts, [0.26, 0.21, 0.18, 0.14], 7, (0.5, 0.33, 0.24), seed)
    far.tube([pts[0], top], [0.24, 0.14], 4, (0.5, 0.33, 0.24), seed, cap=False)
    leaf = (0.22, 0.42, 0.2)
    topc = (0.38, 0.58, 0.26)
    a0 = rv(rnd, 0, math.tau)
    ends = []
    for i in range(5):
        a = a0 + i / 5 * math.tau + rv(rnd, -0.3, 0.3)
        out = Vector((math.cos(a), math.sin(a), 0))
        end = top + out * R * rv(rnd, 0.45, 0.7) + Vector((0, 0, rv(rnd, 0.5, 1.2)))
        near.tube([top, top + out * R * 0.25 + Vector((0, 0, 0.5)), end], [0.11, 0.08, 0.05], 5, (0.5, 0.33, 0.24), seed + i, sway_k=1.2)
        ends.append(end)
    ends.append(top + Vector((0, 0, 1.3)))
    k = 0
    for e in ends:
        for j in range(2):
            off = Vector((rv(rnd, -0.7, 0.7), rv(rnd, -0.7, 0.7), rv(rnd, 0.0, 0.4)))
            near.blob(e + off, R * rv(rnd, 0.38, 0.48), leaf, 1, (1.0, 1.0, 0.45), 0.28, seed * 13 + k, topc, under=0.55)
            k += 1
    far.blob(top + Vector((0, 0, 1.2)), R * 1.05, leaf, 1, (1.0, 1.0, 0.36), 0.12, seed, topc, under=0.55)
    near.finish()
    far.finish()


def fir(name, seed, H=8.0, R=2.0, leaf=(0.16, 0.36, 0.2), top=(0.26, 0.5, 0.28), tiers=6):
    """Köknar: üst üste dişli koni katları, sarkık uçlar; altta gövde görünür."""
    rnd = random.Random(seed)
    near = Part(name, H)
    far = Part(name + "_uzak", H)
    near.tube([Vector((0, 0, -0.2)), Vector((0, 0, H * 0.5))], [0.2 * H / 8, 0.1 * H / 8], 6, (0.4, 0.28, 0.2), seed)
    far.tube([Vector((0, 0, -0.2)), Vector((0, 0, H * 0.3))], [0.18 * H / 8, 0.12 * H / 8], 4, (0.4, 0.28, 0.2), seed, cap=False)
    z0 = H * 0.16
    for part, sides, ntier, jag in ((near, 14, tiers + 2, True), (far, 6, 3, False)):
        faces = []
        for t in range(ntier):
            f = t / ntier
            zb = z0 + (H - z0) * f * 0.92
            zt = zb + (H - z0) / ntier * (1.9 if part is near else 1.6)
            if t == ntier - 1:
                zt = H
            rr = R * (1.0 - f * 0.82) * rv(rnd, 0.92, 1.05)
            apex = part.bm.verts.new(Vector((rv(rnd, -0.05, 0.05), rv(rnd, -0.05, 0.05), zt)))
            ring = []
            a0 = rv(rnd, 0, math.tau)
            for k in range(sides):
                a = a0 + k / sides * math.tau
                long = (1.0 if k % 2 == 0 else 0.72) if jag else 1.0
                droop = (0.28 if k % 2 == 0 else 0.05) * rr if jag else 0.15 * rr
                ring.append(part.bm.verts.new(Vector((math.cos(a) * rr * long, math.sin(a) * rr * long, zb - droop))))
            inner = part.bm.verts.new(Vector((0, 0, zb + 0.15 * rr)))
            for k in range(sides):
                faces.append(part.bm.faces.new((ring[k], ring[(k + 1) % sides], apex)))
                faces.append(part.bm.faces.new((ring[(k + 1) % sides], ring[k], inner)))
        Hh = H

        def fn(f, v, leaf=leaf, top=top):
            nz = f.normal.z
            k = 0.5 + 0.5 * (0.5 + 0.5 * nz)
            k *= 0.8 + 0.2 * min(v.co.z / Hh, 1.0)
            return mul(mix(leaf, top, max(nz, 0.0)), k * (0.94 + 0.12 * noise.noise(v.co * 1.7))), 0.5 + 0.5 * min(v.co.z / Hh, 1.0)
        part.paint(faces, fn)
    near.finish()
    far.finish()


def cypress(name, seed, H=7.5, R=0.75):
    """Servi: ince uzun iğ biçimi (Akdeniz kasabası)."""
    rnd = random.Random(seed)
    near = Part(name, H)
    far = Part(name + "_uzak", H)
    near.tube([Vector((0, 0, -0.2)), Vector((0, 0, 1.0))], [0.13, 0.11], 6, (0.4, 0.3, 0.22), seed, cap=False)
    leaf = (0.15, 0.32, 0.17)
    top = (0.25, 0.45, 0.24)
    mid = H * 0.5 + 0.3
    near.blob(Vector((0, 0, mid)), 1.0, leaf, 2, (R, R, (H - 0.6) * 0.5), 0.16, seed, top, under=0.55, freq=2.2)
    for i in range(3):
        z = rv(rnd, H * 0.3, H * 0.7)
        a = rv(rnd, 0, math.tau)
        near.blob(Vector((math.cos(a) * R * 0.45, math.sin(a) * R * 0.45, z)), 1.0, leaf, 1,
                  (R * 0.6, R * 0.6, H * 0.18), 0.2, seed + 7 + i, top, under=0.55)
    far.blob(Vector((0, 0, mid)), 1.0, leaf, 0, (R * 1.05, R * 1.05, (H - 0.6) * 0.5), 0.05, seed, top, under=0.55)
    near.finish()
    far.finish()


def palm(name, seed, H=7.0):
    """Palmiye: kavisli boğumlu gövde, sarkan yapraklar (iki yüzlü şerit), hindistancevizleri."""
    rnd = random.Random(seed)
    near = Part(name, H)
    far = Part(name + "_uzak", H)
    dirv = Vector((math.cos(seed), math.sin(seed), 0))
    bend = rv(rnd, 0.8, 1.6)
    pts, radii = [], []
    n = 12
    for i in range(n + 1):
        t = i / n
        pts.append(Vector((0, 0, -0.2 + t * H)) + dirv * bend * t * t)
        radii.append((0.22 - 0.07 * t) * (1.0 if i % 2 == 0 else 1.12))
    near.tube(pts, radii, 7, (0.6, 0.48, 0.34), seed)
    far.tube([pts[0], pts[6], pts[-1]], [0.22, 0.2, 0.15], 4, (0.6, 0.48, 0.34), seed, cap=False)
    crown = pts[-1]
    leaf = (0.26, 0.52, 0.2)
    tip = (0.45, 0.65, 0.25)
    fronds = 9
    for part, segs, nf in ((near, 7, fronds), (far, 3, 6)):
        faces = []
        for f in range(nf):
            a = f / nf * math.tau + rv(rnd, -0.2, 0.2)
            out = Vector((math.cos(a), math.sin(a), 0))
            side = Vector((-math.sin(a), math.cos(a), 0))
            L = rv(rnd, 2.6, 3.3)
            up = rv(rnd, 0.4, 0.9)
            spine = []
            for s in range(segs + 1):
                t = s / segs
                spine.append(crown + out * L * t + Vector((0, 0, up * math.sin(t * math.pi * 0.8) - t * t * 1.6)))
            for s in range(segs):
                t0, t1 = s / segs, (s + 1) / segs
                w0 = 0.55 * math.sin(max(t0, 0.08) * math.pi) * (1.0 - 0.3 * t0)
                w1 = 0.55 * math.sin(max(t1, 0.08) * math.pi) * (1.0 - 0.3 * t1)
                for sd in (-1, 1):
                    droop0 = Vector((0, 0, -0.25 * w0))
                    droop1 = Vector((0, 0, -0.25 * w1))
                    a0v = part.bm.verts.new(spine[s])
                    b0v = part.bm.verts.new(spine[s + 1])
                    c0v = part.bm.verts.new(spine[s + 1] + side * sd * w1 + droop1)
                    d0v = part.bm.verts.new(spine[s] + side * sd * w0 + droop0)
                    q = (a0v, b0v, c0v, d0v) if sd > 0 else (d0v, c0v, b0v, a0v)
                    faces.append(part.bm.faces.new(q))
                    # arka yüz
                    a1 = part.bm.verts.new(spine[s]); b1 = part.bm.verts.new(spine[s + 1])
                    c1 = part.bm.verts.new(spine[s + 1] + side * sd * w1 + droop1); d1 = part.bm.verts.new(spine[s] + side * sd * w0 + droop0)
                    q2 = (d1, c1, b1, a1) if sd > 0 else (a1, b1, c1, d1)
                    faces.append(part.bm.faces.new(q2))
        Hh = H

        def fn(f, v):
            d = (v.co - crown).length / 3.2
            k = 0.7 + 0.3 * (0.5 + 0.5 * abs(f.normal.z))
            return mul(mix(leaf, tip, min(d, 1.0)), k), 0.5 + 0.5 * min(0.5 + d * 0.5, 1.0)
        part.paint(faces, fn)
    nuts = [crown + Vector((math.cos(i * 2.1), math.sin(i * 2.1), -0.35)) * 0.28 for i in range(4)]
    near.dots(nuts, 0.16, (0.4, 0.3, 0.15), seed)
    near.finish()
    far.finish()


# ---------------- Çalılar ----------------

def bush(name, seed, R=0.9, leaf=(0.26, 0.5, 0.2), top=(0.42, 0.66, 0.28), flowers=None, n=5):
    rnd = random.Random(seed)
    H = R * 1.3
    near = Part(name, H)
    far = Part(name + "_uzak", H)
    for i in range(n):
        a = rv(rnd, 0, math.tau)
        d = rv(rnd, 0.0, R * 0.55) if i else 0.0
        r = R * (rv(rnd, 0.5, 0.65) if i else 0.72)
        c = Vector((math.cos(a) * d, math.sin(a) * d, r * 0.75 + (rv(rnd, 0, R * 0.2) if i else R * 0.15)))
        near.blob(c, r, leaf, 1, (1.0, 1.0, 0.85), 0.26, seed * 11 + i, top, under=0.58)
    far.blob(Vector((0, 0, R * 0.6)), R * 0.95, leaf, 0, (1.0, 1.0, 0.75), 0.1, seed, top, under=0.58)
    if flowers:
        pts = []
        for _ in range(16):
            d = Vector((rv(rnd, -1, 1), rv(rnd, -1, 1), rv(rnd, 0.1, 1.0))).normalized()
            pts.append(Vector((0, 0, R * 0.62)) + Vector((d.x * R * 0.92, d.y * R * 0.92, d.z * R * 0.78)))
        near.dots(pts, 0.07, flowers, seed)
    near.finish()
    far.finish()


def hedge(name, seed, L=2.0, Hh=0.9, Wd=0.7):
    near = Part(name, Hh)
    far = Part(name + "_uzak", Hh)
    leaf = (0.22, 0.44, 0.19)
    top = (0.36, 0.6, 0.26)
    for part, segs, rough in ((near, 3, 0.1), (far, 1, 0.0)):
        for i in range(segs):
            x = -L * 0.5 + L * (i + 0.5) / segs
            part.blob(Vector((x, 0, Hh * 0.5)), 1.0, leaf, 1, (L / segs * 0.62, Wd * 0.55, Hh * 0.55), rough, seed + i, top, under=0.55, freq=2.0)
    near.finish()
    far.finish()


def bush_group(name, seed, parts, grass=0):
    """Çalı grubu: birkaç çalı, ot öbeği ve isteğe bağlı kaya bir arada (kenarlarda doğal öbekler)."""
    rnd = random.Random(seed)
    H = 1.4
    near = Part(name, H)
    far = Part(name + "_uzak", H)
    for (x, y, R, leaf, top, flowers) in parts:
        n = 4
        for i in range(n):
            a = rv(rnd, 0, math.tau)
            d = rv(rnd, 0, R * 0.5) if i else 0.0
            r = R * (rv(rnd, 0.5, 0.62) if i else 0.7)
            c = Vector((x + math.cos(a) * d, y + math.sin(a) * d, r * 0.75 + (rv(rnd, 0, R * 0.15) if i else R * 0.12)))
            near.blob(c, r, leaf, 1, (1.0, 1.0, 0.82), 0.25, seed * 7 + i + int(x * 10), top, under=0.58)
        far.blob(Vector((x, y, R * 0.6)), R * 0.92, leaf, 0, (1.0, 1.0, 0.75), 0.1, seed, top, under=0.58)
        if flowers:
            pts = []
            for _ in range(10):
                d = Vector((rv(rnd, -1, 1), rv(rnd, -1, 1), rv(rnd, 0.1, 1.0))).normalized()
                pts.append(Vector((x, y, R * 0.6)) + Vector((d.x * R * 0.9, d.y * R * 0.9, d.z * R * 0.75)))
            near.dots(pts, 0.065, flowers, seed + int(x * 10))
    for g in range(grass):
        a = rv(rnd, 0, math.tau)
        near.blades(Vector((math.cos(a) * 1.3, math.sin(a) * 1.1, 0)), 9, 0.45, 0.25, (0.3, 0.5, 0.18), (0.6, 0.75, 0.3), seed + g)
    near.finish()
    far.finish()


def grass_tuft(name, seed, n=16, h=0.5):
    near = Part(name, h)
    far = Part(name + "_uzak", h)
    near.blades(Vector((0, 0, 0)), n, h, 0.28, (0.3, 0.5, 0.18), (0.62, 0.76, 0.32), seed)
    far.blades(Vector((0, 0, 0)), 4, h, 0.2, (0.3, 0.5, 0.18), (0.62, 0.76, 0.32), seed)
    near.finish()
    far.finish()


def rocks(name, seed, R=0.9, n=3):
    rnd = random.Random(seed)
    near = Part(name, R)
    far = Part(name + "_uzak", R)
    col = (0.6, 0.58, 0.55)
    for i in range(n):
        a = rv(rnd, 0, math.tau)
        d = rv(rnd, 0, R * 0.9) if i else 0
        r = R * (rv(rnd, 0.35, 0.55) if i else 1.0)
        c = Vector((math.cos(a) * d, math.sin(a) * d, 0))
        near.rock(c, r, col, (1.0, rv(rnd, 0.7, 0.9), rv(rnd, 0.5, 0.75)), seed * 5 + i)
        if i == 0:
            far.rock(c, r, col, (1.0, 0.8, 0.62), seed * 5, subdiv=0)
    near.finish()
    far.finish()


# ---------------- Üretim ----------------

LEAF_A = ((0.3, 0.55, 0.2), (0.5, 0.72, 0.28))      # çınar yeşili
LEAF_B = ((0.24, 0.47, 0.22), (0.42, 0.64, 0.3))    # ıhlamur, koyu
LEAF_C = ((0.38, 0.58, 0.18), (0.62, 0.78, 0.3))    # açık taze yeşil

broadleaf("cinar_1", 1, H=7.5, R=2.8, leaf=LEAF_A[0], top=LEAF_A[1], branches=4)
broadleaf("cinar_2", 2, H=6.2, R=2.4, leaf=LEAF_B[0], top=LEAF_B[1], branches=3)
broadleaf("cinar_3", 3, H=8.8, R=3.2, leaf=LEAF_C[0], top=LEAF_C[1], branches=5)
broadleaf("erguvan", 4, H=5.2, R=2.3, leaf=(0.86, 0.46, 0.56), top=(1.0, 0.7, 0.78), branches=4,
          bark=(0.36, 0.27, 0.22))
broadleaf("ihlamur", 15, H=6.8, R=2.6, leaf=(0.34, 0.56, 0.2), top=(0.56, 0.74, 0.3), branches=4, blossom=(0.98, 0.94, 0.7))
broadleaf("zeytin", 5, H=4.6, R=2.2, leaf=(0.42, 0.5, 0.32), top=(0.6, 0.66, 0.46), branches=4, bark=BARK_GREY)
stone_pine("fistikcami_1", 6, H=9.5, R=3.6)
stone_pine("fistikcami_2", 7, H=7.8, R=3.0)
fir("koknar_1", 8, H=8.5, R=2.1)
fir("koknar_2", 9, H=6.5, R=1.8, leaf=(0.18, 0.4, 0.22), top=(0.3, 0.55, 0.3))
fir("koknar_3", 10, H=10.5, R=2.4, tiers=7)
cypress("servi_1", 11, H=7.5, R=0.75)
cypress("servi_2", 12, H=5.8, R=0.65)
palm("palmiye_1", 13, H=7.0)
palm("palmiye_2", 14, H=5.6)

bush("cali_1", 21, R=0.8)
bush("cali_2", 22, R=1.05, leaf=LEAF_B[0], top=LEAF_B[1], n=6)
bush("cali_3", 23, R=0.6, leaf=LEAF_C[0], top=LEAF_C[1], n=4)
bush("cali_pembe", 24, R=0.85, leaf=(0.24, 0.46, 0.2), top=(0.38, 0.6, 0.27), flowers=(0.98, 0.5, 0.72))
bush("cali_sari", 25, R=0.75, leaf=(0.3, 0.5, 0.2), top=(0.46, 0.64, 0.28), flowers=(1.0, 0.86, 0.3))
bush("cali_beyaz", 26, R=0.9, leaf=LEAF_B[0], top=LEAF_B[1], flowers=(0.97, 0.96, 0.92))
hedge("cit", 27)
bush_group("cali_grup_1", 31, [(0, 0, 0.9, LEAF_A[0], LEAF_A[1], None), (1.1, 0.5, 0.6, LEAF_C[0], LEAF_C[1], None)], grass=2)
bush_group("cali_grup_2", 32, [(0, 0, 0.8, LEAF_B[0], LEAF_B[1], None), (-0.9, 0.6, 0.65, (0.24, 0.46, 0.2), (0.38, 0.6, 0.27), (0.98, 0.5, 0.72)),
                               (0.8, 0.7, 0.5, LEAF_C[0], LEAF_C[1], None)], grass=2)
bush_group("cali_grup_3", 33, [(0, 0, 1.0, LEAF_A[0], LEAF_A[1], (1.0, 0.86, 0.3)), (1.2, -0.3, 0.7, LEAF_B[0], LEAF_B[1], None)], grass=3)
grass_tuft("ot_1", 41, n=16, h=0.5)
grass_tuft("ot_2", 42, n=22, h=0.75)
rocks("kaya_1", 51, R=0.9, n=3)
rocks("kaya_2", 52, R=1.6, n=2)
rocks("kaya_3", 53, R=0.5, n=4)

for name, tris in STATS:
    print("PEYZAJ %-16s %5d yüz" % (name, tris))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
kw = dict(filepath=OUT, export_format='GLB', export_yup=True, export_apply=True)
try:
    bpy.ops.export_scene.gltf(**kw, export_vertex_color='ACTIVE')
except TypeError:
    bpy.ops.export_scene.gltf(**kw)
print("GLB", OUT)
