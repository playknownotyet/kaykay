"""Sinek: ince, hafif kambur; kalın göğüs (toraks), arı beli, ince uzun kollar. Kafayı
neredeyse tamamen kaplayan dev bileşik gözler (petek deseni), aralarında dar alın, kısa
antenler (ucunda kıl), aşağı sarkan hortum ve sünger uç. Kafayla gövdeyi bağlayan ince
sap boyun, kafada ve boyunda sert kıllar. Sırtta, kıyafetin üstünden çıkan iki damarlı
kanat (2'şer kemik). Eller ince, kıllı, uçta çift tırnaklı.

Hareket karakteri: telaşlı, sık ve kısa adımlar, kafa kesik kesik sağa sola döner. Beklerken
meşhur el ovuşturma; kanatlar ara ara vızıldar (oyunda WingBuzz). Çarpılınca kanatlar açılır.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.2, 0.21, 0.24),      # koyu gri-siyah gövde
    "ten2": (0.42, 0.44, 0.48),    # açık gri çizgiler
    "ten3": (0.1, 0.1, 0.11),      # kıllar
    "iris": (0.62, 0.12, 0.1),     # bileşik göz (koyu kırmızı)
    "tirnak": (0.08, 0.08, 0.09),
}


def body():
    return O.Body(
        hip_z=0.84, shoulder_z=1.27, shoulder_w=0.155,
        chest=(0.155, 0.115), chest_cy=0.0, waist=(0.105, 0.075), belly=(0.12, 0.088), hip=(0.135, 0.095),
        neck_r=0.03, trap=0.6,
        arm=(0.27, 0.26, 0.1), arm_r=(0.032, 0.03, 0.021, 0.025, 0.018),
        leg_r=(0.06, 0.04, 0.042, 0.026), foot_x=0.09, foot_len=0.95, foot_w=0.85,
        neck_pts=[(0, 0.0, 1.27), (0, -0.02, 1.34)],
        head_c=(0, -0.045, 1.42), head_r=(0.13, 0.1, 0.09), head_top=1.52, hats=False, spine_lean=7.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.045, 1.42)), Vector((0, -1, -0.1)), Vector((0, 0, 1)))


def eye_centers(F):
    return [(side, F.p(side * 0.058, 0.012, 0.012)) for side in (1, -1)]


EYE_R = (0.068, 0.072, 0.078)


def wing_frame(B, side):
    base = Vector((side * 0.05, B.chest[1] + 0.05, B.shoulder_z - 0.06))
    d = Vector((side * 0.55, 1.0, -0.3)).normalized()      # dışa, geriye, hafif aşağı
    n = Vector((side * 0.9, -0.35, 0.45))                  # kanat yüzeyinin normali (yana-yukarı)
    n = (n - d * n.dot(d)).normalized()
    return base, d, n


def chains(B):
    out = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, d, n = wing_frame(B, side)
        out.append((f"wing.{sfx}", [base, base + d * 0.17, base + d * 0.36], "chest"))
    F = head_frame()
    out.append(("prob", [F.p(0, 0.035, -0.05), F.p(0, 0.06, -0.1), F.p(0, 0.075, -0.14)], "head"))
    return out


def build(B, parts):
    hairy = O.noise_paint("ten", "ten2", 0.08, seed=3)
    O.build_body_skin(B, parts, paint=hairy, arm_extra=lambda m, side: arm_hairs(m, B, side))
    build_head(B, parts)
    build_hands(B, parts)
    build_wings(B, parts)


def arm_hairs(m, B, side):
    s, e, w, h, d = B.arm_points(side)
    for k in range(6):
        p = e.lerp(w, k / 6)
        out = Vector((side, 0.2 * (k % 2 * 2 - 1), 0)).normalized()
        O.cone(m.bm("ten3", O.arm_tag(side)), p + out * 0.018, p + out * 0.04 + d * 0.012, 0.004, sides=3)


class FacetPaint:
    """Bileşik göz: petek hücreleri (ince koyu sınırlar), gövdede seyrek açık tüy."""

    def __init__(self):
        self.vor = None

    def prepare(self, faces):
        pts = [c for c, mat in faces if mat == "iris"]
        if pts:
            self.vor = O.Voronoi.on_surface(pts, 0.017, seed=4)

    def __call__(self, c, n, src):
        if src == "iris" and self.vor:
            return "goz" if self.vor.edge(c) < 0.0019 else None
        if src == "ten":
            return "ten2" if O.hash01(c, 5) < 0.07 else None
        return None


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    # İnce sap boyun + kafaya oturan küçük boyun halkası
    O.neck_skin(m, B, [0.034, 0.03], grp="chest|neck", flare=3.0, sub=3, segs=12, into=F.p(0, -0.02, -0.02))
    # Kafa: gözlerin arasında kalan küçük, yassı kafa kapsülü
    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u,
              [(-0.07, 0.0, 0.012, 0.012, 0.012, 2.0), (-0.055, 0.0, 0.05, 0.06, 0.05, 2.0), (0.0, 0.004, 0.065, 0.075, 0.07, 2.2),
               (0.05, -0.004, 0.05, 0.06, 0.07, 2.2), (0.075, -0.012, 0.03, 0.035, 0.05, 2.0), (0.082, -0.015, 0.006, 0.006, 0.006, 2.0)],
              segs=16, sub=3)
    # Dev bileşik gözler: kafanın yanlarını ve üstünü kaplar
    for side, c in eye_centers(F):
        O.ellipsoid(m.bm("iris", "head"), c, EYE_R, 40, 28, rot=O.axis_rot(F.d(side, 0.25, 0.1), F.u))
    # Alın şeridi (gözler arası) ve antenler: kısa, iki boğumlu, uçta kıl (arista)
    O.ellipsoid(m.bm("ten2", "head"), F.p(0, 0.055, 0.03), (0.014, 0.022, 0.04), 8, 6, rot=F.mat())
    for side in (-1, 1):
        b = F.p(side * 0.008, 0.072, 0.03)
        k = b + F.d(side * 0.3, 0.6, -0.4) * 0.018
        t = k + F.d(side * 0.2, 0.4, -0.8) * 0.022
        O.path_loft(m.bm("ten", "head"), [b, k, t], [0.006, 0.0055, 0.008], 5)
        O.cone(m.bm("ten3", "head"), t, t + F.d(side * 0.6, 0.6, 0.3) * 0.03, 0.002, sides=3)
    # Kafa ve boyun kılları: sert, seyrek
    for i in range(10):
        a = math.tau * i / 10
        p = F.p(math.cos(a) * 0.03, -0.04 + math.sin(a) * 0.015, 0.06)
        O.cone(m.bm("ten3", "head"), p, p + F.d(math.cos(a) * 0.5, -0.5, 1.0) * 0.03, 0.0025, sides=3)
    for i in range(8):
        a = math.tau * i / 8
        p = Vector((math.sin(a) * 0.032, -0.01 - math.cos(a) * 0.032, 1.31))
        O.cone(m.bm("ten3", "neck"), p, p + Vector((math.sin(a), -math.cos(a), 0.3)) * 0.028, 0.0025, sides=3)
    # Hortum: aşağı sarkan, ucunda sünger yastık (labellum)
    pp = [F.p(0, 0.035, -0.045), F.p(0, 0.055, -0.09), F.p(0, 0.07, -0.13)]
    O.path_loft(m.bm("ten", "prob"), pp, [0.016, 0.012, 0.01], 7, sub=2)
    O.ellipsoid(m.bm("ten2", "prob"), F.p(0, 0.075, -0.142), (0.022, 0.018, 0.012), 8, 5, rot=F.mat())
    m.build("tur_bas", parts, FacetPaint())


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, mat="ten", fingers=3, finger_lens=[0.06, 0.065, 0.055], finger_r=0.006, palm_w=0.026, palm_t=0.014,
               palm_len=0.045, thumb=True, curl=20, spread=1.2, claw_mat="tirnak")
        # Bilekte kıllar
        s, e, w, h, d = B.arm_points(side)
        for k in range(5):
            a = math.tau * k / 5
            o = Vector((math.cos(a), math.sin(a), 0)) * 0.02
            O.cone(m.bm("ten3", "hand." + ("L" if side > 0 else "R")), w + o, w + o * 2.2 - d * 0.01, 0.003, sides=3)
    m.build("tur_eller", parts)


def build_wings(B, parts):
    m = O.Mesh()
    for side, sfx in ((1, "L"), (-1, "R")):
        base, d, n = wing_frame(B, side)
        w = d.cross(n).normalized()
        rings = []
        # Damla biçimli kanat: kökte dar, ortada geniş, uçta yuvarlak
        for t, wid, off in ((-0.01, 0.012, 0.0), (0.04, 0.05, 0.01), (0.12, 0.085, 0.02), (0.22, 0.09, 0.02),
                            (0.3, 0.07, 0.012), (0.355, 0.035, 0.005), (0.37, 0.006, 0.0)):
            rings.append((base + d * t + w * off, d, 0.0035, wid, n))
        O.loft(m.bm("kanat", f"wing.{sfx}"), rings, 8, sub=2, sq=2.0)
        # Kanat kökü: sırta oturan küçük eklem
        O.ellipsoid(m.bm("ten", f"wing.{sfx}"), base, (0.022, 0.022, 0.02), 7, 5)
        # Damarlar: zarın içinden geçen ince çubuklar (iki yüzden de çıkar, titremez):
        # kökten uca yelpaze damarlar + iki çapraz damar
        g = f"wing.{sfx}"
        for k in (-0.55, -0.15, 0.25, 0.62):
            pts = [base + d * 0.01 + w * 0.012]
            for t in (0.1, 0.2, 0.3):
                pts.append(base + d * t + w * (0.015 + k * 0.075 * min(t / 0.12, 1.0)))
            O.path_loft(m.bm("damar", g), pts, [0.0055, 0.0048, 0.0042, 0.0038], 4, sub=2)
        for t, span in ((0.14, 0.06), (0.26, 0.055)):
            a0 = base + d * t + w * (0.015 - span)
            a1 = base + d * t + w * (0.015 + span)
            O.path_loft(m.bm("damar", g), [a0, a1], 0.004, 4)

    m.build("tur_kanat", parts)


STYLE = {
    "frames": 16, "amp": 0.15, "duty": 0.58, "lift": 0.06, "bob": 0.01, "sway": 0.006, "roll": 2.0,
    "twist": 4.0, "lean": 6.0, "arm_swing": 0.04, "arm_fwd": -0.06, "arm_lift": 0.05, "head_stab": 0.6, "toe_out": 10.0,
}

PREVIEW = [
    ["ust_tisort", "alt_kot", "ayk_spor"],
    ["ust_takim", "alt_takim", "ayk_kundura", "aks_evrak"],
    ["ust_kapusonlu", "alt_kargo", "ayk_spor"],
    ["ust_isci", "alt_kargo", "ayk_bot"],
]

SPRINGS = [["prob.0", "prob.1", 3.0, 0.4, 0.3]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    B = A.B

    def wings(pose, open_, flap=0.0):
        # open_: kanatları gövdeden yana açma (+), flap: yukarı-aşağı
        for side, sfx in ((1, "L"), (-1, "R")):
            A.add_wrot(pose, f"wing.{sfx}.0", Z, side * open_)
            A.add_wrot(pose, f"wing.{sfx}.0", Y, -side * flap)

    def head_dart(pose, yaw, pitch=0.0):
        A.add_rot(pose, "head", (pitch, yaw, 0))

    def rub(pose, k, ph):
        # Eller göğsün önünde birleşip birbirine sürtünür
        sz = B.shoulder_z
        for sfx, side in (("L", 1), ("R", -1)):
            x0, y0, z0 = A.hand_rest(side)
            tx, ty, tz = (side * 0.035, -0.2, sz - 0.27)
            r = 0.022 * math.sin(ph * 6 + (0 if side > 0 else math.pi))
            target = (tx, ty + r, tz + r * 0.5)
            pose[f"hand.{sfx}"] = tuple(a + (b - a) * k for a, b in zip((x0, y0, z0), target))
            if k > 0.3:
                pose[f"elbow.{sfx}"] = (side * 0.32, 0.25, sz - 0.3)
                pose[f"hand_rot.{sfx}"] = (-60, 0, -side * 40)

    def f(pose, kind, ph, fr):
        if kind == "walk":
            darts = [0, 18, 18, -14, -14, 6, 0, 0]
            head_dart(pose, darts[int(ph / math.tau * 8) % 8])
            wings(pose, 3 * math.sin(2 * ph))
        elif kind == "idle":
            # Döngünün büyük kısmında el ovuşturma, arada kafa çevirme
            k = min(1.0, max(0.0, math.sin(ph - 0.3) * 1.6))
            rub(pose, k, ph)
            darts = [0, 0, 20, 20, -16, 0, 0, 0, 10, 0, 0, 0]
            head_dart(pose, darts[int(ph / math.tau * 12) % 12], 6 * k)
            wings(pose, 2)
        elif kind == "look":
            darts = [0, 35, 35, -30, -30, 0]
            head_dart(pose, darts[min(int(ph / math.tau * 6), 5)])
            wings(pose, 4)
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.6, 1.0))
            wings(pose, 35 * k, 20 * k)
            head_dart(pose, 15 * math.sin(ph * 12) * (1 - ph))

    return f
