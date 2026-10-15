"""Tilki: ince, sinsi; dar göğüs, ince bel, uzun ince uzuvlar. Turuncu kürk, beyaz gıdı ve
göğüs önü (kabarık önlük tüyleri), siyah "çoraplı" ön kollar ve siyah eller. Dar kafatası,
uzun sivri burun, beyaz yanak tüyleri (geriye taranmış), küçük siyah burun, badem biçimli
çekik altın gözler (yarık gözbebeği), arkası siyah büyük üçgen kulaklar (içi beyaz tüylü,
2 kemik). Ucu beyaz gür kuyruk (4 kemik).

Hareket karakteri: hafif ve hesaplı; parmak ucunda, ayaklar tek çizgide, hafif sinsi
çömelik; kafa önde ve alçak, kuyruk yere paralel süzülür. Beklerken kulakları tek tek
döner, kuyruğunu yavaşça savurur; bakınırken omzunun üstünden sinsice bakar.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.88, 0.45, 0.14),     # turuncu kürk
    "ten2": (0.97, 0.94, 0.88),    # beyaz
    "ten3": (0.12, 0.1, 0.1),      # siyah (kulak arkası, eller, çoraplar)
    "iris": (0.92, 0.66, 0.15),
    "tirnak": (0.15, 0.13, 0.12),
}


def body():
    return O.Body(
        hip_z=0.95, shoulder_z=1.38, shoulder_w=0.16,
        chest=(0.148, 0.102), chest_cy=-0.008, waist=(0.112, 0.078), belly=(0.118, 0.083), hip=(0.132, 0.092), butt=0.006,
        neck_r=0.056, trap=0.7,
        arm=(0.29, 0.27, 0.1), arm_r=(0.039, 0.037, 0.027, 0.033, 0.023),
        leg_r=(0.068, 0.046, 0.048, 0.029), foot_x=0.088, foot_len=1.0, foot_w=0.85,
        neck_pts=[(0, 0.01, 1.38), (0, -0.008, 1.45), (0, -0.025, 1.51)],
        head_c=(0, -0.045, 1.585), head_r=(0.085, 0.1, 0.085), head_top=1.68, spine_lean=4.0, hat_tilt=-4.0,
    )


def head_frame():
    return O.Frame(Vector((0, -0.045, 1.585)), Vector((0, -1, -0.1)), Vector((0, 0, 1)))


HEAD = [
    (-0.09, 0.0, 0.015, 0.015, 0.015, 2.0),
    (-0.075, 0.005, 0.06, 0.06, 0.05, 2.0),
    (-0.035, 0.008, 0.085, 0.078, 0.066, 2.1),
    (0.01, 0.004, 0.088, 0.07, 0.062, 2.2),      # elmacık
    (0.05, -0.008, 0.058, 0.05, 0.05, 2.2),
    (0.1, -0.026, 0.034, 0.032, 0.036, 2.2),     # uzun sivri burun
    (0.145, -0.034, 0.022, 0.021, 0.024, 2.1),
    (0.172, -0.036, 0.012, 0.012, 0.014, 2.0),
    (0.18, -0.036, 0.003, 0.003, 0.003, 2.0),
]


def ear_frame(F, side):
    base = F.p(side * 0.05, -0.03, 0.06)
    up = F.d(side * 0.4, -0.12, 1.0)
    n = F.d(side * 0.3, 1.0, 0.0)
    n = (n - up * n.dot(up)).normalized()
    return base, up, n


def tail_points(B):
    hz = B.hip_z
    y0 = B.hip[1]
    return [Vector((0, y0, hz + 0.02)), Vector((0, y0 + 0.1, hz - 0.08)), Vector((0, y0 + 0.2, hz - 0.2)),
            Vector((0.02, y0 + 0.29, hz - 0.33)), Vector((0.03, y0 + 0.38, hz - 0.43))]


def chains(B):
    F = head_frame()
    out = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, up, n = ear_frame(F, side)
        out.append((f"ear.{sfx}", [base, base + up * 0.06, base + up * 0.12], "head"))
    out.append(("tail", tail_points(B), "hips"))
    return out


def body_paint(B):
    def f(c, n, src):
        if src != "ten":
            return None
        side = 1 if c.x > 0 else -1
        s, e, w, h, d = B.arm_points(side)
        if abs(c.x) > B.shoulder_w - 0.01 and (c - s).dot(d) > B.arm[0] + B.arm[1] * 0.35:
            return "ten3"                                # siyah çoraplar (ön kolun alt yarısı)
        if c.z > B.hip_z + 0.1 and abs(c.x) < 0.08 and n.y < -0.5:
            return "ten2"                                # göğüs önü beyaz
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
    O.neck_skin(m, B, [0.06, 0.056, 0.054], grp="chest|neck", flare=1.9, sub=3, segs=16, into=F.p(0, -0.03, -0.02))
    # Beyaz önlük: gıdıdan göğse kabarık tüyler
    nz = B.neck_pts[1].z
    for i in range(7):
        a = -0.9 + 1.8 * i / 6
        p = Vector((math.sin(a) * 0.055, -0.012 - math.cos(a) * 0.055, nz + 0.01))
        O.tufts(m.bm("ten2", "neck"), p, Vector((math.sin(a) * 0.6, -0.6, -1.0)), 2, 0.035, 0.013, area=0.4)

    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, HEAD, segs=18, sub=3)
    # Yanak tüyleri: elmacıktan geriye ve aşağı taranmış beyaz tutamlar
    for side in (-1, 1):
        for k in range(3):
            p = F.p(side * (0.078 - k * 0.006), 0.025 - k * 0.022, -0.03 - k * 0.012)
            O.cone(m.bm("ten2", "head"), p, p + F.d(side * 0.8, -0.7, -0.35) * 0.05, 0.016, sides=4)
    # Alt çene (beyaz) ve burun
    O.organic(m.bm("ten2", "head"), F.p(0, 0.085, -0.05), F.f, F.u,
              [(-0.06, 0, 0.004, 0.004, 0.004, 2), (-0.03, 0, 0.036, 0.016, 0.018, 2.2), (0.04, 0.006, 0.022, 0.012, 0.013, 2.2),
               (0.075, 0.01, 0.01, 0.006, 0.007, 2), (0.08, 0.01, 0.002, 0.002, 0.002, 2)], segs=12, sub=2)
    O.ellipsoid(m.bm("siyah", "head"), F.p(0, 0.178, -0.03), (0.014, 0.012, 0.012), 8, 5, rot=F.mat())
    for side in (-1, 1):
        O.ribbon(m.bm("agiz", "head"), [F.p(side * 0.006, 0.172, -0.048), F.p(side * 0.02, 0.13, -0.054),
                                         F.p(side * 0.032, 0.09, -0.05)], 0.004, 0.003, u=F.u)
        O.whiskers(m, F, side, 0.02, 0.15, -0.035, n=2, length=0.07, mat="siyah", thick=0.0015, back=0.4)
    # Gözler: badem, çekik (dış köşe yukarı), yarık gözbebeği, ağır kapak: sinsi bakış
    for side in (-1, 1):
        n = F.d(side * 0.6, 0.78, 0.15)
        O.eye(m, O.on_surface(m.bm("ten", "head|neck"), F.p(side * 0.05, 0.05, 0.014), n, r=0.0175, sink=0.68), n, 0.0175, up_hint=F.u, grp="head", iris_k=0.86, pupil="slit", lid=0.3,
              lid_tilt=side * 22, lower_lid=0.2, lower_mat="ten2")
    # Kulaklar: büyük üçgen; arkası siyah (boyama), içi beyaz tüy
    ears = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, up, n = ear_frame(F, side)
        ears.append((base, up, n))
        rings = []
        for t, wid, th in ((-0.012, 0.05, 0.018), (0.03, 0.044, 0.013), (0.07, 0.03, 0.01), (0.105, 0.014, 0.007), (0.125, 0.002, 0.003)):
            rings.append((base + up * t, up, th, wid, n))
        O.loft(m.bm("ten", f"ear.{sfx}"), rings, 6, sub=2, sq=1.6)
        O.tufts(m.bm("ten2", f"ear.{sfx}"), base + up * 0.015 + n * 0.008, up + n * 0.5, 4, 0.04, 0.007, area=1.6)

    fo, ff, fu = F.o, F.f, F.u

    def paint(c, nrm, src):
        if src != "ten":
            return None
        for base, up, n in ears:
            q = c - base
            if -0.01 < q.dot(up) < 0.13 and abs(q.dot(n)) < 0.025 and abs(q.dot(up.cross(n))) < 0.06:
                if nrm.dot(n) < -0.2 or q.dot(up) > 0.085:
                    return "ten3"                          # kulak arkası ve ucu siyah
                return None
        q = c - fo
        d, h = q.dot(ff), q.dot(fu)
        if d > 0.06 and h < -0.03:
            return "ten2"                                  # burnun altı / dudak beyaz
        if c.z < fo.z - 0.06 and nrm.y < -0.35:
            return "ten2"                                  # gıdı
        return None

    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, mat="ten3", fingers=4, finger_len=0.036, finger_r=0.01, palm_w=0.033, palm_t=0.019, palm_len=0.052,
               curl=24, tip_ball=1.15, claw_mat="tirnak", spread=0.85)
    m.build("tur_eller", parts)


def build_tail(B, parts):
    m = O.Mesh()
    pts = tail_points(B)
    pts = [pts[0] + Vector((0, -0.05, 0.02))] + pts + [pts[-1] + Vector((0.01, 0.07, -0.04))]
    # Gür kuyruk: dipte ince, ortada kalın, uçta sivri; tüy pürüzü (dışa kırışık)
    O.path_loft(m.bm("ten", "tail"), pts, [0.028, 0.036, 0.055, 0.07, 0.068, 0.048, 0.008], 12, sub=3, jitter=0.12)
    tip0 = pts[-3]

    def paint(c, n, src):
        if src == "ten" and (c - tip0).dot((pts[-1] - pts[-3]).normalized()) > 0.04:
            return "ten2"                                  # beyaz kuyruk ucu
        return None

    m.build("tur_kuyruk", parts, paint)


STYLE = {
    "frames": 22, "amp": 0.26, "duty": 0.58, "lift": 0.09, "bob": 0.008, "sway": 0.01, "roll": 2.5,
    "twist": 3.0, "lean": 6.0, "arm_swing": 0.08, "arm_fwd": -0.02, "head_stab": 1.0, "toe_out": 0.0, "width": 0.03,
}

PREVIEW = [
    ["ust_kapusonlu", "alt_kot", "ayk_spor"],
    ["ust_takim", "alt_takim", "ayk_kundura", "aks_evrak"],
    ["ust_tisort", "alt_kargo", "ayk_spor", "sapka_kasket"],
    ["ust_kisa", "alt_kot", "ayk_bot", "aks_omuz"],
]

SPRINGS = [["tail.0", "tail.3", 1.0, 0.3, 0.15], ["ear.L.0", "ear.L.1", 3.0, 0.5, 0.0], ["ear.R.0", "ear.R.1", 3.0, 0.5, 0.0]]

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def secondary(A):
    def ears(pose, turn_l, turn_r, flat=0.0):
        for side, sfx, t in ((1, "L", turn_l), (-1, "R", turn_r)):
            A.add_wrot(pose, f"ear.{sfx}.0", Z, -side * t)
            A.add_wrot(pose, f"ear.{sfx}.0", Y, -side * flat)

    def tail(pose, ph, amp, lift):
        for i in range(4):
            A.add_wrot(pose, f"tail.{i}", Z, amp * (0.4 + 0.2 * i) * math.sin(ph - i * 0.7))
            A.add_wrot(pose, f"tail.{i}", X, lift * (1 - 0.2 * i))

    def f(pose, kind, ph, fr):
        if kind == "walk":
            # Kuyruk yere paralel süzülür, hafif salınır; sinsi alçak duruş
            pose["hips"] = (pose["hips"][0], pose["hips"][1], pose["hips"][2] - 0.02)
            tail(pose, ph, 8, 10)
            ears(pose, 3 * math.sin(2 * ph), -3 * math.sin(2 * ph))
        elif kind == "idle":
            tl = 35 * max(0.0, math.sin(ph - 0.5)) ** 4
            tr = 35 * max(0.0, math.sin(ph - 3.2)) ** 4
            ears(pose, tl, tr)
            tail(pose, ph, 16, 4)
            A.add_rot(pose, "head", (0, 0, 7 * math.sin(ph)))
        elif kind == "look":
            # Omzunun üstünden sinsi bakış: gövde de döner, kafa alçak
            k = math.sin(ph)
            A.add_rot(pose, "chest", (0, 18 * k, 0))
            A.spread_neck(pose, (6 * abs(k), 40 * k, 0), 0.5)
            ears(pose, 20 * k, -20 * k)
            tail(pose, ph * 2, 10, 4)
        elif kind == "stumble":
            k = math.sin(math.pi * min(ph * 1.6, 1.0))
            ears(pose, 0, 0, flat=45 * k)
            tail(pose, ph * 8, 10 * (1 - ph), 40 * k)          # kuyruk kabarıp kalkar

    return f
