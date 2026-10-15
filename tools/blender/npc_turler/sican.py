"""Sıçan: ince, hafif kambur (boyun öne uzanır), dar omuzlu, küçük göbekli. İnce öne eğik
boyun, kafada uzun sivri burun, pembe burun ucu, bıyıklar, boncuk gözler, büyük yuvarlak
kulaklar (içi pembe, 2 kemik), ön dişler. Pembe ince parmaklı, tırnaklı eller. Uzun çıplak
pembe halkalı kuyruk (5 kemik).

Hareket karakteri: kambur, telaşlı, kısa hızlı adımlar; kafa öne uzanıp koklar (hızlı küçük
kafa vuruşları), kuyruk S çizerek sürünür. Beklerken burnunu oynatıp koklanır; bakınırken
ani, kesik kafa hareketleri.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.56, 0.52, 0.5),      # gri-kahve
    "ten2": (0.82, 0.78, 0.74),    # karın / gıdı
    "ten3": (0.88, 0.6, 0.6),      # pembe deri (kuyruk, el, burun)
    "iris": (0.08, 0.06, 0.06),
    "tirnak": (0.9, 0.86, 0.8),
}


def body():
    return O.Body(
        hip_z=0.86, shoulder_z=1.3, shoulder_w=0.16,
        chest=(0.15, 0.1), waist=(0.135, 0.095), belly=(0.15, 0.11), belly_cy=-0.015, hip=(0.145, 0.1),
        neck_r=0.056, trap=0.72,
        arm=(0.26, 0.24, 0.09), arm_r=(0.04, 0.038, 0.029, 0.033, 0.022),
        leg_r=(0.072, 0.05, 0.052, 0.03), foot_x=0.095, foot_len=1.05, foot_w=0.9,
        neck_pts=[(0, 0.01, 1.3), (0, -0.025, 1.38), (0, -0.06, 1.44)],
        head_c=(0, -0.08, 1.5), head_r=(0.085, 0.1, 0.08), head_top=1.6, spine_lean=7.0, hat_tilt=-6.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.08, 1.5)), Vector((0, -1, -0.16)), Vector((0, 0, 1)))


HEAD = [
    (-0.085, 0.0, 0.015, 0.015, 0.015, 2.0),
    (-0.07, 0.004, 0.055, 0.058, 0.05, 2.0),
    (-0.03, 0.006, 0.08, 0.075, 0.066, 2.0),
    (0.02, 0.002, 0.075, 0.066, 0.06, 2.1),
    (0.07, -0.01, 0.048, 0.042, 0.044, 2.0),
    (0.12, -0.02, 0.028, 0.026, 0.028, 2.0),
    (0.155, -0.026, 0.014, 0.013, 0.014, 2.0),
    (0.166, -0.028, 0.003, 0.003, 0.003, 2.0),
]


def ear_frame(F, side):
    base = F.p(side * 0.058, -0.02, 0.05)
    up = F.d(side * 0.75, -0.25, 0.75)
    n = F.d(side * 0.3, 1.0, 0.0)
    n = (n - up * n.dot(up)).normalized()
    return base, up, n


def tail_points(B):
    hz = B.hip_z
    return [Vector((0, B.hip[1], hz + 0.02)), Vector((0, B.hip[1] + 0.12, hz - 0.06)), Vector((0.03, B.hip[1] + 0.2, hz - 0.25)),
            Vector((0.07, B.hip[1] + 0.24, hz - 0.45)), Vector((0.08, B.hip[1] + 0.32, hz - 0.65)), Vector((0.06, B.hip[1] + 0.45, hz - 0.78))]


def chains(B):
    F = head_frame()
    out = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, up, n = ear_frame(F, side)
        out.append((f"ear.{sfx}", [base, base + up * 0.04, base + up * 0.085], "head"))
    out.append(("tail", tail_points(B), "hips"))
    return out


def build(B, parts):
    O.build_body_skin(B, parts, paint=O.noise_paint("ten", "ten2", 0.05, seed=12))
    build_head(B, parts)
    build_hands(B, parts)
    build_tail(B, parts)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    O.neck_skin(m, B, [0.06, 0.056, 0.054], grp="chest|neck", flare=1.9, sub=3, segs=16, into=F.p(0, -0.03, -0.01))
    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, HEAD, segs=16, sub=3)
    # Burun ucu, dişler, bıyık
    O.ellipsoid(m.bm("ten3", "head"), F.p(0, 0.165, -0.025), (0.014, 0.012, 0.012), 8, 5, rot=F.mat())
    for side in (-1, 1):
        O.box(m.bm("beyaz", "head"), F.p(side * 0.005, 0.145, -0.052), (0.008, 0.005, 0.016), rot=F.mat())
        O.whiskers(m, F, side, 0.02, 0.145, -0.022, n=3, length=0.11, mat="siyah", thick=0.0016, back=0.3)
        # Yanak tüyü
        O.tufts(m.bm("ten", "head"), F.p(side * 0.07, 0.03, -0.03), F.d(side, -0.4, -0.4), 2, 0.025, 0.01, area=0.4)
    # Boncuk gözler
    for side in (-1, 1):
        n = F.d(side * 0.7, 0.68, 0.15)
        O.eye(m, F.p(side * 0.045, 0.06, 0.02), n, 0.014, up_hint=F.u, grp="head", iris_k=0.95, pupil="full", lid=0.12,
              ak=False)
    # Kulaklar: büyük, yuvarlak, ince; çanak
    ears = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, up, n = ear_frame(F, side)
        ears.append((base, up, n))
        rings = []
        for t, wid, th in ((-0.008, 0.022, 0.012), (0.015, 0.04, 0.01), (0.045, 0.05, 0.009), (0.075, 0.042, 0.008),
                           (0.092, 0.022, 0.007), (0.098, 0.004, 0.004)):
            rings.append((base + up * t, up, th, wid, n))
        O.loft(m.bm("ten", f"ear.{sfx}"), rings, 10, sub=2, sq=2.0)

    def paint(c, nrm, src):
        if src != "ten":
            return None
        for base, up, n in ears:
            q = c - base
            if -0.01 < q.dot(up) < 0.1 and abs(q.dot(n)) < 0.02 and abs(q.dot(up.cross(n))) < 0.06:
                return "ten3" if nrm.dot(n) > 0.3 else None
        if c.z < F.o.z - 0.04 and nrm.y < -0.4:
            return "ten2"
        return None

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, mat="ten3", fingers=4, finger_len=0.05, finger_r=0.0075, palm_w=0.03, palm_t=0.016, palm_len=0.05,
               curl=30, claw_mat="tirnak", spread=1.0)
    m.build("tur_eller", parts)


def build_tail(B, parts):
    m = O.Mesh()
    pts = tail_points(B)
    pts = [pts[0] + Vector((0, -0.05, 0.02))] + pts
    O.path_loft(m.bm("ten3", "tail"), pts, [0.024, 0.022, 0.018, 0.014, 0.011, 0.008, 0.003], 7, sub=3)
    m.build("tur_kuyruk", parts, O.band_paint(pts, 0.03, 0.22, "ten3", "pembe", radius=0.05))


STYLE = {
    "frames": 16, "amp": 0.15, "duty": 0.58, "lift": 0.05, "bob": 0.012, "sway": 0.008, "roll": 2.0,
    "twist": 4.0, "lean": 8.0, "arm_swing": 0.06, "arm_fwd": -0.04, "arm_lift": 0.06, "head_stab": 0.7, "toe_out": 4.0,
}

PREVIEW = [
    ["ust_kapusonlu", "alt_kot", "ayk_spor", "sapka_kasket"],
    ["ust_tisort", "alt_kargo", "ayk_spor"],
    ["ust_takim", "alt_takim", "ayk_kundura"],
    ["ust_isci", "alt_kargo", "ayk_bot", "sapka_bere"],
]

SPRINGS = [["tail.0", "tail.4", 0.6, 0.2, 0.7], ["ear.L.0", "ear.L.1", 2.5, 0.4, 0.1], ["ear.R.0", "ear.R.1", 2.5, 0.4, 0.1]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    def tail(pose, ph, amp, speed=1.0):
        for i in range(5):
            A.add_wrot(pose, f"tail.{i}", Z, amp * (0.4 + 0.15 * i) * math.sin(ph * speed - i * 0.9))

    def ears(pose, back):
        for side, sfx in ((1, "L"), (-1, "R")):
            A.add_wrot(pose, f"ear.{sfx}.0", Z, side * back)

    def sniff(pose, amt, ph, speed=18):
        A.add_rot(pose, "head", (3 * amt * math.sin(ph * speed), 0, 0))

    def f(pose, kind, ph, fr):
        if kind == "walk":
            tail(pose, ph, 16)
            sniff(pose, 0.6, ph, 4)
            ears(pose, 6 * math.sin(2 * ph))
        elif kind == "idle":
            k = max(0.0, math.sin(ph * 2 - 0.5))
            sniff(pose, k, ph, 24)
            tail(pose, ph, 8, 2)
            ears(pose, 10 * max(0.0, math.sin(ph - 1.5)) ** 4)
        elif kind == "look":
            sniff(pose, 0.5, ph, 20)
            tail(pose, ph, 6, 3)
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.6, 1.0))
            ears(pose, 30 * k)
            tail(pose, ph * math.tau, 30 * (1 - ph), 4)

    return f
