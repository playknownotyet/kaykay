"""Bir hayvan NPC türünü üretir: türün gövdesi, kafa/boyun, eller, ona biçilmiş kıyafetler,
iskelet (türün ek zincirleriyle) ve türe özel animasyonlar. Tür başına bir .glb çıkar.

  blender --background --factory-startup --python tools/blender/npc_build.py -- <tur> assets/npc/<tur>.glb [onizleme_klasoru]

Türler tools/blender/npc_turler/<tur>.py içinde. Ortak araçlar npc_ortak.py.
Parça adları Godot kataloğuyla aynı olmalı (scripts/npc/npc_catalog.gd):
  deri_govde, deri_kol_ust, deri_kol_alt, tur_bas, tur_eller, [tur_kuyruk ...],
  ust_*, alt_*, ayk_*, sapka_*, aks_*.
Malzeme adları renk yuvalarıdır (Godot NPC başına boyar).
"""
import importlib.util
import json
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_ortak as O  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TUR = args[0] if args else "zurafa"
OUT_GLB = args[1] if len(args) > 1 else f"{TUR}.glb"
PREVIEW_DIR = os.path.abspath(args[2]) if len(args) > 2 else None
FPS = 30


def load_species(name):
    path = os.path.join(HERE, "npc_turler", f"{name}.py")
    spec = importlib.util.spec_from_file_location(f"tur_{name}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def skin_all(parts, arm, B):
    deform = [b.name for b in arm.data.bones if b.use_deform]
    upper = [b for b in deform if b not in O.LEG_BONES]
    torso = [b for b in deform if b in ("hips", "spine", "chest") or b == "neck" or b.startswith("neck.")]
    for o in parts:
        n = o.name
        if n == "deri_govde":
            O.skin(o, arm, "upper", torso + O.ARM_BONES, B)
        elif n.startswith("deri_kol"):
            O.skin(o, arm, "upper", ["chest"] + O.ARM_BONES, B)
        elif n.startswith("tur_"):
            O.skin(o, arm, "dist", upper)
        elif n.startswith("ust_"):
            O.skin(o, arm, "top", torso + O.ARM_BONES, B)
        elif n.startswith("alt_"):
            O.skin(o, arm, "pants", ["hips"] + O.LEG_BONES, B)
        elif n.startswith("ayk_"):
            O.skin(o, arm, "foot")
        elif n.startswith("sapka_"):
            O.skin(o, arm, "fixed", "head")
        elif n == "aks_evrak":
            O.skin(o, arm, "fixed", "hand.R")
        else:
            O.skin(o, arm, "dist", torso)


def previews(sp, parts, arm, B):
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    tmp = os.path.join(PREVIEW_DIR, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    by = {o.name: o for o in parts}
    base = [n for n in by if n.startswith("tur_")]
    top_z = max(B.head_top, max((v.co.z for v in by["tur_bas"].data.vertices), default=2.0))
    H = top_z * 1.08
    arm.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(0)

    def show(names):
        for o in parts:
            o.hide_render = o.name not in names

    # 1) Kıyafet kombinasyonları
    shots = []
    for i, outfit in enumerate(sp.PREVIEW):
        names = set(base + outfit + O.visible_skin(outfit))
        show(names)
        shots.append(O.render_view(os.path.join(tmp, f"k{i}.png"), H * 0.5, H, -28, res=(420, int(420 * 1.75))))
    O.stitch(shots, os.path.join(PREVIEW_DIR, f"{TUR}_kiyafetler.png"))

    # 2) Kafa / boyun yakın çekim: önden, yandan, 3/4
    outfit = sp.PREVIEW[0]
    show(set(base + outfit + O.visible_skin(outfit)))
    hz = B.head_c.z
    shots = []
    for i, ang in enumerate((0, -35, -90, 160)):
        shots.append(O.render_view(os.path.join(tmp, f"b{i}.png"), hz - 0.08, 0.75, ang, res=(420, 420)))
    O.stitch(shots, os.path.join(PREVIEW_DIR, f"{TUR}_kafa.png"))

    # 2b) Omuz / kol birleşimi: çıplak gövde, tişört, ceket (önden ve 3/4)
    shots = []
    sz = B.shoulder_z
    for outfit in ([], ["ust_tisort", "alt_kot"], ["ust_takim", "alt_takim"]):
        show(set(base + outfit + O.visible_skin(outfit)))
        for ang in (0, -40):
            shots.append(O.render_view(os.path.join(tmp, f"o{len(shots)}.png"), sz - 0.2, 0.9, ang, res=(360, 360)))
    O.stitch(shots, os.path.join(PREVIEW_DIR, f"{TUR}_omuz.png"), cols=6)

    # 3) Yürüyüş evreleri (yandan) ve affallama
    shots = []
    arm.animation_data.action = bpy.data.actions["walk"]
    n = int(bpy.data.actions["walk"].frame_range[1])
    for i in range(4):
        bpy.context.scene.frame_set(int(n * i / 4))
        shots.append(O.render_view(os.path.join(tmp, f"w{i}.png"), H * 0.5, H, -90, res=(300, int(300 * 1.75))))
    arm.animation_data.action = bpy.data.actions["stumble"]
    for f in (3, 8, 14, 26):
        bpy.context.scene.frame_set(f)
        shots.append(O.render_view(os.path.join(tmp, f"s{f}.png"), H * 0.5, H, -60, res=(300, int(300 * 1.75))))
    O.stitch(shots, os.path.join(PREVIEW_DIR, f"{TUR}_hareket.png"), cols=4)
    for o in parts:
        o.hide_render = False
    arm.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(0)


def main():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    sp = load_species(TUR)
    O.PALETTE.update(sp.PALETTE)
    O.reseed(sum(map(ord, TUR)))
    B = sp.body()
    parts = []
    sp.build(B, parts)
    O.build_clothes(B, parts)
    arm = O.build_armature(B, sp.chains(B))
    skin_all(parts, arm, B)
    A = O.Animator(arm, B)
    O.standard_actions(A, sp.STYLE, sp.secondary(A))
    bpy.context.scene.render.fps = FPS
    if PREVIEW_DIR:
        previews(sp, parts, arm, B)
    arm.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(0)
    out_blend = os.path.normpath(os.path.join(HERE, "..", "..", "art", "npc", f"{TUR}.blend"))
    os.makedirs(os.path.dirname(out_blend), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB, export_format='GLB', export_animations=True,
        export_animation_mode='ACTIONS', export_force_sampling=True,
        export_def_bones=True, export_yup=True,
    )
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in parts)
    print("GLB", OUT_GLB, "PARCA", len(parts), "UCGEN", tris, "ANIM", A.actions,
          "YURUME_HIZI %.3f" % O.walk_speed(sp.STYLE), "BOY %.2f" % B.head_top)


main()
