"""Onaylı bir eşyanın renk varyantını üretir (ajan gerekmez): köşe renklerinde verilen hex'leri değiştirir,
cikti/<ad>_<v>/ altına .blend + .glb + önizleme yazar.
  Blender --background --python tools/argon/renk_varyanti.py -- <ad> <v> <eski_hex>=<yeni_hex> [...]
"""
import os
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
AD, V = args[0], args[1]
ESLEME = []
for a in args[2:]:
    e, y = a.split("=")
    ESLEME.append((e, y))

KOK = "/Users/kerem/Projects/kaykay/art/argon"
exec(open(os.path.join(KOK, "araclar/kaykay_araclar.py")).read())

bpy.ops.wm.open_mainfile(filepath=os.path.join(KOK, "cikti", AD, AD + ".blend"))
yeni = AD + "_" + V
o = bpy.data.objects[AD]
o.name = yeni
o.data.name = yeni
klasor = os.path.join(KOK, "cikti", yeni)
os.makedirs(klasor, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(klasor, yeni + ".blend"))
ca = o.data.color_attributes["Col"]
n = 0
for d in ca.data:
    c = d.color_srgb
    for e, y in ESLEME:
        er = _hex(e)
        if abs(c[0] - er[0]) < 0.02 and abs(c[1] - er[1]) < 0.02 and abs(c[2] - er[2]) < 0.02:
            yr = _hex(y)
            d.color_srgb = (yr[0], yr[1], yr[2], c[3])
            n += 1
            break
o.data.update()
print("VARYANT", yeni, "degisen", n)
print("AKTAR", disa_aktar(yeni))
