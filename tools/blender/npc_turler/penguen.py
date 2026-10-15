"""Penguen: kısa, armut gövdeli (dar omuz, geniş alçak göbek ve kalça), kısa bacaklı. Kollar
yassı yüzgeç, eller yüzgeç ucu (dışı siyah, altı beyaz). Neredeyse boyunsuz: kafa gövdeye
oturur, boyun önü beyaz. Siyah kafa, beyaz yüz maskesi, beyaz göz halkası, iki parçalı
turuncu gaga, enseden kısa tüy tutamı, küçük sert kuyruk.

Hareket karakteri: paytak yürüyüş: kısa hızlı adımlar, her adımda gövde iki yana yatar,
yüzgeçler yanlara açık ve adımla çırpar, kafa yatışı dengeler. Beklerken yüzgeçlerini
çırpar, kafasını meraklı meraklı yana eğer; bakınırken kesik kesik döner.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.12, 0.13, 0.16),     # siyah tüy
    "ten2": (0.95, 0.94, 0.9),     # beyaz
    "ten3": (0.98, 0.78, 0.2),     # sarımsı boyun lekesi
    "iris": (0.25, 0.12, 0.1),
    "gaga": (0.95, 0.55, 0.12),
}


def body():
    return O.Body(
        hip_z=0.66, shoulder_z=1.1, shoulder_w=0.165,
        chest=(0.17, 0.13), waist=(0.2, 0.15), belly=(0.225, 0.175), belly_cy=-0.03, hip=(0.225, 0.165), butt=0.01,
        neck_r=0.105, trap=0.95,
        arm=(0.2, 0.2, 0.12), arm_r=(0.06, 0.066, 0.062, 0.06, 0.048), arm_flat=0.42,
        leg_r=(0.1, 0.075, 0.075, 0.055), foot_x=0.115, foot_len=0.95, foot_w=1.1,
        neck_pts=[(0, 0.01, 1.1), (0, 0.0, 1.2)],
        head_c=(0, -0.005, 1.3), head_r=(0.125, 0.135, 0.13), head_top=1.44, hat_tilt=-6.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.005, 1.3)), Vector((0, -1, -0.05)), Vector((0, 0, 1)))


HEAD = [
    (-0.135, 0.0, 0.02, 0.02, 0.02, 2.0),
    (-0.115, 0.0, 0.08, 0.09, 0.085, 2.0),
    (-0.06, 0.005, 0.118, 0.125, 0.125, 2.1),
    (0.0, 0.005, 0.125, 0.13, 0.13, 2.1),
    (0.06, 0.0, 0.11, 0.115, 0.12, 2.1),
    (0.1, -0.01, 0.075, 0.08, 0.09, 2.0),
    (0.125, -0.02, 0.03, 0.035, 0.04, 2.0),
    (0.13, -0.02, 0.005, 0.005, 0.005, 2.0),
]


def chains(B):
    hz = B.hip_z
    return [("tail", [Vector((0, B.hip[1] + 0.0, hz + 0.0)), Vector((0, B.hip[1] + 0.06, hz - 0.06)),
                      Vector((0, B.hip[1] + 0.1, hz - 0.11))], "hips")]


def body_paint(B):
    def f(c, n, src):
        if src != "ten":
            return None
        if c.z > B.hip_z - 0.05 and abs(c.x) < B.chest[0] + 0.05:
            # Gövde: önü beyaz
            if n.y < -0.35 and c.y < 0:
                return "ten2"
            return None
        # Kollar (yüzgeç): iç / alt yüz beyaz
        side = 1 if c.x > 0 else -1
        return "ten2" if n.x * side < -0.35 else None
    return f


def build(B, parts):
    O.build_body_skin(B, parts, paint=body_paint(B))
    build_head(B, parts)
    build_flippers(B, parts)
    build_tail(B, parts)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    # Boyun: kafayla gövde arası kesintisiz (penguende boyun görünmez, kafa omuza oturur)
    O.neck_skin(m, B, [0.11, 0.115], grp="chest|neck", flare=1.35, sub=3, segs=18, into=F.p(0, -0.03, -0.02))
    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, HEAD, segs=18, sub=3)
    # Yanaklar biraz dolgun
    for side in (-1, 1):
        O.ellipsoid(m.bm("ten", "head"), F.p(side * 0.065, 0.05, -0.04), (0.06, 0.06, 0.06), 9, 6)

    # Gaga: üst ve alt çene ayrı, hafif aralık; üstte kanca uç
    O.organic(m.bm("gaga", "head"), F.p(0, 0.095, -0.012), F.d(0, 1, -0.12), F.u,
              [(-0.02, 0.0, 0.03, 0.022, 0.012, 2.0), (0.01, 0.002, 0.03, 0.024, 0.012, 2.2), (0.06, -0.004, 0.018, 0.016, 0.01, 2.2),
               (0.1, -0.012, 0.008, 0.01, 0.007, 2.0), (0.112, -0.02, 0.002, 0.003, 0.003, 2.0)], segs=10, sub=2)
    O.organic(m.bm("gaga", "head"), F.p(0, 0.095, -0.034), F.d(0, 1, -0.2), F.u,
              [(-0.015, 0.0, 0.024, 0.008, 0.012, 2.0), (0.02, 0.0, 0.022, 0.008, 0.012, 2.1), (0.07, 0.002, 0.01, 0.005, 0.006, 2.0),
               (0.085, 0.002, 0.002, 0.002, 0.002, 2.0)], segs=8, sub=2)
    # Burun deliği çizgisi
    for side in (-1, 1):
        O.patch(m.bm("goz", "head"), F.p(side * 0.016, 0.135, 0.004), F.d(side * 0.6, 0.6, 0.5), 0.012, 0.004, depth=0.004, rot=0.3 * side)

    # Gözler: küçük, koyu, beyaz halkalı
    for side in (-1, 1):
        n = F.d(side * 0.8, 0.55, 0.12)
        c = F.p(side * 0.088, 0.065, 0.032)
        O.eye(m, c, n, 0.015, up_hint=F.u, grp="head", iris_k=0.85, pupil="full", lid=0.16, lid_mat="ten")
        O.eye_ring(m, "ten2", c + n * 0.006, n, 0.019, 0.0035, up_hint=F.u)

    # Ense tüy tutamı
    O.tufts(m.bm("ten", "head"), F.p(0, -0.11, 0.06), F.d(0, -1, 0.5), 5, 0.035, 0.012, area=1.3)

    fo, ff, fu = F.o, F.f, F.u

    def paint(c, nrm, src):
        if src != "ten":
            return None
        q = c - fo
        d, h = q.dot(ff), q.dot(fu)
        # Yüz maskesi: önde, gözlerin altında beyaz; boğazdan göğse iner
        # Yüz maskesi: göz hizasının altında, önde; yanaklar ve gıdı beyaz, gözler siyahta kalır
        if h < -0.018 and nrm.dot(ff) > 0.25 and d > -0.01:
            return "ten2"
        if c.z < fo.z - 0.09 and nrm.y < -0.25:
            return "ten3" if c.z > fo.z - 0.13 and abs(c.x) > 0.03 else "ten2"
        return None

    m.build("tur_bas", parts, paint)


def build_flippers(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        s, e, w, h, d = B.arm_points(side)
        a = Vector((0, -1, 0))
        n = (d.cross(a) * side).normalized()
        g = "hand." + ("L" if side > 0 else "R")
        # Yüzgeç ucu: geniş yassı kürek, yuvarlak uç; ön kenar kalın
        rings = []
        for t, wid, th in ((-0.02, 0.05, 0.022), (0.03, 0.058, 0.02), (0.07, 0.055, 0.016), (0.1, 0.04, 0.012),
                           (0.125, 0.018, 0.008), (0.135, 0.004, 0.004)):
            rings.append((w + d * t + a * 0.006, d, th, wid, n))
        O.loft(m.bm("ten", g), rings, 10, sub=2, sq=2.4)
    paint = body_paint(B)
    m.build("tur_eller", parts, paint)


def build_tail(B, parts):
    m = O.Mesh()
    hz = B.hip_z
    base = Vector((0, B.hip[1] - 0.01, hz + 0.0))
    for k in (-1, 0, 1):
        tip = base + Vector((k * 0.03, 0.12, -0.09))
        O.path_loft(m.bm("ten", "tail"), [base + Vector((k * 0.01, 0, 0)), base.lerp(tip, 0.5), tip], [0.022, 0.018, 0.004], 5,
                    flatten=0.35, u=Vector((1, 0, 0)))
    m.build("tur_kuyruk", parts)


STYLE = {
    "frames": 18, "amp": 0.13, "duty": 0.6, "lift": 0.035, "bob": 0.008, "sway": 0.04, "roll": 10.0,
    "twist": 2.0, "lean": 0.0, "arm_swing": 0.02, "arm_out": 0.08, "arm_lift": 0.03, "head_stab": 0.4, "toe_out": 22.0,
    "width": 0.13, "stumble_arms": 0.45,
}

PREVIEW = [
    ["ust_kapusonlu", "alt_kargo", "ayk_spor", "sapka_kasket"],
    ["ust_tisort", "alt_kot", "ayk_spor"],
    ["ust_takim", "alt_takim", "ayk_kundura"],
    ["ust_kisa", "alt_kot", "ayk_bot", "sapka_bere"],
]

SPRINGS = [["tail.0", "tail.1", 2.5, 0.4, 0.1]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    def flippers(pose, out_l, out_r=None):
        out_r = out_l if out_r is None else out_r
        A.add_wrot(pose, "hand.L", Y, -out_l)
        A.add_wrot(pose, "hand.R", Y, out_r)

    def tail(pose, swing):
        for i in range(2):
            A.add_wrot(pose, f"tail.{i}", Z, swing)

    def f(pose, kind, ph, fr):
        if kind == "walk":
            # Yatışa karşı kafa dengesi, yüzgeçler adımla çırpar
            A.add_rot(pose, "head", (0, 0, -6 * math.sin(ph)))
            flippers(pose, 14 + 10 * math.sin(ph + 0.6), 14 - 10 * math.sin(ph + 0.6))
            tail(pose, 14 * math.sin(ph - 0.8))
        elif kind == "idle":
            flap = max(0.0, math.sin(ph * 3 - 1.0)) ** 6
            flippers(pose, 6 + 26 * flap)
            A.add_rot(pose, "head", (0, 0, 12 * max(0.0, math.sin(ph - 0.5)) ** 3))
            tail(pose, 6 * math.sin(ph * 2))
        elif kind == "look":
            A.add_rot(pose, "head", (0, 0, 8 * math.sin(ph * 2)))
            flippers(pose, 8)
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.5, 1.0))
            flippers(pose, 30 * k + 10 * math.sin(ph * 14) * (1 - ph))
            tail(pose, 20 * math.sin(ph * 10) * (1 - ph))

    return f
