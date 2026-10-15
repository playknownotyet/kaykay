"""Papağan (ara/amazon): orta boy, göğsü tombul ve öne çıkık, hafif öne eğik. Tüylü
kalınca boyun (pul tüy dokusu). Yuvarlak kafa, iri kanca gaga (üst gaga alt gagayı örter,
alt gaga çene kemiğiyle açılır), gaga kökünde et (cere), gözün çevresinde beyaz çıplak deri
ve ince tüy çizgileri (ara maskesi), soluk sarı iris. Tepede kısa tepelik tüyleri. Eller
renkli tüy uçlu kanat-el. Uzun, sivri, renkli kuyruk tüyleri (3 kemik).

Hareket karakteri: kurumlu çalım: hafif paytak yürür, kafa her adımda yukarı aşağı sallanır
(dans eder gibi). Beklerken ritimle kafa sallar, meraklı meraklı kafa eğer, gagasını
şıkırdatır. Bakınırken tek gözle bakmak için kafasını yana çevirip eğer. Çarpılınca
gagasını açıp ciyaklar, kuyruğu kalkar.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.85, 0.15, 0.12),     # kırmızı (ara)
    "ten2": (0.98, 0.82, 0.18),    # sarı (göğüs / kanat şeridi)
    "ten3": (0.15, 0.4, 0.85),     # mavi (kanat ve kuyruk uçları)
    "iris": (0.95, 0.92, 0.7),
    "tirnak": (0.92, 0.88, 0.8),   # gaga (açık kemik rengi)
}


def body():
    return O.Body(
        hip_z=0.88, shoulder_z=1.33, shoulder_w=0.165,
        chest=(0.18, 0.145), chest_cy=-0.035, waist=(0.135, 0.1), belly=(0.15, 0.115), hip=(0.145, 0.1),
        neck_r=0.07, trap=0.8,
        arm=(0.27, 0.25, 0.11), arm_r=(0.045, 0.043, 0.032, 0.038, 0.027),
        leg_r=(0.07, 0.048, 0.05, 0.03), foot_x=0.09, foot_len=0.95, foot_w=0.9,
        neck_pts=[(0, 0.0, 1.33), (0, -0.015, 1.41), (0, -0.03, 1.47)],
        head_c=(0, -0.045, 1.555), head_r=(0.095, 0.1, 0.09), head_top=1.66, spine_lean=4.0, hat_tilt=-8.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.045, 1.555)), Vector((0, -1, -0.06)), Vector((0, 0, 1)))


HEAD = [
    (-0.105, 0.0, 0.016, 0.016, 0.016, 2.0),
    (-0.09, 0.004, 0.066, 0.07, 0.065, 2.0),
    (-0.042, 0.008, 0.097, 0.097, 0.087, 2.05),
    (0.01, 0.006, 0.095, 0.095, 0.084, 2.1),
    (0.052, 0.0, 0.076, 0.078, 0.072, 2.1),     # yüz düz, gagaya iner
    (0.075, -0.008, 0.052, 0.054, 0.054, 2.0),
    (0.083, -0.01, 0.01, 0.01, 0.01, 2.0),
]


def chains(B):
    F = head_frame()
    hz = B.hip_z
    return [("jaw", [F.p(0, 0.06, -0.035), F.p(0, 0.12, -0.075)], "head"),
            ("tail", [Vector((0, B.hip[1] - 0.01, hz + 0.02)), Vector((0, B.hip[1] + 0.12, hz - 0.12)),
                      Vector((0, B.hip[1] + 0.2, hz - 0.32)), Vector((0, B.hip[1] + 0.25, hz - 0.52))], "hips")]


def build(B, parts):
    O.build_body_skin(B, parts, paint=body_paint(B), arm_extra=lambda m, side: wing_band(m, B, side))
    build_head(B, parts)
    build_hands(B, parts)
    build_tail(B, parts)


def body_paint(B):
    def f(c, n, src):
        if src != "ten":
            return None
        side = 1 if c.x > 0 else -1
        if abs(c.x) > B.shoulder_w + 0.02:                # kollar: dış yüz mavi, ortası sarı şerit
            return "ten3" if n.x * side > 0.3 and c.z < B.shoulder_z - 0.25 else ("ten2" if n.y > 0.4 else None)
        return None
    return f


def wing_band(m, B, side):
    """Ön kolun arka kenarında uzun tüy saçağı (kanat): dışı mavi, kökü sarı."""
    s, e, w, h, d = B.arm_points(side)
    back = Vector((0, 1, 0))
    for k in range(6):
        p = e.lerp(w, 0.1 + 0.16 * k)
        mat = "ten2" if k < 2 else "ten3"
        O.cone(m.bm(mat, O.arm_tag(side)), p + back * 0.018, p + back * 0.05 + d * 0.07, 0.018, sides=3, flatten=0.3)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    O.neck_skin(m, B, [0.08, 0.074, 0.066], grp="chest|neck", flare=1.8, sub=4, segs=18, into=F.p(0, -0.03, -0.02))
    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, HEAD, segs=18, sub=3)
    # Yanak / göz çevresi beyaz çıplak deri (ara maskesi): yanlarda yassı yastık
    for side in (-1, 1):
        # Yüze yapışık yassı beyaz alan: gözle gaga arası (yalnız dış yüzü görünür)
        nrm = F.d(side * 0.75, 0.66, -0.05)
        O.ellipsoid(m.bm("beyaz", "head"), F.p(side * 0.058, 0.058, -0.008) - nrm * 0.008, (0.034, 0.04, 0.016), 12, 8,
                    rot=O.axis_rot(nrm, F.u))
        # Maskede ince tüy çizgileri
        for k in range(3):
            pts = [F.p(side * (0.075 + 0.006 * k), 0.03 + 0.012 * k, -0.025 + 0.012 * k),
                   F.p(side * (0.07 + 0.004 * k), 0.065 + 0.008 * k, -0.03 + 0.012 * k)]
            O.path_loft(m.bm("siyah", "head"), pts, 0.0028, 4)
    # Göz: soluk sarı iris, küçük göz bebeği
    for side in (-1, 1):
        n = F.d(side * 0.82, 0.5, 0.12)
        O.eye(m, F.p(side * 0.07, 0.035, 0.022), n, 0.015, up_hint=F.u, grp="head", iris_k=0.85, pupil="round", lid=0.12,
              lid_mat="beyaz")
    # Üst gaga: kökü geniş, öne kıvrılıp aşağı kanca yapar; yanlardan basık
    up = [F.p(0, 0.055, 0.03), F.p(0, 0.1, 0.03), F.p(0, 0.135, 0.008), F.p(0, 0.145, -0.035), F.p(0, 0.13, -0.075),
          F.p(0, 0.115, -0.09)]
    O.path_loft(m.bm("tirnak", "head"), up, [0.045, 0.04, 0.032, 0.022, 0.012, 0.003], 10, flatten=[1.0, 1.0, 1.1, 1.3, 1.4, 1.0],
                sub=3, u=F.s)
    # Cere (gaga kökündeki et) ve burun delikleri
    O.ellipsoid(m.bm("beyaz", "head"), F.p(0, 0.06, 0.042), (0.03, 0.02, 0.014), 8, 5, rot=F.mat())
    for side in (-1, 1):
        O.ellipsoid(m.bm("goz", "head"), F.p(side * 0.012, 0.072, 0.05), (0.004, 0.004, 0.004), 5, 4)
    # Alt gaga: çene kemiğine bağlı (açılır); içinde koyu ağız + kalın dil
    lo = [F.p(0, 0.055, -0.03), F.p(0, 0.09, -0.045), F.p(0, 0.112, -0.062)]
    O.path_loft(m.bm("siyah", "jaw"), lo, [0.032, 0.022, 0.006], 8, flatten=0.8, sub=2, u=F.s)
    O.ellipsoid(m.bm("dil", "jaw"), F.p(0, 0.085, -0.032), (0.014, 0.022, 0.01), 7, 5, rot=F.mat())
    O.ellipsoid(m.bm("agiz", "head"), F.p(0, 0.075, -0.02), (0.028, 0.035, 0.02), 8, 5, rot=F.mat())
    # Tepelik: tepede arkaya yatık birkaç tüy
    for k in range(5):
        x = (k - 2) * 0.012
        b = F.p(x, 0.0 - abs(x), 0.085)
        O.cone(m.bm("ten", "head"), b, b + F.d(x * 4, -0.7, 0.6) * (0.05 - abs(x)), 0.012, sides=3, flatten=0.4)

    fo, ff, fu = F.o, F.f, F.u

    def paint(c, nrm, src):
        if src != "ten":
            return None
        q = c - fo
        if c.z < fo.z - 0.08 and nrm.y < -0.2:
            return "ten2" if c.z < B.shoulder_z + 0.05 else None      # gerdan altı sarı (göğse iner)
        # Pul tüy dokusu: boyunda seyrek koyu ton
        if c.z < fo.z - 0.06 and O.hash01(c, 2) < 0.12:
            return "ten3" if O.hash01(c, 7) < 0.15 else None
        return None

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, mat="ten", fingers=4, finger_lens=[0.08, 0.1, 0.095, 0.08], finger_r=0.011, palm_w=0.04,
               palm_t=0.018, palm_len=0.055, curl=10, spread=1.25, claw_mat="siyah")

    def paint(c, n, src):
        # Parmaklar (tüy uçları) mavi, avuç kırmızı
        if src == "ten":
            side = 1 if c.x > 0 else -1
            s, e, w, h, d = B.arm_points(side)
            return "ten3" if (c - w).dot(d) > 0.06 * B.hand_scale else None
        return None

    m.build("tur_eller", parts, paint)


def build_tail(B, parts):
    m = O.Mesh()
    hz = B.hip_z
    base = Vector((0, B.hip[1] - 0.02, hz + 0.03))
    u = Vector((1, 0, 0))
    for k in (-2, -1, 0, 1, 2):
        L = 0.55 - abs(k) * 0.06
        tip = base + Vector((k * 0.03, 0.22 + abs(k) * 0.01, -L))
        mid = base.lerp(tip, 0.55) + Vector((0, 0.04, 0))
        pts = [base + Vector((k * 0.01, 0, 0)), mid, tip]
        O.path_loft(m.bm("ten", "tail"), pts[:2] + [pts[1].lerp(pts[2], 0.4)], [0.02, 0.026, 0.024], 5, flatten=0.3, u=u, sub=2)
        O.path_loft(m.bm("ten3", "tail"), [pts[1].lerp(pts[2], 0.4), tip], [0.024, 0.004], 5, flatten=0.3, u=u)
    m.build("tur_kuyruk", parts)


STYLE = {
    "frames": 22, "amp": 0.18, "duty": 0.6, "lift": 0.06, "bob": 0.01, "sway": 0.03, "roll": 6.0,
    "twist": 3.0, "lean": 3.0, "arm_swing": 0.06, "head_stab": 0.3, "toe_out": 14.0,
}

PREVIEW = [
    ["ust_tisort", "alt_kot", "ayk_spor", "sapka_kasket"],
    ["ust_kisa", "alt_kargo", "ayk_spor", "aks_omuz"],
    ["ust_takim", "alt_takim", "ayk_kundura"],
    ["ust_kapusonlu", "alt_kot", "ayk_bot"],
]

SPRINGS = [["tail.0", "tail.2", 1.2, 0.3, 0.4]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    neck = A.neck

    def bob(pose, k):
        # Kafa yukarı-aşağı: boyun öne, kafa ters (kafa düz kalır, dikey sallanır)
        for b in neck:
            A.add_rot(pose, b, (k / len(neck), 0, 0))
        A.add_rot(pose, "head", (-k * 0.7, 0, 0))

    def jaw(pose, deg):
        A.add_wrot(pose, "jaw.0", X, deg)

    def tail(pose, swing, lift):
        for i in range(3):
            A.add_wrot(pose, f"tail.{i}", Y, swing * (0.5 + 0.3 * i))
            A.add_wrot(pose, f"tail.{i}", X, lift)

    def f(pose, kind, ph, fr):
        if kind == "walk":
            bob(pose, 10 * math.sin(2 * ph - 0.6))
            tail(pose, 8 * math.sin(ph - 1.0), 4)
        elif kind == "idle":
            # Ritimli kafa sallama (dans), sonra meraklı kafa eğme; arada gaga şıkırtısı
            dance = max(0.0, math.sin(ph)) ** 0.5
            bob(pose, 14 * dance * math.sin(ph * 6))
            A.add_rot(pose, "head", (0, 0, 22 * max(0.0, -math.sin(ph)) ** 2))
            jaw(pose, 6 * max(0.0, math.sin(ph * 9)) * max(0.0, -math.sin(ph)))
            tail(pose, 6 * math.sin(ph * 3), 2)
        elif kind == "look":
            # Tek gözle bakış: kafayı yana çevirip eğer
            k = math.sin(ph)
            A.spread_neck(pose, (0, 55 * k, 0), 0.6)
            A.add_rot(pose, "head", (0, 0, 25 * k))
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.6, 1.0))
            jaw(pose, 28 * k)                      # ciyak!
            tail(pose, 12 * math.sin(ph * 10) * (1 - ph), -25 * k)
            A.add_rot(pose, "head", (-10 * k, 0, 0))

    return f
