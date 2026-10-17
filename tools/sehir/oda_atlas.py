"""Süs binalarının camdan görünen odaları (iç mekân atlası): assets/sehir/odalar.png

  python tools/sehir/oda_atlas.py

Önce tools/sehir/hayvan_cek.tscn ile hayvan figürleri çekilmiş olmalı (art/sehir_odalar/).
Hücre 64x64 piksel = odanın 3 m'lik yüzü. Atlas 8 sütun:
  satır 0-2: arka duvarlar (24): 0-5 ofis (masada çalışan hayvan), 6-9 salon (koltukta),
             10-13 mutfak (tezgâhta ayakta), 14-17 boş oda, 18-23 dükkân (kasada kasiyer, raflar)
  satır 3: yan duvarlar (8)       satır 4: zeminler (8)       satır 5: tavanlar (8)
Gölgelendirici (shaders/bina.gdshader) odayı her pencerede açıya göre perspektifle çizer.
"""
import glob
import os
import random

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
SRC = os.path.join(ROOT, "art", "sehir_odalar")
OUT = os.path.join(ROOT, "assets", "sehir", "odalar.png")
C = 64
COLS, ROWS = 8, 6
PX_M = C / 3.0                     # piksel / metre
SRC_PX_M = 128 / 2.2               # hayvan_cek.gd: 128 piksel = 2,2 m
SRC_FLOOR = 128 - (0.95 - 1.1 + 0.0) * -1 * SRC_PX_M  # yer çizgisi (aşağıda hesaplanıyor)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


class Cell:
    def __init__(self, img, idx):
        self.img = img
        self.x0 = (idx % COLS) * C
        self.y0 = (idx // COLS) * C

    def px(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < C and 0 <= y < C:
            self.img.putpixel((self.x0 + x, self.y0 + y), c + (255,))

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.px(x, y, c)

    def paste(self, sprite, x, y):
        """sprite: RGBA; (x, y) sol üst. Saydam olmayan pikseller kopyalanır."""
        w, h = sprite.size
        for j in range(h):
            for i in range(w):
                p = sprite.getpixel((i, j))
                if p[3] > 127:
                    self.px(x + i, y + j, p[:3])


WALLS = ["#f3e6cf", "#dfe9e3", "#e9dcef", "#f6e0d2", "#e0e6f2", "#f2efe0", "#e7d9c4", "#d9e7ef"]
FLOORS = ["#a8784e", "#8d6a4a", "#c9b79c", "#7d8a8f", "#b98a5a", "#9e7b5f", "#c2b28f", "#6f7f6a"]


def wall(cell, base, rnd, stripes=False):
    b = rgb(base)
    for y in range(C):
        for x in range(C):
            c = shade(b, 0.97 + rnd.random() * 0.05)
            if stripes and (x // 4) % 2 == 0:
                c = shade(c, 0.95)
            cell.px(x, y, c)
    cell.rect(0, C - 4, C - 1, C - 1, shade(b, 0.7))            # süpürgelik


def frame_pic(cell, rnd, x, y, w, h):
    cell.rect(x, y, x + w, y + h, rgb("#6b4e3d"))
    sky = rgb(rnd.choice(["#9fd3f0", "#f6c38a", "#b8e0b0", "#e8b4c8"]))
    cell.rect(x + 1, y + 1, x + w - 1, y + h - 1, sky)
    cell.rect(x + 1, y + h - 3, x + w - 1, y + h - 1, rgb(rnd.choice(["#4f9a4a", "#3e6fb0", "#c98a46"])))


def plant(cell, x, y):
    cell.rect(x, y + 6, x + 4, y + 10, rgb("#b5644a"))
    for (dx, dy) in [(2, 0), (1, 1), (3, 1), (0, 2), (2, 2), (4, 2), (1, 3), (3, 3), (2, 4), (0, 4), (4, 4), (1, 5), (3, 5)]:
        cell.px(x + dx, y + dy, rgb("#4f9a4a" if (dx + dy) % 2 else "#6dbb5a"))


def shelf(cell, rnd, x, y, w):
    cell.rect(x, y, x + w, y + 1, rgb("#8a5a3c"))
    for i in range(x + 1, x + w, 2):
        if rnd.random() < 0.75:
            h = rnd.randint(2, 4)
            cell.rect(i, y - h, i, y - 1, rgb(rnd.choice(["#c0392b", "#2e4a6e", "#3f7f5f", "#f0c05a", "#8b5fbf"])))


def window_light(cell, x, y):
    cell.rect(x, y, x + 10, y + 14, rgb("#fbf6e8"))
    cell.rect(x + 5, y, x + 5, y + 14, rgb("#d9cfb8"))


SPRITES = {}


def sprite(species, pose, v):
    key = (species, pose, v)
    if key in SPRITES:
        return SPRITES[key]
    path = os.path.join(SRC, "hayvan_%s_%s_%d.png" % (species, pose, v))
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGBA")
    s = PX_M / SRC_PX_M
    w, h = im.size
    im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.BOX)
    # Kenarlar keskin (piksel sanat): alfa eşiklenir
    px = im.load()
    for j in range(im.size[1]):
        for i in range(im.size[0]):
            r, g, b, a = px[i, j]
            px[i, j] = (r, g, b, 255 if a > 110 else 0)
    bbox = im.getbbox()
    SPRITES[key] = (im, bbox)
    return SPRITES[key]


def put_animal(cell, rnd, species_list, pose, cx, floor_y):
    """Figürü yer çizgisi floor_y'ye (hücrede), ortası cx'e gelecek şekilde koy."""
    for _ in range(6):
        sp = rnd.choice(species_list)
        got = sprite(sp, pose, rnd.randint(0, 1))
        if got:
            break
    else:
        return
    im, bbox = got
    # Kaynakta yer: kamera merkezi 0,95 m, boy 2,2 m -> yer, alt kenardan 0,15 m yukarıda
    src_floor = im.size[1] - round(0.15 * PX_M)
    cell.paste(im, cx - im.size[0] // 2, floor_y - src_floor)


SPECIES = sorted({os.path.basename(p).split("_")[1] for p in glob.glob(os.path.join(SRC, "hayvan_*.png"))})


def back_office(cell, rnd):
    wall(cell, rnd.choice(WALLS), rnd)
    frame_pic(cell, rnd, rnd.choice([6, 44]), 14, 12, 9)
    shelf(cell, rnd, 40 if rnd.random() < 0.5 else 4, 30, 18)
    floor = C - 2
    put_animal(cell, rnd, SPECIES, "masa", 32, floor)
    # Masa (önde): tabla ve ön panel, üstünde dizüstü (ekran ışığı)
    top = floor - round(0.75 * PX_M)
    cell.rect(14, top, 50, top + 1, rgb("#8a5a3c"))
    cell.rect(15, top + 2, 49, floor, rgb("#a8744a"))
    cell.rect(15, top + 2, 49, top + 3, rgb("#7a4f30"))
    cell.rect(40, top - 6, 49, top - 1, rgb("#3a3a42"))          # dizüstü (yanda: yüz görünsün)
    cell.rect(41, top - 5, 48, top - 2, rgb("#9fd8f5"))
    if rnd.random() < 0.6:
        plant(cell, 52, floor - 11)


def back_salon(cell, rnd):
    wall(cell, rnd.choice(WALLS), rnd, stripes=rnd.random() < 0.5)
    frame_pic(cell, rnd, 24, 10, 16, 10)
    floor = C - 2
    sofa = rgb(rnd.choice(["#c0623a", "#3f7f5f", "#4d79a8", "#8b5fbf", "#d9a441"]))
    # Koltuk arkalığı figürün arkasında
    cell.rect(12, floor - 22, 52, floor - 10, shade(sofa, 0.85))
    put_animal(cell, rnd, SPECIES, "otur", 32, floor - 2)
    cell.rect(10, floor - 10, 54, floor - 4, sofa)                 # oturak (önde)
    cell.rect(10, floor - 16, 13, floor - 4, shade(sofa, 0.9))
    cell.rect(51, floor - 16, 54, floor - 4, shade(sofa, 0.9))
    cell.rect(12, floor - 3, 13, floor, rgb("#5a3a26"))
    cell.rect(51, floor - 3, 52, floor, rgb("#5a3a26"))
    if rnd.random() < 0.7:
        plant(cell, 2, floor - 11)


def back_kitchen(cell, rnd):
    wall(cell, rnd.choice(WALLS), rnd)
    # Üst dolaplar
    cab = rgb(rnd.choice(["#f2efe6", "#9fc7b5", "#d98a62", "#7f9bb0"]))
    cell.rect(4, 8, 59, 20, cab)
    for x in range(4, 60, 11):
        cell.rect(x, 8, x, 20, shade(cab, 0.8))
        cell.px(x + 5, 18, rgb("#3a3a3a"))
    floor = C - 2
    put_animal(cell, rnd, SPECIES, "ayakta", rnd.choice([22, 40]), floor)
    top = floor - round(0.9 * PX_M)
    cell.rect(0, top, C - 1, top + 1, rgb("#d8d1c3"))                 # tezgâh
    cell.rect(0, top + 2, C - 1, floor, shade(cab, 0.9))
    for x in range(2, 64, 11):
        cell.rect(x, top + 3, x, floor - 1, shade(cab, 0.75))
    cell.rect(48, top - 4, 53, top - 1, rgb("#c0392b"))                # tencere


def back_empty(cell, rnd):
    wall(cell, rnd.choice(WALLS), rnd, stripes=rnd.random() < 0.4)
    floor = C - 2
    kind = rnd.random()
    if kind < 0.5:
        # Kitaplık
        cell.rect(8, 14, 30, floor, rgb("#7a4f30"))
        for y in range(18, floor - 2, 9):
            shelf(cell, rnd, 9, y, 20)
        frame_pic(cell, rnd, 40, 16, 14, 10)
    else:
        window_light(cell, 26, 12)
        plant(cell, 10, floor - 11)
        cell.rect(40, floor - 18, 56, floor, rgb("#9e7b5f"))          # dolap
        cell.rect(48, floor - 18, 48, floor, rgb("#7a5f45"))


def back_shop(cell, rnd):
    wall(cell, rnd.choice(["#f5f1e8", "#eef3f1", "#f6ecdf"]), rnd)
    floor = C - 2
    for y in (16, 26, 36):                                            # mal rafları
        cell.rect(2, y, C - 3, y + 1, rgb("#8a8f94"))
        for x in range(3, C - 3, 3):
            h = rnd.randint(3, 6)
            col = rgb(rnd.choice(["#e05a6a", "#f0b44c", "#7cc6b0", "#8b5fbf", "#4f9a4a", "#4d79a8", "#ffffff"]))
            cell.rect(x, y - h, x + 1, y - 1, col)
    put_animal(cell, rnd, SPECIES, "ayakta", rnd.choice([18, 46]), floor)
    top = floor - round(0.95 * PX_M)
    cell.rect(4, top, 60, top + 1, rgb("#5a3a26"))                    # tezgâh
    cell.rect(5, top + 2, 59, floor, rgb("#a8744a"))
    cell.rect(28, top - 5, 36, top - 1, rgb("#3a3a42"))               # yazar kasa
    cell.rect(29, top - 4, 35, top - 3, rgb("#7fe0a0"))


def side(cell, rnd, i):
    base = WALLS[i % len(WALLS)]
    wall(cell, base, rnd, stripes=i % 3 == 1)
    if i % 2 == 0:
        frame_pic(cell, rnd, 24, 14, 14, 10)
    else:
        shelf(cell, rnd, 10, 30, 30)


def floor_tex(cell, rnd, i):
    base = rgb(FLOORS[i % len(FLOORS)])
    for y in range(C):
        for x in range(C):
            if i % 3 == 0:          # parke
                c = shade(base, 0.85) if y % 8 == 7 or (x + (y // 8) * 13) % 24 == 0 else shade(base, 0.96 + rnd.random() * 0.06)
            elif i % 3 == 1:        # karo
                c = shade(base, 0.8) if x % 16 == 15 or y % 16 == 15 else shade(base, 1.0 + rnd.random() * 0.04)
            else:                   # halı
                c = shade(base, 0.95 + rnd.random() * 0.08)
            cell.px(x, y, c)
    if i % 3 == 2:
        rug = rgb(rnd.choice(["#c0392b", "#2e4a6e", "#8b5fbf"]))
        cell.rect(16, 16, 47, 47, rug)
        cell.rect(18, 18, 45, 45, shade(rug, 1.2))


def ceiling(cell, rnd, i):
    base = rgb("#f4f1ea")
    for y in range(C):
        for x in range(C):
            cell.px(x, y, shade(base, 0.96 + rnd.random() * 0.03))
    cell.rect(28, 28, 35, 35, rgb("#fff2c4"))                         # lamba


def main():
    img = Image.new("RGBA", (C * COLS, C * ROWS), (0, 0, 0, 255))
    rnd = random.Random(42)
    makers = [back_office] * 6 + [back_salon] * 4 + [back_kitchen] * 4 + [back_empty] * 4 + [back_shop] * 6
    for i, mk in enumerate(makers):
        mk(Cell(img, i), rnd)
    for i in range(8):
        side(Cell(img, 24 + i), rnd, i)
        floor_tex(Cell(img, 32 + i), rnd, i)
        ceiling(Cell(img, 40 + i), rnd, i)
    img.save(OUT)
    print("ODA", OUT, "türler:", len(SPECIES))


main()
