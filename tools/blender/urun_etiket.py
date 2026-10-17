"""Market ürünlerinin etiketleri (piksel-art doku atlası): assets/dukkan/urun_etiket.png

  python tools/blender/urun_etiket.py

Hücre 64x64 piksel; atlas 8 sütun x 2 satır. Hücre sırası tools/blender/dukkan_build.py LABELS ile aynı.
Silindir ürünlerde (kola, su, bal, şampuan, konserve) etiket gövdeyi saran şerittir: hücrenin
genişliği çevre, yüksekliği şeridin boyu; ön yüz hücrenin ortasında (u = 0,5).
"""
import os
import random

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "dukkan", "urun_etiket.png")
C = 64
COLS, ROWS = 8, 2
CELLS = ["kola", "su", "sut_on", "sut_yan", "gevrek_on", "gevrek_yan", "cips_on", "cikolata",
         "bal", "kurabiye", "macun", "sampuan", "konserve", "yumurta_kapak", "", ""]


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# 3x5 piksel yazı (büyük harf, Türkçe)
FONT = {
    "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
    "C": ["011", "100", "100", "100", "011"], "Ç": ["011", "100", "100", "011", "010"],
    "D": ["110", "101", "101", "101", "110"], "E": ["111", "100", "110", "100", "111"],
    "F": ["111", "100", "110", "100", "100"], "G": ["011", "100", "101", "101", "011"],
    "Ğ": ["111", "011", "100", "101", "011"], "H": ["101", "101", "111", "101", "101"],
    "I": ["111", "010", "010", "010", "111"], "İ": ["010", "000", "010", "010", "010"],
    "K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
    "M": ["101", "111", "111", "101", "101"], "N": ["110", "101", "101", "101", "101"],
    "O": ["010", "101", "101", "101", "010"], "Ö": ["101", "010", "101", "101", "010"],
    "P": ["110", "101", "110", "100", "100"], "R": ["110", "101", "110", "101", "101"],
    "S": ["011", "100", "010", "001", "110"], "Ş": ["011", "100", "011", "001", "110"],
    "T": ["111", "010", "010", "010", "010"], "U": ["101", "101", "101", "101", "111"],
    "Ü": ["101", "000", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"],
    "Y": ["101", "101", "010", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
    "%": ["101", "001", "010", "100", "101"], "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"], "6": ["011", "100", "111", "101", "111"],
    " ": ["000", "000", "000", "000", "000"], "!": ["010", "010", "010", "000", "010"],
}


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

    def fill(self, c):
        self.rect(0, 0, C - 1, C - 1, c)

    def disc(self, cx, cy, r, c, ry=None):
        ry = r if ry is None else ry
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if ((x - cx) / r) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.px(x, y, c)

    def text(self, s, cx, y, c, scale=1, shadow=None):
        w = len(s) * 4 * scale - scale
        x = int(cx - w / 2)
        for ch in s:
            g = FONT.get(ch, FONT[" "])
            for j, row in enumerate(g):
                for i, b in enumerate(row):
                    if b == "1":
                        if shadow:
                            self.rect(x + i * scale + scale // 2 + 1, y + j * scale + 1, x + i * scale + scale // 2 + scale, y + j * scale + scale, shadow)
                        self.rect(x + i * scale, y + j * scale, x + i * scale + scale - 1, y + j * scale + scale - 1, c)
            x += 4 * scale


def noise(cell, base, rnd, amt=0.05):
    for y in range(C):
        for x in range(C):
            cell.px(x, y, shade(base, 1.0 - amt + rnd.random() * amt * 2))


# ---------- Etiketler ----------

def kola(c, rnd):
    red = rgb("#d81e2a")
    noise(c, red, rnd, 0.03)
    # Beyaz dalga şerit (kutuyu sarar)
    for x in range(C):
        import math
        y = 34 + int(math.sin(x / C * math.tau * 2) * 4)
        c.rect(x, y, x, y + 4, (250, 250, 250))
        c.px(x, y + 5, shade(red, 0.75))
    c.text("KOLA", 32, 14, (255, 255, 255), 3, shadow=shade(red, 0.6))
    for x in (12, 52):
        c.disc(x, 50, 2, (255, 230, 120))


def su(c, rnd):
    import math
    for y in range(C):
        for x in range(C):
            c.px(x, y, mix(rgb("#bfe6ff"), rgb("#2a7fd0"), y / C))
    # Dağ ve dalga
    for x in range(14, 50):
        h = 16 - abs(x - 32) * 0.8
        c.rect(x, 42 - h, x, 42, rgb("#2b5f9e") if x < 32 else rgb("#244f86"))
        if h > 10:
            c.rect(x, 42 - h, x, 42 - h + 3, (255, 255, 255))
    for x in range(C):
        y = 44 + int(math.sin(x / 6.0) * 1.5)
        c.rect(x, y, x, y + 2, (255, 255, 255))
    c.text("SU", 32, 6, (255, 255, 255), 3, shadow=rgb("#1a4f90"))
    c.text("DOĞAL", 32, 52, (255, 255, 255), 1)


def sut_on(c, rnd):
    import math
    c.fill((250, 250, 248))
    # İnek benekleri
    for (x, y, r) in ((10, 12, 4), (52, 8, 5), (48, 26, 3), (8, 30, 3)):
        c.disc(x, y, r, (40, 40, 45), r * 0.8)
    c.text("SÜT", 32, 12, rgb("#1f5fc4"), 3, shadow=rgb("#9ab8e8"))
    # Mavi dalga taban ve süt bardağı
    for x in range(C):
        y = 44 + int(math.sin(x / 8.0) * 2)
        c.rect(x, y, x, C - 1, rgb("#2d6fd6"))
    c.rect(26, 32, 37, 50, (235, 240, 248))
    c.rect(27, 33, 36, 49, (255, 255, 255))
    c.rect(26, 32, 37, 33, rgb("#9ab8e8"))
    c.text("TAZE", 32, 55, (255, 255, 255), 1)


def sut_yan(c, rnd):
    c.fill((250, 250, 248))
    c.rect(0, 40, C - 1, C - 1, rgb("#2d6fd6"))
    for (x, y) in ((16, 20), (32, 14), (48, 22)):
        c.disc(x, y, 4, rgb("#9ab8e8"), 5)
        c.px(x, y - 6, rgb("#9ab8e8"))


def gevrek_on(c, rnd):
    noise(c, rgb("#ffcb2b"), rnd, 0.03)
    # Güneş ışınları
    for k in range(12):
        import math
        a = k / 12 * math.tau
        for r in range(18, 40):
            if k % 2 == 0:
                c.px(32 + math.cos(a) * r, 42 + math.sin(a) * r * 0.8, rgb("#ffdc64"))
    # Logo bandı
    c.rect(0, 2, C - 1, 15, rgb("#d93a2a"))
    c.rect(0, 16, C - 1, 17, rgb("#a82418"))
    c.text("GEVREK", 32, 5, (255, 245, 210), 2)
    # Kase ve gevrekler
    c.disc(32, 44, 20, rgb("#f4f4f4"), 7)
    c.disc(32, 41, 18, rgb("#fffaf0"), 5)
    for _ in range(28):
        x = 32 + rnd.randint(-15, 15)
        y = 40 + rnd.randint(-5, 2)
        c.rect(x, y, x + 1, y, rgb(rnd.choice(["#e8a23a", "#d98a2a", "#f2b84a"])))
    for y in range(46, 58):
        w = int(20 * (1 - ((y - 46) / 12) ** 2) ** 0.5)
        c.rect(32 - w, y, 32 + w, y, rgb("#3a7bd5"))
    c.rect(18, 46, 46, 47, rgb("#6aa0ea"))
    # Çilek
    c.disc(48, 36, 3, rgb("#e0303a"))
    c.px(48, 32, rgb("#3f9a3a"))


def gevrek_yan(c, rnd):
    noise(c, rgb("#ffcb2b"), rnd, 0.03)
    c.rect(0, 2, C - 1, 15, rgb("#d93a2a"))
    c.rect(6, 22, 57, 58, (255, 255, 255))
    for y in range(26, 56, 4):
        c.rect(9, y, 54, y, (120, 120, 120))
        c.rect(40, y, 54, y, (60, 60, 60))


def cips_on(c, rnd):
    noise(c, rgb("#f4801f"), rnd, 0.04)
    # Parlak folyo çizgileri
    for x in range(0, C, 9):
        c.rect(x, 0, x, C - 1, shade(rgb("#f4801f"), 1.12))
    c.rect(0, 6, C - 1, 20, rgb("#7a2a8c"))
    c.rect(0, 21, C - 1, 22, rgb("#4e1a5a"))
    c.text("CİPS", 32, 9, (255, 230, 90), 2, shadow=rgb("#3a1044"))
    # Cips yığını
    for (x, y, r) in ((22, 44, 9), (36, 40, 10), (44, 50, 8), (28, 52, 8), (14, 52, 6)):
        c.disc(x, y, r, rgb("#f6cf5a"), r * 0.7)
        c.disc(x - 2, y - 1, r * 0.5, rgb("#ffe58a"), r * 0.3)
        c.px(x + r * 0.3, y + 1, rgb("#d9a23a"))
    c.text("ACI", 50, 28, (255, 255, 255), 1)


def cikolata(c, rnd):
    purple = rgb("#5a2a8a")
    noise(c, purple, rnd, 0.03)
    # Yaldız uçlar
    c.rect(0, 0, 9, C - 1, rgb("#e8b83a"))
    c.rect(54, 0, C - 1, C - 1, rgb("#e8b83a"))
    for y in range(0, C, 3):
        c.rect(0, y, 9, y, rgb("#c9952a"))
        c.rect(54, y, C - 1, y, rgb("#c9952a"))
    c.text("ÇİKO", 32, 10, rgb("#ffd34a"), 3, shadow=rgb("#2a103e"))
    # Kırık çikolata parçası
    for i in range(3):
        for j in range(2):
            x0, y0 = 18 + i * 9, 36 + j * 9
            c.rect(x0, y0, x0 + 7, y0 + 7, rgb("#6b3a1f"))
            c.rect(x0 + 1, y0 + 1, x0 + 6, y0 + 2, rgb("#8a5230"))
    c.rect(18, 54, 44, 55, (255, 255, 255))


def bal(c, rnd):
    amber = rgb("#e89a20")
    noise(c, amber, rnd, 0.03)
    # Petek
    for row in range(0, 10):
        for col in range(0, 10):
            x = col * 7 + (3 if row % 2 else 0)
            y = row * 6
            c.rect(x, y, x + 5, y, shade(amber, 0.75))
            c.rect(x, y, x, y + 4, shade(amber, 0.75))
    c.rect(4, 16, 59, 46, rgb("#fff2c8"))
    c.rect(4, 16, 59, 17, rgb("#8a4f10"))
    c.rect(4, 45, 59, 46, rgb("#8a4f10"))
    c.text("BAL", 32, 22, rgb("#8a4f10"), 3)
    # Arı
    c.disc(50, 40, 3, rgb("#f2c22a"), 2)
    c.rect(49, 38, 49, 42, (30, 30, 30))
    c.rect(51, 38, 51, 42, (30, 30, 30))
    c.disc(49, 36, 2, (230, 240, 255), 1)


def kurabiye(c, rnd):
    noise(c, rgb("#2a62b8"), rnd, 0.03)
    c.text("KURABİYE", 32, 4, (255, 240, 200), 1)
    # Kurabiye resmi: çikolata parçacıklı
    for (x, y, r) in ((20, 34, 12), (44, 38, 12), (32, 50, 10)):
        c.disc(x, y, r, rgb("#d39a52"))
        c.disc(x - 2, y - 2, r * 0.7, rgb("#e2b26a"))
        for _ in range(5):
            c.rect(x + rnd.randint(-r + 3, r - 4), y + rnd.randint(-r + 3, r - 4), 0, 0, (0, 0, 0)) if False else None
        for _ in range(5):
            px = x + rnd.randint(-r + 4, r - 4)
            py = y + rnd.randint(-r + 4, r - 4)
            c.rect(px, py, px + 1, py + 1, rgb("#4a2a14"))
    c.rect(0, 12, C - 1, 13, rgb("#f0c64a"))


def macun(c, rnd):
    c.fill((248, 250, 252))
    c.rect(0, 0, C - 1, 20, rgb("#1f6fd6"))
    c.text("DİŞ", 32, 4, (255, 255, 255), 2)
    # Fırça ve macun
    c.rect(8, 40, 50, 43, rgb("#2aa0e0"))
    c.rect(44, 33, 56, 39, (255, 255, 255))
    for x in range(45, 56, 2):
        c.rect(x, 33, x, 39, rgb("#9ad0f0"))
    for (x, y) in ((44, 30), (48, 28), (52, 29), (56, 31)):
        c.disc(x, y, 2, (255, 255, 255))
        c.px(x, y, rgb("#e03a3a"))
    c.rect(0, 52, C - 1, 55, rgb("#e03a3a"))
    c.text("NANE", 32, 57, rgb("#1f6fd6"), 1)


def sampuan(c, rnd):
    green = rgb("#3fb06a")
    noise(c, green, rnd, 0.03)
    c.rect(6, 10, 57, 52, (250, 255, 250))
    c.rect(6, 10, 57, 11, shade(green, 0.7))
    c.text("ŞAMPUAN", 32, 14, shade(green, 0.65), 1)
    # Köpük ve yaprak
    for (x, y, r) in ((24, 34, 7), (34, 30, 6), (40, 38, 5), (28, 42, 4)):
        c.disc(x, y, r, rgb("#d6f0ff"))
        c.disc(x - r * 0.3, y - r * 0.3, r * 0.3, (255, 255, 255))
    c.disc(46, 44, 4, rgb("#4f9a4a"), 2)


def konserve(c, rnd):
    green = rgb("#2f8a3a")
    noise(c, green, rnd, 0.03)
    c.rect(0, 4, C - 1, 15, rgb("#f2e6c8"))
    c.text("BEZELYE", 32, 7, rgb("#2f6a2a"), 1)
    # Bezelyeler kâsede
    c.disc(32, 44, 18, rgb("#f4f4f4"), 6)
    for _ in range(26):
        x = 32 + rnd.randint(-14, 14)
        y = 38 + rnd.randint(-5, 4)
        c.disc(x, y, 2, rgb(rnd.choice(["#6fcf4a", "#5ab83a", "#86de5a"])))
    c.rect(0, 58, C - 1, 61, rgb("#f2e6c8"))


def yumurta_kapak(c, rnd):
    base = rgb("#b8a68a")
    noise(c, base, rnd, 0.06)
    c.rect(8, 16, 55, 46, (250, 245, 232))
    c.text("YUMURTA", 32, 20, rgb("#8a5a2a"), 1)
    c.disc(32, 36, 7, (255, 250, 238), 8)
    c.disc(32, 36, 5, rgb("#ffd34a"))
    c.text("6", 50, 40, rgb("#8a5a2a"), 1)


MAKERS = {"kola": kola, "su": su, "sut_on": sut_on, "sut_yan": sut_yan, "gevrek_on": gevrek_on,
          "gevrek_yan": gevrek_yan, "cips_on": cips_on, "cikolata": cikolata, "bal": bal, "kurabiye": kurabiye,
          "macun": macun, "sampuan": sampuan, "konserve": konserve, "yumurta_kapak": yumurta_kapak}


def main():
    img = Image.new("RGBA", (C * COLS, C * ROWS), (255, 255, 255, 255))
    for i, name in enumerate(CELLS):
        if name:
            MAKERS[name](Cell(img, i), random.Random(100 + i))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("ETIKET", OUT)


main()
