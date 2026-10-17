"""Şehir planlayıcı: adanın bloklarına binaları, dükkânları, özel binaları, parkları ve kaykay
meydanlarını yerleştirir; bir kroki çizer. Çıktı oyun içi editörün dosyası biçiminde.

  python tools/sehir/sehir_planla.py [cikti_klasoru]        -> plan.json + kroki.png
  python tools/sehir/sehir_planla.py --uygula                -> assets/ada/sehir.json'a yazar

Plan:
  - Meydan çevresi (merkez, meydana ~150 m): kültür ve alışveriş; müze, sinema, kütüphane, otel,
    teknoloji ve kıyafet mağazası, kafe. Caddeler boyunca dükkânlı zemin katlı apartmanlar.
  - Liman (iskelelerin karşısı): kafe, fırın, bakkal (Penguen Market).
  - Mahalleler (iç halkalar, sahil yolu): konutlar (beşik çatılı evler, apartmanlar), aralara
    yayılmış bakkallar (girilebilir).
  - Blok içleri: büyük avlular park (yeşil alan, çevresinde alçak korkuluk), bazıları kaykay
    meydanı (yükselti, korkuluklu merdiven, uzun grind korkuluğu, alçak ledge).
  - Binalar kaldırıma yaslı, ön yüzleri yola bakar; ara ara geçitler bırakılır.
Koordinatlar: ada verisi plan düzleminde (x, y); oyun (x, z = -y).
"""
import json
import math
import os
import random
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ADA = json.load(open(os.path.join(ROOT, "assets", "ada", "ada.json"), encoding="utf-8"))
OUT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.path.join(ROOT, "tests", "tmp", "plan")
APPLY = "--uygula" in sys.argv
rnd = random.Random(7)

# ---------------------------------------------------------------- ızgara
raw = open(os.path.join(ROOT, "assets", "ada", "ada_h.bin"), "rb").read()
NN = len(raw) // 9
N = int(round(math.sqrt(NN)))
STEP = 2.0
EXT = (N - 1) * 0.5 * STEP
hcol = np.frombuffer(raw[: NN * 4], dtype=np.float32).reshape(N, N)
mat = np.frombuffer(raw[NN * 8: NN * 9], dtype=np.uint8).reshape(N, N)
blockH = np.fromfile(os.path.join(ROOT, "assets", "ada", "bloklar.bin"), dtype=np.float32).reshape(N, N)
ROAD, SEA = 5, 0
inner = (blockH > -9000) & (mat != ROAD)           # blok içi (kenar şeridi hariç)
anyblk = blockH > -9000


def cell(x, y):
    i = int(round((x + EXT) / STEP))
    j = int(round((y + EXT) / STEP))
    return min(max(i, 0), N - 1), min(max(j, 0), N - 1)


# Bileşenler (bloklar) ve kenara uzaklık
comp = -np.ones((N, N), dtype=np.int32)
blocks = []
for j0 in range(N):
    for i0 in range(N):
        if not inner[j0, i0] or comp[j0, i0] >= 0:
            continue
        bid = len(blocks)
        q = deque([(i0, j0)])
        comp[j0, i0] = bid
        cells = []
        while q:
            i, j = q.popleft()
            cells.append((i, j))
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ii, jj = i + di, j + dj
                if 0 <= ii < N and 0 <= jj < N and inner[jj, ii] and comp[jj, ii] < 0:
                    comp[jj, ii] = bid
                    q.append((ii, jj))
        blocks.append({"id": bid, "cells": cells})
dist = np.full((N, N), 1e9)
q = deque()
for j in range(N):
    for i in range(N):
        if inner[j, i]:
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ii, jj = i + di, j + dj
                if not (0 <= ii < N and 0 <= jj < N) or not inner[jj, ii]:
                    dist[j, i] = 0
                    q.append((i, j))
                    break
while q:
    i, j = q.popleft()
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ii, jj = i + di, j + dj
        if 0 <= ii < N and 0 <= jj < N and inner[jj, ii] and dist[jj, ii] > dist[j, i] + 1:
            dist[jj, ii] = dist[j, i] + 1
            q.append((ii, jj))
dist_m = dist * STEP

PLAZA = ADA["plaza"]
PC = (PLAZA["x"], PLAZA["y"])
PIERS = ADA.get("piers", [])
HARBOR = (sum(p["x"] for p in PIERS) / len(PIERS) - 40.0, sum(p["y"] for p in PIERS) / len(PIERS)) if PIERS else None
OLD_SHOP = ADA.get("shop")


def zone(x, y):
    if math.hypot(x - PC[0], y - PC[1]) < 150:
        return "merkez"
    if HARBOR and math.hypot(x - HARBOR[0], y - HARBOR[1]) < 110:
        return "liman"
    return "mahalle"


# ---------------------------------------------------------------- dikdörtgenler (plan düzlemi)
placed = []        # {"c": (x, y), "ax": (ux, uy), "hw", "hd"}


def corners(c, ax, hw, hd):
    ux, uy = ax
    vx, vy = -uy, ux
    return [(c[0] + ux * a * hw + vx * b * hd, c[1] + uy * a * hw + vy * b * hd) for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]


def obb_overlap(A, B, pad=0.3):
    for R in (A, B):
        for axis in (R["ax"], (-R["ax"][1], R["ax"][0])):
            def proj(S):
                c = S["c"][0] * axis[0] + S["c"][1] * axis[1]
                ux, uy = S["ax"]
                vx, vy = -uy, ux
                r = abs(ux * axis[0] + uy * axis[1]) * S["hw"] + abs(vx * axis[0] + vy * axis[1]) * S["hd"]
                return c - r, c + r
            a0, a1 = proj(A)
            b0, b1 = proj(B)
            if a1 + pad <= b0 or b1 + pad <= a0:
                return False
    return True


def fits(rect, front_ok=True):
    # Köşeler, kenar ortaları ve merkez blokta olmalı (ön kenar kaldırım şeridinde olabilir)
    c, ax, hw, hd = rect["c"], rect["ax"], rect["hw"], rect["hd"]
    ux, uy = ax
    vx, vy = -uy, ux
    fr = rect.get("front", (vx, vy))           # yola bakan yön (ön kenar kaldırım şeridine değebilir)
    for a in (-1, -0.5, 0, 0.5, 1):
        for b in (-1, -0.5, 0, 0.5, 1):
            ox = ux * a * (hw - 0.3) + vx * b * (hd - 0.3)
            oy = uy * a * (hw - 0.3) + vy * b * (hd - 0.3)
            x, y = c[0] + ox, c[1] + oy
            i, j = cell(x, y)
            toward = (ox * fr[0] + oy * fr[1]) / max(hd - 0.3, 0.01)
            ok = anyblk[j, i] if (toward > 0.6 and front_ok) else inner[j, i]
            if not ok:
                return False
    for o in placed:
        if obb_overlap(rect, o):
            return False
    if OLD_SHOP:
        sx, sy = OLD_SHOP["x"], OLD_SHOP["y"]
        if math.hypot(c[0] - sx, c[1] - sy) < 12:
            return False
    return True


# ---------------------------------------------------------------- öğe üretimi (oyun düzlemi)
items = []
counts = {}


def gdeg_front(nx, ny):
    """Ön yüz yola baksın: plan normali n (yoldan bloğa) -> oyun açısı."""
    fx, fz = -nx, ny                          # oyun (x, z): z = -y
    return round(math.degrees(math.atan2(fx, fz)), 2)


def add_bina(c, n, w, d, extra):
    it = {"t": "bina", "p": [round(c[0], 2), round(-c[1], 2)], "r": gdeg_front(*n), "w": w, "d": d}
    it.update(extra)
    items.append(it)
    counts[extra.get("tur", "ev")] = counts.get(extra.get("tur", "ev"), 0) + 1


def add_shop(door, n, tur, ad):
    items.append({"t": "dukkan", "p": [round(door[0], 2), round(-door[1], 2)], "r": gdeg_front(*n), "tur": tur, "ad": ad})
    counts[tur] = counts.get(tur, 0) + 1


SPECIAL = {  # tür: (en, derinlik, kat, çatı)
    "muze": (16.0, 12.0, 2, "duz"), "sinema": (12.0, 14.0, 2, "duz"), "kafe": (8.0, 7.0, 2, "besik"),
    "otel": (12.0, 10.0, 5, "duz"), "kutuphane": (14.0, 10.0, 2, "besik"), "firin": (7.0, 7.0, 2, "besik"),
}
SHOPW = {"bakkal": (10.4, 9.0), "teknoloji": (9.0, 8.0), "kiyafet": (9.0, 8.0)}
queues = {
    "merkez": ["muze", "sinema", "teknoloji", "kutuphane", "kiyafet", "otel", "kafe"],
    "liman": ["kafe", "bakkal:PENGUEN MARKET", "firin"],
    "mahalle": ["bakkal:TİLKİ BAKKAL", "kafe", "bakkal:KEDİ BAKKAL", "firin", "bakkal:FİL ŞARKÜTERİ"],
}
bakkal_pts = [(OLD_SHOP["x"], OLD_SHOP["y"])] if OLD_SHOP else []
special_pts = []
labels = []        # kroki yazıları: (x, y, metin, renk)


def try_special(kind, p, t, n, zn):
    """kind: özel bina ya da bakkal/mağaza. p kenar noktası, t teğet, n yoldan bloğa."""
    if kind.startswith("bakkal"):
        ad = kind.split(":")[1]
        if any(math.hypot(p[0] - b[0], p[1] - b[1]) < 140 for b in bakkal_pts):
            return 0.0
        w, d = SHOPW["bakkal"]
        door = (p[0] + t[0] * w * 0.5 + n[0] * 0.95, p[1] + t[1] * w * 0.5 + n[1] * 0.95)
        c = (door[0] + n[0] * (d * 0.5 - 0.45), door[1] + n[1] * (d * 0.5 - 0.45))
        rect = {"c": c, "ax": t, "front": (-n[0], -n[1]), "hw": w * 0.5 + 0.2, "hd": d * 0.5}
        if not fits(rect):
            return 0.0
        placed.append(rect)
        add_shop(door, n, "bakkal", ad)
        bakkal_pts.append(door)
        labels.append((c[0], c[1], ad.title(), (255, 210, 60)))
        return w
    if kind in SHOPW:
        w, d = SHOPW[kind]
        door = (p[0] + t[0] * w * 0.5 + n[0] * 0.05, p[1] + t[1] * w * 0.5 + n[1] * 0.05)
        c = (door[0] + n[0] * d * 0.5, door[1] + n[1] * d * 0.5)
        rect = {"c": c, "ax": t, "front": (-n[0], -n[1]), "hw": w * 0.5 + 0.2, "hd": d * 0.5}
        if not fits(rect):
            return 0.0
        placed.append(rect)
        add_shop(door, n, kind, {"teknoloji": "TEKNO DÜNYA", "kiyafet": "MODA KÖŞE"}[kind])
        labels.append((c[0], c[1], {"teknoloji": "Teknoloji", "kiyafet": "Kıyafet"}[kind], (120, 200, 255)))
        return w
    w, d, k, cati = SPECIAL[kind]
    if any(math.hypot(p[0] - s[0], p[1] - s[1]) < 40 for s in special_pts):
        return 0.0
    c = (p[0] + t[0] * w * 0.5 + n[0] * (d * 0.5 + 0.05), p[1] + t[1] * w * 0.5 + n[1] * (d * 0.5 + 0.05))
    extra_front = 3.0 if kind == "muze" else (2.0 if kind == "kutuphane" else (2.5 if kind == "kafe" else 0.0))
    # Müze sütunları / kafe masaları önde: bina o kadar geri çekilir
    c = (c[0] + n[0] * extra_front, c[1] + n[1] * extra_front)
    rect = {"c": c, "ax": t, "front": (-n[0], -n[1]), "hw": w * 0.5 + 0.2, "hd": d * 0.5 + extra_front * 0.5}
    if not fits(rect):
        return 0.0
    placed.append(rect)
    add_bina(c, n, w, d, {"tur": kind, "k": k, "cati": cati})
    special_pts.append(p)
    names = {"muze": "Müze", "sinema": "Sinema", "kafe": "Kafe", "otel": "Otel", "kutuphane": "Kütüphane", "firin": "Fırın"}
    labels.append((c[0], c[1], names[kind], (255, 140, 120)))
    return w


def regular(p, t, n, road_kind, zn, last_style):
    avenue = road_kind == "avenue" or zn == "merkez"
    w = rnd.choice([7.5, 8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0])
    d = rnd.choice([9.0, 10.0, 11.0]) if avenue else rnd.choice([7.0, 8.0, 9.0])
    c = (p[0] + t[0] * w * 0.5 + n[0] * (d * 0.5 + 0.05), p[1] + t[1] * w * 0.5 + n[1] * (d * 0.5 + 0.05))
    rect = {"c": c, "ax": t, "front": (-n[0], -n[1]), "hw": w * 0.5, "hd": d * 0.5}
    if not fits(rect):
        return 0.0, last_style
    s = rnd.randrange(16)
    while s == last_style:
        s = rnd.randrange(16)
    if avenue:
        k = rnd.choice([3, 3, 4, 4, 5])
        extra = {"tur": "ev", "k": k, "s": s, "cati": "duz" if rnd.random() < 0.75 else "besik", "zemin": "dukkan" if rnd.random() < 0.85 else "konut"}
    else:
        k = rnd.choice([1, 2, 2, 2, 3, 3, 4])
        extra = {"tur": "ev", "k": k, "s": s, "cati": "besik" if rnd.random() < 0.6 else "duz", "zemin": "konut" if rnd.random() < 0.75 else "dukkan"}
    placed.append(rect)
    add_bina(c, n, w, d, extra)
    return w, s


# ---------------------------------------------------------------- kaldırım kenarları boyunca
road_kind = {r["id"]: r["kind"] for r in ADA["roads"]}
road_pts = {r["id"]: [(p[0], p[1]) for p in r["pts"]] for r in ADA["roads"]}
runs = []
for run in ADA["sidewalks"]:
    if run["road"] in ("ada", "kose", "plaza"):
        continue
    pts = run["pts"]
    if len(pts) < 2:
        continue
    poly = [(q[2], q[3]) for q in pts]
    inn = [(q[0], q[1]) for q in pts]
    # Dış kenar: yolun orta çizgisine uzak olan (kayıtta iki uç sırası kenara göre değişebilir)
    rp = road_pts.get(run["road"])
    if rp:
        m = len(pts) // 2
        def dline(x, y):
            best = 1e9
            for k in range(len(rp) - 1):
                ax_, ay_ = rp[k]
                bx_, by_ = rp[k + 1]
                dx, dy = bx_ - ax_, by_ - ay_
                L2 = dx * dx + dy * dy or 1
                tt = max(0, min(1, ((x - ax_) * dx + (y - ay_) * dy) / L2))
                best = min(best, math.hypot(ax_ + dx * tt - x, ay_ + dy * tt - y))
            return best
        if dline(*inn[m]) > dline(*poly[m]):
            poly, inn = inn, poly
    L = sum(math.dist(poly[k], poly[k + 1]) for k in range(len(poly) - 1))
    # Bloğa bakan kenar mı? (dışa 4 m)
    mid = len(poly) // 2
    nx, ny = poly[mid][0] - inn[mid][0], poly[mid][1] - inn[mid][1]
    nl = math.hypot(nx, ny) or 1
    tx, ty = poly[mid][0] + nx / nl * 4, poly[mid][1] + ny / nl * 4
    i, j = cell(tx, ty)
    if not inner[j, i]:
        continue
    runs.append({"poly": poly, "inn": inn, "L": L, "kind": road_kind.get(run["road"], "street"), "road": run["road"],
                 "zone": zone(*poly[mid]), "dpc": math.dist(poly[mid], PC)})
# Önce meydana yakın caddeler (özel binalar en iyi yerlere)
runs.sort(key=lambda r: (r["zone"] != "merkez", r["kind"] != "avenue", r["dpc"]))


def frame_at(run, s):
    poly, inn = run["poly"], run["inn"]
    acc = 0.0
    for k in range(len(poly) - 1):
        seg = math.dist(poly[k], poly[k + 1])
        if acc + seg >= s or k == len(poly) - 2:
            u = 0.0 if seg < 1e-6 else min(max((s - acc) / seg, 0.0), 1.0)
            p = (poly[k][0] + (poly[k + 1][0] - poly[k][0]) * u, poly[k][1] + (poly[k + 1][1] - poly[k][1]) * u)
            t = ((poly[k + 1][0] - poly[k][0]) / (seg or 1), (poly[k + 1][1] - poly[k][1]) / (seg or 1))
            ix = inn[k][0] + (inn[k + 1][0] - inn[k][0]) * u
            iy = inn[k][1] + (inn[k + 1][1] - inn[k][1]) * u
            n = (p[0] - ix, p[1] - iy)
            nlen = math.hypot(*n) or 1
            n = (n[0] / nlen, n[1] / nlen)
            # teğet: yürüme yönünde, normale tam dik (binalar s arttıkça ileri dizilir)
            dot = t[0] * n[0] + t[1] * n[1]
            t = (t[0] - n[0] * dot, t[1] - n[1] * dot)
            tl = math.hypot(*t) or 1
            t = (t[0] / tl, t[1] / tl)
            return p, t, n
        acc += seg
    return None


for run in runs:
    s = 4.0
    last = -1
    since_gap = 0
    queue = queues[run["zone"]]
    while s < run["L"] - 6.0:
        fr = frame_at(run, s)
        p, t, n = fr
        # Viraj: 10 m ileride yön çok değiştiyse ilerle
        fr2 = frame_at(run, min(s + 10.0, run["L"]))
        if fr2 and abs(t[0] * fr2[1][1] - t[1] * fr2[1][0]) > 0.22:
            s += 2.0
            continue
        used = 0.0
        if queue:
            for kind in list(queue):
                used = try_special(kind, p, t, n, run["zone"])
                if used > 0:
                    queue.remove(kind)
                    break
        if used <= 0:
            used, last = regular(p, t, n, run["kind"], run["zone"], last)
        if used <= 0:
            s += 2.0
            continue
        s += used + 0.3
        since_gap += 1
        # Ara ara geçit (avluya giriş)
        if since_gap >= rnd.choice([4, 5, 6]):
            s += rnd.choice([5.0, 6.0, 7.0])
            since_gap = 0

# ---------------------------------------------------------------- blok içleri: park ve kaykay meydanı
def hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def simplify(poly, n_max=10):
    poly = list(poly)
    while len(poly) > n_max:
        best, bi = None, 0
        for k in range(len(poly)):
            a, b, c = poly[k - 1], poly[k], poly[(k + 1) % len(poly)]
            area = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
            if best is None or area < best:
                best, bi = area, k
        poly.pop(bi)
    return poly


def gp(p):
    return [round(p[0], 2), round(-p[1], 2)]


parks, skates = [], []
interiors = []
for b in blocks:
    deep = [(i, j) for (i, j) in b["cells"] if dist_m[j, i] >= 22.0]
    if len(deep) * STEP * STEP < 500:
        continue
    interiors.append((len(deep), b, deep))
interiors.sort(key=lambda x: -x[0])
for rank, (n_deep, b, deep) in enumerate(interiors):
    pts = [(-EXT + i * STEP, -EXT + j * STEP) for (i, j) in deep]
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    # En derin nokta (avlunun ortası)
    bi, bj = max(deep, key=lambda c: dist_m[c[1], c[0]])
    mx, my = -EXT + bi * STEP, -EXT + bj * STEP
    # Ana eksen (PCA): kaykay meydanı bu yöne hizalı
    xs = np.array([p[0] - cx for p in pts])
    ys = np.array([p[1] - cy for p in pts])
    cov = np.cov(np.vstack([xs, ys]))
    w_, v_ = np.linalg.eigh(cov)
    ax = (float(v_[0, 1]), float(v_[1, 1]))
    skate = rank in (0, 2, 4) and dist_m[bj, bi] >= 30.0
    park_pts = pts
    if skate:
        # Kaykay meydanı: yükselti + korkuluklu merdiven + uzun grind korkuluğu + alçak ledge
        ux, uy = ax
        vx, vy = -uy, ux
        P = (mx, my)
        plat_c = (P[0] - vx * 4.0, P[1] - vy * 4.0)
        items.append({"t": "yukselti", "p": gp(plat_c), "r": gdeg_front(vx, vy), "w": 12.0, "d": 7.0, "h": 1.1, "s": 14})
        # Merdiven: platformun ön kenarına (v yönünde), ortadan
        a = (plat_c[0] + vx * (3.5 + 4.2), plat_c[1] + vy * (3.5 + 4.2))
        bb = (plat_c[0] + vx * 3.0, plat_c[1] + vy * 3.0)
        items.append({"t": "merdiven", "a": gp(a), "b": gp(bb), "w": 3.0, "korkuluk": True})
        # Uzun grind korkuluğu (u yönünde) ve alçak ledge
        r0 = (P[0] + vx * 9.0 - ux * 9.0, P[1] + vy * 9.0 - uy * 9.0)
        r1 = (P[0] + vx * 9.0 + ux * 9.0, P[1] + vy * 9.0 + uy * 9.0)
        items.append({"t": "korkuluk", "pts": [gp(r0), gp(r1)], "h": 0.55})
        led_c = (P[0] + vx * 14.0 + ux * 4.0, P[1] + vy * 14.0 + uy * 4.0)
        items.append({"t": "yukselti", "p": gp(led_c), "r": gdeg_front(vx, vy), "w": 8.0, "d": 2.0, "h": 0.45, "s": 7})
        skates.append((P, ax))
        # Meydanın altı Arnavut kaldırımı (park çimi buraya taşmasın): geniş "ara sokak" boyası
        items.append({"t": "yol", "pts": [gp((P[0] - ux * 10.0 + vx * 3.0, P[1] - uy * 10.0 + vy * 3.0)), gp((P[0] + ux * 10.0 + vx * 3.0, P[1] + uy * 10.0 + vy * 3.0))], "w": 32.0})
        labels.append((P[0], P[1], "Kaykay meydanı", (255, 160, 60)))
        # Park meydanın dışında kalan avluda (merkeze 20 m'den uzak hücreler)
        park_pts = [p for p in pts if math.hypot(p[0] - P[0], p[1] - P[1]) > 24.0]
    if len(park_pts) * STEP * STEP < 300:
        continue
    poly = simplify(hull(park_pts), 10)
    # Hull içbükey avludan taşmasın: köşeleri avlu merkezine doğru biraz çek
    poly = [(p[0] + (cx - p[0]) * 0.08, p[1] + (cy - p[1]) * 0.08) for p in poly]
    items.append({"t": "yesil", "pts": [gp(p) for p in poly]})
    parks.append(poly)
    # Parkın en uzun iki kenarına alçak korkuluk (grind yapılabilir)
    edges = sorted(range(len(poly)), key=lambda k: -math.dist(poly[k], poly[(k + 1) % len(poly)]))[:2]
    for k in edges:
        a, c2 = poly[k], poly[(k + 1) % len(poly)]
        if math.dist(a, c2) < 8:
            continue
        a2 = (a[0] + (c2[0] - a[0]) * 0.15, a[1] + (c2[1] - a[1]) * 0.15)
        c3 = (a[0] + (c2[0] - a[0]) * 0.85, a[1] + (c2[1] - a[1]) * 0.85)
        items.append({"t": "korkuluk", "pts": [gp(a2), gp(c3)], "h": 0.5})
    if not skate:
        labels.append((cx, cy, "Park", (120, 220, 120)))

# Zürafa Bakkal (adanın ilk dükkânı) olduğu gibi kalır
old = json.load(open(os.path.join(ROOT, "assets", "ada", "sehir.json"), encoding="utf-8"))["items"]
keep = [it for it in old if it.get("t") == "dukkan" and str(it.get("ad", "")).upper() == "ZÜRAFA BAKKAL"]
if OLD_SHOP:
    labels.append((OLD_SHOP["x"], OLD_SHOP["y"], "Zürafa Bakkal", (255, 210, 60)))
final = keep + items
for k, it in enumerate(final):
    it["id"] = k + 1

os.makedirs(OUT, exist_ok=True)
json.dump({"items": final}, open(os.path.join(OUT, "plan.json"), "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
summary = {k: v for k, v in sorted(counts.items())}
print("PLAN:", len(final), "öge", summary, "park", len(parks), "kaykay", len(skates), "kenar", len(runs))

# ---------------------------------------------------------------- kroki
xs_all = [p[0] for r in ADA["roads"] for p in r["pts"]]
ys_all = [p[1] for r in ADA["roads"] for p in r["pts"]]
x0, x1 = min(xs_all) - 30, max(xs_all) + 30
y0, y1 = min(ys_all) - 30, max(ys_all) + 30
S = 2.2
W, H = int((x1 - x0) * S), int((y1 - y0) * S)


def P(x, y):
    return ((x - x0) * S, (y1 - y) * S)


img = Image.new("RGB", (W, H + 150), (70, 110, 170))
dr = ImageDraw.Draw(img)
# Kara, bloklar
land = np.zeros((N, N, 3), dtype=np.uint8)
land[...] = (70, 110, 170)
land[mat != SEA] = (120, 175, 105)
land[anyblk] = (205, 196, 178)
land_img = Image.fromarray(land[::-1, :, :])            # plan y yukarı
# Izgarayı kroki koordinatına yerleştir
lw = int(N * STEP * S)
land_img = land_img.resize((lw, lw), Image.NEAREST)
img.paste(land_img, (int((-EXT - STEP * 0.5 - x0) * S), int((y1 - EXT - STEP * 0.5) * S)))
# Parklar
for poly in parks:
    dr.polygon([P(*p) for p in poly], fill=(110, 190, 95), outline=(70, 140, 70))
# Yollar
for r in ADA["roads"]:
    pts = [P(p[0], p[1]) for p in r["pts"]]
    if r.get("closed"):
        pts.append(pts[0])
    dr.line(pts, fill=(235, 232, 225), width=int((r["width"] + 6) * S))
for r in ADA["roads"]:
    pts = [P(p[0], p[1]) for p in r["pts"]]
    if r.get("closed"):
        pts.append(pts[0])
    dr.line(pts, fill=(78, 80, 92), width=int(r["width"] * S))
# Binalar
TYPE_COL = {"ev": None, "muze": (240, 235, 220), "sinema": (150, 40, 60), "kafe": (140, 220, 200), "otel": (230, 200, 150),
            "kutuphane": (160, 80, 60), "firin": (240, 200, 110)}
STYLE_COL = [(242, 184, 192), (185, 227, 207), (243, 226, 191), (184, 90, 69), (205, 187, 230), (232, 193, 90), (169, 207, 238), (183, 180, 174),
             (217, 138, 98), (127, 155, 176), (227, 196, 106), (244, 165, 150), (167, 178, 122), (62, 74, 107), (217, 201, 163), (246, 199, 161)]
for it in final:
    if it["t"] == "bina":
        c = (it["p"][0], -it["p"][1])
        r = math.radians(it["r"])
        # oyun ekseni x = (cos r, -sin r) (x, z) -> plan (cos r, sin r)
        ax = (math.cos(r), math.sin(r))
        cs = corners(c, ax, it["w"] * 0.5, it["d"] * 0.5)
        col = TYPE_COL.get(it.get("tur", "ev")) or STYLE_COL[int(it.get("s", 0)) % 16]
        dr.polygon([P(*q) for q in cs], fill=col, outline=(40, 40, 50))
    elif it["t"] == "dukkan":
        door = (it["p"][0], -it["p"][1])
        r = math.radians(it["r"])
        ax = (math.cos(r), math.sin(r))
        fwd = (math.sin(r), -math.cos(r))                     # oyun +Z (ön) -> plan
        w, d = SHOPW.get(it["tur"], (10, 9))
        c = (door[0] - fwd[0] * d * 0.5, door[1] - fwd[1] * d * 0.5)
        cs = corners(c, ax, w * 0.5, d * 0.5)
        col = (255, 205, 60) if it["tur"] == "bakkal" else (110, 180, 250)
        dr.polygon([P(*q) for q in cs], fill=col, outline=(40, 40, 50))
    elif it["t"] == "yukselti":
        c = (it["p"][0], -it["p"][1])
        r = math.radians(it["r"])
        cs = corners(c, (math.cos(r), math.sin(r)), it["w"] * 0.5, it["d"] * 0.5)
        dr.polygon([P(*q) for q in cs], fill=(255, 150, 60), outline=(120, 60, 20))
    elif it["t"] == "merdiven":
        dr.line([P(it["a"][0], -it["a"][1]), P(it["b"][0], -it["b"][1])], fill=(255, 110, 40), width=int(3 * S))
    elif it["t"] == "korkuluk":
        dr.line([P(q[0], -q[1]) for q in it["pts"]], fill=(60, 60, 70), width=2)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 15)
    big = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 30)
    small = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 15)
except OSError:
    font = big = small = ImageFont.load_default()
for (x, y, text, col) in labels:
    px, py = P(x, y)
    tw = dr.textlength(text, font=font)
    dr.rounded_rectangle([px - tw / 2 - 4, py - 11, px + tw / 2 + 4, py + 10], 4, fill=(30, 30, 40))
    dr.text((px - tw / 2, py - 10), text, fill=col, font=font)
# Bölge adları
for name, pos in (("MEYDAN", PC), ("LİMAN", HARBOR)):
    if pos:
        px, py = P(*pos)
        dr.text((px - 50, py - 18), name, fill=(255, 255, 255), font=big, stroke_width=3, stroke_fill=(30, 30, 40))
hpos = (-215, 135)
px, py = P(*hpos)
dr.text((px - 30, py - 18), "TEPE", fill=(255, 255, 255), font=big, stroke_width=3, stroke_fill=(30, 30, 40))
# Lejant
ly = H + 12
legend = [((205, 196, 178), "Arnavut kaldırımı (blok)"), ((242, 184, 192), "Bina (renk = cephe stili)"), ((255, 205, 60), "Bakkal (girilebilir)"),
          ((110, 180, 250), "Mağaza (teknoloji, kıyafet)"), ((150, 40, 60), "Özel bina"), ((110, 190, 95), "Park"),
          ((255, 150, 60), "Kaykay: yükselti / merdiven")]
x = 20
for col, text in legend:
    dr.rectangle([x, ly, x + 22, ly + 22], fill=col, outline=(30, 30, 40))
    dr.text((x + 30, ly), text, fill=(255, 255, 255), font=small)
    x += 40 + int(dr.textlength(text, font=small)) + 20
    if x > W - 300:
        x = 20
        ly += 34
dr.text((20, ly + 40), "%d bina, %d dükkân, %d özel bina, %d park, %d kaykay meydanı" % (
    counts.get("ev", 0), sum(counts.get(k, 0) for k in ("bakkal", "teknoloji", "kiyafet")) + len(keep),
    sum(counts.get(k, 0) for k in SPECIAL), len(parks), len(skates)), fill=(255, 255, 255), font=small)
img.save(os.path.join(OUT, "kroki.png"))
print("KROKI", os.path.join(OUT, "kroki.png"), img.size)

if APPLY:
    json.dump({"items": final}, open(os.path.join(ROOT, "assets", "ada", "sehir.json"), "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
    print("UYGULANDI: assets/ada/sehir.json")
