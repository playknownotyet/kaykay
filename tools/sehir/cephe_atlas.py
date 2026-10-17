"""Süs binalarının piksel-art cephe dokusu (atlas): assets/sehir/cepheler.png

  python tools/sehir/cephe_atlas.py

Her stil bir sütun, hücre 32x32 piksel = bina cephesinde 3 m x 3 m (bir kat, bir bölme).
Satırlar (shaders/bina.gdshader ile aynı):
  0 üst kat bölmesi A            1 zemin kat vitrini (dükkânlı zemin)
  2 zemin kat kapısı             3 silme / korniş (düz renk)
  4 düz çatı (çakıl)             5 düz duvar (pencere yok)
  6 kiremit çatı                 7 üst kat bölmesi B (çeşit: balkon, kemer, çift pencere...)
Sütunlar: 0-15 sıradan binalar, 16-21 özel binalar (müze, sinema, kafe, otel, kütüphane, fırın;
sırası scripts/sehir/sehir.gd OZEL ile aynı).

Cam pikselleri saydamlık kanalında işaretli (alfa = GLASS_A): gölgelendirici oralarda camın
arkasındaki odayı çizer (iç mekân). Perdeler, raftaki mallar camın önünde, opak kalır.
Pencerelerin, denizliklerin, tentelerin ve balkonların yerleri assets/sehir/cephe.json'a yazılır:
şehir bunlardan cephe derinliğini (pervaz, denizlik, tente, balkon) kurar.
"""
import json
import math
import os
import random

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "sehir", "cepheler.png")
OUT_JSON = os.path.join(HERE, "..", "..", "assets", "sehir", "cephe.json")
GLASS_A = 160
# (stil, satır) -> [{t: tür, x, y, w, h}] piksel (hücre içinde, y aşağı)
PARTS = {}
_cur = [None]


def note(t, x, y, w, h, **kw):
    if _cur[0] is None:
        return
    d = dict(t=t, x=x, y=y, w=w, h=h)
    d.update(kw)
    PARTS.setdefault(_cur[0], []).append(d)
C = 32
COLS = 24
ROWS = 8


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# Duvar dokusu: sıva / tuğla / ahşap kaplama / kesme taş
# Pencere: A ve B türleri: dik (rect), kemer (arch), çift (double), balkon (balcony), yuvarlak (round), fransız (french)
STYLES = [
    dict(wall="#f2b8c0", trim="#fbf3ea", accent="#7cc6b0", door="#5e8fb8", tex="siva", a="rect", b="balcony", flowers=True, awning="#e05a6a"),
    dict(wall="#b9e3cf", trim="#fff4dc", accent="#e98b7a", door="#b5644a", tex="siva", a="rect", b="double", flowers=False, awning="#f0b44c"),
    dict(wall="#f3e2bf", trim="#c8694a", accent="#4f7fb5", door="#3e5f8e", tex="siva", a="rect", b="arch", flowers=True, awning="#3f8f7a"),
    dict(wall="#b85a45", trim="#f4ece0", accent="#2f5d50", door="#2f5d50", tex="tugla", a="rect", b="arch", flowers=False, awning="#2f5d50"),
    dict(wall="#cdbbe6", trim="#fdf7ff", accent="#f2c14e", door="#8b5fbf", tex="siva", a="rect", b="french", flowers=True, awning="#8b5fbf"),
    dict(wall="#e8c15a", trim="#7a4a2c", accent="#7a4a2c", door="#5a3a26", tex="siva", a="double", b="rect", flowers=False, awning="#c0392b"),
    dict(wall="#a9cfee", trim="#ffffff", accent="#f08f6c", door="#f08f6c", tex="siva", a="rect", b="balcony", flowers=True, awning="#f08f6c"),
    dict(wall="#b7b4ae", trim="#e7e2d8", accent="#e5874a", door="#4b5560", tex="siva", a="rect", b="balcony", flowers=False, awning="#e5874a"),
    dict(wall="#d98a62", trim="#fbefdc", accent="#3f7f5f", door="#3f7f5f", tex="siva", a="arch", b="french", flowers=True, awning="#3f7f5f"),
    dict(wall="#7f9bb0", trim="#f6f3ec", accent="#f0c05a", door="#c44d3a", tex="ahsap", a="rect", b="double", flowers=False, awning="#c44d3a"),
    dict(wall="#e3c46a", trim="#2f5d50", accent="#2f5d50", door="#2f5d50", tex="tugla", a="double", b="arch", flowers=False, awning="#2f5d50"),
    dict(wall="#f4a596", trim="#ffffff", accent="#5aa3c8", door="#5aa3c8", tex="siva", a="arch", b="balcony", flowers=True, awning="#5aa3c8"),
    dict(wall="#a7b27a", trim="#f7f0da", accent="#a84c3c", door="#a84c3c", tex="siva", a="rect", b="round", flowers=True, awning="#a84c3c"),
    dict(wall="#3e4a6b", trim="#e8c66a", accent="#e8c66a", door="#e8c66a", tex="siva", a="arch", b="french", flowers=False, awning="#e8c66a"),
    dict(wall="#d9c9a3", trim="#f5ecd6", accent="#7b5d3e", door="#7b5d3e", tex="tas", a="rect", b="arch", flowers=False, awning="#7b5d3e"),
    dict(wall="#f6c7a1", trim="#fffaf0", accent="#4d79a8", door="#4d79a8", tex="siva", a="double", b="balcony", flowers=True, awning="#4d79a8"),
    # Özel binalar (16..21)
    dict(wall="#e4ddd0", trim="#f8f4ec", accent="#b8a98c", door="#6b4e3d", tex="tas", a="arch", b="arch", flowers=False, awning="#8a2f2f", ozel="muze"),
    dict(wall="#7a2632", trim="#f0c94e", accent="#f0c94e", door="#2a1a20", tex="siva", a="rect", b="rect", flowers=False, awning="#f0c94e", ozel="sinema"),
    dict(wall="#bfe3d6", trim="#fff8ec", accent="#e6866f", door="#e6866f", tex="ahsap", a="rect", b="french", flowers=True, awning="#e6866f", ozel="kafe"),
    dict(wall="#f1e3c8", trim="#8c5a3c", accent="#8c5a3c", door="#8c5a3c", tex="siva", a="french", b="balcony", flowers=True, awning="#8c5a3c", ozel="otel"),
    dict(wall="#9a5440", trim="#efe6d5", accent="#2e4a6e", door="#2e4a6e", tex="tugla", a="arch", b="arch", flowers=False, awning="#2e4a6e", ozel="kutuphane"),
    dict(wall="#f3d488", trim="#8a5530", accent="#c0623a", door="#8a5530", tex="siva", a="rect", b="double", flowers=True, awning="#c0623a", ozel="firin"),
]


class Cell:
    def __init__(self, img, col, row):
        self.img, self.x0, self.y0 = img, col * C, row * C

    def px(self, x, y, c, a=255):
        x, y = int(x), int(y)
        if 0 <= x < C and 0 <= y < C:
            self.img.putpixel((self.x0 + x, self.y0 + y), c + (a,))

    def glass(self, x, y, c):
        self.px(x, y, c, GLASS_A)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.px(x, y, c)


# ---------- Duvar ----------

def wall_fill(cell, st, rnd):
    base = rgb(st["wall"])
    for y in range(C):
        for x in range(C):
            t = st["tex"]
            if t == "tugla":
                row = y // 4
                off = 4 if row % 2 else 0
                mortar = y % 4 == 3 or (x + off) % 8 == 7
                c = mix(base, (235, 225, 212), 0.75) if mortar else shade(base, 0.9 + rnd.random() * 0.16)
            elif t == "ahsap":
                c = shade(base, 0.72) if y % 4 == 3 else shade(base, 1.04 if y % 4 == 0 else 0.95 + rnd.random() * 0.06)
            elif t == "tas":
                row = y // 8
                off = 8 if row % 2 else 0
                joint = y % 8 == 7 or (x + off) % 16 == 15
                c = shade(base, 0.82) if joint else shade(base, 0.95 + rnd.random() * 0.08)
            else:
                c = shade(base, 0.96 + rnd.random() * 0.07)
            cell.px(x, y, c)


def glass(y, h):
    return mix(rgb("#cfe8f6"), rgb("#5f8fb4"), y / max(h - 1, 1))


def curtain(cell, rnd, x0, y0, w, h):
    if rnd.random() < 0.55:
        cur = rgb(rnd.choice(["#f7d6e0", "#fff1c9", "#d9f0e3", "#e3dcf7", "#ffd9b8"]))
        for y in range(h // 2):
            cell.px(x0, y0 + y, cur)
            cell.px(x0 + w - 1, y0 + y, cur)
    elif rnd.random() < 0.3:                                 # içeride lamba ışığı
        cell.rect(x0 + w // 2 - 1, y0 + 2, x0 + w // 2, y0 + 3, rgb("#ffe7a0"))


def pane(cell, x0, y0, w, h, trim, bars=True):
    note("cam", x0, y0, w, h)
    cell.rect(x0 - 1, y0 - 1, x0 + w, y0 + h, trim)
    for y in range(h):
        g = glass(y, h)
        for x in range(w):
            c = mix(g, (255, 255, 255), 0.45) if (x - y) % 9 in (0, 1) and y < h * 0.6 else g
            cell.glass(x0 + x, y0 + y, c)
    if bars:
        cell.rect(x0 + w // 2, y0, x0 + w // 2, y0 + h - 1, trim)
        cell.rect(x0, y0 + h // 3, x0 + w - 1, y0 + h // 3, trim)


def sill(cell, st, x0, y, w):
    note("denizlik", x0 - 2, y, w + 4, 2)
    cell.rect(x0 - 2, y, x0 + w + 1, y + 1, shade(rgb(st["trim"]), 0.92))
    cell.rect(x0 - 2, y + 2, x0 + w + 1, y + 2, shade(rgb(st["wall"]), 0.72))


def shutters(cell, st, x0, y0, w, h):
    acc = rgb(st["accent"])
    for sx in (x0 - 5, x0 + w + 1):
        cell.rect(sx, y0 - 1, sx + 3, y0 + h, acc)
        for y in range(y0, y0 + h, 2):
            cell.rect(sx + 1, y, sx + 2, y, shade(acc, 0.8))


def flower_box(cell, x0, y0, w, rnd):
    cell.rect(x0, y0, x0 + w - 1, y0 + 2, rgb("#8a5a3c"))
    for x in range(x0, x0 + w):
        cell.px(x, y0 - 1, rgb("#4f9a4a"))
        if rnd.random() < 0.55:
            cell.px(x, y0 - 2, rgb(rnd.choice(["#ff6f8f", "#ffd34f", "#ff9a4f", "#ffffff"])))


def railing(cell, st, x0, y0, w):
    note("korkuluk", x0, y0, w, 7)
    acc = shade(rgb(st["accent"]), 0.9)
    cell.rect(x0, y0, x0 + w - 1, y0, acc)
    cell.rect(x0, y0 + 5, x0 + w - 1, y0 + 6, shade(acc, 0.75))
    for x in range(x0, x0 + w, 2):
        cell.rect(x, y0, x, y0 + 5, acc)


# ---------- Pencere türleri ----------

def win_rect(cell, st, rnd):
    pane(cell, 10, 6, 12, 15, rgb(st["trim"]))
    curtain(cell, rnd, 10, 6, 12, 15)
    sill(cell, st, 10, 22, 12)
    if st["tex"] not in ("tugla", "tas") and st["accent"] != st["trim"]:
        shutters(cell, st, 10, 6, 12, 15)
    if st["flowers"]:
        flower_box(cell, 9, 26, 14, rnd)


def win_arch(cell, st, rnd):
    trim = rgb(st["trim"])
    x0, y0, w, h = 10, 8, 12, 14
    pane(cell, x0, y0, w, h, trim)
    # Kemer: yarım daire üst
    r = w / 2
    cx = x0 + r - 0.5
    for y in range(int(y0 - r) - 1, y0):
        for x in range(x0 - 1, x0 + w + 1):
            d = math.hypot(x - cx, (y - y0 + 0.5))
            if d <= r + 0.6:
                if d > r - 0.6:
                    cell.px(x, y, trim)
                else:
                    cell.glass(x, y, mix(rgb("#e7f3fb"), rgb("#9fc4dc"), 0.3))
    curtain(cell, rnd, x0, y0, w, h)
    sill(cell, st, x0, y0 + h + 1, w)
    if st["flowers"]:
        flower_box(cell, 9, 27, 14, rnd)


def win_double(cell, st, rnd):
    trim = rgb(st["trim"])
    for x0 in (6, 18):
        pane(cell, x0, 7, 8, 14, trim, bars=False)
        cell.rect(x0, 12, x0 + 7, 12, trim)
        curtain(cell, rnd, x0, 7, 8, 14)
    sill(cell, st, 6, 22, 20)
    if st["flowers"]:
        flower_box(cell, 5, 26, 22, rnd)


def win_balcony(cell, st, rnd):
    trim = rgb(st["trim"])
    pane(cell, 11, 4, 10, 22, trim)
    curtain(cell, rnd, 11, 4, 10, 22)
    note("balkon", 4, 26, 24, 2)
    cell.rect(4, 26, 27, 27, shade(trim, 0.9))                 # balkon döşemesi
    cell.rect(5, 28, 26, 28, shade(rgb(st["wall"]), 0.6))
    railing(cell, st, 4, 19, 24)
    if st["flowers"]:
        for x in (6, 24):
            cell.rect(x, 17, x + 2, 18, rgb("#4f9a4a"))
            cell.px(x + 1, 16, rgb("#ff6f8f"))


def win_french(cell, st, rnd):
    trim = rgb(st["trim"])
    pane(cell, 10, 3, 12, 22, trim)
    curtain(cell, rnd, 10, 3, 12, 22)
    railing(cell, st, 8, 19, 16)
    sill(cell, st, 10, 26, 12)


def win_round(cell, st, rnd):
    trim = rgb(st["trim"])
    cx, cy, r = 15.5, 13.5, 6.5
    note("yuvarlak", 9, 7, 14, 14)
    for y in range(C):
        for x in range(C):
            d = math.hypot(x - cx, y - cy)
            if d <= r + 1:
                if d > r - 0.5:
                    cell.px(x, y, trim)
                else:
                    cell.glass(x, y, glass(int(y - (cy - r)), int(2 * r)))
    cell.rect(15, 8, 16, 19, trim)
    cell.rect(10, 13, 21, 14, trim)
    if st["flowers"]:
        flower_box(cell, 10, 25, 12, rnd)


WINDOWS = {"rect": win_rect, "arch": win_arch, "double": win_double, "balcony": win_balcony,
           "french": win_french, "round": win_round}


def upper(cell, st, rnd, kind):
    wall_fill(cell, st, rnd)
    WINDOWS[kind](cell, st, rnd)
    cell.rect(0, C - 1, C - 1, C - 1, shade(rgb(st["wall"]), 0.85))   # kat çizgisi


# ---------- Zemin kat ----------

def awning(cell, color, y0=3):
    note("tente", 1, y0, 30, 6, renk=color)
    aw = rgb(color)
    for x in range(1, 31):
        c = aw if (x // 3) % 2 == 0 else (250, 246, 238)
        cell.rect(x, y0, x, y0 + 4, c)
        if x % 3 == 1:
            cell.px(x, y0 + 5, c)


def shopfront(cell, st, rnd, goods=None):
    trim = rgb(st["trim"])
    note("vitrin", 4, 10, 24, 18)
    cell.rect(3, 9, 28, 28, trim)
    for y in range(10, 28):
        g = mix(rgb("#d8eef8"), rgb("#6c97b8"), (y - 10) / 17)
        for x in range(4, 28):
            cell.glass(x, y, mix(g, (255, 255, 255), 0.4) if (x - y) % 11 in (0, 1) and y < 20 else g)
    goods = goods or ["#e05a6a", "#f0b44c", "#7cc6b0", "#8b5fbf", "#4f9a4a"]
    for x in range(5, 27, 3):
        cell.rect(x, 24, x + 1, 27, rgb(rnd.choice(goods)))


def ground(cell, st, rnd):
    wall_fill(cell, st, rnd)
    oz = st.get("ozel")
    trim = rgb(st["trim"])
    if oz == "muze":
        # Uzun kemerli pencere
        pane(cell, 10, 8, 12, 18, trim)
        for y in range(2, 8):
            for x in range(9, 23):
                if math.hypot(x - 15.5, y - 8) <= 6.6:
                    cell.px(x, y, trim if math.hypot(x - 15.5, y - 8) > 5.5 else rgb("#d7e9f3"))
    elif oz == "sinema":
        # Film afişleri (ışıklı çerçeve)
        for x0, col in ((3, "#3a6fb5"), (17, "#d8483e")):
            cell.rect(x0, 6, x0 + 11, 25, rgb("#f0c94e"))
            cell.rect(x0 + 1, 7, x0 + 10, 24, rgb(col))
            cell.rect(x0 + 3, 10, x0 + 8, 14, rgb("#fff2c4"))
            cell.rect(x0 + 2, 18, x0 + 9, 19, rgb("#ffffff"))
            cell.rect(x0 + 2, 21, x0 + 7, 21, rgb("#ffffff"))
            for y in range(6, 26, 3):
                cell.px(x0, y, rgb("#fff7c0"))
                cell.px(x0 + 11, y, rgb("#fff7c0"))
    elif oz == "kafe":
        awning(cell, st["awning"])
        shopfront(cell, st, rnd, goods=["#8a5a3c"])
        for x0 in (6, 18):                                      # masa ve sandalyeler
            cell.rect(x0, 22, x0 + 6, 22, rgb("#8a5a3c"))
            cell.rect(x0 + 3, 23, x0 + 3, 27, rgb("#8a5a3c"))
            cell.rect(x0 + 2, 20, x0 + 4, 21, rgb("#ffffff"))
    elif oz == "firin":
        awning(cell, st["awning"])
        shopfront(cell, st, rnd, goods=["#c98a46", "#e0a95a", "#a8662f"])
        for x0 in range(5, 27, 6):                               # ekmekler
            cell.rect(x0, 20, x0 + 4, 21, rgb("#d39550"))
            cell.px(x0 + 1, 20, rgb("#f0c27f"))
    elif oz in ("otel", "kutuphane"):
        pane(cell, 8, 7, 16, 20, trim)
        if oz == "kutuphane":
            for y in (12, 17, 22):
                for x in range(9, 23):
                    cell.px(x, y, rgb(rnd.choice(["#8a2f2f", "#2e4a6e", "#3f7f5f", "#c08a3a"])))
    else:
        awning(cell, st["awning"])
        shopfront(cell, st, rnd)
    cell.rect(0, 29, C - 1, C - 1, shade(rgb(st["wall"]), 0.7))   # kaide


def door(cell, st, rnd):
    wall_fill(cell, st, rnd)
    trim = rgb(st["trim"])
    d = rgb(st["door"])
    if st.get("ozel") in ("muze", "otel", "kutuphane", "sinema"):
        # Çift kanatlı büyük kapı
        cell.rect(5, 5, 26, 31, trim)
        cell.rect(7, 7, 24, 31, d)
        cell.rect(15, 7, 16, 31, shade(d, 0.7))
        for x0 in (9, 18):
            cell.rect(x0, 10, x0 + 4, 18, mix(rgb("#cfe8f6"), d, 0.3))
        cell.rect(13, 21, 13, 23, rgb("#f2d16b"))
        cell.rect(18, 21, 18, 23, rgb("#f2d16b"))
        cell.rect(4, 30, 27, 31, rgb("#b7b4ae"))
        return
    cell.rect(9, 7, 22, 31, trim)
    cell.rect(11, 9, 20, 31, d)
    cell.rect(12, 10, 19, 16, mix(rgb("#cfe8f6"), d, 0.25))
    for y in (19, 25):
        cell.rect(12, y, 19, y + 3, shade(d, 0.85))
    cell.px(18, 21, rgb("#f2d16b"))
    cell.rect(13, 4, 18, 5, rgb("#3a3a3a"))
    cell.rect(14, 6, 17, 7, rgb("#ffe7a0"))
    cell.rect(8, 30, 23, 31, rgb("#b7b4ae"))


def trim_cell(cell, st):
    t = rgb(st["trim"])
    cell.rect(0, 0, C - 1, C - 1, t)
    cell.rect(0, 0, C - 1, 1, shade(t, 1.08))
    cell.rect(0, C - 2, C - 1, C - 1, shade(t, 0.82))


def roof_flat(cell, rnd):
    for y in range(C):
        for x in range(C):
            cell.px(x, y, shade(rgb("#8f8c88"), 0.85 + rnd.random() * 0.25))
    for _ in range(3):
        x, y = rnd.randrange(C), rnd.randrange(C)
        cell.rect(x, y, x + 4, y + 2, rgb("#5f5d5a"))


def roof_tiles(cell, rnd, base_hex):
    base = rgb(base_hex)
    for y in range(C):
        for x in range(C):
            off = 2 if (y // 4) % 2 else 0
            edge = y % 4 == 3 or ((x + off) % 4 == 0 and y % 4 == 2)
            cell.px(x, y, shade(base, 0.7 if edge else 0.95 + rnd.random() * 0.12))


ROOF_TILES = ["#c4563a", "#b8492f", "#9c4a3a", "#5d6b78", "#c4563a", "#8a5a3c", "#c4563a", "#6f6f6f",
              "#c4563a", "#4f6170", "#9c4a3a", "#c4563a", "#7a6a4a", "#3d4a5c", "#b8492f", "#c4563a",
              "#7b7d80", "#4a2a2a", "#c4563a", "#9c4a3a", "#6b3a2a", "#b8492f"]


def main():
    img = Image.new("RGBA", (C * COLS, C * ROWS), (0, 0, 0, 0))
    for i, st in enumerate(STYLES):
        rnd = random.Random(1000 + i)
        _cur[0] = (i, 0)
        upper(Cell(img, i, 0), st, rnd, st["a"])
        _cur[0] = (i, 1)
        ground(Cell(img, i, 1), st, rnd)
        _cur[0] = None
        door(Cell(img, i, 2), st, rnd)
        trim_cell(Cell(img, i, 3), st)
        roof_flat(Cell(img, i, 4), rnd)
        wall_fill(Cell(img, i, 5), st, rnd)
        roof_tiles(Cell(img, i, 6), rnd, ROOF_TILES[i % len(ROOF_TILES)])
        _cur[0] = (i, 7)
        upper(Cell(img, i, 7), st, rnd, st["b"])
        _cur[0] = None
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    data = {"hucre": C, "stiller": []}
    for i, st in enumerate(STYLES):
        data["stiller"].append({
            "duvar": st["wall"], "pervaz": st["trim"], "vurgu": st["accent"], "tente": st["awning"],
            "satirlar": {str(r): PARTS.get((i, r), []) for r in (0, 1, 7)},
        })
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("CEPHE", OUT, len(STYLES), "stil;", OUT_JSON)


main()
