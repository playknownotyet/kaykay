"""Kedi: ince, zarif; dar omuz, ince bel, uzun ince kollar. İnce uzun boyun, yanlarda ve
gerdanda tüy yakası (yanak tutamları), açık renk gıdı. Yuvarlak kafatası, kısa ağız,
bıyık yastıkları, pembe üçgen burun, "w" ağız, uzun beyaz bıyıklar, iri yarık gözbebekli
gözler, üçgen kulaklar (içi pembe, tüylü; her biri 2 kemik), alında tekir çizgileri.
Eller pati: kısa parmaklar, pembe avuç ve parmak yastıkları. Uzun ince kuyruk (5 kemik).

Hareket karakteri: zarif, ayaklar neredeyse tek çizgide (podyum yürüyüşü), kalça salınır,
kafa sabit; kuyruk ucu S dalgasıyla salınır, kulaklar ara ara döner. Beklerken kuyruk ucu
seğirir, kulak oynatır; bakınırken kulaklar baktığı yöne döner, kafasını hafif eğer.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.86, 0.55, 0.26),     # turuncu tekir
    "ten2": (0.97, 0.92, 0.84),    # gıdı, ağız, göğüs
    "ten3": (0.6, 0.32, 0.12),     # çizgiler
    "iris": (0.55, 0.78, 0.25),
    "tirnak": (0.92, 0.9, 0.86),
}


def body():
    return O.Body(
        hip_z=0.95, shoulder_z=1.4, shoulder_w=0.165,
        chest=(0.155, 0.1), waist=(0.118, 0.08), belly=(0.124, 0.085), hip=(0.142, 0.095), butt=0.008,
        neck_r=0.058, trap=0.72,
        arm=(0.3, 0.28, 0.1), arm_r=(0.04, 0.038, 0.029, 0.034, 0.024),
        leg_r=(0.07, 0.048, 0.05, 0.03), foot_x=0.095, foot_len=1.0, foot_w=0.9,
        neck_pts=[(0, 0.01, 1.4), (0, -0.0, 1.46), (0, -0.01, 1.51)],
        head_c=(0, -0.02, 1.6), head_r=(0.1, 0.1, 0.1), head_top=1.71, hat_tilt=-4.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.02, 1.6)), Vector((0, -1, -0.05)), Vector((0, 0, 1)))


HEAD = [
    (-0.1, 0.0, 0.015, 0.015, 0.015, 2.0),
    (-0.085, 0.006, 0.07, 0.07, 0.06, 2.0),
    (-0.04, 0.01, 0.1, 0.095, 0.08, 2.1),
    (0.01, 0.006, 0.105, 0.09, 0.08, 2.2),       # elmacık (geniş)
    (0.055, -0.004, 0.085, 0.07, 0.07, 2.2),
    (0.085, -0.014, 0.05, 0.05, 0.05, 2.0),
    (0.098, -0.02, 0.01, 0.01, 0.01, 2.0),
]


def ear_frame(F, side):
    base = F.p(side * 0.058, -0.03, 0.075)
    up = F.d(side * 0.38, -0.08, 1.0)
    n = F.d(side * 0.25, 1.0, 0.0)               # kulak içi öne
    n = (n - up * n.dot(up)).normalized()
    return base, up, n


def chains(B):
    F = head_frame()
    out = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, up, n = ear_frame(F, side)
        out.append((f"ear.{sfx}", [base, base + up * 0.045, base + up * 0.09], "head"))
    out.append(("tail", tail_points(B), "hips"))
    return out


def tail_points(B):
    hz = B.hip_z
    return [Vector((0, B.hip[1] + 0.0, hz + 0.03)), Vector((0, B.hip[1] + 0.13, hz - 0.05)), Vector((0.02, B.hip[1] + 0.24, hz - 0.2)),
            Vector((0.05, B.hip[1] + 0.29, hz - 0.37)), Vector((0.04, B.hip[1] + 0.36, hz - 0.5)), Vector((0.0, B.hip[1] + 0.44, hz - 0.52))]


def stripes(c, F, base="ten"):
    """Tekir çizgileri: alında dikey, yanaklarda yatay; kollar / kuyrukta halka."""
    q = c - F.o
    up = q.dot(F.u)
    if up > 0.03 and q.dot(F.f) > -0.02:
        return math.sin(q.x * 95) > 0.55 and abs(q.x) < 0.06
    if up < 0.03 and abs(q.x) > 0.06 and q.dot(F.f) > -0.04:
        return math.sin(up * 140) > 0.6
    return False


def body_paint(B):
    def f(c, n, src):
        if src != "ten":
            return None
        if c.z > B.hip_z and abs(c.x) < B.chest[0] + 0.03 and n.y < -0.5:
            return "ten2"                                 # göğüs / karın
        return "ten3" if math.sin(c.z * 70 + c.x * 10) > 0.65 else None
    return f


def build(B, parts):
    O.build_body_skin(B, parts, paint=body_paint(B))
    build_head(B, parts)
    build_hands(B, parts)
    build_tail(B, parts)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    O.neck_skin(m, B, [0.064, 0.06, 0.058], grp="chest|neck", flare=1.8, sub=3, segs=16, into=F.p(0, -0.03, -0.02))
    # Yanak tutamları: elmacığın yüzeyinden yana-aşağı taşan kabarık tüy (kafadan boyna akar)
    for side in (-1, 1):
        for k in range(3):
            p = F.p(side * (0.092 - k * 0.008), 0.03 - k * 0.025, -0.035 - k * 0.012)
            O.tufts(m.bm("ten", "head"), p, F.d(side * 1.0, -0.2, -0.6), 2, 0.03, 0.012, area=0.5)
    # Boyun yakası: boyun yüzeyinden çıkan tutamlar (gerdan açık renk)
    nz = B.neck_pts[1].z
    for i in range(10):
        a = math.tau * i / 10
        p = Vector((math.sin(a) * 0.06, -0.005 - math.cos(a) * 0.06, nz + 0.02 * math.cos(a)))
        mat = "ten2" if math.cos(a) > 0.3 else "ten"
        O.tufts(m.bm(mat, "neck"), p, Vector((math.sin(a), -math.cos(a), -0.8)), 2, 0.03, 0.012, area=0.4)

    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, HEAD, segs=18, sub=3)
    # Ağız bölgesi: iki bıyık yastığı + çene
    for side in (-1, 1):
        O.ellipsoid(m.bm("ten2", "head"), F.p(side * 0.024, 0.086, -0.03), (0.03, 0.028, 0.024), 8, 6, rot=F.mat())
    O.ellipsoid(m.bm("ten2", "head"), F.p(0, 0.072, -0.058), (0.028, 0.026, 0.018), 8, 5, rot=F.mat())
    # Burun: pembe ters üçgen
    O.cone(m.bm("pembe", "head"), F.p(0, 0.104, -0.004), F.p(0, 0.112, -0.022), 0.014, sides=3, u=F.u)
    # Ağız çizgisi "w"
    for side in (-1, 1):
        O.ribbon(m.bm("agiz", "head"), [F.p(0, 0.112, -0.026), F.p(side * 0.012, 0.11, -0.04), F.p(side * 0.026, 0.104, -0.036)],
                 0.004, 0.003, u=F.u)
        O.whiskers(m, F, side, 0.035, 0.095, -0.028, n=3, length=0.12, thick=0.0018)
    # Gözler: iri, yarık gözbebekli, hafif çekik
    for side in (-1, 1):
        n = F.d(side * 0.5, 0.85, 0.06)
        O.eye(m, F.p(side * 0.045, 0.072, 0.018), n, 0.022, up_hint=F.u, grp="head", iris_k=0.86, pupil="slit", lid=0.2,
              lid_tilt=side * 12, lower_lid=0.12)
    # Kulaklar: üçgen, ince; iç yüz pembe, kökünde tüy tutamı
    ears = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, up, n = ear_frame(F, side)
        ears.append((base, up, n))
        w = up.cross(n).normalized()
        rings = []
        for t, wid, th in ((-0.012, 0.042, 0.016), (0.02, 0.038, 0.012), (0.05, 0.026, 0.009), (0.075, 0.012, 0.006), (0.095, 0.002, 0.003)):
            rings.append((base + up * t, up, th, wid, n))
        O.loft(m.bm("ten", f"ear.{sfx}"), rings, 6, sub=2, sq=1.6)
        O.tufts(m.bm("ten2", f"ear.{sfx}"), base + up * 0.012 + n * 0.008, up + n * 0.6, 3, 0.03, 0.006, area=1.5)

    fo, ff = F.o, F.f

    def paint(c, nrm, src):
        if src != "ten":
            return None
        for base, up, n in ears:
            q = c - base
            if 0.0 < q.dot(up) < 0.08 and abs(q.dot(n)) < 0.02 and nrm.dot(n) > 0.5:
                return "pembe"
        if (c - fo).length < 0.15 and stripes(c, F):
            return "ten3"
        if c.z < fo.z - 0.06 and nrm.y < -0.4:
            return "ten2"                          # gıdı ve boğaz
        return None

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, fingers=4, finger_len=0.038, finger_r=0.011, palm_w=0.036, palm_t=0.02, palm_len=0.055,
               curl=22, tip_ball=1.2, pad_mat="pembe", spread=0.9)
    m.build("tur_eller", parts, body_paint(B))


def build_tail(B, parts):
    m = O.Mesh()
    pts = tail_points(B)
    pts = [pts[0] + Vector((0, -0.06, 0.02))] + pts
    O.path_loft(m.bm("ten", "tail"), pts, [0.03, 0.03, 0.028, 0.026, 0.025, 0.024, 0.016], 8, sub=3)
    m.build("tur_kuyruk", parts, O.band_paint(pts, 0.07, 0.32, "ten", "ten3", radius=0.06))


STYLE = {
    "frames": 26, "amp": 0.28, "duty": 0.6, "lift": 0.08, "bob": 0.01, "sway": 0.022, "roll": 3.5,
    "twist": 4.0, "lean": 1.0, "arm_swing": 0.1, "head_stab": 1.0, "toe_out": 2.0, "width": 0.035,
}

PREVIEW = [
    ["ust_tisort", "alt_kot", "ayk_spor"],
    ["ust_kisa", "alt_kargo", "ayk_spor", "aks_omuz"],
    ["ust_takim", "alt_takim", "ayk_kundura"],
    ["ust_kapusonlu", "alt_kot", "ayk_bot", "sapka_bere"],
]

SPRINGS = [["tail.0", "tail.4", 0.7, 0.25, 0.25], ["ear.L.0", "ear.L.1", 3.0, 0.5, 0.0], ["ear.R.0", "ear.R.1", 3.0, 0.5, 0.0]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    def ears(pose, turn_l, turn_r, flat=0.0):
        # turn: kulağın dikey eksende dönüşü (+ dışa), flat: geriye yatma
        for side, sfx, t in ((1, "L", turn_l), (-1, "R", turn_r)):
            A.add_wrot(pose, f"ear.{sfx}.0", Z, -side * t)
            A.add_wrot(pose, f"ear.{sfx}.0", Y, -side * flat)

    def tail(pose, ph, amp, lift=0.0, speed=1.0):
        for i in range(5):
            k = 0.4 + 0.15 * i
            A.add_wrot(pose, f"tail.{i}", Y, amp * k * math.sin(ph * speed - i * 0.8))
            A.add_wrot(pose, f"tail.{i}", X, lift * (1 - i * 0.15))

    def f(pose, kind, ph, fr):
        if kind == "walk":
            tail(pose, ph, 14, lift=6 + 2 * math.sin(2 * ph))
            ears(pose, 4 * math.sin(ph * 2), -4 * math.sin(ph * 2))
        elif kind == "idle":
            twitch = max(0.0, math.sin((ph - 2.0) * 5)) if 2.0 < ph < 2.0 + math.pi / 5 else 0.0
            ears(pose, 30 * twitch, 0)
            tail(pose, ph, 10, lift=4)
            # Kuyruk ucu seğirmesi
            A.add_wrot(pose, "tail.4", Y, 18 * math.sin(ph * 6) * max(0.0, math.sin(ph)))
        elif kind == "look":
            look = math.sin(ph) * 30
            ears(pose, look, -look)
            A.add_rot(pose, "head", (0, 0, 8 * math.sin(ph * 2)))
            tail(pose, ph, 8, lift=4, speed=2)
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.6, 1.0))
            ears(pose, 0, 0, flat=40 * k)
            tail(pose, ph * math.tau, 6, lift=35 * k, speed=3)    # kuyruk kabarıp kalkar

    return f
