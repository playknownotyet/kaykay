"""Adanın peyzajını üretir: ağaç, çalı, ot öbeği ve kaya yerleri -> assets/ada/peyzaj.json

  python tools/sehir/peyzaj_uret.py            (sonra Godot'ta tools/sehir/peyzaj_dogrula.tscn: sokak
                                               eşyası / bina ile çakışanları ayıklar)

Kurallar
  - Yalnız boş arazi: deniz, yol + kaldırım (+pay), kavşak, yaya yolları (NPC), binalar, dükkânlar
    (kapı önü dahil), ara sokaklar, merdivenler, yükseltiler, korkuluklar, iskeleler, doğuş noktası
    ve şehir blokları (Arnavut kaldırımı) dışı. Yeşil alanlar (sehir.json "yesil") boyayı kaldırır:
    şehrin içindeki yeşil alanlar ekilir.
  - Dağ: yükseklikle değişen karışık orman (tepede köknar, ortada fıstık çamı + yapraklılar, eteklerde
    zeytin, çınar, erguvan); gürültüyle açıklıklar; aynı türler öbek öbek (her tür kendi gürültüsüyle).
    Seyir Tepesi açık kalır (manzara). Dik yamaçlarda kaya.
  - Ova (şehir dışı çimen): korular ve tek tük ağaçlar.
  - Şehrin yeşil alanları: ağaçlar, kenarlarda çiçekli çalılar, servi çiftleri; çocuk parkının çevresi.
  - Kumsal: halka yolun deniz tarafında palmiyeler.
  - Ağaç diplerinde çalı / ot öbekleri / kaya.
Biçim: {"v": 1, "items": [[tur, x, z, yon_derece, olcek], ...]} (dünya x, z)
"""
import json
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ADA = os.path.join(ROOT, "assets", "ada")
rnd = random.Random(20261018)
np.random.seed(7)

d = json.load(open(os.path.join(ADA, "ada.json"), encoding="utf-8"))
city = json.load(open(os.path.join(ADA, "sehir.json"), encoding="utf-8"))
g = d["grid"]
n, ext, step = int(g["n"]), float(g["ext"]), float(g["step"])
raw = np.fromfile(os.path.join(ADA, "ada_h.bin"), dtype=np.uint8)
H2 = np.frombuffer(raw[n * n * 4:n * n * 8].tobytes(), dtype=np.float32).reshape(n, n)[::-1, :]
M2 = raw[n * n * 8:n * n * 9].reshape(n, n)[::-1, :]
blk = np.fromfile(os.path.join(ADA, "bloklar.bin"), dtype=np.float32).reshape(n, n)[::-1, :] > -9000.0

# 1 m ızgara: piksel (i, r) <-> dünya (x = -ext + i, z = -ext + r)
N = int(ext * 2) + 1
src = np.arange(N) / step
i0 = np.clip(np.floor(src).astype(int), 0, n - 2)
f = src - i0
hr = H2[i0, :] * (1 - f)[:, None] + H2[i0 + 1, :] * f[:, None]
H = hr[:, i0] * (1 - f)[None, :] + hr[:, i0 + 1] * f[None, :]
near = np.clip(np.round(src).astype(int), 0, n - 1)
M = M2[near][:, near]
PAVE = blk[near][:, near]
SEA, SAND, GRASS, ROCK, SOIL, ROAD = range(6)
gz, gx = np.gradient(H, 1.0)
SLOPE = np.degrees(np.arctan(np.sqrt(gx * gx + gz * gz)))


def px(x, z):
    return (x + ext, z + ext)


def wp(p):          # plan (x, y) -> dünya (x, z)
    return (float(p[0]), -float(p[1]))


# ---------- Engel maskesi ----------
block = Image.new("L", (N, N), 0)
dr = ImageDraw.Draw(block)


def line(pts, w):
    pp = [px(*p) for p in pts]
    if len(pp) >= 2:
        dr.line(pp, fill=255, width=max(int(round(w)), 1), joint="curve")
    for p in pp:
        r = w * 0.5
        dr.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)


def circle(c, r):
    p = px(*c)
    dr.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)


def poly(pts, grow=0.0):
    pp = [px(*p) for p in pts]
    dr.polygon(pp, fill=255)
    if grow > 0:
        dr.line(pp + [pp[0]], fill=255, width=int(grow * 2 + 1))


SIDEWALK = float(d.get("sidewalk", 3))
for r in d["roads"]:
    pts = [wp(p) for p in r["pts"]]
    if r.get("closed"):
        pts.append(pts[0])
    line(pts, float(r["width"]) + SIDEWALK * 2 + 3.0)
for disc in d["discs"]:
    circle(wp((disc["x"], disc["y"])), float(disc["r"]) + SIDEWALK + 2.5)
pl = d["plaza"]
circle(wp((pl["x"], pl["y"])), float(pl["r"]) + 4.0)
sp = d["spawn"]
circle(wp((sp["x"], sp["y"])), 8.0)
walk_nodes = [wp(nd) for nd in d["walk"]["nodes"]]
for e in d["walk"]["edges"]:
    line([walk_nodes[int(e[0])], walk_nodes[int(e[1])]], 3.0)
for p in d["piers"]:
    cx, cz, a = p["x"], -p["y"], p["angle"]
    ux, uz = math.cos(a), -math.sin(a)
    vx, vz = -uz, ux
    hl, hw = p["length"] * 0.5 + 2, p["width"] * 0.5 + 2
    poly([(cx + ux * sx * hl + vx * sz * hw, cz + uz * sx * hl + vz * sz * hw) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
st = d.get("street", {})
for o in st.get("crosswalks", []):
    circle(wp((o["c"][0], o["c"][1])), float(o.get("w", 4)) * 0.6 + 2.0)
for key in ("lights", "signs", "billboards", "props"):
    for o in st.get(key, []):
        circle(wp((o["p"][0], o["p"][1])), 2.0 if key != "billboards" else 4.0)

SHOP_SIZE = {"bakkal": (10.4, 9.0), "teknoloji": (9.0, 8.0), "kiyafet": (9.0, 8.0)}


def rect(c, r_deg, w, dd, grow):
    a = math.radians(r_deg)
    # Godot: Basis(UP, a) * (x, 0, z) -> (x cos a + z sin a, -x sin a + z cos a)
    out = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        lx, lz = sx * (w * 0.5 + grow), sz * (dd * 0.5 + grow)
        out.append((c[0] + lx * math.cos(a) + lz * math.sin(a), c[1] - lx * math.sin(a) + lz * math.cos(a)))
    return out


def local(c, r_deg, lx, lz):
    a = math.radians(r_deg)
    return (c[0] + lx * math.cos(a) + lz * math.sin(a), c[1] - lx * math.sin(a) + lz * math.cos(a))


greens = []
parks = []
for it in city["items"]:
    t = it["t"]
    if t in ("bina", "yukselti"):
        poly(rect(it["p"], float(it.get("r", 0)), float(it.get("w", 9)), float(it.get("d", 8)), 1.8))
    elif t == "park":
        parks.append(it)
        poly(rect(it["p"], float(it.get("r", 0)), float(it.get("w", 30)), float(it.get("d", 24)), 1.2))
    elif t == "dukkan":
        w, dd = SHOP_SIZE.get(it.get("tur", "bakkal"), (10.4, 9.0))
        r = float(it.get("r", 0))
        c = it["p"]
        pts = [local(c, r, sx * (w * 0.5 + 1.5), sz) for sx, sz in ((-1, 6.0), (1, 6.0), (1, -dd - 1.5), (-1, -dd - 1.5))]
        poly(pts)
    elif t == "yol":
        line([tuple(q) for q in it["pts"]], float(it.get("w", 2.6)) + 2.5)
    elif t == "korkuluk":
        line([tuple(q) for q in it["pts"]], 2.5)
    elif t == "merdiven":
        line([tuple(it["a"]), tuple(it["b"])], float(it.get("w", 2.4)) + 3.0)
    elif t == "yesil":
        greens.append([tuple(q) for q in it["pts"]])

BLOCK = np.array(block) > 0
green_img = Image.new("L", (N, N), 0)
gd = ImageDraw.Draw(green_img)
for gpts in greens:
    gd.polygon([px(*p) for p in gpts], fill=255)
GREEN = np.array(green_img) > 0
LAND = (H > 0.9) & (M != SEA)
FREE = LAND & ~BLOCK & (~PAVE | GREEN) & (M != ROAD)

# ---------- Gürültü ----------

def value_noise(cell, seed):
    rs = np.random.RandomState(seed)
    k = int(N / cell) + 3
    grid = rs.rand(k, k)
    s = np.arange(N) / cell
    a = np.floor(s).astype(int)
    t = s - a
    t = t * t * (3 - 2 * t)
    r0 = grid[a, :] * (1 - t)[:, None] + grid[a + 1, :] * t[:, None]
    return r0[:, a] * (1 - t)[None, :] + r0[:, a + 1] * t[None, :]


N_FOREST = value_noise(70, 1) * 0.65 + value_noise(25, 2) * 0.35
N_DENSE = value_noise(18, 3)
SPECIES_N = {}


def species_noise(name):
    if name not in SPECIES_N:
        SPECIES_N[name] = value_noise(45, 100 + len(SPECIES_N))
    return SPECIES_N[name]


hill = d["plan"]["hill"]
HC = wp((hill["x"], hill["y"]))
HR = float(hill["radius"])
summit = None
for r in d["roads"]:
    if r["id"] == "summit":
        xs = [p[0] for p in r["pts"]]
        ys = [p[1] for p in r["pts"]]
        summit = wp((sum(xs) / len(xs), sum(ys) / len(ys)))
ETEK = float(d.get("etekH", 15.0))


def at(arr, x, z):
    i, r = int(round(x + ext)), int(round(z + ext))
    if i < 0 or r < 0 or i >= N or r >= N:
        return None
    return arr[r, i]


def free(x, z, slope_max=34.0):
    v = at(FREE, x, z)
    if not v:
        return False
    return at(SLOPE, x, z) <= slope_max


# ---------- Yerleştirme (değişken aralıklı dart atma) ----------

items = []
trunks = []          # (x, z, aralık) -- ağaç gövdeleri
smalls = []          # (x, z, r) -- çalı / kaya
CELL = 4.0
grid_t = {}
grid_s = {}


def _key(x, z):
    return (int(math.floor(x / CELL)), int(math.floor(z / CELL)))


def near_any(grid, x, z, dist, own=True):
    """own: komşunun kendi aralığı da sayılır (ağaçlar arası); False: yalnız dist (çalı - gövde)."""
    kx, kz = _key(x, z)
    R = int(math.ceil((dist if not own else max(dist, 32.0)) / CELL)) + 1
    for i in range(kx - R, kx + R + 1):
        for j in range(kz - R, kz + R + 1):
            for (qx, qz, qr) in grid.get((i, j), ()):
                lim = max(dist, qr) if own else dist
                if (qx - x) ** 2 + (qz - z) ** 2 < lim * lim:
                    return True
    return False


def add_tree(tur, x, z, spacing, scale=None):
    items.append([tur, round(x, 2), round(z, 2), round(rnd.uniform(-180, 180), 1), round(scale or rnd.uniform(0.82, 1.18), 2)])
    grid_t.setdefault(_key(x, z), []).append((x, z, spacing))
    trunks.append((x, z))


def add_small(tur, x, z, r, scale=None, rot=None):
    items.append([tur, round(x, 2), round(z, 2), round(rot if rot is not None else rnd.uniform(-180, 180), 1),
                  round(scale or rnd.uniform(0.8, 1.2), 2)])
    grid_s.setdefault(_key(x, z), []).append((x, z, r))


def pick(weights, x, z):
    # Her türün ağırlığı kendi gürültüsüyle çarpılır: aynı türler öbek öbek
    best, tot = None, 0.0
    ws = []
    for name, w in weights:
        k = w * (0.25 + 1.5 * at(species_noise(name), x, z) ** 2)
        ws.append((name, k))
        tot += k
    u = rnd.uniform(0, tot)
    for name, k in ws:
        u -= k
        if u <= 0:
            return name
    return ws[-1][0]


def zone(x, z):
    h = at(H, x, z)
    dh = math.hypot(x - HC[0], z - HC[1])
    if dh < HR * 1.02 and h > ETEK - 4.0:
        return "dag"
    if at(GREEN, x, z):
        return "yesil"
    m = at(M, x, z)
    if m == SAND:
        return "kum"
    return "ova"


W_DAG_UST = [("koknar_1", 3), ("koknar_2", 2), ("koknar_3", 2), ("fistikcami_1", 1.5), ("fistikcami_2", 1), ("cinar_2", 0.6)]
W_DAG_ORTA = [("fistikcami_1", 2), ("fistikcami_2", 1.6), ("koknar_1", 1.2), ("koknar_3", 0.8), ("cinar_1", 1), ("ihlamur", 0.8), ("zeytin", 0.8), ("erguvan", 0.3)]
W_DAG_ALT = [("zeytin", 2), ("cinar_1", 1.2), ("cinar_3", 1), ("ihlamur", 1), ("fistikcami_2", 1), ("erguvan", 0.5), ("servi_1", 0.4)]
W_OVA = [("cinar_1", 1.2), ("cinar_3", 0.9), ("ihlamur", 1), ("zeytin", 1.4), ("erguvan", 0.5), ("fistikcami_2", 0.6), ("servi_2", 0.3)]
W_YESIL = [("cinar_1", 1), ("cinar_2", 0.8), ("ihlamur", 1), ("erguvan", 0.9), ("zeytin", 0.6), ("servi_1", 0.7)]
BUSH = [("cali_1", 3), ("cali_2", 2.5), ("cali_3", 2), ("cali_grup_1", 1.4), ("cali_grup_2", 1), ("cali_grup_3", 1),
        ("cali_pembe", 0.7), ("cali_sari", 0.6), ("cali_beyaz", 0.6)]
BUSH_CITY = [("cali_pembe", 1.5), ("cali_sari", 1.2), ("cali_beyaz", 1.2), ("cali_1", 1), ("cali_3", 1), ("cali_grup_2", 0.8)]


def spacing_for(x, z, zn):
    nf = at(N_FOREST, x, z)
    nd = at(N_DENSE, x, z)
    h = at(H, x, z)
    if zn == "dag":
        if summit and math.hypot(x - summit[0], z - summit[1]) < 32:
            return None
        if nf > 0.27:
            return 4.8 + 3.2 * (1 - nd)
        return 13.0
    if zn == "ova":
        if nf > 0.6:
            return 8.0 + 3.0 * (1 - nd)
        return 30.0 if nf > 0.4 else None
    if zn == "yesil":
        # Park gibi: öbekler ve aralarında çimen
        return 10.0 + 6.0 * (1 - nd) if nf > 0.35 else 22.0
    if zn == "kum":
        return 13.0 if nd > 0.35 and h > 1.2 else None
    return None


def tree_for(x, z, zn):
    h = at(H, x, z)
    if zn == "dag":
        w = W_DAG_UST if h > 58 else (W_DAG_ORTA if h > 34 else W_DAG_ALT)
        return pick(w, x, z)
    if zn == "ova":
        return pick(W_OVA, x, z)
    if zn == "yesil":
        return pick(W_YESIL, x, z)
    if zn == "kum":
        return "palmiye_1" if rnd.random() < 0.55 else "palmiye_2"
    return None


cands = []
STEP = 2.2
for zi in np.arange(-ext + 1, ext - 1, STEP):
    for xi in np.arange(-ext + 1, ext - 1, STEP):
        cands.append((xi + rnd.uniform(0, STEP), zi + rnd.uniform(0, STEP)))
rnd.shuffle(cands)
for (x, z) in cands:
    if not free(x, z, 44.0):
        continue
    zn = zone(x, z)
    if zn != "dag" and at(SLOPE, x, z) > 32.0:
        continue
    s = spacing_for(x, z, zn)
    if s is None:
        continue
    if near_any(grid_t, x, z, s):
        continue
    tur = tree_for(x, z, zn)
    if tur is None:
        continue
    add_tree(tur, x, z, s)
    # Servi: yeşil alanlarda bazen çift
    if tur.startswith("servi") and zn == "yesil":
        a = rnd.uniform(0, math.tau)
        x2, z2 = x + math.cos(a) * 2.6, z + math.sin(a) * 2.6
        if free(x2, z2):
            add_tree(tur, x2, z2, 2.0)

# Çocuk parkının çevresi: uzun kenarlarda ağaç, aralarda çalı
for pk in parks:
    c, r = pk["p"], float(pk.get("r", 0))
    w, dd = float(pk.get("w", 30)), float(pk.get("d", 24))
    for side in (-1, 1):
        for k in range(5):
            lx = -w * 0.5 + 2 + k * (w - 4) / 4
            x, z = local(c, r, lx, side * (dd * 0.5 + 3.2))
            if free(x, z) and not near_any(grid_t, x, z, 5.0, False):
                add_tree("ihlamur" if k % 2 == 0 else "cinar_2", x, z, 5.0)
            x, z = local(c, r, lx + (w - 4) / 8, side * (dd * 0.5 + 2.2))
            if k < 4 and free(x, z):
                add_small(pick(BUSH_CITY, x, z), x, z, 1.2)

# Yeşil alan kenarları: kenardan 1.6 m içeride çiçekli çalılar
for gpts in greens:
    m = len(gpts)
    for k in range(m):
        a, b = gpts[k], gpts[(k + 1) % m]
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        if L < 1:
            continue
        ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        for t in np.arange(1.5, L - 1.5, 4.2):
            for sd in (1, -1):
                x, z = a[0] + ux * t - uz * 1.6 * sd, a[1] + uz * t + ux * 1.6 * sd
                if at(GREEN, x, z) and free(x, z) and rnd.random() < 0.55 \
                        and not near_any(grid_s, x, z, 2.2) and not near_any(grid_t, x, z, 2.2, False):
                    add_small(pick(BUSH_CITY, x, z), x, z, 1.4)
                    break

# Ağaç dipleri: çalı, ot öbeği, kaya
for (tx, tz) in list(trunks):
    zn = zone(tx, tz)
    if zn == "kum":
        continue
    nb = rnd.choice((0, 1, 1, 2)) if zn != "yesil" else rnd.choice((0, 0, 1))
    for _ in range(nb):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(2.2, 4.2)
        x, z = tx + math.cos(a) * rr, tz + math.sin(a) * rr
        if free(x, z, 38) and not near_any(grid_s, x, z, 1.8) and not near_any(grid_t, x, z, 1.9, False):
            add_small(pick(BUSH, x, z), x, z, 1.5)
    for _ in range(rnd.choice((1, 2, 3))):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(1.0, 6.0)
        x, z = tx + math.cos(a) * rr, tz + math.sin(a) * rr
        if free(x, z, 40) and not near_any(grid_s, x, z, 0.9):
            add_small("ot_1" if rnd.random() < 0.6 else "ot_2", x, z, 0.6)
    if zn == "dag" and rnd.random() < (0.12 + 0.5 * min(at(SLOPE, tx, tz) / 30.0, 1.0) ** 2):
        a = rnd.uniform(0, math.tau)
        x, z = tx + math.cos(a) * rnd.uniform(2.5, 5), tz + math.sin(a) * rnd.uniform(2.5, 5)
        if free(x, z, 45) and not near_any(grid_s, x, z, 2.0) and not near_any(grid_t, x, z, 2.5, False):
            add_small(rnd.choice(("kaya_1", "kaya_1", "kaya_3", "kaya_2")), x, z, 2.0)

# Açıklıklarda tek tük ot öbeği ve dağda kaya
for (x, z) in cands[: len(cands) // 6]:
    if not free(x, z, 45):
        continue
    zn = zone(x, z)
    if zn == "kum":
        continue
    if zn == "dag" and at(SLOPE, x, z) > 20 and rnd.random() < 0.08 and not near_any(grid_s, x, z, 6) and not near_any(grid_t, x, z, 3, False):
        add_small(rnd.choice(("kaya_2", "kaya_1", "kaya_3")), x, z, 3.0)
    elif rnd.random() < 0.05 and not near_any(grid_s, x, z, 3):
        add_small("ot_1" if rnd.random() < 0.5 else "ot_2", x, z, 0.6)

from collections import Counter
cnt = Counter(i[0] for i in items)
print("toplam", len(items))
for k, v in sorted(cnt.items()):
    print("  %-14s %d" % (k, v))
json.dump({"v": 1, "items": items}, open(os.path.join(ADA, "peyzaj.json"), "w", encoding="utf-8"), separators=(",", ":"))

# Ön izleme: harita üstünde noktalar
try:
    base = Image.open(os.path.join(ADA, "harita.png")).convert("RGB")
    dd2 = ImageDraw.Draw(base)
    for (b, col) in ((BLOCK & LAND, (200, 60, 60)),):
        pass
    for it in items:
        x, z = px(it[1], it[2])
        t = it[0]
        col = (20, 90, 30) if not t.startswith(("cali", "ot", "kaya", "cit")) else ((120, 200, 80) if t.startswith("cali") else (140, 140, 140))
        if t.startswith("ot"):
            continue
        r = 2 if col == (20, 90, 30) else 1
        dd2.ellipse([x - r, z - r, x + r, z + r], fill=col)
    ov = np.array(base)
    ov[PAVE & ~GREEN & LAND] = (ov[PAVE & ~GREEN & LAND] * 0.7 + np.array([170, 150, 130]) * 0.3).astype(np.uint8)
    Image.fromarray(ov).save(os.path.join(ROOT, "tests", "tmp", "peyzaj_harita.png"))
except Exception as ex:
    print("önizleme yok", ex)
