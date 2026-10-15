"""Kurbağa: basık, geniş; kısa geniş gövde, uzun ince kollar, geniş basan büyük ayaklar.
Boyun yok denecek kadar kısa ve geniş: kafa doğrudan gövdeye oturur; gerdanda şişen gırtlak
kesesi (kemik ölçeğiyle canlanır). Yassı geniş kafa, kafanın üstünde kabarık göz yuvaları
ve pörtlek altın gözler (yatay gözbebeği), kulaktan kulağa ağız çizgisi, burun delikleri,
sırtta ve kafada koyu benekler, açık renk gerdan ve karın. Uzun ince parmaklar, yuvarlak
yapışkan parmak uçları.

Hareket karakteri: geniş basışlı, dizler dışa, hafif sekerek ağır ağır yürür; kollar
gövdeden açık. Beklerken gırtlak kesesi şişip iner, kafasını yavaşça çevirir.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.42, 0.66, 0.3),      # yeşil
    "ten2": (0.9, 0.88, 0.6),      # gerdan / karın açık sarı
    "ten3": (0.22, 0.4, 0.18),     # benek
    "iris": (0.9, 0.7, 0.15),
    "tirnak": (0.36, 0.56, 0.26),
}


def body():
    return O.Body(
        hip_z=0.78, shoulder_z=1.2, shoulder_w=0.19,
        chest=(0.18, 0.12), waist=(0.17, 0.12), belly=(0.19, 0.14), belly_cy=-0.02, hip=(0.18, 0.12),
        neck_r=0.1, trap=0.9,
        arm=(0.29, 0.27, 0.12), arm_r=(0.038, 0.036, 0.026, 0.031, 0.022),
        leg_r=(0.075, 0.052, 0.055, 0.032), foot_x=0.13, foot_len=1.15, foot_w=1.1,
        neck_pts=[(0, 0.01, 1.2), (0, 0.0, 1.3)],
        head_c=(0, -0.03, 1.38), head_r=(0.12, 0.12, 0.07), head_top=1.47, hats=False,
    )


def head_frame():
    return O.Frame(Vector((0, -0.03, 1.38)), Vector((0, -1, -0.05)), Vector((0, 0, 1)))


HEAD = [
    (-0.1, 0.0, 0.03, 0.015, 0.015, 2.0),
    (-0.085, 0.0, 0.095, 0.05, 0.05, 2.2),
    (-0.04, 0.0, 0.13, 0.068, 0.066, 2.4),
    (0.02, -0.004, 0.13, 0.066, 0.064, 2.5),
    (0.07, -0.01, 0.11, 0.05, 0.05, 2.4),
    (0.105, -0.016, 0.07, 0.035, 0.036, 2.1),
    (0.118, -0.018, 0.02, 0.012, 0.012, 2.0),
]


def chains(B):
    F = head_frame()
    return [("throat", [F.p(0, 0.02, -0.058), F.p(0, 0.075, -0.07)], "head")]


SPOTS = None


def spots(c):
    return O.hash01(Vector((round(c.x / 0.05), round(c.y / 0.05), round(c.z / 0.05))), 7) < 0.28 and O.hash01(c, 2) < 0.8


def body_paint(B):
    def f(c, n, src):
        if src != "ten":
            return None
        if c.z > B.hip_z and abs(c.x) < B.belly[0] and n.y < -0.5:
            return "ten2"
        return "ten3" if spots(c) else None
    return f


def build(B, parts):
    O.build_body_skin(B, parts, paint=body_paint(B))
    build_head(B, parts)
    build_hands(B, parts)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    O.neck_skin(m, B, [0.105, 0.1], grp="chest|neck", flare=1.5, sub=3, segs=18, into=F.p(0, -0.02, -0.02))
    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, HEAD, segs=20, sub=3)
    # Gırtlak kesesi: çene altında, açık renk (gırtlak kemiğiyle şişer)
    O.ellipsoid(m.bm("ten2", "throat"), F.p(0, 0.045, -0.05), (0.075, 0.06, 0.035), 12, 7, rot=F.mat())
    # Göz yuvaları: kafanın üstünde kabarık tümsekler; üstte pörtlek gözler
    for side in (-1, 1):
        sc = F.p(side * 0.065, 0.025, 0.045)
        O.ellipsoid(m.bm("ten", "head"), sc, (0.042, 0.04, 0.036), 10, 7)
        n = F.d(side * 0.7, 0.55, 0.45)
        O.eye(m, sc + n * 0.012, n, 0.03, up_hint=F.u, grp="head", iris_k=0.88, pupil="wide", lid=0.22, lid_tilt=0)
    # Ağız çizgisi: kulaktan kulağa
    pts = [F.p(x, y, -0.018) for (x, y) in ((-0.115, -0.01), (-0.1, 0.06), (-0.06, 0.1), (0, 0.118), (0.06, 0.1), (0.1, 0.06), (0.115, -0.01))]
    O.path_loft(m.bm("agiz", "head"), pts, 0.004, 5, sub=2)
    # Burun delikleri
    for side in (-1, 1):
        O.ellipsoid(m.bm("goz", "head"), F.p(side * 0.018, 0.105, 0.02), (0.006, 0.004, 0.004), 6, 4, rot=F.mat())
        # Timpan (kulak zarı): gözün arkasında yuvarlak
        O.patch(m.bm("ten3", "head"), F.p(side * 0.122, -0.03, 0.0), F.d(side, 0, 0), 0.04, 0.04, depth=0.006, sides=8)

    def paint(c, nrm, src):
        if src != "ten":
            return None
        if (c - F.o).dot(F.u) < -0.02 and nrm.dot(F.u) < -0.2:
            return "ten2"
        return "ten3" if spots(c) and nrm.dot(F.u) > 0.2 else None

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, fingers=4, finger_lens=[0.07, 0.085, 0.08, 0.065], finger_r=0.008, palm_w=0.034, palm_t=0.016,
               palm_len=0.05, curl=8, spread=1.4, tip_ball=1.9)
    m.build("tur_eller", parts, body_paint(B))


STYLE = {
    "frames": 24, "amp": 0.22, "duty": 0.6, "lift": 0.07, "bob": 0.008, "sway": 0.02, "roll": 3.0,
    "twist": 2.5, "lean": 3.0, "arm_swing": 0.07, "arm_out": 0.07, "head_stab": 0.7, "toe_out": 24.0,
    "width": 0.15, "bounce": 0.022,
}

PREVIEW = [
    ["ust_isci", "alt_kot", "ayk_bot"],
    ["ust_tisort", "alt_kargo", "ayk_spor"],
    ["ust_kapusonlu", "alt_kot", "ayk_spor"],
    ["ust_takim", "alt_takim", "ayk_kundura"],
]

SPRINGS = []


def secondary(A):
    A.scaled.add("throat.0")

    def puff(pose, k):
        s = 1.0 + 0.7 * k
        pose.setdefault("scale", {})["throat.0"] = (s, 1.0 + 0.25 * k, s)

    def f(pose, kind, ph, fr):
        if kind == "walk":
            puff(pose, 0.1 + 0.1 * math.sin(2 * ph))
        elif kind == "idle":
            # Gırtlak kesesi: iki kez şişip iner
            k = max(0.0, math.sin(ph * 2 - 0.4)) ** 2
            puff(pose, k)
            A.add_rot(pose, "head", (0, 6 * math.sin(ph * 0.5), 0))
        elif kind == "look":
            puff(pose, 0.15)
        elif kind == "stumble":
            puff(pose, math.sin(math.pi * min(ph * 1.5, 1.0)))

    return f
