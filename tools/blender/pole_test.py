"""IK pole açısını ölçerek bul: çömelmede diz öne (-Y), dirsek arkaya (+Y) gitmeli."""
import math

import bpy
from mathutils import Vector

arm = bpy.data.objects["KarakterIskelet"]
act = bpy.data.actions[__import__("sys").argv[-1]]
arm.animation_data.action = act
scene = bpy.context.scene

for angle in (-90, 0, 90, 180):
    for p in arm.pose.bones:
        for c in p.constraints:
            if c.type == 'IK':
                c.pole_angle = math.radians(angle)
    scene.frame_set(1)
    scene.frame_set(0)
    out = []
    for sfx in ("L", "R"):
        knee = arm.matrix_world @ arm.pose.bones[f"shin.{sfx}"].head
        hip = arm.matrix_world @ arm.pose.bones[f"thigh.{sfx}"].head
        ankle = arm.matrix_world @ arm.pose.bones[f"shin.{sfx}"].tail
        mid = (hip + ankle) * 0.5
        elbow = arm.matrix_world @ arm.pose.bones[f"forearm.{sfx}"].head
        sh = arm.matrix_world @ arm.pose.bones[f"upper_arm.{sfx}"].head
        wr = arm.matrix_world @ arm.pose.bones[f"forearm.{sfx}"].tail
        emid = (sh + wr) * 0.5
        k = knee - mid
        e = elbow - emid
        out.append(f"{sfx}: diz dy={k.y:+.3f} dx={k.x:+.3f} | dirsek dy={e.y:+.3f} dx={e.x:+.3f}")
    print(f"POLE {angle:4d}: " + "  ".join(out))
