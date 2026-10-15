"""Güvercin: orta boy, ince belli ama göğsü kabarık (öne taşan), ince bacaklı. Kalın, kısa
boyun yanardöner tüylü (yeşil-mor parıltı, tüy pulları), küçük yuvarlak mavi-gri kafa,
turuncu irisli kırmızı göz halkalı gözler, burun üstünde beyaz et kabarcığı (cere), kısa
koyu gaga. Eller tüy uçlu kanat-el (uzun yassı tüy parmaklar, bilekte tüy saçağı).
Kuyruk: siyah uç bantlı yelpaze tüyler.

Hareket karakteri: yürürken meşhur kafa vuruşu: her adımda kafa önce olduğu yerde kalır
(gövde ilerlerken), sonra hızla öne fırlar. Kısa, hızlı, ayaklar neredeyse tek çizgide;
göğüs önde. Beklerken kafasını kesik kesik yana çevirir, tüylerini kabartıp hafif gerinir.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.52, 0.56, 0.66),     # mavi-gri tüy
    "ten2": (0.36, 0.55, 0.45),    # boyun yeşil parıltı
    "ten3": (0.5, 0.36, 0.56),     # boyun mor parıltı
    "iris": (0.95, 0.5, 0.1),
    "tirnak": (0.3, 0.3, 0.34),
}


def body():
    return O.Body(
        hip_z=0.9, shoulder_z=1.36, shoulder_w=0.175,
        chest=(0.185, 0.145), chest_cy=-0.035, waist=(0.135, 0.095), belly=(0.15, 0.11), hip=(0.15, 0.1),
        neck_r=0.075, trap=0.8,
        arm=(0.28, 0.26, 0.12), arm_r=(0.046, 0.044, 0.034, 0.04, 0.028),
        leg_r=(0.07, 0.048, 0.05, 0.03), foot_x=0.085, foot_len=0.95, foot_w=0.9,
        neck_pts=[(0, 0.0, 1.36), (0, -0.02, 1.45), (0, -0.04, 1.53)],
        head_c=(0, -0.06, 1.61), head_r=(0.085, 0.095, 0.09), head_top=1.71, spine_lean=3.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.06, 1.61)), Vector((0, -1, -0.08)), Vector((0, 0, 1)))


HEAD = [
    (-0.095, -0.01, 0.015, 0.015, 0.015, 2.0),
    (-0.08, -0.004, 0.058, 0.062, 0.07, 2.0),
    (-0.04, 0.004, 0.08, 0.084, 0.082, 2.0),
    (0.005, 0.006, 0.078, 0.082, 0.074, 2.05),
    (0.045, -0.004, 0.06, 0.058, 0.06, 2.0),      # alın gagaya doğru eğimli
    (0.075, -0.014, 0.034, 0.03, 0.038, 2.0),
    (0.088, -0.016, 0.008, 0.008, 0.008, 2.0),
]

NECK_R = [0.088, 0.082, 0.07]


def chains(B):
    hz = B.hip_z
    return [("tail", [Vector((0, B.hip[1] - 0.01, hz + 0.02)), Vector((0, B.hip[1] + 0.08, hz - 0.05)),
                      Vector((0, B.hip[1] + 0.16, hz - 0.12))], "hips")]


def build(B, parts):
    O.build_body_skin(B, parts, paint=O.noise_paint("ten", "tirnak", 0.06, seed=2), arm_extra=lambda m, side: wing_fringe(m, B, side))
    build_head(B, parts)
    build_hands(B, parts)
    build_tail(B, parts)


def wing_fringe(m, B, side):
    """Ön kolun arka kenarında tüy saçağı (kısa kollu kıyafette görünür)."""
    s, e, w, h, d = B.arm_points(side)
    back = Vector((0, 1, 0))
    for k in range(5):
        p = e.lerp(w, 0.2 + 0.18 * k)
        O.cone(m.bm("ten", O.arm_tag(side)), p + back * 0.02, p + back * 0.06 + d * 0.05, 0.016, sides=3, flatten=0.35)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    # Boyun: kalın, kabarık; tüy pulları (kırık yüzey) için hafif pürüz
    O.neck_skin(m, B, NECK_R, mat="ten2", grp="chest|neck", flare=1.7, sub=4, segs=20, into=F.p(0, -0.04, -0.01))
    # Gerdan kabarıklığı: boynun önüne gömülü, göğse akan yumuşak şişkinlik
    O.ellipsoid(m.bm("ten2", "neck"), Vector((0, -0.045, 1.42)), (0.084, 0.052, 0.085), 12, 8)

    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, HEAD, segs=16, sub=3)
    # Gaga: kısa, koyu, ucu hafif kanca; kökünde beyaz cere
    O.organic(m.bm("tirnak", "head"), F.p(0, 0.08, -0.012), F.d(0, 1, -0.2), F.u,
              [(-0.01, 0.0, 0.016, 0.012, 0.009, 2.0), (0.02, 0.0, 0.013, 0.01, 0.008, 2.0), (0.05, -0.004, 0.008, 0.007, 0.006, 2.0),
               (0.066, -0.01, 0.003, 0.003, 0.003, 2.0)], segs=8, sub=2)
    O.ellipsoid(m.bm("beyaz", "head"), F.p(0, 0.088, 0.002), (0.016, 0.018, 0.01), 8, 5, rot=F.mat())
    # Gözler: yanlarda, turuncu iris, kırmızımsı göz halkası
    for side in (-1, 1):
        n = F.d(side * 0.85, 0.4, 0.12)
        c = F.p(side * 0.058, 0.03, 0.02)
        O.eye(m, c, n, 0.016, up_hint=F.u, grp="head", iris_k=0.82, pupil="round", lid=0.0, ak=False)
        O.eye_ring(m, "pembe", c + n * 0.004, n, 0.018, 0.0035, up_hint=F.u)
    head_bottom = F.o.z - 0.06

    def paint(c, n, src):
        if src == "ten2":
            if c.z > head_bottom - 0.02:
                return "ten"                         # boynun üstü kafa gibi gri
            # Yanardöner: önde ve yanlarda mor pullar, arkada / üstte yeşil; geçişte serpiştirme
            purple = (-n.y * 0.6 + abs(n.x) * 0.5) - (c.z - 1.42) * 6 + (O.hash01(c, 6) - 0.5) * 0.5
            return "ten3" if purple > 0.35 else None
        if src == "ten":
            return "tirnak" if O.hash01(c, 9) < 0.05 else None
        return None

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, fingers=4, finger_lens=[0.08, 0.095, 0.09, 0.075], finger_r=0.011, palm_w=0.04, palm_t=0.018,
               palm_len=0.055, thumb=True, curl=10, spread=1.25, claw_mat="tirnak")
    m.build("tur_eller", parts, O.noise_paint("ten", "tirnak", 0.12, seed=3))


def build_tail(B, parts):
    m = O.Mesh()
    hz = B.hip_z
    base = Vector((0, B.hip[1] - 0.02, hz + 0.02))
    for k in range(-3, 4):
        tip = base + Vector((k * 0.03, 0.17, -0.13))
        mid = base.lerp(tip, 0.75)
        u = Vector((1, 0, 0))
        O.path_loft(m.bm("ten", "tail"), [base + Vector((k * 0.008, 0, 0)), mid], [0.018, 0.022], 5, flatten=0.3, u=u)
        O.path_loft(m.bm("siyah", "tail"), [mid, tip], [0.022, 0.012], 5, flatten=0.3, u=u)
    m.build("tur_kuyruk", parts)


STYLE = {
    "frames": 20, "amp": 0.15, "duty": 0.6, "lift": 0.06, "bob": 0.01, "sway": 0.01, "roll": 3.0,
    "twist": 3.0, "lean": 6.0, "arm_swing": 0.05, "head_stab": 0.0, "toe_out": 0.0, "width": 0.05,
}

PREVIEW = [
    ["ust_kisa", "alt_kargo", "ayk_spor", "aks_omuz"],
    ["ust_tisort", "alt_kot", "ayk_spor", "sapka_kasket"],
    ["ust_kapusonlu", "alt_kot", "ayk_bot"],
    ["ust_takim", "alt_takim", "ayk_kundura", "aks_evrak"],
]

SPRINGS = [["tail.0", "tail.1", 2.0, 0.4, 0.1]]

X = Vector((1, 0, 0))


def secondary(A):
    neck = A.neck

    def head_pos(pose, fwd, turn=0.0, tilt=0.0):
        # fwd: kafa ileri (+) / geri (-) öteleme açısı: boyun öne, kafa ters yönde döner (kafa düz kalır)
        for b in neck:
            A.add_rot(pose, b, (fwd / len(neck), turn / (len(neck) + 1), 0))
        A.add_rot(pose, "head", (-fwd, turn / (len(neck) + 1), tilt))

    def tail(pose, lift):
        for i in range(2):
            A.add_wrot(pose, f"tail.{i}", X, lift)

    def f(pose, kind, ph, fr):
        if kind == "walk":
            # Kafa vuruşu: adım başına (döngüde 2) kafa önce yerinde kalır, sonra öne fırlar
            s = (2 * ph / math.tau) % 1.0
            if s < 0.62:
                k = s / 0.62
                fwd = 14 - 28 * k          # gövde ilerlerken kafa yerinde: gövdeye göre geri kayar
            else:
                k = (s - 0.62) / 0.38
                k = k * k * (3 - 2 * k)
                fwd = -14 + 28 * k         # hızla öne
            head_pos(pose, fwd)
            tail(pose, 4 * math.sin(2 * ph))
        elif kind == "idle":
            # Kesik kesik yana bakış ve kafa eğme
            step = int(ph / math.tau * 5)
            turns = [0, 25, 25, -18, 0]
            tilts = [0, 10, 0, -8, 0]
            head_pos(pose, 3 * math.sin(ph * 2), turns[step % 5], tilts[step % 5])
            tail(pose, 3 * math.sin(ph * 3))
        elif kind == "look":
            head_pos(pose, 8 * math.sin(ph * 3), 0, 14 * math.sin(ph * 2))
        elif kind == "stumble":
            head_pos(pose, -24 * math.sin(math.pi * min(ph * 2, 1)) + 10 * math.sin(ph * 10) * (1 - ph))
            tail(pose, 25 * math.sin(math.pi * ph))

    return f
