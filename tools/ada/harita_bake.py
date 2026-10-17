"""Oyun içi harita: adanın kuş bakışı resmi ve yol / yer adları.

Girdi: assets/ada/ada.json (yollar, iskeleler, meydan) ve assets/ada/ada_h.bin (yükseklik + zemin cinsi).
Çıktı:
  assets/ada/harita.png   1 piksel = 1 m; kuzey yukarı (dünya -Z yukarı, +X sağa). Kara: zemin rengi,
                          gölgelendirme ve 10 m eş yükselti çizgileri; deniz: derinliğe göre mavi; iskeleler.
  assets/ada/harita.json  {"origin": sol üst köşe (x = z), "px": metre/piksel, "roads": [{name, kind, w, closed, pts:[x,z,...]}],
                          "places": [{name, kind, p:[x,z]}]}  (dünya koordinatı: x, z)
Ada yeniden üretilince (ada_bake) bunu da çalıştır:  python tools/ada/harita_bake.py
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ADA = os.path.join(ROOT, "assets", "ada")

d = json.load(open(os.path.join(ADA, "ada.json"), encoding="utf-8"))
g = d["grid"]
n, ext, step = int(g["n"]), float(g["ext"]), float(g["step"])
raw = np.fromfile(os.path.join(ADA, "ada_h.bin"), dtype=np.uint8)
h = np.frombuffer(raw[n * n * 4:n * n * 8].tobytes(), dtype=np.float32).reshape(n, n)   # [j, i]
mat = raw[n * n * 8:n * n * 9].reshape(n, n)

# Resim satırı r: dünya z = -ext + r * step (plan y = -z): satırları ters çevir
h = h[::-1, :]
mat = mat[::-1, :]

# 2 kat büyüt (1 piksel = 1 m): yükseklik çift doğrusal, zemin cinsi en yakın
K = 2
N = (n - 1) * K + 1
src = np.arange(N) / K
i0 = np.clip(np.floor(src).astype(int), 0, n - 2)
f = src - i0
hr = h[i0, :] * (1 - f)[:, None] + h[i0 + 1, :] * f[:, None]
H = hr[:, i0] * (1 - f)[None, :] + hr[:, i0 + 1] * f[None, :]
near = np.clip(np.round(src).astype(int), 0, n - 1)
M = mat[near][:, near]

SEA, SAND, GRASS, ROCK, SOIL, ROAD = range(6)
COL = {
    SAND: (0.93, 0.85, 0.62),
    GRASS: (0.50, 0.70, 0.36),
    ROCK: (0.62, 0.60, 0.55),
    SOIL: (0.62, 0.52, 0.36),
    ROAD: (0.80, 0.78, 0.74),
}
img = np.zeros((N, N, 3), dtype=np.float32)
for k, c in COL.items():
    img[M == k] = c
sea = (M == SEA) | (H < -0.2)
depth = np.clip(1.0 + H / 12.0, 0.0, 1.0)[..., None]
deep = np.array([0.15, 0.40, 0.58], dtype=np.float32)
shallow = np.array([0.38, 0.70, 0.80], dtype=np.float32)
img[sea] = (deep + (shallow - deep) * depth)[sea]

# Gölgelendirme (ışık sol üstten) yalnız karada
gz, gx = np.gradient(H, 1.0)
nx, nz, ny = -gx, -gz, np.ones_like(H) * 1.6
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
L = np.array([-0.55, 0.65, -0.55])
L = L / np.linalg.norm(L)
shade = (nx * L[0] + ny * L[1] + nz * L[2]) / ln
shade = 0.72 + 0.4 * shade
land = ~sea
img[land] *= np.clip(shade, 0.55, 1.15)[land][:, None]

# 10 m eş yükselti çizgileri
band = np.floor(H / 10.0)
edge = np.zeros_like(H, dtype=bool)
edge[:, 1:] |= band[:, 1:] != band[:, :-1]
edge[1:, :] |= band[1:, :] != band[:-1, :]
edge &= land & (H > 3.0)
img[edge] *= 0.86

# Kıyı: kara ile denizin sınırında açık köpük çizgisi
coast = np.zeros_like(sea)
coast[:, 1:] |= sea[:, 1:] != sea[:, :-1]
coast[1:, :] |= sea[1:, :] != sea[:-1, :]
coast &= sea
img[coast] = img[coast] * 0.4 + 0.6

out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB")

# İskeleler (dünya: merkez (x, -y), uzunluk yerel X boyunca, Y ekseni etrafında angle)
dr = ImageDraw.Draw(out)
def to_px(x, z):
    return ((x + ext) * K / step, (z + ext) * K / step)
for p in d["piers"]:
    cx, cz, a = p["x"], -p["y"], p["angle"]
    ux, uz = math.cos(a), -math.sin(a)
    vx, vz = -uz, ux
    hl, hw = p["length"] * 0.5, p["width"] * 0.5
    poly = [to_px(cx + ux * sx * hl + vx * sz * hw, cz + uz * sx * hl + vz * sz * hw)
            for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    dr.polygon(poly, fill=(140, 102, 66), outline=(92, 66, 42))
out.save(os.path.join(ADA, "harita.png"), optimize=True)


# ---------- Yollar ve yer adları ----------

def simplify(pts, tol):
    """Douglas-Peucker (2B)."""
    if len(pts) < 3:
        return pts
    a, b = np.array(pts[0]), np.array(pts[-1])
    ab = b - a
    L2 = float(ab @ ab)
    best, bi = -1.0, 0
    for i in range(1, len(pts) - 1):
        p = np.array(pts[i])
        if L2 < 1e-9:
            dd = float(np.linalg.norm(p - a))
        else:
            t = max(0.0, min(1.0, float((p - a) @ ab) / L2))
            dd = float(np.linalg.norm(p - (a + ab * t)))
        if dd > best:
            best, bi = dd, i
    if best <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[:bi + 1], tol)[:-1] + simplify(pts[bi:], tol)


roads = []
for r in d["roads"]:
    pts = [(float(p[0]), -float(p[1])) for p in r["pts"]]
    if r.get("closed") and pts[0] != pts[-1]:
        pts.append(pts[0])
    pts = simplify(pts, 0.6)
    flat = []
    for x, z in pts:
        flat += [round(x, 1), round(z, 1)]
    roads.append({"name": r.get("name", ""), "kind": r["kind"], "w": float(r["width"]),
                  "closed": bool(r.get("closed", False)), "pts": flat})

places = []
pl = d["plaza"]
places.append({"name": "Meydan", "kind": "meydan", "p": [pl["x"], -pl["y"]]})
for r in d["roads"]:
    if r["id"] == "summit":
        xs = [p[0] for p in r["pts"]]
        ys = [p[1] for p in r["pts"]]
        places.append({"name": "Seyir Tepesi", "kind": "tepe", "p": [round(sum(xs) / len(xs), 1), round(-sum(ys) / len(ys), 1)]})
if d["piers"]:
    px = sum(p["x"] for p in d["piers"]) / len(d["piers"])
    py = sum(p["y"] for p in d["piers"]) / len(d["piers"])
    places.append({"name": "İskele", "kind": "iskele", "p": [round(px, 1), round(-py, 1)]})

# Resmin sol üst köşesi dünyada (origin, origin): piksel merkezleri ızgara noktalarında
json.dump({"origin": -ext - step / K * 0.5, "px": step / K, "roads": roads, "places": places},
          open(os.path.join(ADA, "harita.json"), "w", encoding="utf-8"), ensure_ascii=False)
print("harita.png", out.size, "yollar", len(roads), "nokta", sum(len(r["pts"]) // 2 for r in roads))
