"""Fil: iri, göbekli, kalın kollu ve bacaklı; hafif kambur duruş. Çift kubbeli alın, beş
kemikli kırışık hortum, iki kemikli yelpaze kulaklar (iç yüz pembe), fildişleri, kırışık
kalın boyun, küçük kirpikli gözler, kalın tırnaklı tıknaz eller, püsküllü ince kuyruk.

Hareket karakteri: ağır, geniş basan, iki yana yalpalayan yürüyüş; hortum sarkaç gibi
gecikmeyle salınır, kulaklar her adımda yelpazelenir. Beklerken kulaklarıyla serinler,
hortumunu kıvırıp koklar; çarpılınca kulaklar açılır, hortum havaya savrulur.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.56, 0.56, 0.6),     # gri deri
    "ten2": (0.46, 0.46, 0.5),    # kırışık / gölge tonu
    "ten3": (0.68, 0.56, 0.57),     # kulak içi, ağız
    "iris": (0.42, 0.28, 0.14),
    "tirnak": (0.86, 0.82, 0.72),
}


def body():
    return O.Body(
        hip_z=0.9, shoulder_z=1.42, shoulder_w=0.25,
        chest=(0.25, 0.17), chest_cy=-0.01, waist=(0.26, 0.2), belly=(0.285, 0.215), belly_cy=-0.055,
        hip=(0.25, 0.165), butt=0.01, neck_r=0.12, trap=0.8,
        arm=(0.3, 0.27, 0.11), arm_r=(0.076, 0.074, 0.062, 0.068, 0.056),
        leg_r=(0.125, 0.1, 0.1, 0.08), foot_x=0.13, foot_len=1.1, foot_w=1.3, hand_scale=1.1,
        neck_pts=[(0, 0.02, 1.42), (0, 0.0, 1.52)],
        head_c=(0, -0.03, 1.63), head_r=(0.165, 0.185, 0.15), head_top=1.8, hat_tilt=-4.0, spine_lean=4.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.03, 1.63)), Vector((0, -1, -0.12)), Vector((0, 0, 1)))


SKULL = [
    (-0.175, 0.0, 0.02, 0.02, 0.02, 2.0),
    (-0.155, 0.005, 0.09, 0.105, 0.08, 2.0),
    (-0.10, 0.01, 0.14, 0.15, 0.12, 2.1),
    (-0.03, 0.01, 0.155, 0.16, 0.135, 2.2),
    (0.04, 0.0, 0.15, 0.155, 0.13, 2.3),
    (0.10, -0.012, 0.13, 0.135, 0.12, 2.4),     # yüz düzlemi
    (0.14, -0.03, 0.1, 0.105, 0.1, 2.3),
    (0.162, -0.045, 0.06, 0.07, 0.07, 2.0),
    (0.168, -0.045, 0.01, 0.012, 0.012, 2.0),
]


def trunk_points():
    # Dünya koordinatı: yüzün altından göğsün önüne sarkar, ucu hafifçe öne kıvrık
    return [Vector((0, -0.17, 1.58)), Vector((0, -0.25, 1.5)), Vector((0, -0.31, 1.4)),
            Vector((0, -0.345, 1.29)), Vector((0, -0.365, 1.19)), Vector((0, -0.395, 1.13))]


TRUNK_R = [0.072, 0.06, 0.05, 0.042, 0.036, 0.032]


def ear_frame(F, side):
    root = F.p(side * 0.125, -0.045, 0.01)
    e = F.d(side * 1.0, -0.42, -0.12)          # dışa ve geriye
    n = F.d(side * 0.35, 1.0, 0.0)             # iç yüz öne bakar
    n = (n - e * n.dot(e)).normalized()
    w = e.cross(n).normalized()
    if w.z < 0:
        w = -w
    return root, e, n, w


def chains(B):
    F = head_frame()
    out = []
    for side, sfx in ((1, "L"), (-1, "R")):
        root, e, n, w = ear_frame(F, side)
        out.append((f"ear.{sfx}", [root, root + e * 0.11, root + e * 0.24], "head"))
    out.append(("trunk", trunk_points(), "head"))
    hz = B.hip_z
    out.append(("tail", [Vector((0, B.hip[1] + 0.02, hz + 0.02)), Vector((0, B.hip[1] + 0.06, hz - 0.1)),
                         Vector((0, B.hip[1] + 0.07, hz - 0.24)), Vector((0, B.hip[1] + 0.065, hz - 0.36))], "hips"))
    return out


def skin_paint(B):
    return O.noise_paint("ten", "ten2", 0.16, seed=4)


def build(B, parts):
    O.build_body_skin(B, parts, paint=skin_paint(B))
    build_head(B, parts)
    build_hands(B, parts)
    build_tail(B, parts)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()

    # Kalın, kırışık boyun: kafanın içine kadar
    O.neck_skin(m, B, [0.13, 0.125], grp="chest|neck", flare=1.5, sub=3, segs=18, into=F.p(0, -0.05, -0.02))

    # Kafatası + çift kubbeli alın + şakak çukurları
    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, SKULL, segs=20, sub=3)
    for side in (-1, 1):
        O.ellipsoid(m.bm("ten", "head"), F.p(side * 0.05, 0.1, 0.045), (0.062, 0.05, 0.06), 10, 7, rot=F.mat())
        # Elmacık kemiği: gözün altında
        O.ellipsoid(m.bm("ten", "head"), F.p(side * 0.105, 0.085, -0.01), (0.04, 0.05, 0.035), 8, 5, rot=F.mat())

    # Hortum: kökten uca incelen, hafif yassı (önden arkaya basık)
    tp = trunk_points()
    O.path_loft(m.bm("ten", "trunk|head"), tp, TRUNK_R, 12, flatten=0.88, sub=3, u=Vector((1, 0, 0)))
    # Burun delikleri: uçta, aşağı-öne bakan
    tip = tp[-1]
    tdir = (tp[-1] - tp[-2]).normalized()
    for side in (-1, 1):
        O.ellipsoid(m.bm("goz", "trunk"), tip + tdir * 0.001 + Vector((side * 0.012, 0, 0)), (0.009, 0.006, 0.009), 6, 4,
                    rot=O.axis_rot(tdir))
    # Ağız: hortum kökünün altında küçük alt dudak
    O.ellipsoid(m.bm("ten3", "head"), F.p(0, 0.115, -0.115), (0.045, 0.035, 0.022), 8, 5, rot=F.mat())

    # Fildişleri: ağzın iki yanından öne-aşağı, sonra yukarı kıvrılır
    for side in (-1, 1):
        b = F.p(side * 0.07, 0.11, -0.085)
        pts = [b - F.f * 0.02, b, b + Vector((side * 0.01, -0.06, -0.07)), b + Vector((side * 0.012, -0.13, -0.09)),
               b + Vector((side * 0.008, -0.18, -0.065))]
        O.path_loft(m.bm("tirnak", "head"), pts, [0.022, 0.02, 0.016, 0.01, 0.003], 7, sub=2)

    # Gözler: küçük, yanlarda, kırışık kapaklı, uzun kirpikli
    for side in (-1, 1):
        n = F.d(side * 0.75, 0.6, 0.1)
        O.eye(m, F.p(side * 0.112, 0.07, 0.035), n, 0.016, up_hint=F.u, grp="head", iris_k=0.72, lid=0.32,
              lid_tilt=-side * 10, lower_lid=0.22, lower_mat="ten2", lashes=3, lash_mat="siyah")

    # Kulaklar: büyük yelpaze; kökten dışa geniş, alt lobu sarkık, kenarı yuvarlak
    ears = []
    for side, sfx in ((1, "L"), (-1, "R")):
        root, e, n, w = ear_frame(F, side)
        ears.append((root, e, n, w))
        rings = []
        for t, top, bot, th in ((-0.01, 0.07, 0.07, 0.025), (0.03, 0.12, 0.13, 0.02), (0.08, 0.15, 0.18, 0.016),
                                (0.14, 0.15, 0.2, 0.014), (0.19, 0.12, 0.18, 0.013), (0.225, 0.08, 0.12, 0.012),
                                (0.245, 0.03, 0.05, 0.01), (0.25, 0.005, 0.01, 0.008)):
            c = root + e * t + w * ((top - bot) * 0.5)
            rings.append((c, e, th, (top + bot) * 0.5, n))
        O.loft(m.bm("ten", f"ear.{sfx}"), rings, 12, sub=2, sq=2.6)
        # Kulak kökü kafaya oturan kalın kıvrım
        O.ellipsoid(m.bm("ten", "head"), root - e * 0.01, (0.03, 0.05, 0.09), 8, 5, rot=O.axis_rot(w, e))

    trunk_band = O.band_paint(tp, 0.034, 0.3, "ten", "ten2", radius=0.09)
    neck_band = O.band_paint([B.neck_pts[0] + Vector((0, 0, -0.06)), F.p(0, -0.08, -0.06)], 0.045, 0.28, "ten", "ten2", radius=0.2)
    noise = O.noise_paint("ten", "ten2", 0.12, seed=8)

    def paint(c, nrm, src):
        if src != "ten":
            return None
        for root, e, n, w in ears:
            q = c - root
            if q.length < 0.27 and abs(q.dot(n)) < 0.04 and q.dot(e) > 0.01:
                if nrm.dot(n) > 0.4 and 0.04 < q.dot(e) < 0.19 and abs(q.dot(w)) < 0.11:
                    return "ten3"                      # kulak içi (ortası, kenarı gri)
                return "ten2" if O.hash01(c, 3) < 0.1 else None
        r = trunk_band(c, nrm, src)
        if r:
            return r
        if c.z < F.o.z - 0.1 and (c - F.o).dot(F.f) < 0.05:
            r = neck_band(c, nrm, src)
            if r:
                return r
        return noise(c, nrm, src)

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, fingers=4, finger_len=0.052, finger_r=0.019, palm_w=0.058, palm_t=0.034, palm_len=0.07,
               nail_mat="tirnak", curl=14, tip_ball=1.0, spread=0.9)
    m.build("tur_eller", parts, skin_paint(B))


def build_tail(B, parts):
    m = O.Mesh()
    hz = B.hip_z
    pts = [Vector((0, B.hip[1] - 0.02, hz + 0.04)), Vector((0, B.hip[1] + 0.03, hz + 0.0)), Vector((0, B.hip[1] + 0.06, hz - 0.1)),
           Vector((0, B.hip[1] + 0.07, hz - 0.24)), Vector((0, B.hip[1] + 0.065, hz - 0.34))]
    O.path_loft(m.bm("ten", "tail"), pts, [0.03, 0.026, 0.02, 0.014, 0.01], 7, sub=2)
    O.tufts(m.bm("siyah", "tail"), pts[-1], Vector((0, 0.05, -1)), 6, 0.06, 0.007, area=1.4)
    m.build("tur_kuyruk", parts)


STYLE = {
    "frames": 34, "amp": 0.27, "duty": 0.66, "lift": 0.06, "bob": 0.018, "sway": 0.034, "roll": 4.5,
    "twist": 2.0, "lean": 4.0, "arm_swing": 0.08, "arm_out": 0.05, "head_stab": 0.5, "toe_out": 12.0,
}

PREVIEW = [
    ["ust_isci", "alt_kargo", "ayk_bot", "sapka_baret"],
    ["ust_tisort", "alt_kot", "ayk_spor", "sapka_kasket"],
    ["ust_takim", "alt_takim", "ayk_kundura"],
    ["ust_kapusonlu", "alt_kargo", "ayk_spor", "sapka_bere"],
]

SPRINGS = [["trunk.0", "trunk.4", 0.8, 0.3, 0.5], ["ear.L.0", "ear.L.1", 1.2, 0.45, 0.3], ["ear.R.0", "ear.R.1", 1.2, 0.45, 0.3],
           ["tail.0", "tail.2", 0.9, 0.25, 0.6]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    def ears(pose, fan, droop=0.0):
        # fan > 0: kulaklar öne açılır (yelpaze); < 0 geriye yatar
        for side, sfx in ((1, "L"), (-1, "R")):
            A.add_wrot(pose, f"ear.{sfx}.0", Z, -side * fan * 0.6)
            A.add_wrot(pose, f"ear.{sfx}.1", Z, -side * fan * 0.4)
            A.add_wrot(pose, f"ear.{sfx}.1", Y, -side * droop)

    def trunk(pose, swing, lift):
        for i in range(5):
            k = 0.5 + 0.5 * i / 4
            A.add_wrot(pose, f"trunk.{i}", Y, (swing[i] if isinstance(swing, list) else swing) * k)
            A.add_wrot(pose, f"trunk.{i}", X, -(lift[i] if isinstance(lift, list) else lift))

    def tail(pose, swing):
        for i in range(3):
            A.add_wrot(pose, f"tail.{i}", Y, swing * (0.6 + 0.4 * i))

    def f(pose, kind, ph, fr):
        if kind == "walk":
            trunk(pose, [7 * math.sin(ph - 1.0 - i * 0.55) for i in range(5)],
                  [3 * math.sin(2 * ph - 1.2 - i * 0.5) for i in range(5)])
            ears(pose, 6 * math.sin(2 * ph - 0.8), 3 * math.sin(2 * ph))
            tail(pose, 12 * math.sin(ph - 1.5))
        elif kind == "idle":
            # Kulaklarla serinleme (iki vuruş), hortum yavaşça kıvrılıp koklar
            fan = 14 * max(0.0, math.sin(ph * 2)) ** 2
            ears(pose, fan - 3, 2 * math.sin(ph * 2))
            curl = 10 * max(0.0, math.sin(ph - 1.0)) ** 2
            trunk(pose, [4 * math.sin(ph * 1.5 - i * 0.6) for i in range(5)], [curl * (0.2 + 0.25 * i) for i in range(5)])
            tail(pose, 16 * math.sin(ph * 3))
        elif kind == "look":
            sniff = math.sin(ph / 2) ** 2
            trunk(pose, [5 * math.sin(ph * 2 - i * 0.5) for i in range(5)], [sniff * (6 + 9 * i) for i in range(5)])
            ears(pose, 8 * sniff)
            tail(pose, 8 * math.sin(ph * 2))
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.6, 1.0))
            ears(pose, 22 * k)
            trunk(pose, [10 * math.sin(ph * 9 - i * 0.7) * (1 - ph) for i in range(5)],
                  [(14 + 8 * i) * k * (1 - ph * 0.6) for i in range(5)])
            tail(pose, 20 * math.sin(ph * 8) * (1 - ph))

    return f
