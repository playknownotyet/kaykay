"""Tabela dokusu: trafik levhaları, yön tabelaları, sokak adı levhaları ve reklam panoları tek
bir dokuda (tek çizim çağrısı). ada_export.js'ten sonra çalışır:

  python tools/ada/tabela_atlas.py

Okur:  assets/ada/ada.json (street.signs anahtarları, reklam panosu sayısı), art/portre/<tur>.png
Yazar: assets/ada/tabelalar.png ve tabelalar.json (anahtar -> [u0, v0, u1, v1], en/boy oranı)
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FONT_DIR = "C:/Windows/Fonts"
SIZE = 2048


def font(name, px):
    return ImageFont.truetype(os.path.join(FONT_DIR, name), px)


BOLD = "verdanab.ttf"
HEAVY = "impact.ttf"
WHITE = (250, 250, 248, 255)
RED = (205, 30, 35, 255)
BLUE = (22, 78, 170, 255)
DARK = (25, 25, 28, 255)
YELLOW = (250, 205, 40, 255)


def fit_text(d, text, box_w, box_h, fname, max_px):
    px = max_px
    while px > 8:
        f = font(fname, px)
        l, t, r, b = d.textbbox((0, 0), text, font=f)
        if r - l <= box_w and b - t <= box_h:
            return f, (r - l, b - t, l, t)
        px -= 2
    f = font(fname, 8)
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    return f, (r - l, b - t, l, t)


def center_text(d, text, cx, cy, box_w, box_h, fname, max_px, fill):
    f, (w, h, l, t) = fit_text(d, text, box_w, box_h, fname, max_px)
    d.text((cx - w / 2 - l, cy - h / 2 - t), text, font=f, fill=fill)


# ---------------------------------------------------------------------------
# Levhalar (128 x 128, saydam köşeler)
# ---------------------------------------------------------------------------
def speed_sign(kmh):
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([4, 4, 123, 123], fill=RED)
    d.ellipse([19, 19, 108, 108], fill=WHITE)
    center_text(d, str(kmh), 64, 66, 70, 52, BOLD, 52, DARK)
    return im


def round_blue(draw_fn):
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([4, 4, 123, 123], fill=WHITE)
    d.ellipse([9, 9, 118, 118], fill=BLUE)
    draw_fn(d)
    return im


def arrow_poly(d, cx, cy, ang, length, width, fill, head=1.8):
    """ang: radyan (0 = yukarı, saat yönünde artar)."""
    ca, sa = math.cos(ang), math.sin(ang)
    rot = lambda x, y: (cx + x * ca - y * sa, cy + x * sa + y * ca)
    hw = width / 2
    hl = width * head
    pts = [(-hw, length / 2), (-hw, -length / 2 + hl), (-hw * 2.1, -length / 2 + hl), (0, -length / 2),
           (hw * 2.1, -length / 2 + hl), (hw, -length / 2 + hl), (hw, length / 2)]
    d.polygon([rot(x, y) for x, y in pts], fill=fill)


def roundabout(d):
    for k in range(3):
        a = k * math.tau / 3
        cx, cy = 64 + math.sin(a) * 26, 64 - math.cos(a) * 26
        arrow_poly(d, cx, cy, a + math.pi / 2 + 0.35, 34, 10, WHITE, 1.4)


def triangle_sign(draw_fn):
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(64, 6), (124, 116), (4, 116)], fill=RED)
    d.polygon([(64, 28), (104, 104), (24, 104)], fill=WHITE)
    draw_fn(d)
    return im


def curve(d, left):
    s = -1 if left else 1
    pts = []
    for k in range(13):
        t = k / 12
        pts.append((64 + s * (-10 + 22 * math.sin(t * math.pi * 0.5) ** 2) * (1 if t < 0.6 else 1), 98 - t * 52))
    d.line(pts, fill=DARK, width=8)
    a = math.atan2(pts[-1][0] - pts[-3][0], -(pts[-1][1] - pts[-3][1]))
    arrow_poly(d, pts[-1][0] + math.sin(a) * 4, pts[-1][1] - math.cos(a) * 4, a, 16, 8, DARK, 1.0)


def pedestrian(d):
    # Mavi kare içinde beyaz üçgen, üçgende yaya geçidinde yürüyen bir penguen silüeti
    d.polygon([(64, 14), (116, 108), (12, 108)], fill=WHITE)
    for k in range(5):
        d.rectangle([28 + k * 15, 96, 34 + k * 15, 104], fill=DARK)
    d.ellipse([54, 40, 74, 58], fill=DARK)            # kafa
    d.ellipse([50, 54, 78, 90], fill=DARK)            # gövde
    d.ellipse([57, 60, 71, 86], fill=WHITE)           # karın
    d.polygon([(74, 47), (84, 50), (74, 52)], fill=(240, 150, 30, 255))   # gaga
    d.line([(58, 88), (54, 96)], fill=DARK, width=4)
    d.line([(70, 88), (76, 95)], fill=DARK, width=4)


def ped_square():
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([4, 4, 123, 123], fill=WHITE)
    d.rectangle([9, 9, 118, 118], fill=BLUE)
    pedestrian(d)
    return im


# ---------------------------------------------------------------------------
# Yön tabelası (mavi): her satır "Hedef ok mesafe"
# ---------------------------------------------------------------------------
TURN_ANG = {"duz": 0.0, "sol": -math.pi / 2, "sag": math.pi / 2, "u": math.pi}


def direction_sign(lines):
    h = 20 + 58 * len(lines)
    im = Image.new("RGBA", (400, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, 399, h - 1], radius=12, fill=WHITE)
    d.rounded_rectangle([5, 5, 394, h - 6], radius=9, fill=BLUE)
    for i, ln in enumerate(lines):
        name, turn = ln.split(":")[:2]
        cy = 10 + 58 * i + 29
        ang = TURN_ANG.get(turn, 0.0)
        # Sola dönüş oku solda, sağa dönüş oku sağda (Türkiye yön levhası düzeni)
        ax = 360 if turn == "sag" else 40
        arrow_poly(d, ax, cy, ang, 40, 12, WHITE, 1.3)
        tx0 = 76 if turn != "sag" else 20
        f, (w, hh, l, t) = fit_text(d, name.upper(), 300, 40, BOLD, 38)
        d.text((tx0 + (300 - w) / 2 - l, cy - hh / 2 - t), name.upper(), font=f, fill=WHITE)
    return im


def street_sign(name):
    im = Image.new("RGBA", (384, 88), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, 383, 87], radius=8, fill=WHITE)
    d.rounded_rectangle([5, 5, 378, 82], radius=6, fill=BLUE)
    center_text(d, name.upper(), 192, 46, 350, 56, BOLD, 40, WHITE)
    return im


# ---------------------------------------------------------------------------
# Reklam panoları (512 x 256): türlerin kendi işini yaptığı esprili ilanlar
# ---------------------------------------------------------------------------
ADS = [
    ("fil", "FİL SİGORTA", "Biz asla unutmayız.", (24, 40, 92), YELLOW),
    ("papagan", "PAPAĞAN DİL KURSU", "Tekrar et, tekrar et, tekrar et!", (250, 200, 40), (180, 20, 30, 255)),
    ("kedi", "KEDİ KAHVE", "Dokuz canınıza dokuz shot.", (90, 52, 32), (255, 220, 160, 255)),
    ("tilki", "TİLKİ EMLAK", "Kurnaz fiyatlar, sıcak yuvalar.", (40, 46, 52), (255, 140, 40, 255)),
    ("aslan", "ASLAN DİŞ", "Kükreyen gülüşler. Randevu: 444 ROAR", (20, 120, 118), WHITE),
    ("sinek", "SİNEK TV", "Duvardaki her şeyi gördük.", (18, 18, 20), (230, 40, 40, 255)),
    ("kurbaga", "KURBAĞA SPA", "Çamur banyosunda %50 indirim", (52, 120, 50), (240, 250, 200, 255)),
    ("penguen", "PENGUEN KARGO", "Takım elbiseyle, buz gibi teslimat.", (160, 210, 240), (20, 30, 60, 255)),
]


def billboard(i):
    tur, title, sub, bg, accent = ADS[i % len(ADS)]
    im = Image.new("RGBA", (512, 256), (*bg[:3], 255))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 511, 255], outline=(240, 240, 235, 255), width=6)
    # Şerit desen (retro)
    for k in range(-256, 512, 48):
        d.polygon([(k, 255), (k + 24, 255), (k + 280, 0), (k + 256, 0)], fill=(*[min(255, c + 14) for c in bg[:3]], 255))
    path = os.path.join(ROOT, "art", "portre", f"{tur}.png")
    if os.path.exists(path):
        p = Image.open(path).convert("RGBA").resize((236, 236), Image.LANCZOS)
        im.alpha_composite(p, (276, 14))
    center_text(d, title, 150, 92, 270, 90, HEAVY, 64, accent)
    center_text(d, sub, 150, 178, 270, 60, BOLD, 22, (250, 250, 250, 255) if sum(bg[:3]) < 400 else (20, 20, 20, 255))
    return im


# ---------------------------------------------------------------------------
def main():
    data = json.load(open(os.path.join(ROOT, "assets", "ada", "ada.json"), encoding="utf-8"))
    street = data["street"]
    keys = sorted({s["key"] for s in street["signs"]})
    cells = {}
    for k in keys:
        if k.startswith("hiz_"):
            cells[k] = speed_sign(int(k[4:]))
        elif k == "donel_kavsak":
            cells[k] = round_blue(roundabout)
        elif k == "yaya_gecidi":
            cells[k] = ped_square()
        elif k in ("viraj_sol", "viraj_sag"):
            cells[k] = triangle_sign(lambda d, left=(k == "viraj_sol"): curve(d, left))
        elif k.startswith("yon|"):
            cells[k] = direction_sign(k.split("|")[1:])
        elif k.startswith("ad|"):
            cells[k] = street_sign(k[3:])
    # Panolar tasarımı paylaşır (reklam_<i mod tasarım sayısı>)
    for b in street["billboards"]:
        k = f"reklam_{b['idx'] % len(ADS)}"
        if k not in cells:
            cells[k] = billboard(b["idx"])
    back = Image.new("RGBA", (64, 64), (120, 122, 126, 255))
    cells["arka"] = back

    # Raf yerleşimi (yüksekten alçağa)
    atlas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    order = sorted(cells, key=lambda k: -cells[k].height)
    x = y = shelf = 0
    rects = {}
    for k in order:
        im = cells[k]
        if x + im.width + 2 > SIZE:
            x, y, shelf = 0, y + shelf + 2, 0
        if y + im.height > SIZE:
            raise SystemExit("tabela dokusu doldu")
        atlas.alpha_composite(im, (x + 1, y + 1))
        rects[k] = [round((x + 1) / SIZE, 6), round((y + 1) / SIZE, 6), round((x + 1 + im.width) / SIZE, 6),
                    round((y + 1 + im.height) / SIZE, 6), round(im.width / im.height, 4)]
        x += im.width + 2
        shelf = max(shelf, im.height)
    # Doku kullanılan yüksekliğe kırpılır (bellek)
    used = 1 << max(8, math.ceil(math.log2(y + shelf + 2)))
    if used < SIZE:
        atlas = atlas.crop((0, 0, SIZE, used))
        for k, r in rects.items():
            rects[k] = [r[0], round(r[1] * SIZE / used, 6), r[2], round(r[3] * SIZE / used, 6), r[4]]
    out = os.path.join(ROOT, "assets", "ada", "tabelalar.png")
    atlas.save(out)
    json.dump(rects, open(os.path.join(ROOT, "assets", "ada", "tabelalar.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print(f"TABELA: {len(cells)} hücre, doku {atlas.width}x{atlas.height}")


main()
