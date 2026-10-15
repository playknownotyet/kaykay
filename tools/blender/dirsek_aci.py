"""Kol IK pole açısını tara: dirsek arkaya ve hafif dışa bakmalı."""
import math

import bpy

arm = bpy.data.objects["KarakterIskelet"]
scene = bpy.context.scene
pb = arm.pose.bones
for angle in range(0, 181, 15):
    for sfx in ("L", "R"):
        for c in pb[f"forearm.{sfx}"].constraints:
            if c.type == 'IK':
                c.pole_angle = math.radians(angle)
    row = []
    for name in ("ride_idle", "run"):
        arm.animation_data.action = bpy.data.actions[name]
        scene.frame_set(1)
        scene.frame_set(0)
        for sfx, side in (("L", 1), ("R", -1)):
            sh = arm.matrix_world @ pb[f"upper_arm.{sfx}"].head
            el = arm.matrix_world @ pb[f"forearm.{sfx}"].head
            wr = arm.matrix_world @ pb[f"forearm.{sfx}"].tail
            o = el - (sh + wr) * 0.5
            row.append(f"{name[:4]}{sfx} arka={o.y:+.3f} dis={o.x * side:+.3f}")
    print(f"ACI {angle:4d}: " + " | ".join(row))
