"""Köpek: atletik; geniş göğüs, dar bel, kaslı kollar. Kalın tüylü boyun ve tasma (künyeli).
Uzun burunlu kafa: belirgin stop (alın-burun kırılımı), kaş çıkıntıları, siyah ıslak burun,
sarkık dudak kenarları, dil ucu; sarkık uzun kulaklar (2 kemik, sallanır), sıcak kahve
gözler, ağız çevresi ve göğüs açık renk. Eller pati: kalın kısa parmaklar, koyu tırnaklar.
Kuyruk yukarı kıvrık, 3 kemik.

Hareket karakteri: enerjik, yaylanan adımlar; kollar rahat sallanır; kuyruk adımdan hızlı
sallanır, kulaklar her adımda zıplar. Beklerken hızlı nefes (göğüs), kuyruk sallama; bakınırken
meşhur kafa eğme.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.66, 0.46, 0.28),     # kahve
    "ten2": (0.93, 0.86, 0.74),    # ağız çevresi, göğüs
    "ten3": (0.4, 0.26, 0.15),     # kulaklar, sırt koyu
    "iris": (0.42, 0.24, 0.1),
    "tirnak": (0.2, 0.17, 0.15),
}


def body():
    return O.Body(
        hip_z=0.94, shoulder_z=1.42, shoulder_w=0.2,
        chest=(0.19, 0.125), chest_cy=-0.015, waist=(0.14, 0.09), belly=(0.145, 0.095), hip=(0.155, 0.1), butt=0.006,
        neck_r=0.07, trap=0.78,
        arm=(0.3, 0.27, 0.1), arm_r=(0.052, 0.05, 0.036, 0.044, 0.03),
        leg_r=(0.082, 0.056, 0.06, 0.036), foot_x=0.105, foot_len=1.0,
        neck_pts=[(0, 0.01, 1.42), (0, -0.0, 1.49), (0, -0.015, 1.55)],
        head_c=(0, -0.03, 1.63), head_r=(0.1, 0.11, 0.1), head_top=1.74, hat_tilt=-3.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.03, 1.63)), Vector((0, -1, -0.12)), Vector((0, 0, 1)))


SKULL = [
    (-0.105, 0.0, 0.015, 0.015, 0.015, 2.0),
    (-0.09, 0.006, 0.065, 0.075, 0.06, 2.0),
    (-0.045, 0.01, 0.092, 0.095, 0.08, 2.1),
    (0.0, 0.01, 0.094, 0.09, 0.082, 2.2),
    (0.04, 0.0, 0.08, 0.072, 0.08, 2.3),        # stop: alın burna kırılır
    (0.075, -0.03, 0.052, 0.042, 0.06, 2.4),
    (0.12, -0.036, 0.048, 0.038, 0.052, 2.4),   # burun köprüsü
    (0.16, -0.036, 0.046, 0.036, 0.048, 2.3),
    (0.182, -0.036, 0.034, 0.028, 0.036, 2.1),
    (0.192, -0.036, 0.008, 0.008, 0.008, 2.0),
]


def ear_frame(F, side):
    base = F.p(side * 0.078, -0.035, 0.065)
    d = F.d(side * 0.55, 0.1, -1.0)                 # aşağı sarkar
    n = F.d(side * 1.0, 0.0, 0.2)                   # dış yüz yana
    n = (n - d * n.dot(d)).normalized()
    return base, d, n


def chains(B):
    F = head_frame()
    out = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, d, n = ear_frame(F, side)
        out.append((f"ear.{sfx}", [base, base + d * 0.065, base + d * 0.13], "head"))
    hz = B.hip_z
    out.append(("tail", [Vector((0, B.hip[1], hz + 0.03)), Vector((0, B.hip[1] + 0.1, hz + 0.08)),
                         Vector((0, B.hip[1] + 0.18, hz + 0.18)), Vector((0, B.hip[1] + 0.21, hz + 0.3))], "hips"))
    return out


def body_paint(B):
    def f(c, n, src):
        if src != "ten":
            return None
        if c.z > B.hip_z + 0.15 and abs(c.x) < 0.09 and n.y < -0.55:
            return "ten2"
        if c.z > B.hip_z and n.y > 0.5 and abs(c.x) < 0.1:
            return "ten3"                                # sırt koyu
        return None
    return f


def build(B, parts):
    O.build_body_skin(B, parts, paint=body_paint(B))
    build_head(B, parts)
    build_hands(B, parts)
    build_tail(B, parts)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    O.neck_skin(m, B, [0.078, 0.074, 0.07], grp="chest|neck", flare=1.7, sub=3, segs=18, into=F.p(0, -0.03, -0.03))
    # Tasma ve künye
    nz = B.neck_pts[1].z
    O.loft(m.bm("tasma", "neck"), [(Vector((0, -0.005, nz - 0.012)), O.UP, 0.083, 0.083), (Vector((0, -0.005, nz + 0.014)), O.UP, 0.083, 0.083)], 16)
    O.ellipsoid(m.bm("gaga", "neck"), Vector((0, -0.092, nz - 0.03)), (0.016, 0.004, 0.018), 8, 4)
    O.loft(m.bm("tirnak", "neck"), [(Vector((0, -0.09, nz - 0.012)), Vector((0, 0, 1)), 0.005, 0.003), (Vector((0, -0.09, nz - 0.004)), Vector((0, 0, 1)), 0.005, 0.003)], 5)
    # Ense / boyun tüyü
    for i in range(8):
        a = math.pi * 0.25 + math.pi * 1.5 * i / 7
        p = Vector((math.sin(a) * 0.075, -0.01 - math.cos(a) * 0.075, nz + 0.035))
        O.tufts(m.bm("ten", "neck"), p, Vector((math.sin(a), -math.cos(a), -0.5)), 1, 0.026, 0.012, area=0.3)

    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, SKULL, segs=18, sub=3)
    # Kaş çıkıntıları ve yanaklar
    for side in (-1, 1):
        O.ellipsoid(m.bm("ten", "head"), F.p(side * 0.036, 0.045, 0.052), (0.03, 0.022, 0.014), 8, 5, rot=F.mat())
        # Sarkık dudak kenarı (jowl)
        O.ellipsoid(m.bm("ten2", "head"), F.p(side * 0.038, 0.13, -0.075), (0.022, 0.05, 0.026), 8, 5, rot=F.mat())
    # Alt çene
    O.organic(m.bm("ten2", "head"), F.p(0, 0.09, -0.078), F.f, F.u,
              [(-0.05, 0, 0.005, 0.005, 0.005, 2), (-0.02, 0, 0.04, 0.016, 0.02, 2.2), (0.06, 0.004, 0.036, 0.014, 0.018, 2.2),
               (0.085, 0.006, 0.014, 0.008, 0.01, 2), (0.09, 0.006, 0.003, 0.003, 0.003, 2)], segs=12, sub=2)
    # Dil ucu
    O.ellipsoid(m.bm("dil", "head"), F.p(0.012, 0.165, -0.082), (0.016, 0.02, 0.006), 8, 4, rot=F.mat())
    # Burun: siyah, iki delikli
    O.ellipsoid(m.bm("siyah", "head"), F.p(0, 0.185, -0.012), (0.03, 0.022, 0.022), 10, 6, rot=F.mat())
    for side in (-1, 1):
        O.ellipsoid(m.bm("goz", "head"), F.p(side * 0.012, 0.203, -0.016), (0.006, 0.004, 0.005), 6, 4, rot=F.mat())
    # Gözler: sıcak kahve, hafif hüzünlü kaş
    for side in (-1, 1):
        n = F.d(side * 0.45, 0.88, 0.1)
        O.eye(m, F.p(side * 0.046, 0.05, 0.03), n, 0.019, up_hint=F.u, grp="head", iris_k=0.8, lid=0.22, lid_tilt=-side * 14)
    # Kulaklar: uzun sarkık, yassı, uçta yuvarlak
    for side, sfx in ((1, "L"), (-1, "R")):
        base, d, n = ear_frame(F, side)
        rings = []
        for t, wid, th in ((-0.01, 0.03, 0.018), (0.02, 0.045, 0.014), (0.06, 0.055, 0.012), (0.1, 0.05, 0.012),
                           (0.125, 0.032, 0.011), (0.138, 0.006, 0.006)):
            rings.append((base + d * t, d, th, wid, n))
        O.loft(m.bm("ten3", f"ear.{sfx}"), rings, 8, sub=2, sq=2.3)

    fo, ff, fu = F.o, F.f, F.u

    def paint(c, nrm, src):
        if src != "ten":
            return None
        q = c - fo
        d, h = q.dot(ff), q.dot(fu)
        if d > 0.085 and h < -0.0:
            return "ten2"                         # ağız çevresi
        if d > 0.1 and abs(q.x) < 0.012:
            return "ten2"                         # burun köprüsünde açık çizgi
        if c.z < fo.z - 0.07 and nrm.y < -0.45:
            return "ten2"                         # gerdan
        return None

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, fingers=4, finger_len=0.042, finger_r=0.013, palm_w=0.042, palm_t=0.024, palm_len=0.058,
               curl=24, tip_ball=1.15, pad_mat="siyah", claw_mat="tirnak", spread=0.85)
    m.build("tur_eller", parts, body_paint(B))


def build_tail(B, parts):
    m = O.Mesh()
    hz = B.hip_z
    pts = [Vector((0, B.hip[1] - 0.04, hz + 0.02)), Vector((0, B.hip[1] + 0.01, hz + 0.03)), Vector((0, B.hip[1] + 0.1, hz + 0.08)),
           Vector((0, B.hip[1] + 0.18, hz + 0.18)), Vector((0, B.hip[1] + 0.21, hz + 0.3))]
    O.path_loft(m.bm("ten", "tail"), pts, [0.035, 0.035, 0.032, 0.026, 0.01], 8, sub=2)
    O.tufts(m.bm("ten2", "tail"), pts[-1], Vector((0, 0.2, 1)), 4, 0.04, 0.01, area=1.2)
    m.build("tur_kuyruk", parts)


STYLE = {
    "frames": 22, "amp": 0.27, "duty": 0.58, "lift": 0.1, "bob": 0.02, "sway": 0.008, "roll": 2.0,
    "twist": 5.0, "lean": 3.0, "arm_swing": 0.15, "head_stab": 0.5, "toe_out": 6.0, "bounce": 0.01,
}

PREVIEW = [
    ["ust_kapusonlu", "alt_kot", "ayk_spor", "sapka_kasket"],
    ["ust_isci", "alt_kargo", "ayk_bot", "sapka_baret"],
    ["ust_tisort", "alt_kot", "ayk_spor"],
    ["ust_takim", "alt_takim", "ayk_kundura", "aks_evrak"],
]

SPRINGS = [["ear.L.0", "ear.L.1", 0.9, 0.3, 0.8], ["ear.R.0", "ear.R.1", 0.9, 0.3, 0.8], ["tail.0", "tail.2", 1.6, 0.3, 0.1]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    def ears(pose, swing, lift):
        for side, sfx in ((1, "L"), (-1, "R")):
            for i in range(2):
                A.add_wrot(pose, f"ear.{sfx}.{i}", Y, -side * lift * (0.6 + 0.4 * i))
                A.add_wrot(pose, f"ear.{sfx}.{i}", X, swing * (0.5 + 0.5 * i))

    def wag(pose, ph, amp, up=0.0):
        for i in range(3):
            A.add_wrot(pose, f"tail.{i}", Z, amp * (0.5 + 0.3 * i) * math.sin(ph - i * 0.6))
            A.add_wrot(pose, f"tail.{i}", X, -up)

    def f(pose, kind, ph, fr):
        if kind == "walk":
            ears(pose, 10 * math.sin(2 * ph - 1.2), 6 + 6 * math.sin(2 * ph - 0.6))
            wag(pose, ph * 3, 22)
        elif kind == "idle":
            pant = math.sin(ph * 12)
            A.add_rot(pose, "chest", (1.2 * pant, 0, 0))
            A.add_rot(pose, "head", (0.8 * pant, 0, 0))
            wag(pose, ph * 6, 18 * (0.5 + 0.5 * math.sin(ph)))
            ears(pose, 3 * math.sin(ph * 2), 4)
        elif kind == "look":
            tilt = math.sin(ph) * 18                         # meraklı kafa eğme
            A.add_rot(pose, "head", (0, 0, tilt))
            ears(pose, 0, 10 + 8 * abs(math.sin(ph)))
            wag(pose, ph * 4, 10)
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.6, 1.0))
            ears(pose, -30 * k + 20 * math.sin(ph * 12) * (1 - ph), 20 * k)
            wag(pose, ph * 10, 10 * (1 - ph), up=-30 * k)     # kuyruk kısılır

    return f
