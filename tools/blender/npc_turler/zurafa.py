"""Zürafa: uzun boylu, ince, uzun bacaklı ve uzun kollu. Yana basık uzun boyun (4 kemik),
ensede koyu yele, ağ desenli benekler (boyanmış yüzler), uzun burunlu kafa, püsküllü
boynuzlar, oynak kulaklar, ağır kapaklı sakin gözler, ince benekli eller, püsküllü kuyruk.

Hareket karakteri: ağır ve uzun adımlı; her adımda boyun dalga gibi hafifçe öne-arkaya ve
yana salınır (zincir boyunca gecikmeli), kafa bakışını sabit tutmaya çalışır; kuyruk
salınır, kulaklar ara ara seğirir. Bakınırken boynunu indirip merakla uzanır.
"""
import math

from mathutils import Vector

import npc_ortak as O

PALETTE = {
    "ten": (0.8, 0.5, 0.2),      # benek (turuncu kahve)
    "ten2": (0.96, 0.87, 0.66),  # ağ çizgileri, burun (krem)
    "ten3": (0.36, 0.2, 0.11),   # yele, boynuz püskülü, kuyruk ucu
    "iris": (0.3, 0.17, 0.08),
    "tirnak": (0.24, 0.16, 0.1),
}

NECK_R = [0.072, 0.064, 0.058, 0.054, 0.052]


def body():
    return O.Body(
        hip_z=1.02, shoulder_z=1.5, shoulder_w=0.18,
        chest=(0.162, 0.104), waist=(0.128, 0.086), belly=(0.132, 0.09), hip=(0.142, 0.096), butt=0.004,
        neck_r=0.072, trap=0.74,
        arm=(0.33, 0.3, 0.115), arm_r=(0.044, 0.041, 0.031, 0.037, 0.025),
        leg_r=(0.074, 0.05, 0.052, 0.033), foot_x=0.1, foot_len=1.05, foot_w=0.9,
        neck_pts=[(0, 0.02, 1.5), (0, 0.006, 1.66), (0, -0.014, 1.81), (0, -0.04, 1.94), (0, -0.07, 2.05)],
        head_c=(0, -0.11, 2.12), head_r=(0.07, 0.09, 0.07), head_top=2.36, hats=False, spine_lean=1.0,
    )


# Kafa çerçevesi: burun öne-aşağı ~25°
def head_frame():
    return O.Frame(Vector((0, -0.1, 2.12)), Vector((0, -0.9, -0.42)), Vector((0, 0, 1)))


HEAD = [
    # öne, yukarı, yarı gen., üst yük., alt yük., köşelilik
    (-0.10, 0.012, 0.012, 0.012, 0.012, 2.0),
    (-0.086, 0.012, 0.044, 0.05, 0.042, 2.0),
    (-0.05, 0.01, 0.064, 0.07, 0.06, 2.2),
    (-0.005, 0.006, 0.07, 0.072, 0.064, 2.4),   # elmacık / gözler
    (0.045, -0.002, 0.058, 0.062, 0.06, 2.5),
    (0.10, -0.01, 0.046, 0.052, 0.054, 2.5),    # burun kemeri
    (0.15, -0.016, 0.044, 0.047, 0.05, 2.4),
    (0.19, -0.02, 0.047, 0.045, 0.048, 2.3),    # dudak şişkinliği
    (0.222, -0.022, 0.039, 0.037, 0.039, 2.1),
    (0.24, -0.022, 0.019, 0.019, 0.021, 2.0),
    (0.246, -0.022, 0.004, 0.004, 0.004, 2.0),
]


def ear_frame(F, side):
    base = F.p(side * 0.058, -0.062, 0.046)
    d = F.d(side * 1.0, -0.5, 0.18)
    n = F.d(side * 0.15, 1.0, 0.25)          # kulak içi öne bakar
    n = (n - d * n.dot(d)).normalized()
    return base, d, n


def chains(B):
    F = head_frame()
    out = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, d, n = ear_frame(F, side)
        out.append((f"ear.{sfx}", [base, base + d * 0.05, base + d * 0.1], "head"))
    hz = B.hip_z
    out.append(("tail", [Vector((0, 0.115, hz + 0.02)), Vector((0, 0.17, hz - 0.08)), Vector((0.01, 0.2, hz - 0.22)),
                         Vector((0.016, 0.205, hz - 0.36)), Vector((0.02, 0.195, hz - 0.48))], "hips"))
    return out


# --- Desen -----------------------------------------------------------------
class Pattern:
    """Zürafa ağ deseni: turuncu hücreler, ince krem sınırlar. Tohumlar yüzeyin kendisinden
    seçilir (eşit boy hücreler). select(c) -> bölge adı ya da None; bölge başına aralık / çizgi."""

    def __init__(self, regions):
        self.regions = regions          # ad -> (aralık, çizgi kalınlığı)
        self.vor = {}

    def region(self, c):
        return "govde"

    def prepare(self, faces):
        pts = {}
        for c, mat in faces:
            if mat == "ten":
                r = self.region(c)
                if r:
                    pts.setdefault(r, []).append(c)
        for r, lst in pts.items():
            self.vor[r] = O.Voronoi.on_surface(lst, self.regions[r][0], seed=len(lst))

    def line(self, c):
        r = self.region(c)
        if r is None or r not in self.vor:
            return False
        return self.vor[r].edge(c) < self.regions[r][1]

    def __call__(self, c, n, src):
        if src != "ten":
            return None
        return "ten2" if self.line(c) else None


def body_paint():
    return Pattern({"govde": (0.07, 0.0055)})


def build(B, parts):
    O.build_body_skin(B, parts, paint=body_paint())
    build_head(B, parts)
    build_hands(B, parts)
    build_tail(B, parts)


def build_head(B, parts):
    F = head_frame()
    m = O.Mesh()

    # Boyun: yana basık (derinlik > genişlik), dipte yakaya oturan geniş kök
    O.neck_skin(m, B, NECK_R, grp="chest|neck", flatten=1.22, flare=1.75, sub=7, segs=28, into=F.p(0, -0.02, 0.0))

    # Kafa
    O.organic(m.bm("ten", "head|neck"), F.o, F.f, F.u, HEAD, segs=18, sub=3)
    # Alt çene hattı: dudak altı hafif çıkıntı
    O.organic(m.bm("ten", "head"), F.p(0, 0.17, -0.035), F.f, F.u,
              [(-0.05, 0, 0.004, 0.004, 0.004, 2), (-0.02, 0, 0.03, 0.02, 0.022, 2.2), (0.04, 0.004, 0.036, 0.02, 0.022, 2.3),
               (0.065, 0.008, 0.02, 0.012, 0.014, 2), (0.072, 0.008, 0.003, 0.003, 0.003, 2)], segs=12, sub=2)

    # Ağız çizgisi ve burun delikleri
    for side in (-1, 1):
        pts = [F.p(side * 0.012, 0.244, -0.03), F.p(side * 0.034, 0.226, -0.032), F.p(side * 0.047, 0.19, -0.03),
               F.p(side * 0.046, 0.158, -0.022)]
        O.ribbon(m.bm("agiz", "head"), pts, 0.006, 0.004, u=F.u)
        O.patch(m.bm("goz", "head"), F.p(side * 0.022, 0.232, 0.006), F.d(side * 0.45, 0.7, 0.55), 0.018, 0.007,
                depth=0.006, sides=6, rot=side * 0.5)
        # Elmacık / kaş çıkıntısı: gözün üstünde yumuşak kemik
        O.ellipsoid(m.bm("ten", "head"), F.p(side * 0.05, 0.01, 0.05), (0.03, 0.04, 0.018), 8, 5, rot=F.mat())

    # Gözler: yanlarda, iri, ağır kapaklı (sakin bakış), kirpikli
    for side in (-1, 1):
        n = F.d(side * 0.82, 0.38, 0.22)
        O.eye(m, F.p(side * 0.058, 0.008, 0.028), n, 0.019, up_hint=F.u, grp="head", iris_k=0.7, lid=0.36,
              lid_tilt=-side * 6, lashes=4, lash_mat="ten3")

    # Boynuzlar (ossikon): hafif geriye eğik, ucu koyu püsküllü
    for side in (-1, 1):
        b = F.p(side * 0.03, -0.045, 0.055)
        t = F.p(side * 0.04, -0.085, 0.15)
        O.path_loft(m.bm("ten", "head"), [b - F.u * 0.02, b, b.lerp(t, 0.6), t], [0.019, 0.015, 0.012, 0.012], 7)
        O.ellipsoid(m.bm("ten3", "head"), t + F.u * 0.006, (0.019, 0.019, 0.017), 8, 5)
        O.tufts(m.bm("ten3", "head"), t + F.u * 0.01, F.u, 4, 0.02, 0.006, area=1.5)

    # Kulaklar: yaprak biçimli, ince; iç yüz krem (boyamayla)
    ears = []
    for side, sfx in ((1, "L"), (-1, "R")):
        base, d, n = ear_frame(F, side)
        ears.append((base, d, n))
        w = d.cross(n).normalized()
        rings = []
        for t, wid, th in ((-0.008, 0.014, 0.012), (0.018, 0.022, 0.012), (0.045, 0.028, 0.011), (0.07, 0.024, 0.009),
                           (0.09, 0.013, 0.007), (0.102, 0.003, 0.004)):
            rings.append((base + d * t, d, th, wid, n))
        O.loft(m.bm("ten", f"ear.{sfx}"), rings, 8, sub=2, sq=2.2)

    # Yele: enseden omuzlara koyu, kısa, dik tüy sırtı
    pts = B.neck_pts
    mane = []
    for i in range(len(pts)):
        p = pts[i]
        r = NECK_R[i] * 1.22
        mane.append(p + Vector((0, r - 0.006, 0)))
    top = F.p(0, -0.07, 0.065)
    mane = [mane[0] + Vector((0, 0.02, -0.05))] + mane + [top]
    rings = []
    for i, p in enumerate(mane):
        a = mane[min(i + 1, len(mane) - 1)] - mane[max(i - 1, 0)]
        h = 0.026 if 0 < i < len(mane) - 1 else 0.012
        rings.append((p, a.normalized(), 0.011, h * 1.15, Vector((1, 0, 0))))
    O.loft(m.bm("ten3", "neck|head"), rings, 6, sub=3)
    for i in range(1, len(mane) - 1):
        for k in range(2):
            p = mane[i].lerp(mane[i + 1], k * 0.5)
            O.tufts(m.bm("ten3", "neck|head"), p + Vector((0, 0.018, 0)), Vector((0, 1, 0.3)), 2, 0.02, 0.006, area=0.5)

    fo = F.o
    ff = F.f

    class HeadPattern(Pattern):
        def region(self, c):
            if (c - fo).length < 0.3 and c.z > 2.0:
                return None if (c - fo).dot(ff) > 0.165 else "kafa"
            return "boyun" if c.z > B.shoulder_z - 0.06 else None

        def __call__(self, c, nrm, src):
            if src != "ten":
                return None
            for base, d, n in ears:             # kulak içi krem
                if (c - base).length < 0.12 and nrm.dot(n) > 0.45:
                    return "ten2"
            if (c - fo).length < 0.3 and c.z > 2.0 and (c - fo).dot(ff) > 0.165:
                return "ten2"                    # burun / dudaklar açık
            return "ten2" if self.line(c) else None

    paint = HeadPattern({"kafa": (0.05, 0.0042), "boyun": (0.085, 0.0062)})
    m.build("tur_bas", parts, paint)


def build_hands(B, parts):
    m = O.Mesh()
    for side in (-1, 1):
        O.hand(m, B, side, fingers=4, finger_len=0.06, finger_r=0.0095, palm_w=0.038, palm_t=0.02, palm_len=0.065,
               nail_mat="tirnak", curl=24)
    m.build("tur_eller", parts, Pattern({"govde": (0.045, 0.004)}))


def build_tail(B, parts):
    m = O.Mesh()
    hz = B.hip_z
    pts = [Vector((0, 0.08, hz + 0.04)), Vector((0, 0.13, hz + 0.0)), Vector((0, 0.17, hz - 0.08)), Vector((0.01, 0.2, hz - 0.22)),
           Vector((0.016, 0.205, hz - 0.36)), Vector((0.02, 0.195, hz - 0.46))]
    O.path_loft(m.bm("ten", "tail"), pts, [0.022, 0.02, 0.016, 0.012, 0.01, 0.008], 7, sub=2)
    end = pts[-1]
    O.ellipsoid(m.bm("ten3", "tail"), end + Vector((0, 0, -0.03)), (0.022, 0.022, 0.05), 7, 5)
    O.tufts(m.bm("ten3", "tail"), end + Vector((0, 0, -0.05)), Vector((0, 0.1, -1)), 7, 0.06, 0.008, area=1.6)
    m.build("tur_kuyruk", parts)


# --- Hareket ---------------------------------------------------------------
STYLE = {
    "frames": 34, "amp": 0.38, "duty": 0.62, "lift": 0.1, "bob": 0.012, "sway": 0.006, "roll": 1.5,
    "twist": 3.0, "lean": 2.0, "arm_swing": 0.09, "head_stab": 0.6, "toe_out": 4.0,
}

PREVIEW = [
    ["ust_takim", "alt_takim", "ayk_kundura", "aks_evrak"],
    ["ust_tisort", "alt_kot", "ayk_spor"],
    ["ust_isci", "alt_kargo", "ayk_bot"],
    ["ust_kapusonlu", "alt_kargo", "ayk_spor"],
]

# Godot yay kemikleri: [kök, uç, sertlik, sönüm, yerçekimi]
SPRINGS = [["ear.L.0", "ear.L.1", 2.2, 0.35, 0.2], ["ear.R.0", "ear.R.1", 2.2, 0.35, 0.2],
           ["tail.0", "tail.3", 0.9, 0.25, 0.6]]

Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))
X = Vector((1, 0, 0))


def secondary(A):
    neck = A.neck
    nn = len(neck)

    def ears(pose, up, back):
        for side, sfx in ((1, "L"), (-1, "R")):
            for i in range(2):
                A.add_wrot(pose, f"ear.{sfx}.{i}", Y, -side * up * (0.6 + 0.4 * i))
                A.add_wrot(pose, f"ear.{sfx}.{i}", Z, side * back * (0.7 + 0.3 * i))

    def tail(pose, swing, lift):
        for i in range(4):
            A.add_wrot(pose, f"tail.{i}", Y, swing[i] if isinstance(swing, list) else swing)
            A.add_wrot(pose, f"tail.{i}", X, lift)

    def f(pose, kind, ph, fr):
        if kind == "walk":
            # Boyun dalgası: adım vuruşunda (2x) öne-arkaya, adım döngüsünde yana; zincir boyunca gecikmeli
            for i, b in enumerate(neck):
                k = (i + 1) / nn
                A.add_rot(pose, b, (2.4 * k * math.sin(2 * ph - 1.0 - i * 0.6), 0,
                                    2.6 * (0.5 + k) * math.sin(ph - 0.7 - i * 0.5)))
            A.add_rot(pose, "head", (-3.2 * math.sin(2 * ph - 1.0 - nn * 0.6), 0, -2.5 * math.sin(ph - 0.7 - nn * 0.5)))
            ears(pose, 4 * math.sin(2 * ph + 0.5), 6 + 3 * math.sin(2 * ph))
            tail(pose, [10 * math.sin(ph - 1.2 - i * 0.7) for i in range(4)], 6 + 3 * math.sin(2 * ph - 1))
        elif kind == "idle":
            for i, b in enumerate(neck):
                A.add_rot(pose, b, (0.8 * math.sin(ph * 2 + i * 0.4), 0.6 * math.sin(ph + i * 0.3), 1.6 * math.sin(ph + i * 0.45)))
            # Kulak seğirmesi (döngüde bir kez, hızlı)
            tw = max(0.0, math.sin((ph - 4.0) * 6)) if 4.0 < ph < 4.0 + math.pi / 6 else 0.0
            ears(pose, 3 + 22 * tw, 8 - 12 * tw)
            tail(pose, [14 * math.sin(ph * 2 - i * 0.8) for i in range(4)], 4)
        elif kind == "look":
            # Merakla boynunu indirip uzanır
            peer = math.sin(ph / 2) ** 2
            A.spread_neck(pose, (10 * peer, 0, 0), 0.0)
            A.add_rot(pose, "head", (-8 * peer, 0, 0))
            ears(pose, 10 * peer, -6 * peer)
            tail(pose, [6 * math.sin(ph * 3 - i) for i in range(4)], 5)
        elif kind == "stumble":
            # Boyun kırbaç gibi: önce geri, sonra öne savrulur; kulaklar yatar, kuyruk kalkar
            for i, b in enumerate(neck):
                k = (i + 1) / nn
                t = ph * math.tau * 1.4 - i * 0.55
                A.add_rot(pose, b, (-9 * k * math.sin(t) * (1 - ph), 0, 4 * k * math.sin(t * 0.7) * (1 - ph)))
            ears(pose, -10 * (1 - ph), 30 * math.sin(math.pi * min(ph * 2, 1)))
            tail(pose, 0, 30 * math.sin(math.pi * ph))

    return f
