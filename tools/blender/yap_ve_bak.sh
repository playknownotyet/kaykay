#!/bin/bash
# Modeli üretir, ön izleme render'larını alır ve tek görselde birleştirir.
set -e
B="/d/SteamLibrary/steamapps/common/Blender/blender.exe"
cd /d/kaykay
"$B" --background --factory-startup --python tools/blender/karakter_model.py -- "D:/kaykay/art/karakter/karakter.blend" 2>&1 | grep -iE "Traceback|Error|KAYDEDILDI" || true
"$B" --background "D:/kaykay/art/karakter/karakter.blend" --python tools/blender/onizleme.py -- "D:/kaykay/tests/screens/karakter" ${1:-on,ucdort,yan,arka,yuz} 2>&1 | grep -iE "Traceback|Error" || true
cd tests/screens/karakter && python -c "
import sys
from PIL import Image
names='${1:-on,ucdort,yan,arka,yuz}'.split(',')
ims=[Image.open(f'karakter_{n}.png') for n in names]
W=sum(i.width for i in ims); H=max(i.height for i in ims)
g=Image.new('RGB',(W,H)); x=0
for i in ims: g.paste(i,(x,0)); x+=i.width
g.save('karakter_hepsi.png')"
"$B" --background "D:/kaykay/art/karakter/karakter.blend" --python tools/blender/karakter_rig.py -- "D:/kaykay/assets/karakter/karakter.glb" 2>&1 | grep -iE "Traceback|Error|GLB" || true
echo TAMAM
