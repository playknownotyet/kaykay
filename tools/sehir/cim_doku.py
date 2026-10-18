"""Çim dokusu: 64 x 64 piksel, kenarları birleşen (döşenir) piksel çim -> assets/ada/cim.png

  python tools/sehir/cim_doku.py

Renk değil çarpan dokusu: 128 = 1.0 (arazinin köşe rengi aynen kalır), açık pikseller ot uçları,
koyu pikseller ot dipleri ve gölge. Ortalaması ~1.0: uzaktan bakınca (mipmap) arazinin rengi değişmez.
shaders/terrain.gdshader çimen olan yerlerde (köşe rengi yeşilse) iki ölçekte okuyup çarpar.
"""
import math
import os
import random

import numpy as np
from PIL import Image

S = 64
rnd = random.Random(11)
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ada", "cim.png")

# Döşenebilir yumuşak benek: periyodik değer gürültüsü
def periodic_noise(cells, seed):
    rs = np.random.RandomState(seed)
    g = rs.rand(cells, cells)
    t = np.arange(S) / S * cells
    a = np.floor(t).astype(int)
    f = t - a
    f = f * f * (3 - 2 * f)
    b = (a + 1) % cells
    a = a % cells
    r0 = g[a, :] * (1 - f)[:, None] + g[b, :] * f[:, None]
    return r0[:, a] * (1 - f)[None, :] + r0[:, b] * f[None, :]

base = 0.94 + 0.12 * periodic_noise(4, 1) + 0.06 * periodic_noise(8, 2)
img = np.stack([base, base, base], axis=-1)

# Ot yaprakları: dipte koyu, uçta açık; hafif eğik; sarımsı ve mavimsi uçlar
for _ in range(260):
    x = rnd.randrange(S)
    y = rnd.randrange(S)
    h = rnd.randint(2, 5)
    lean = rnd.choice((-1, 0, 0, 1))
    tipc = rnd.choice(((1.22, 1.24, 1.0), (1.18, 1.22, 0.96), (1.12, 1.2, 1.08), (1.3, 1.26, 0.9)))
    for k in range(h):
        t = k / max(h - 1, 1)
        xx = (x + int(round(lean * t * 1.5))) % S
        yy = (y - k) % S
        if k == 0:
            c = (0.72, 0.76, 0.78)
        else:
            c = tuple(0.95 + (v - 0.95) * t for v in tipc)
        img[yy, xx] = c
# Küçük koyu boşluklar (toprak)
for _ in range(14):
    x, y = rnd.randrange(S), rnd.randrange(S)
    img[y, x] = (0.7, 0.68, 0.62)

# Ortalama 1.0'a çek
img /= img.reshape(-1, 3).mean(axis=0)
out = np.clip(img * 128.0, 0, 255).astype(np.uint8)
Image.fromarray(out, "RGB").save(OUT)
print("cim.png", out.reshape(-1, 3).mean(axis=0) / 128.0)
