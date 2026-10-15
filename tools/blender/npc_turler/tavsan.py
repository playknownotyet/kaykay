"""Tavşan: küçük, narin; dar omuz, hafif armut (kalça geniş), büyük ayaklar. Kısa kabarık
boyun (açık renk yaka tutamları). Yuvarlak kafa, tombul yanaklar, küçük pembe Y burun,
öne çıkık iki ön diş, bıyıklar, iri parlak gözler. Uzun dik kulaklar (3 kemik; içi pembe):
yürürken ve dönerken gecikmeyle sallanır. Ponpon kuyruk. Eller kabarık küçük pati.

Hareket karakteri: yaylanarak, sekerek yürür (her adımda hafif zıplama), kısa hızlı adımlar;
kulaklar her sekişte gecikmeli eğilip doğrulur, birbirinden bağımsız. Beklerken burnunu
oynatır (kafa titreşimi), kulaklarını tek tek çevirir; bakınırken kulaklar dikilir.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.8, 0.78, 0.76),      # açık gri-bej
    "ten2": (0.97, 0.96, 0.94),    # beyaz
    "ten3": (0.62, 0.56, 0.52),    # kulak arkası / uç koyu
    "iris": (0.3, 0.18, 0.12),
    "tirnak": (0.9, 0.88, 0.84),
}


def body():
    return O.Body(
        hip_z=0.8, shoulder_z=1.2, shoulder_w=0.15,
        chest=(0.14, 0.1), waist=(0.13, 0.09), belly=(0.145, 0.1), hip=(0.16, 0.11), butt=0.012,
        neck_r=0.058, trap=0.8,
        arm=(0.24, 0.22, 0.09), arm_r=(0.04, 0.038, 0.03, 0.034, 0.026),
        leg_r=(0.08, 0.055, 0.058, 0.035), foot_x=0.095, foot_len=1.22, foot_w=0.95,
        neck_pts=[(0, 0.01, 1.2), (0, 0.0, 1.29)],
        head_c=(0, -0.01, 1.38), head_r=(0.1, 0.105, 0.1), head_top=1.49, hats=True, hat_tilt=-5.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.01, 1.38)), Vector((0, -1, -0.1)), Vector((0, 0, 1)))


HEAD = [
    (-0.1, 0.0, 0.015, 0.015, 0.015, 2.0),
    (-0.085, 0.005, 0.07, 0.072, 0.065, 2.0),
    (-0.04, 0.008, 0.095, 0.095, 0.085, 2.0),
    (0.01, 0.004, 0.098, 0.088, 0.088, 2.05),
    (0.055, -0.01, 0.08, 0.066, 0.078, 2.1),       # tombul yanaklar
    (0.088, -0.022, 0.05, 0.042, 0.05, 2.0),
    (0.102, -0.026, 0.012, 0.012, 0.012, 2.0),
]


def ear_frame(F, side):
    base = F.p(side * 0.035, -0.035, 0.08)
    up = F.d(side * 0.18, -0.15, 1.0)
    n = F.d(side * 0.2, 1.0, 0.1)
    n = (n - up * n.dot(up)).normalized()
    return base, up, n


EAR_LEN = 0.28


def chains(B):
    F = head_frame()
    out = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, up, n = ear_frame(F, side)
        out.append((f"ear.{sfx}", [base + up * (EAR_LEN * k / 3) for k in range(4)], "head"))
    hz = B.hip_z
    out.append(("tail", [Vector((0, B.hip[1] + 0.01, hz + 0.02)), Vector((0, B.hip[1] + 0.07, hz + 0.04))], "hips"))
    return out


def build(B, parts):
    O.build_body_skin(B, parts, paint=O.noise_paint("ten", "ten2", 0.06, seed=1))
    build_head(B, parts)
    build_hands(B, parts)
    build_tail(B, parts)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    O.neck_skin(m, B, [0.07, 0.068], grp="chest|neck", flare=1.7, sub=3, segs=16, into=F.p(0, -0.03, -0.02))
    # Kabarık boyun yakası (önde beyaz)
    nz = B.neck_pts[1].z - 0.02
    for i in range(12):
        a = math.tau * i / 12
        p = Vector((math.sin(a) * 0.068, -math.cos(a) * 0.068, nz))
        mat = "ten2" if math.cos(a) > 0.0 else "ten"
        O.tufts(m.bm(mat, "neck"), p, Vector((math.sin(a), -math.cos(a), -0.7)), 2, 0.03, 0.014, area=0.4)

    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, HEAD, segs=18, sub=3)
    # Ağız: iki tombul bıyık yastığı, ortada Y burun, altında dişler
    for side in (-1, 1):
        O.ellipsoid(m.bm("ten2", "head"), F.p(side * 0.022, 0.09, -0.036), (0.026, 0.024, 0.022), 8, 6, rot=F.mat())
        O.whiskers(m, F, side, 0.03, 0.098, -0.03, n=3, length=0.1, mat="ten3", thick=0.0016)
    O.ellipsoid(m.bm("pembe", "head"), F.p(0, 0.104, -0.014), (0.013, 0.008, 0.01), 8, 5, rot=F.mat())
    for side in (-1, 1):
        O.box(m.bm("beyaz", "head"), F.p(side * 0.0065, 0.1, -0.068), (0.012, 0.006, 0.02), rot=F.mat())
    O.ellipsoid(m.bm("ten2", "head"), F.p(0, 0.078, -0.066), (0.02, 0.02, 0.014), 8, 5, rot=F.mat())
    # Gözler: iri, yanlarda, parlak (kapaksız masum bakış)
    for side in (-1, 1):
        n = F.d(side * 0.75, 0.62, 0.1)
        O.eye(m, F.p(side * 0.07, 0.045, 0.025), n, 0.023, up_hint=F.u, grp="head", iris_k=0.9, pupil="full", lid=0.1)
    # Kulaklar: uzun, dibi dar, ortası geniş, uca doğru incelir; hafif çanak
    ears = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, up, n = ear_frame(F, side)
        ears.append((base, up, n))
        rings = []
        for t, wid, th in ((-0.01, 0.02, 0.02), (0.03, 0.03, 0.016), (0.09, 0.042, 0.014), (0.16, 0.044, 0.013),
                           (0.22, 0.036, 0.012), (0.26, 0.022, 0.01), (0.282, 0.004, 0.005)):
            rings.append((base + up * t, up, th, wid, n))
        O.loft(m.bm("ten", f"ear.{sfx}"), rings, 10, sub=2, sq=2.2)

    def paint(c, nrm, src):
        if src != "ten":
            return None
        for base, up, n in ears:
            q = c - base
            t = q.dot(up)
            if -0.01 < t < 0.3 and abs(q.dot(n)) < 0.03 and abs(q.dot(up.cross(n))) < 0.05:
                if nrm.dot(n) > 0.4 and 0.02 < t < 0.25 and abs(q.dot(up.cross(n))) < 0.028:
                    return "pembe"
                if t > 0.24:
                    return "ten3"                       # kulak ucu koyu
                return None
        if c.z < F.o.z - 0.05 and nrm.y < -0.3:
            return "ten2"
        return None

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, fingers=4, finger_len=0.03, finger_r=0.011, palm_w=0.034, palm_t=0.022, palm_len=0.05,
               curl=30, tip_ball=1.3, spread=0.8, thumb=False)
    m.build("tur_eller", parts)


def build_tail(B, parts):
    m = O.Mesh()
    hz = B.hip_z
    O.ellipsoid(m.bm("ten2", "tail"), Vector((0, B.hip[1] + 0.06, hz + 0.04)), (0.05, 0.045, 0.048), 9, 7)
    O.tufts(m.bm("ten2", "tail"), Vector((0, B.hip[1] + 0.08, hz + 0.04)), Vector((0, 1, 0.2)), 6, 0.03, 0.014, area=1.5)
    m.build("tur_kuyruk", parts)


STYLE = {
    "frames": 18, "amp": 0.17, "duty": 0.55, "lift": 0.07, "bob": 0.006, "sway": 0.006, "roll": 2.0,
    "twist": 3.0, "lean": 4.0, "arm_swing": 0.06, "arm_fwd": -0.02, "head_stab": 0.6, "toe_out": 8.0, "bounce": 0.035,
}

PREVIEW = [
    ["ust_kisa", "alt_kot", "ayk_spor", "aks_omuz"],
    ["ust_tisort", "alt_kargo", "ayk_spor"],
    ["ust_kapusonlu", "alt_kot", "ayk_bot"],
    ["ust_takim", "alt_takim", "ayk_kundura", "sapka_bere"],
]

SPRINGS = [["ear.L.0", "ear.L.2", 1.4, 0.3, 0.15], ["ear.R.0", "ear.R.2", 1.4, 0.3, 0.15]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    def ear(pose, sfx, side, bend, turn, splay=0.0):
        # bend: öne(+)/arkaya(-) eğilme (zincir boyunca artar), turn: kulağın kendi ekseninde dönmesi
        for i in range(3):
            k = 0.5 + 0.4 * i
            A.add_wrot(pose, f"ear.{sfx}.{i}", X, -bend * k)
            A.add_wrot(pose, f"ear.{sfx}.{i}", Y, -side * splay * k)
        A.add_wrot(pose, f"ear.{sfx}.0", Z, -side * turn)

    def f(pose, kind, ph, fr):
        if kind == "walk":
            # Her sekişte kulaklar gecikmeyle geri savrulup doğrulur; sağ-sol hafif farklı
            for side, sfx, off in ((1, "L", 0.0), (-1, "R", 0.5)):
                ear(pose, sfx, side, -14 * math.sin(2 * ph - 1.6 - off), 5 * math.sin(ph + off), 5 + 5 * math.sin(2 * ph - 2.0 + off))
            A.add_wrot(pose, "tail.0", X, 10 * math.sin(2 * ph))
        elif kind == "idle":
            # Burun / kafa titreşimi ve tek tek kulak çevirme
            sniff = math.sin(ph * 16) * max(0.0, math.sin(ph * 2))
            A.add_rot(pose, "head", (1.5 * sniff, 0, 0))
            turn_l = 35 * max(0.0, math.sin(ph - 0.8)) ** 4
            turn_r = 35 * max(0.0, math.sin(ph - 3.6)) ** 4
            flop = 25 * max(0.0, math.sin(ph * 0.5 - 0.2)) ** 6
            ear(pose, "L", 1, 2 * math.sin(ph * 2), turn_l, 3)
            ear(pose, "R", -1, -flop + 2 * math.sin(ph * 2 + 1), turn_r, 3 + flop * 0.6)
        elif kind == "look":
            k = math.sin(ph / 2) ** 2
            ear(pose, "L", 1, 6 * k, 25 * math.sin(ph), -2)
            ear(pose, "R", -1, 6 * k, -25 * math.sin(ph), -2)
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.6, 1.0))
            w = math.sin(ph * 14) * (1 - ph)
            ear(pose, "L", 1, -30 * k + 18 * w, 0, 18 * k)
            ear(pose, "R", -1, -30 * k - 18 * w, 0, 18 * k)

    return f
