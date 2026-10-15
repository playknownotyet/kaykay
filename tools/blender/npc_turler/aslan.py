"""Aslan: iri, kaslı; geniş göğüs ve omuzlar, dar kalça, kalın kollar. Kocaman yele: kafanın
arkasını, yanlarını ve boynu saran koyu, katmanlı tutamlar (göğse ve omuzlara taşar).
Geniş kafatası, ağır kaş çıkıntısı, geniş burun köprüsü ve büyük kahve-pembe burun,
tombul bıyık yastıkları, alt çene ayrı kemikte (esner / kükrer: köpek dişleri görünür),
amber gözler (yuvarlak gözbebeği), yelenin içinde küçük yuvarlak kulaklar. Büyük pati
eller (tırnaklı). İnce uzun kuyruk, ucunda koyu püskül (4 kemik).

Hareket karakteri: kendinden emin, ağır çalım: omuzlar yuvarlanır (gövde burgusu büyük),
göğüs önde, kafa dik; adımlar uzun ve yavaş. Beklerken kocaman esner, kuyruk ucu seğirir;
bakınırken ağır ve asil kafa dönüşü; çarpılınca kükrer, kuyruğu kamçılar.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.85, 0.66, 0.38),     # altın sarısı kürk
    "ten2": (0.95, 0.88, 0.72),    # ağız çevresi, gıdı açık
    "ten3": (0.45, 0.26, 0.12),    # yele, kuyruk püskülü
    "iris": (0.85, 0.6, 0.15),
    "tirnak": (0.9, 0.87, 0.8),
}


def body():
    return O.Body(
        hip_z=0.98, shoulder_z=1.5, shoulder_w=0.24,
        chest=(0.225, 0.15), chest_cy=-0.02, waist=(0.165, 0.11), belly=(0.17, 0.115), hip=(0.17, 0.112), butt=0.006,
        neck_r=0.09, trap=0.86,
        arm=(0.32, 0.29, 0.12), arm_r=(0.066, 0.064, 0.048, 0.058, 0.042),
        leg_r=(0.1, 0.07, 0.075, 0.045), foot_x=0.12, foot_len=1.12, foot_w=1.1, hand_scale=1.12,
        neck_pts=[(0, 0.01, 1.5), (0, -0.005, 1.58), (0, -0.02, 1.64)],
        head_c=(0, -0.04, 1.73), head_r=(0.13, 0.14, 0.12), head_top=1.86, hats=False, spine_lean=-1.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.04, 1.73)), Vector((0, -1, -0.12)), Vector((0, 0, 1)))


SKULL = [
    (-0.11, 0.0, 0.02, 0.02, 0.02, 2.0),
    (-0.095, 0.006, 0.085, 0.085, 0.075, 2.0),
    (-0.045, 0.01, 0.12, 0.11, 0.1, 2.2),
    (0.01, 0.008, 0.125, 0.105, 0.1, 2.4),       # geniş elmacık
    (0.06, 0.0, 0.1, 0.09, 0.09, 2.5),           # kaş hizası
    (0.1, -0.022, 0.078, 0.06, 0.075, 2.6),      # geniş burun köprüsü
    (0.135, -0.032, 0.072, 0.05, 0.065, 2.5),
    (0.158, -0.036, 0.06, 0.042, 0.05, 2.3),
    (0.168, -0.036, 0.012, 0.012, 0.012, 2.0),
]


def chains(B):
    F = head_frame()
    hz = B.hip_z
    y0 = B.hip[1]
    return [("jaw", [F.p(0, 0.02, -0.07), F.p(0, 0.13, -0.1)], "head"),
            ("tail", [Vector((0, y0, hz + 0.02)), Vector((0, y0 + 0.15, hz - 0.1)), Vector((0.02, y0 + 0.25, hz - 0.3)),
                      Vector((0.05, y0 + 0.3, hz - 0.5)), Vector((0.08, y0 + 0.42, hz - 0.62))], "hips")]


def build(B, parts):
    O.build_body_skin(B, parts, paint=body_paint(B))
    build_head(B, parts)
    build_hands(B, parts)
    build_tail(B, parts)


def body_paint(B):
    def f(c, n, src):
        if src != "ten":
            return None
        if c.z > B.hip_z + 0.1 and abs(c.x) < 0.1 and n.y < -0.5:
            return "ten2"
        return None
    return f


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()
    O.neck_skin(m, B, [0.1, 0.095, 0.09], grp="chest|neck", flare=1.7, sub=3, segs=18, into=F.p(0, -0.04, -0.03))
    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, SKULL, segs=20, sub=3)
    # Ağır kaş çıkıntısı
    for side in (-1, 1):
        O.ellipsoid(m.bm("ten", "head"), F.p(side * 0.044, 0.068, 0.058), (0.04, 0.03, 0.018), 8, 5, rot=F.mat())
    # Bıyık yastıkları (geniş, tombul), burun (büyük, ters üçgen), bıyıklar
    for side in (-1, 1):
        O.ellipsoid(m.bm("ten2", "head"), F.p(side * 0.032, 0.148, -0.058), (0.04, 0.036, 0.032), 10, 7, rot=F.mat())
        O.whiskers(m, F, side, 0.05, 0.155, -0.055, n=3, length=0.12, mat="ten2", thick=0.0022)
    O.cone(m.bm("ten3", "head"), F.p(0, 0.168, -0.008), F.p(0, 0.178, -0.04), 0.032, sides=3, u=F.u)
    O.ellipsoid(m.bm("ten3", "head"), F.p(0, 0.16, -0.012), (0.03, 0.02, 0.016), 8, 5, rot=F.mat())
    # Ağız içi (koyu) ve üst köpek dişleri
    O.ellipsoid(m.bm("agiz", "head"), F.p(0, 0.1, -0.075), (0.055, 0.06, 0.025), 10, 6, rot=F.mat())
    for side in (-1, 1):
        O.cone(m.bm("beyaz", "head"), F.p(side * 0.03, 0.142, -0.075), F.p(side * 0.028, 0.144, -0.105), 0.008, sides=4)
    # Alt çene: ayrı kemikte; açık renk çene, alt köpek dişleri, dil
    O.organic(m.bm("ten2", "jaw"), F.p(0, 0.09, -0.098), F.f, F.u,
              [(-0.07, 0.01, 0.006, 0.006, 0.006, 2), (-0.04, 0.0, 0.06, 0.02, 0.028, 2.3), (0.03, 0.0, 0.055, 0.016, 0.026, 2.4),
               (0.06, 0.002, 0.04, 0.012, 0.02, 2.2), (0.068, 0.002, 0.006, 0.004, 0.004, 2)], segs=14, sub=2)
    O.ellipsoid(m.bm("dil", "jaw"), F.p(0, 0.1, -0.085), (0.032, 0.04, 0.008), 8, 5, rot=F.mat())
    for side in (-1, 1):
        O.cone(m.bm("beyaz", "jaw"), F.p(side * 0.026, 0.135, -0.092), F.p(side * 0.025, 0.137, -0.072), 0.006, sides=4)
    # Gözler: amber, yuvarlak gözbebeği, ağır (kendinden emin) kapak
    for side in (-1, 1):
        n = F.d(side * 0.5, 0.86, 0.06)
        O.eye(m, O.on_surface(m.bm("ten", "head|neck"), F.p(side * 0.054, 0.08, 0.008), n, r=0.02, sink=0.45), n, 0.02, up_hint=F.u, grp="head", iris_k=0.82, pupil="round",
              lid=0.2, lid_tilt=-side * 6, lower_lid=0.1)
    # Kulaklar: küçük, yuvarlak, yelenin içinden çıkar
    for side in (-1, 1):
        b = F.p(side * 0.085, -0.04, 0.085)
        O.ellipsoid(m.bm("ten", "head"), b, (0.03, 0.012, 0.03), 8, 5, rot=O.axis_rot(F.d(side * 0.3, 1, 0.1), F.u))

    # Yele: alnın arkasından başlayıp kafanın arkasını, yanlarını ve boynu saran dolgun, katmanlı
    # koyu tutamlar. Taban kabuk (dolgunluk) + dışa ve aşağı taranmış kalın, kısa koniler.
    import random
    r = random.Random(17)
    mane_c = F.p(0, -0.075, -0.02)
    O.ellipsoid(m.bm("ten3", "head|neck"), mane_c, (0.165, 0.13, 0.17), 16, 11, rot=F.mat())
    rows = [(65, 9, 0.07, 0.042), (42, 16, 0.085, 0.045), (18, 20, 0.09, 0.046), (-6, 22, 0.095, 0.046),
            (-30, 22, 0.095, 0.045), (-52, 18, 0.085, 0.042)]
    for li, (elev_deg, count, length, rad) in enumerate(rows):
        e = math.radians(elev_deg)
        for i in range(count):
            a = math.tau * (i + 0.5 * (li % 2)) / count + r.uniform(-0.08, 0.08)
            dirv = F.s * (math.cos(a) * math.cos(e)) + (-F.f) * (math.sin(a) * math.cos(e)) + F.u * math.sin(e)
            if dirv.dot(F.f) > 0.35:
                continue                                   # yüzün önü açık
            base = mane_c + F.s * (dirv.dot(F.s) * 0.15) - F.f * (-dirv.dot(F.f) * 0.11) + F.u * (dirv.dot(F.u) * 0.155)
            tip = base + (dirv + Vector((0, 0.2, -0.7))).normalized() * length * r.uniform(0.85, 1.2)
            mat = "ten" if r.random() < 0.08 else "ten3"
            grp = "head" if elev_deg > -10 else "head|neck"
            O.cone(m.bm(mat, grp), base, tip, rad * r.uniform(0.9, 1.15), sides=5, tip_radius=rad * 0.25)
    # Yüzü çevreleyen ön yele kenarı (şakaktan yanaklara, çenenin altına)
    for k in range(11):
        a = math.pi * (-0.1 + 1.2 * k / 10)
        base = F.p(math.cos(a) * 0.118, 0.01, math.sin(a) * 0.085 - 0.04)
        tip = base + F.d(math.cos(a) * 0.7, -0.4, math.sin(a) * 0.3 - 0.5) * 0.065
        O.cone(m.bm("ten3", "head"), base, tip, 0.03, sides=5, tip_radius=0.008)

    fo, ff, fu = F.o, F.f, F.u

    def paint(c, nrm, src):
        if src != "ten":
            return None
        q = c - fo
        if q.dot(ff) > 0.11 and q.dot(fu) < -0.035:
            return "ten2"                      # ağız çevresi
        if c.z < fo.z - 0.09 and nrm.y < -0.4:
            return "ten2"
        return None

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, fingers=4, finger_len=0.045, finger_r=0.016, palm_w=0.05, palm_t=0.03, palm_len=0.065,
               curl=22, tip_ball=1.15, pad_mat="ten3", claw_mat="tirnak", spread=0.85)
    m.build("tur_eller", parts)


def build_tail(B, parts):
    m = O.Mesh()
    hz = B.hip_z
    y0 = B.hip[1]
    pts = [Vector((0, y0 - 0.04, hz + 0.03)), Vector((0, y0, hz + 0.02)), Vector((0, y0 + 0.15, hz - 0.1)),
           Vector((0.02, y0 + 0.25, hz - 0.3)), Vector((0.05, y0 + 0.3, hz - 0.5)), Vector((0.08, y0 + 0.42, hz - 0.62))]
    O.path_loft(m.bm("ten", "tail"), pts, [0.03, 0.03, 0.026, 0.022, 0.02, 0.018], 8, sub=3)
    end = pts[-1]
    O.ellipsoid(m.bm("ten3", "tail"), end + Vector((0.01, 0.02, -0.02)), (0.04, 0.04, 0.055), 8, 6)
    O.tufts(m.bm("ten3", "tail"), end + Vector((0.01, 0.03, -0.04)), Vector((0.2, 0.4, -1)), 6, 0.06, 0.016, area=1.2)
    m.build("tur_kuyruk", parts)


STYLE = {
    "frames": 30, "amp": 0.33, "duty": 0.62, "lift": 0.08, "bob": 0.015, "sway": 0.012, "roll": 3.0,
    "twist": 8.0, "lean": -1.0, "arm_swing": 0.14, "arm_out": 0.04, "head_stab": 0.8, "toe_out": 8.0,
}

PREVIEW = [
    ["ust_takim", "alt_takim", "ayk_kundura"],
    ["ust_tisort", "alt_kot", "ayk_bot"],
    ["ust_isci", "alt_kargo", "ayk_bot"],
    ["ust_kapusonlu", "alt_kot", "ayk_spor", "aks_omuz"],
]

SPRINGS = [["tail.0", "tail.3", 0.8, 0.25, 0.5]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    def jaw(pose, deg):
        A.add_wrot(pose, "jaw.0", X, deg)

    def tail(pose, ph, amp, lift=0.0):
        for i in range(4):
            A.add_wrot(pose, f"tail.{i}", Y, amp * (0.4 + 0.2 * i) * math.sin(ph - i * 0.8))
            A.add_wrot(pose, f"tail.{i}", X, lift)

    def f(pose, kind, ph, fr):
        if kind == "walk":
            # Omuz yuvarlama: göğüs adımla dönerken kafa sabit ve dik
            tail(pose, ph, 12, 4)
        elif kind == "idle":
            # Kocaman esneme (döngünün ortasında): kafa geriye, çene ardına kadar açık
            yawn = max(0.0, math.sin((ph - 1.6) * 1.6)) if 1.6 < ph < 1.6 + math.pi / 1.6 else 0.0
            jaw(pose, 38 * yawn)
            A.spread_neck(pose, (-14 * yawn, 0, 4 * yawn), 0.5)
            A.add_rot(pose, "chest", (-4 * yawn, 0, 0))
            tail(pose, ph * 2, 8)
            A.add_wrot(pose, "tail.3", Y, 25 * math.sin(ph * 7) * max(0.0, math.sin(ph + 2)))
        elif kind == "look":
            tail(pose, ph, 6)
            A.add_rot(pose, "head", (-4 * math.sin(ph), 0, 0))
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.6, 1.0))
            jaw(pose, 32 * k)                     # kükreme
            A.add_rot(pose, "head", (-12 * k, 0, 0))
            tail(pose, ph * 10, 30 * (1 - ph), 10 * k)

    return f
