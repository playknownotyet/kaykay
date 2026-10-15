"""Kol IK pole açısını kalibre et: dirsek tam olarak pole hedefine baksın.
Böylece her pozda dirsek yönü, hedefin konumuyla doğrudan kontrol edilebilir.
İki farklı hedef konumunda, kol eksenine dik düzlemde dirsek yönü ile hedef yönü
arasındaki açıyı ölçer; her iki konumda da en küçük hatayı veren açı doğrudur."""
import math

import bpy
from mathutils import Vector

arm = bpy.data.objects["KarakterIskelet"]
scene = bpy.context.scene
pb = arm.pose.bones
arm.animation_data.action = bpy.data.actions["ride_idle"]


def perp(v, axis):
    return (v - axis * v.dot(axis)).normalized()


def set_pole(sfx, world):
    b = arm.data.bones[f"pole_elbow.{sfx}"]
    pb[f"pole_elbow.{sfx}"].location = b.matrix_local.to_3x3().inverted() @ (Vector(world) - b.head_local)


TESTS = {"L": [(0.3, 0.5, 0.7), (0.6, 0.0, 0.6)], "R": [(-0.3, 0.5, 0.7), (-0.6, 0.0, 0.6)]}
for sfx in ("L", "R"):
    best = None
    for angle in range(0, 360, 3):
        for c in pb[f"forearm.{sfx}"].constraints:
            if c.type == 'IK':
                c.pole_angle = math.radians(angle)
        errs = []
        for pole in TESTS[sfx]:
            scene.frame_set(0)
            # Animasyonun pole anahtarını ez: kemiği elle yerleştir ve yeniden hesapla
            set_pole(sfx, pole)
            bpy.context.view_layer.update()
            sh = arm.matrix_world @ pb[f"upper_arm.{sfx}"].head
            el = arm.matrix_world @ pb[f"forearm.{sfx}"].head
            wr = arm.matrix_world @ pb[f"forearm.{sfx}"].tail
            axis = (wr - sh).normalized()
            d_el = perp(el - sh, axis)
            d_po = perp(Vector(pole) - sh, axis)
            errs.append(math.degrees(d_el.angle(d_po)))
        e = max(errs)
        if best is None or e < best[0]:
            best = (e, angle, errs)
    print(f"KALIBRE {sfx}: en iyi açı {best[1]}°, hata {best[2][0]:.1f}° / {best[2][1]:.1f}°")
