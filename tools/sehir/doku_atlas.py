"""Girilebilir dükkânların (Zürafa Bakkal) piksel dokuları: assets/sehir/dokular.png

  python tools/sehir/doku_atlas.py

Süs binalarının cepheleriyle (cephe_atlas.py) aynı tarz: 32x32 piksel karolar, hafif gren.
Karolar (soldan, shaders/doku.gdshader "tile"):
  0 dış sıva          1 taş kaide         2 silme / korniş    3 çatı çakılı
  4 iç sıva           5 ahşap lambri      6 tabela tahtası    7 ahşap
"""
import os
import random

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "sehir", "dokular.png")
C = 32


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def tile(img, i, fn, seed):
    rnd = random.Random(seed)
    for y in range(C):
        for x in range(C):
            img.putpixel((i * C + x, y), fn(x, y, rnd) + (255,))


def stucco(base, speck=0.05):
    b = rgb(base)

    def f(x, y, rnd):
        k = 0.96 + rnd.random() * 0.07
        if rnd.random() < speck:
            k *= 0.9
        return shade(b, k)
    return f


def stone(x, y, rnd):
    row = y // 8
    off = 6 if row % 2 else 0
    mortar = y % 8 == 7 or (x + off) % 12 == 11
    if mortar:
        return rgb("#d9d2c6")
    blk = ((x + off) // 12 + row * 7) % 3
    base = [rgb("#a39d95"), rgb("#958f88"), rgb("#aca69d")][blk]
    return shade(base, 0.93 + rnd.random() * 0.12)


def trim(x, y, rnd):
    t = rgb("#fbf3ea")
    if y in (0, 1, 16, 17):
        return shade(t, 1.04)
    if y in (14, 15, 30, 31):
        return shade(t, 0.84)
    return shade(t, 0.97 + rnd.random() * 0.04)


def gravel(x, y, rnd):
    return shade(rgb("#8f8c88"), 0.82 + rnd.random() * 0.28)


def planks(base, w=8):
    b = rgb(base)

    def f(x, y, rnd):
        if x % w == w - 1:
            return shade(b, 0.72)
        if x % w == 0:
            return shade(b, 1.06)
        return shade(b, 0.95 + rnd.random() * 0.08 - (0.04 if (y + x * 3) % 13 == 0 else 0.0))
    return f


def board(x, y, rnd):
    b = rgb("#2c5c4c")
    if y % 8 == 7:
        return shade(b, 0.78)
    return shade(b, 0.94 + rnd.random() * 0.1)


def main():
    img = Image.new("RGBA", (C * 8, C), (0, 0, 0, 0))
    tile(img, 0, stucco("#f3dcae"), 1)
    tile(img, 1, stone, 2)
    tile(img, 2, trim, 3)
    tile(img, 3, gravel, 4)
    tile(img, 4, stucco("#f6f1e4", 0.02), 5)
    tile(img, 5, planks("#7fb79c"), 6)
    tile(img, 6, board, 7)
    tile(img, 7, planks("#9a6a42", 6), 8)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("DOKU", OUT)


main()
