"""Her animasyonda dirseğin nereye büküldüğünü ölçer.
Dirsek, omuz-bilek çizgisinin ortasına göre: dy > 0 = arkaya (doğru), dy < 0 = öne;
dis > 0 = gövdeden dışa, dis < 0 = gövdeye doğru (yanlış). Ayrıca kolun açılma açısı.

  blender --background art/karakter/karakter_rig.blend --python tools/blender/dirsek_olc.py
"""
import math

import bpy

arm = bpy.data.objects["KarakterIskelet"]
scene = bpy.context.scene
pb = arm.pose.bones
for name in ["ride_idle", "ride_turn_l", "push", "air", "grind", "flip", "ollie", "run"]:
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    f0, f1 = act.frame_range
    for f in (f0, (f0 + f1) / 2):
        scene.frame_set(int(f))
        out = []
        for sfx, side in (("L", 1), ("R", -1)):
            sh = arm.matrix_world @ pb[f"upper_arm.{sfx}"].head
            el = arm.matrix_world @ pb[f"forearm.{sfx}"].head
            wr = arm.matrix_world @ pb[f"forearm.{sfx}"].tail
            mid = (sh + wr) * 0.5
            o = el - mid
            arm_vec = wr - sh
            spread = math.degrees(math.atan2(abs(arm_vec.x), -arm_vec.z))
            out.append(f"{sfx}: arka={o.y:+.3f} dis={o.x * side:+.3f} asagi={-o.z:+.3f} aciklik={spread:3.0f}°")
        print(f"DIRSEK {name:11s} f{int(f):3d}  " + "   ".join(out))
