"""Karakter modeline iskelet, ağırlık ve animasyonlar ekler; Godot için .glb verir.

  blender --background art/karakter/karakter.blend --python tools/blender/karakter_rig.py -- assets/karakter/karakter.glb [onizleme_klasoru]

Kaynak .blend dosyaları art/ altında (Godot orayı taramaz, .gdignore); Godot sadece .glb'yi görür.

İskelet:
- Deform kemikler: hips, spine, chest, neck, head, kollar (upper_arm/forearm/hand),
  bacaklar (thigh/shin/foot) ve ayrı bir kök kemik olarak "board" (kaykay).
- Kontrol kemikleri: ayak/el hedefleri, diz/dirsek yönleri (IK) ve sağ ele bağlı
  "board_carry" (kaykayın elde taşınma noktası).
- "board" kemiği bir Copy Transforms kısıtıyla board_carry'yi izler; kısıtın etkisi
  (carry) animasyonda anahtarlanır: 0 = kaykay yerde/ayak altında, 1 = elde.

Pozlar "ayak şurada, el şurada" diye dünya koordinatında verilir (IK çözer).
Kaykay pozlarında ayaklar kaykay yüzeyinde (z = DECK_TOP), zemin z = 0.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = args[0] if args else "karakter.glb"
PREVIEW_DIR = args[1] if len(args) > 1 else None

DECK_TOP = 0.09
FPS = 30
MOUNT_FRAMES = 24        # 0.8 sn: Godot'taki MOUNT_TIME ile aynı
MOUNT_SPEED = 2.2        # binerken yürüyüş hızı (m/sn): Godot ile aynı olmalı
DISMOUNT_FRAMES = 15
OLLIE_POP_FRAME = 3      # 0.1 sn hazırlık: Godot'taki ollie_windup ile aynı
PUSH_RET_FRAMES = 10     # itmeden dönüş: Godot player_visual.gd ile aynı süre
YAYA_ZIPLA_FRAMES = 12   # Godot player_visual.gd ile aynı
YAYA_INIS_FRAMES = 10
TUCK = 0.08              # havada dizler toplu: ayaklar ve kaykay köke göre bu kadar yukarıda

# ---------------------------------------------------------------------------
# Kemikler (Blender: karakter -Y'ye bakar, solu +X)
# ---------------------------------------------------------------------------
ARM_DIR = Vector((math.sin(math.radians(40)), 0, -math.cos(math.radians(40))))


def arm(side):
    d = Vector((ARM_DIR.x * side, 0, ARM_DIR.z))
    s = Vector((0.165 * side, 0.0, 1.075))
    # Dirseğe hafif geri bükülme: düz zincirde IK bükülme yönünü bulamaz
    e = s + d * 0.25 + Vector((0, 0.015, 0))
    w = s + d * 0.47
    h = w + d * 0.1
    return s, e, w, h


def deform_bones():
    b = {
        "hips": ((0, 0.005, 0.70), (0, 0.005, 0.84), None),
        "spine": ((0, 0.005, 0.84), (0, 0.0, 0.96), "hips"),
        "chest": ((0, 0.0, 0.96), (0, 0.0, 1.10), "spine"),
        "neck": ((0, 0.005, 1.10), (0, 0.01, 1.18), "chest"),
        "head": ((0, 0.01, 1.18), (0, 0.01, 1.42), "neck"),
        "board": ((0, 0, 0), (0, -0.3, 0), None),
        # Sırt çantası: kısıtlarla ya sırtta (göğse bağlı) ya sol elde (bkz. add_bag_bones)
        "canta": ((0, 0.18, 0.96), (0, 0.18, 1.08), None),
    }
    for side, sfx in ((1, "L"), (-1, "R")):
        s, e, w, h = arm(side)
        b[f"upper_arm.{sfx}"] = (tuple(s), tuple(e), "chest")
        b[f"forearm.{sfx}"] = (tuple(e), tuple(w), f"upper_arm.{sfx}")
        b[f"hand.{sfx}"] = (tuple(w), tuple(h), f"forearm.{sfx}")
        x = 0.11 * side
        b[f"thigh.{sfx}"] = ((0.085 * side, 0.005, 0.70), (0.1 * side, -0.012, 0.40), "hips")
        b[f"shin.{sfx}"] = ((0.1 * side, -0.012, 0.40), (x, 0.01, 0.075), f"thigh.{sfx}")
        b[f"foot.{sfx}"] = ((x, 0.01, 0.075), (x, -0.13, 0.03), f"shin.{sfx}")
    return b


def build_armature():
    arm_data = bpy.data.armatures.new("KarakterIskelet")
    arm_obj = bpy.data.objects.new("KarakterIskelet", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones
    bones = deform_bones()
    for name, (h, t, _) in bones.items():
        bone = eb.new(name)
        bone.head = h
        bone.tail = t
        bone.use_deform = True
    for name, (_, _, parent) in bones.items():
        if parent:
            eb[name].parent = eb[parent]
            eb[name].use_connect = (Vector(eb[parent].tail) - Vector(eb[name].head)).length < 1e-4
    for sfx, side in (("L", 1), ("R", -1)):
        foot = eb[f"foot.{sfx}"]
        ik = eb.new(f"ik_foot.{sfx}")
        ik.head = foot.head
        ik.tail = foot.tail
        ik.use_deform = False
        pole = eb.new(f"pole_knee.{sfx}")
        pole.head = (0.1 * side, -0.5, 0.42)
        pole.tail = (0.1 * side, -0.55, 0.42)
        pole.use_deform = False
        hand = eb[f"hand.{sfx}"]
        ikh = eb.new(f"ik_hand.{sfx}")
        ikh.head = hand.head
        ikh.tail = hand.tail
        ikh.use_deform = False
        pe = eb.new(f"pole_elbow.{sfx}")
        e = eb[f"forearm.{sfx}"].head
        pe.head = (e.x, 0.45, e.z)
        pe.tail = (e.x, 0.5, e.z)
        pe.use_deform = False
    bpy.ops.object.mode_set(mode='POSE')
    pb = arm_obj.pose.bones
    for sfx in ("L", "R"):
        c = pb[f"shin.{sfx}"].constraints.new('IK')
        c.target = arm_obj
        c.subtarget = f"ik_foot.{sfx}"
        c.pole_target = arm_obj
        c.pole_subtarget = f"pole_knee.{sfx}"
        c.pole_angle = math.radians(-90)  # ölçüldü: diz öne (-Y) bakar
        c.chain_count = 2
        cr = pb[f"foot.{sfx}"].constraints.new('COPY_ROTATION')
        cr.target = arm_obj
        cr.subtarget = f"ik_foot.{sfx}"
        c = pb[f"forearm.{sfx}"].constraints.new('IK')
        c.target = arm_obj
        c.subtarget = f"ik_hand.{sfx}"
        c.pole_target = arm_obj
        c.pole_subtarget = f"pole_elbow.{sfx}"
        # Kalibre edildi (tools/blender/pole_kalibre.py): bu açılarda dirsek tam olarak
        # pole_elbow hedefine bakar (±1°). Sol/sağ eksenler ayna olduğu için açılar farklı.
        # Dirsek yönü her pozda hedefin konumuyla belirlenir (LIMB_POLES / RAISED_ELBOWS).
        c.pole_angle = math.radians(129 if sfx == "L" else 51)
        c.chain_count = 2
    for p in pb:
        p.rotation_mode = 'XYZ'
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm_obj


# ---------------------------------------------------------------------------
# Ağırlıklar
# ---------------------------------------------------------------------------
HEAD_PARTS = {"Kafa", "Burun", "Gozler", "GozParlak", "Kaslar", "Agiz", "Sac"}
FOOT_PARTS = {"Taban", "Ayakkabi", "AyakkabiSerit"}
CHEST_PARTS = {"Canta", "CantaCep", "CantaEtiket"}
PART_BONES = {
    "Boyun": ["neck", "head", "chest"],
    "Tisort": ["spine", "chest", "neck", "upper_arm.L", "upper_arm.R"],
    "TisortKol": ["chest", "upper_arm.L", "forearm.L", "upper_arm.R", "forearm.R"],
    "Kollar": ["chest", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R"],
    "Eller": ["forearm.L", "hand.L", "forearm.R", "hand.R"],
    "Pantolon": ["hips", "thigh.L", "shin.L", "thigh.R", "shin.R"],
    "Askilar": ["chest", "spine"],
}


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def _smooth(a, b, x):
    k = max(0.0, min(1.0, (x - a) / (b - a)))
    return k * k * (3 - 2 * k)


# Kol olan parçalar (tamamı kol geometrisi): yalnız omuz ekleminde gövdeye karışır
ARM_PARTS = {"Kollar", "TisortKol"}
TORSO_BONES = {"hips", "spine", "chest", "neck", "head"}


def arm_share(p, name):
    """Noktanın kola ait payı (0 gövde ... 1 kol). Omuz ekleminden kol yönünde ilerledikçe
    ve (gövde parçalarında) kol ekseninden uzaklaşmadıkça artar: omuz başı yumuşak döner,
    koltuk altı ve trapez kolla birlikte çökmez."""
    side = 1 if p.x > 0 else -1
    s, e, w, h = arm(side)
    d = Vector((ARM_DIR.x * side, 0, ARM_DIR.z))
    q = p - s
    t = q.dot(d)
    if name in ARM_PARTS:
        return _smooth(-0.05, 0.05, t)
    radial = (q - d * t).length
    r = 0.065
    return _smooth(-0.02, 0.08, t) * (1.0 - _smooth(r, r * 1.45, radial))


def assign_weights(obj, arm_obj):
    segs = {b.name: (Vector(b.head_local), Vector(b.tail_local)) for b in arm_obj.data.bones}
    name = obj.name
    groups = {}

    def add(bname, idx, w):
        if bname not in groups:
            groups[bname] = obj.vertex_groups.new(name=bname)
        groups[bname].add([idx], w, 'REPLACE')

    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        if name in HEAD_PARTS:
            add("head", v.index, 1.0)
            continue
        if name in FOOT_PARTS:
            add("foot.L" if p.x > 0 else "foot.R", v.index, 1.0)
            continue
        if name in CHEST_PARTS:
            add("canta", v.index, 1.0)
            continue
        # Tişört eteği ve pantolon beli aynı kemikle (hips) hareket eder:
        # böylece pantolon tişörtün içinden dışarı taşmaz.
        if name == "Tisort" and p.z < 0.84 and abs(p.x) < 0.2:
            add("hips", v.index, 1.0)
            continue
        if name == "Pantolon" and p.z > 0.68:
            add("hips", v.index, 1.0)
            continue
        def dist_w(cands):
            ws = []
            for bname in cands:
                d = seg_dist(p, *segs[bname]) + 0.01
                ws.append((1.0 / d ** 4, bname))
            ws.sort(reverse=True)
            ws = ws[:3]
            total = sum(w for w, _ in ws)
            return {b: w / total for w, b in ws}

        cands = PART_BONES[name]
        if name in ("Tisort", "TisortKol", "Kollar"):
            # Omuz: gövde ve kol ağırlıkları omuz eklemine göre paylaştırılır
            k = arm_share(p, name)
            sfx = "L" if p.x > 0 else "R"
            body = [b for b in cands if b in TORSO_BONES] or ["chest"]
            limb = [b for b in ("upper_arm", "forearm", "hand") if f"{b}.{sfx}" in segs]
            final = {b: w * (1 - k) for b, w in dist_w(body).items()}
            if k > 0.001:
                for b, w in dist_w([f"{b}.{sfx}" for b in limb]).items():
                    final[b] = final.get(b, 0.0) + w * k
        else:
            final = dist_w(cands)
        for bname, w in final.items():
            if w > 0.002:
                add(bname, v.index, w)


def join_children(root_name, new_name):
    root = bpy.data.objects[root_name]
    parts = [o for o in root.children if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = new_name
    mw = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = mw
    bpy.data.objects.remove(root, do_unlink=True)
    return obj, parts


def skin(obj, arm_obj):
    obj.parent = arm_obj
    obj.matrix_parent_inverse.identity()
    mod = obj.modifiers.new("Iskelet", 'ARMATURE')
    mod.object = arm_obj


def skin_character(arm_obj):
    root = bpy.data.objects["Karakter"]
    for o in [o for o in root.children if o.type == 'MESH']:
        assign_weights(o, arm_obj)
    body, _ = join_children("Karakter", "KarakterMesh")
    skin(body, arm_obj)


def skin_board(arm_obj):
    board, _ = join_children("Kaykay", "KaykayMesh")
    board.location = (0, 0, 0)
    vg = board.vertex_groups.new(name="board")
    vg.add([v.index for v in board.data.vertices], 1.0, 'REPLACE')
    skin(board, arm_obj)


# ---------------------------------------------------------------------------
# Poz yardımcıları
# ---------------------------------------------------------------------------
REST = {}


def rest_heads(arm_obj):
    for b in arm_obj.data.bones:
        REST[b.name] = Vector(b.head_local)


def to_local(arm_obj, bone, world_delta):
    """Ebeveynsiz kemikte poz konumu kemiğin kendi dinlenme eksenlerindedir."""
    b = arm_obj.data.bones[bone]
    return b.matrix_local.to_3x3().inverted() @ Vector(world_delta)


def set_target(arm_obj, bone, world_pos):
    arm_obj.pose.bones[bone].location = to_local(arm_obj, bone, Vector(world_pos) - REST[bone])


def apply_pose(arm_obj, pose):
    """pose sözlüğü: hips (dx,dy,dz), *_rot (derece), foot/hand/knee/elbow hedefleri,
    hand_rot.L/R (bilek), board (kaykay konumu, carry=0 iken), carry (0..1)."""
    pb = arm_obj.pose.bones
    for p in pb:
        p.location = (0, 0, 0)
        p.rotation_euler = (0, 0, 0)
    pb["hips"].location = to_local(arm_obj, "hips", pose.get("hips", (0, 0, 0)))
    for key, bone in (("hips_rot", "hips"), ("spine_rot", "spine"), ("chest_rot", "chest"),
                      ("neck_rot", "neck"), ("head_rot", "head"),
                      ("hand_rot.L", "hand.L"), ("hand_rot.R", "hand.R"), ("board_rot", "board")):
        if key in pose:
            pb[bone].rotation_euler = [math.radians(a) for a in pose[key]]
    if "board" in pose:
        pb["board"].location = to_local(arm_obj, "board", pose["board"])
    if "board_raw" in pose:
        pb["board"].location = Vector(pose["board_raw"][0])
        pb["board"].rotation_euler = pose["board_raw"][1]
    for sfx in ("L", "R"):
        if f"foot.{sfx}" in pose:
            set_target(arm_obj, f"ik_foot.{sfx}", pose[f"foot.{sfx}"])
        if f"foot_rot.{sfx}" in pose:
            # (parmak eğimi, -, yön): yön dünyanın dik ekseni etrafında; böylece taban yerde
            # düz kalır (kemiğin eğik ekseni etrafında dönünce ayak yan yatıyordu).
            # Eğim: eksi = topuk kalkık / parmak ucuna basış (eski anlamıyla aynı).
            pitch, _roll, yaw = pose[f"foot_rot.{sfx}"]
            rest = arm_obj.data.bones[f"ik_foot.{sfx}"].matrix_local.to_3x3()
            m = Matrix.Rotation(math.radians(yaw), 3, 'Z') @ Matrix.Rotation(math.radians(-pitch), 3, 'X')
            pb[f"ik_foot.{sfx}"].rotation_euler = (rest.inverted() @ m @ rest).to_euler('XYZ')
        if f"hand.{sfx}" in pose:
            set_target(arm_obj, f"ik_hand.{sfx}", pose[f"hand.{sfx}"])
        if f"knee.{sfx}" in pose:
            set_target(arm_obj, f"pole_knee.{sfx}", pose[f"knee.{sfx}"])
        if f"elbow.{sfx}" in pose:
            set_target(arm_obj, f"pole_elbow.{sfx}", pose[f"elbow.{sfx}"])
    con = pb["board"].constraints.get("Tasima")
    if con:
        con.influence = pose.get("carry", 0.0)
    if "canta" in pb:
        bc = pb["canta"].constraints.get("El")
        if bc:
            bc.influence = pose.get("bag", 0.0)


def key_pose(arm_obj, frame, pose):
    apply_pose(arm_obj, pose)
    for p in arm_obj.pose.bones:
        p.keyframe_insert("location", frame=frame)
        p.keyframe_insert("rotation_euler", frame=frame)
    con = arm_obj.pose.bones["board"].constraints.get("Tasima")
    if con:
        con.keyframe_insert("influence", frame=frame)
    if "canta" in arm_obj.pose.bones:
        bc = arm_obj.pose.bones["canta"].constraints.get("El")
        if bc:
            bc.keyframe_insert("influence", frame=frame)


def new_action(arm_obj, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    arm_obj.animation_data.action = act
    return act


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def blend_pose(a, b, t):
    """İki poz sözlüğünü karıştırır (hedefler ve açılar doğrusal)."""
    out = dict(a)
    for k, v in b.items():
        if k in a:
            if isinstance(v, tuple):
                out[k] = lerp(a[k], v, t)
            elif isinstance(v, (int, float)):
                out[k] = a[k] + (v - a[k]) * t
        else:
            out[k] = v
    return out


# ---------------------------------------------------------------------------
# Kaykayı elde taşıma noktası
# ---------------------------------------------------------------------------
LIMB_POLES = {
    "knee.L": (0.15, -0.6, 0.45), "knee.R": (-0.15, -0.6, 0.45),
    # Sarkık kollar: dirsek arkaya ve hafif dışa -> önkol yüzün baktığı yöne bükülür
    "elbow.L": (0.27, 0.5, 0.75), "elbow.R": (-0.27, 0.5, 0.75),
}
# Kalkık / açık kollar (havada, grind, kickflip): dirsek aşağı ve hafif geriye sarkar
RAISED_ELBOWS = {"elbow.L": (0.32, 0.3, 0.2), "elbow.R": (-0.32, 0.3, 0.2)}
HAND_RELAX = {"hand_rot.L": (-12, 0, 8), "hand_rot.R": (-12, 0, -8)}


UPPER_LEN, FORE_LEN = 0.25, 0.22     # omuz -> dirsek -> bilek (arm() ile aynı)


def swing_arm(p, sfx, swing, bend, out=0.05, hips=(0.0, 0.0, 0.0), lean=0.0, yaw=0.0):
    """Kolu omuzdan sarkaç gibi yerleştirir: swing = üst kolun öne açısı (derece, eksi = geride),
    bend = dirseğin ayrıca öne bükülmesi (hep >= 0: kol ters bükülmez). Dirsek hedefi dirseğin
    arkasında: IK dirseği hep geriye, önkolu öne büker. lean / yaw: gövdenin öne eğimi ve
    dönüşü (omuzların yeri buna göre kayar)."""
    side = 1.0 if sfx == "L" else -1.0
    y = math.radians(yaw)
    fwd = Vector((math.sin(y), -math.cos(y), 0.0))
    outv = Vector((math.cos(y), math.sin(y), 0.0)) * side
    up = Vector((0.0, 0.0, 1.0))
    ln = math.radians(lean)
    sh = Vector((hips[0], hips[1], 0.70 + hips[2])) + outv * 0.165 + fwd * (0.375 * math.sin(ln)) \
        + up * (0.375 * math.cos(ln))
    a = math.radians(swing)
    b = math.radians(swing + max(bend, 0.0))
    elbow = sh + fwd * (UPPER_LEN * math.sin(a)) - up * (UPPER_LEN * math.cos(a)) + outv * out
    wrist = elbow + fwd * (FORE_LEN * math.sin(b)) - up * (FORE_LEN * math.cos(b)) + outv * (out * 0.4)
    p[f"hand.{sfx}"] = tuple(wrist)
    p[f"elbow.{sfx}"] = tuple(elbow - fwd * 0.35 + outv * 0.06)
    return p


STAND_ARMS = {}
swing_arm(STAND_ARMS, "L", 0.0, 10.0, out=0.06)
swing_arm(STAND_ARMS, "R", 4.0, 14.0, out=0.08)       # kaykayı tutan kol
STAND_HAND_L = STAND_ARMS["hand.L"]
STAND_HAND_R = STAND_ARMS["hand.R"]


def stand_pose(**over):
    p = {"hips": (0, 0, -0.012)}
    for sfx, side in (("L", 1), ("R", -1)):
        p[f"foot.{sfx}"] = (0.11 * side, 0.01, 0.075)
    p.update(LIMB_POLES)
    p.update(STAND_ARMS)
    p.update(HAND_RELAX)
    p["carry"] = 1.0
    p.update(over)
    return p


BAG_HOLD_HAND = (0.13, -0.3, 0.9)


def bag_hold_pose(**over):
    p = stand_pose(**over)
    p["hand.L"] = BAG_HOLD_HAND
    p["hand_rot.L"] = (-20, 0, 25)
    p["elbow.L"] = (0.32, 0.2, 0.7)
    p["head_rot"] = (22, -6, 0)
    p["spine_rot"] = (6, 0, 0)
    return p


def add_bag_bones(arm_obj):
    """Çanta iki yerde durabilir: sırtta (göğse bağlı) ya da sol elde, önde. Kısıt etkisi
    (bag) animasyonda anahtarlanır. Tutuş pozunda elin dönüşümü ölçülüp yardımcı kemik ona göre konur."""
    apply_pose(arm_obj, bag_hold_pose())
    bpy.context.view_layer.update()
    hand_pose = arm_obj.pose.bones["hand.L"].matrix.copy()
    hand_rest = arm_obj.data.bones["hand.L"].matrix_local.copy()
    chest_rest = arm_obj.data.bones["chest"].matrix_local.copy()
    bag_rest = arm_obj.data.bones["canta"].matrix_local.copy()
    # Elde: göğsün önünde, sırt yüzü karaktere dönük (Z ekseni etrafında 180°), üstü hafif öne
    hold = Matrix.Translation((0.03, -0.34, 0.88)) @ Matrix.Rotation(math.radians(180), 4, 'Z') @ \
        Matrix.Rotation(math.radians(-15), 4, 'X') @ Matrix.Translation(-Vector(bag_rest.translation)) @ bag_rest
    hand_helper = hand_rest @ hand_pose.inverted() @ hold
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_obj.data.edit_bones
    sb = eb.new("canta_sirt")
    sb.head = (0, 0, 0)
    sb.tail = (0, 0.12, 0)
    sb.matrix = bag_rest
    sb.parent = eb["chest"]
    sb.use_deform = False
    hb = eb.new("canta_el")
    hb.head = (0, 0, 0)
    hb.tail = (0, 0.12, 0)
    hb.matrix = hand_helper
    hb.parent = eb["hand.L"]
    hb.use_deform = False
    bpy.ops.object.mode_set(mode='POSE')
    pc = arm_obj.pose.bones["canta"]
    c1 = pc.constraints.new('COPY_TRANSFORMS')
    c1.name = "Sirt"
    c1.target = arm_obj
    c1.subtarget = "canta_sirt"
    c1.influence = 1.0
    c2 = pc.constraints.new('COPY_TRANSFORMS')
    c2.name = "El"
    c2.target = arm_obj
    c2.subtarget = "canta_el"
    c2.influence = 0.0
    for n in ("canta_sirt", "canta_el"):
        arm_obj.pose.bones[n].rotation_mode = 'XYZ'
    bpy.ops.object.mode_set(mode='OBJECT')
    rest_heads(arm_obj)


def add_carry_bone(arm_obj):
    """Ayakta duruş pozunda kaykay sağ yanda dik, grip yüzü vücuda dönük dursun.
    O pozda elin dönüşümünü ölçüp el kemiğine bağlı yardımcı kemiği buna göre koyar."""
    apply_pose(arm_obj, stand_pose(carry=0.0))
    bpy.context.view_layer.update()
    hand_pose = arm_obj.pose.bones["hand.R"].matrix.copy()
    hand_rest = arm_obj.data.bones["hand.R"].matrix_local.copy()
    board_rest = arm_obj.data.bones["board"].matrix_local.copy()
    # Kaykay modeli: boyu Y (ucu -Y), üst yüz +Z, genişlik X. Elde (bavul gibi): boyu yere
    # paralel ve gidiş yönünde (ucu önde), üst yüz (grip) vücuda dönük (+X), tekerlekler
    # dışarıda; el tahtanın üst kenarını ortasından kavrar. Sütunlar: model X -> -Z,
    # Y -> +Y, Z (üst yüz) -> +X, konum son sütun.
    wx, wy, wz = STAND_HAND_R
    rot = Matrix(((0, 0, 1, wx - 0.117), (0, 1, 0, wy), (-1, 0, 0, wz - 0.18), (0, 0, 0, 1)))
    desired_bone = rot @ board_rest
    helper_rest = hand_rest @ hand_pose.inverted() @ desired_bone

    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_obj.data.edit_bones
    h = eb.new("board_carry")
    h.head = (0, 0, 0)
    h.tail = (0, 0.2, 0)
    h.matrix = helper_rest
    h.parent = eb["hand.R"]
    h.use_deform = False
    bpy.ops.object.mode_set(mode='POSE')
    c = arm_obj.pose.bones["board"].constraints.new('COPY_TRANSFORMS')
    c.name = "Tasima"
    c.target = arm_obj
    c.subtarget = "board_carry"
    c.influence = 0.0
    arm_obj.pose.bones["board_carry"].rotation_mode = 'XYZ'
    bpy.ops.object.mode_set(mode='OBJECT')
    rest_heads(arm_obj)


# ---------------------------------------------------------------------------
# Kaykay pozları. Ayaklar: sağ ayak önde, sol ayak arkada; karakter öne bakar.
# ---------------------------------------------------------------------------
D = DECK_TOP
RIGHT_ON_BOARD = (-0.035, -0.11, D + 0.075)
LEFT_ON_BOARD = (0.035, 0.17, D + 0.075)


def ride_base(crouch=0.04, **over):
    p = {
        "hips": (0.0, 0.02, D - crouch),
        "foot.R": RIGHT_ON_BOARD,
        "foot.L": LEFT_ON_BOARD,
        "hand.L": (0.215, -0.02, 0.7 + D - crouch),
        "hand.R": (-0.215, -0.02, 0.7 + D - crouch),
        "spine_rot": (6, 0, 0),
        "carry": 0.0,
    }
    p.update(LIMB_POLES)
    p.update(HAND_RELAX)
    p.update(over)
    return p


# ---------------------------------------------------------------------------
# Yan duruş (kayarken / süzülürken): sağ ayak önde, gövde sola (+X) döner, sağ omuz
# gidiş yönüne bakar, baş gidişe döner. İtmede ve hızlanmada gövde öne döner.
# Referans: kaykay referans.mov (gerçek kaykaycılardan pozlar)
# ---------------------------------------------------------------------------
SIDE_YAW = 72.0
SIDE_FRONT = (0.0, -0.17, 55.0)      # ön ayak: ortası (x, y), parmak yönü (0 = burun, 90 = sol)
SIDE_BACK = (0.0, 0.2, 86.0)         # arka ayak: kuyruk vidalarının üstü


def body_axes(yaw):
    a = math.radians(yaw)
    fwd = Vector((math.sin(a), -math.cos(a), 0.0))      # gövdenin baktığı yön
    right = Vector((-math.cos(a), -math.sin(a), 0.0))   # gövdenin sağı (öndeki omuz)
    return fwd, right


def bp(yaw, right, fwd, z, base=(0.0, 0.02)):
    """Gövde ekseninde (sağ, ön, yükseklik) verilen noktayı dünya koordinatına çevirir."""
    f, r = body_axes(yaw)
    v = r * right + f * fwd
    return (base[0] + v.x, base[1] + v.y, z)


def foot_on(center, yaw_deg, dz=0.0, z0=None):
    """Ayak hedefi: ayağın ortası center (x, y) olsun, parmak ucu yaw_deg yönüne baksın."""
    a = math.radians(yaw_deg)
    toe = Vector((math.sin(a), -math.cos(a), 0.0))
    ank = Vector((center[0], center[1], 0.0)) - toe * 0.07
    z = (D + 0.075 if z0 is None else z0) + dz
    return (ank.x, ank.y, z), (0.0, 0.0, yaw_deg)


def knee_pole(foot, yaw, along=0.0, out=0.6, z=0.5):
    f, _ = body_axes(yaw)
    return (foot[0] + f.x * out, foot[1] + f.y * out + along, z)


def side_base(crouch=0.06, yaw=SIDE_YAW, front=SIDE_FRONT, back=SIDE_BACK, dz=0.0, **over):
    """Yan duruş: dizler gövdenin baktığı yöne bükülür, kollar gevşek yanlarda,
    baş gidiş yönüne (-Y) döner. dz: ayaklar ve kaykay köke göre yukarıda (havada)."""
    twist = -12.0                                       # omuzlar biraz gidişe açılır
    p = {
        "hips": (0.0, 0.015, D - crouch + dz),
        "hips_rot": (0, yaw, 0),
        "spine_rot": (8, twist * 0.5, 0),
        "chest_rot": (2, twist * 0.5, 0),
        "neck_rot": (0, -24, 0),
        "head_rot": (-4, -30, 0),
        "carry": 0.0,
    }
    fr, frr = foot_on(front[:2], front[2], dz)
    bk, bkr = foot_on(back[:2], back[2], dz)
    p["foot.R"], p["foot_rot.R"] = fr, frr
    p["foot.L"], p["foot_rot.L"] = bk, bkr
    p["knee.R"] = knee_pole(fr, yaw, along=-0.12, z=0.5 + dz)
    p["knee.L"] = knee_pole(bk, yaw, along=0.08, z=0.5 + dz)
    sy = yaw + twist
    hz = 0.7 + D - crouch + dz
    p["hand.R"] = bp(sy, 0.215, 0.02, hz)
    p["hand.L"] = bp(sy, -0.215, 0.02, hz)
    p["elbow.R"] = bp(sy, 0.27, -0.5, 0.75 + dz)
    p["elbow.L"] = bp(sy, -0.27, -0.5, 0.75 + dz)
    p.update(HAND_RELAX)
    if "board" not in over and dz:
        p["board"] = (0, 0, dz)
    p.update(over)
    return p


def arms(p, yaw, crouch, dz=0.0, **pts):
    """Kolları gövde ekseninde yerleştirir: hand_R=(sağ, ön, yükseklik farkı), elbow_R=..."""
    hz = 0.7 + D - crouch + dz
    for key, (r, f, z) in pts.items():
        part, sfx = key.split("_")
        if part == "hand":
            p[f"hand.{sfx}"] = bp(yaw, r, f, hz + z)
        else:
            p[f"elbow.{sfx}"] = bp(yaw, r, f, hz + z)
    return p


def run_legs(ph, stride=0.32, lift=0.16, side_x=0.1):
    """Basit adım (binme animasyonundaki kısa koşu için): ph faz (radyan)."""
    out = {}
    for sfx, side, off in (("L", 1, 0.0), ("R", -1, math.pi)):
        a = ph + off
        up = max(0.0, math.sin(a))
        # Havadayken ayak öne (-Y), yerdeyken arkaya (+Y) gider
        y = stride * math.cos(a)
        out[f"foot.{sfx}"] = (side_x * side, y, 0.075 + up * lift)
        out[f"foot_rot.{sfx}"] = (-25 * up, 0, 0)
    return out


# Adım ölçüleri: Godot'taki animasyon hızı bunlardan hesaplanır (yer hızı = 2*amp / (duty*süre))
WALK = {"frames": 22, "amp": 0.28, "duty": 0.6, "lift": 0.08}
RUN = {"frames": 18, "amp": 0.33, "duty": 0.3, "lift": 0.2}


def gait_foot(u, amp, duty, lift):
    """Bir ayağın döngüdeki konumu. u: 0..1 faz.
    Yerde (u < duty): ayak sabit hızla öne-ortadan arkaya gider -> zeminde kaymaz.
    Havada: yay çizerek öne döner."""
    u = u % 1.0
    if u < duty:
        k = u / duty
        y = -amp + 2 * amp * k
        z = 0.0
        pitch = 0.0
        if k > 0.8:  # parmak ucuyla itiş
            pitch = -30 * (k - 0.8) / 0.2
    else:
        k = (u - duty) / (1 - duty)
        sm = k * k * (3 - 2 * k)
        y = amp - 2 * amp * sm
        z = math.sin(math.pi * k) * lift
        pitch = -30 * (1 - k) + 10 * math.sin(math.pi * k)
    return y, z, pitch


def gait_pose(u, g, side_x=0.1):
    out = {}
    for sfx, side, off in (("L", 1, 0.0), ("R", -1, 0.5)):
        y, z, pitch = gait_foot(u + off, g["amp"], g["duty"], g["lift"])
        out[f"foot.{sfx}"] = (side_x * side, y, 0.075 + z)
        out[f"foot_rot.{sfx}"] = (pitch, 0, 0)
    return out


# ---------------------------------------------------------------------------
# Müzik çalar: cepten çıkarma, kulaklıkları takma, bakma, cebe koyma
# Kaykay önce sağ yana, kenarı üstünde yere bırakılır (iki el boşta), sonunda geri alınır.
# Cihaz ve kulaklıklar karakterin parçası (kemiklere bağlı ayrı meshler; Godot görünürlüğünü
# animasyona göre açar): "Calar_L" / "Calar_R" elde, "Tomurcuk_El_L/R" parmak ucunda,
# "Tomurcuk_Kulak_L/R" kulakta. Kablo uç noktaları için kemikler: jack.L/R (cihazın girişi),
# kulak.L/R, kulaklik_el.L/R, cep.L (sol ön cep), ayirac (göğsün önünde kablonun ayrıldığı yer).
# ---------------------------------------------------------------------------
MUZIK_GLB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "muzikcalar", "muzikcalar.glb")
CALAR_SCALE = 1.5
BUD_SCALE = 1.7
HOLD_L = (0.06, -0.3, 0.97)
HOLD_R = (-0.06, -0.3, 0.97)
POCKET_L = (0.15, -0.075, 0.71)
DEVICE_TOP = (0.0, -0.36, 1.07)
EAR_HAND_L = (0.175, -0.05, 1.2)
EAR_HAND_R = (-0.175, -0.05, 1.2)
EAR_L = Vector((0.118, 0.005, 1.275))
EAR_R = Vector((-0.118, 0.005, 1.275))
BOARD_DOWN_HAND = None          # add_music_bones hesaplar (STAND_HAND_R'nin altı)
MUZIK_FRAMES = 80               # cikar: Godot MUZIK_CIKAR_TIME = 80 / 30
MUZIK_KOY_FRAMES = 34
# Animasyonda olaylar (kare): Godot muzik_aksesuar.gd ile aynı
MZ_CEPTEN = 22          # cihaz sol elde görünür
MZ_SAG_AL = 36          # sağ kulaklık sağ elde
MZ_SAG_TAK = 46         # sağ kulaklık kulakta
MZ_EL_DEGIS = 56        # cihaz sağ ele geçer
MZ_SOL_AL = 60          # sol kulaklık sol elde
MZ_SOL_TAK = 68         # sol kulaklık kulakta
MZ_IKI_EL = 76          # cihaz yeniden sol elde (iki el tutar)
MUZIK_KISA_FRAMES = 36          # muzik_cikar_kisa (kulaklıklar zaten takılı)
# muzik_kulaklik_cikar (güç kapatma): kareler, Godot muzik_aksesuar.gd ile aynı
KC_SAG_KULAK = 8        # sağ el kulakta
KC_SAG_CEK = 12         # sağ kulaklık elde (çekildi)
KC_SAG_BIT = 19         # sağ el cihazda: kulaklık sarılıp gizlenir
KC_EL_DEGIS = 20        # cihaz sağ ele
KC_SOL_KULAK = 27
KC_SOL_CEK = 31
KC_SOL_BIT = 38
KC_IKI_EL = 39          # cihaz sol ele
KC_CEBE = 50            # cihaz cepte (gizlenir)
MUZIK_KC_FRAMES = 72


def music_hold_pose(**over):
    p = stand_pose(carry=0.0, head_rot=(24, 0, 0), neck_rot=(8, 0, 0), spine_rot=(4, 0, 0), **over)
    p["hand.L"], p["hand_rot.L"], p["elbow.L"] = HOLD_L, (-60, 0, 22), (0.34, 0.22, 0.74)
    p["hand.R"], p["hand_rot.R"], p["elbow.R"] = HOLD_R, (-60, 0, -22), (-0.34, 0.22, 0.74)
    return p


def device_matrix(center):
    """Cihaz göğsün önünde, ekranı yüze dönük (model: ön -Y, üst +Z), CALAR_SCALE büyük."""
    eye = Vector((0, -0.1, 1.31))
    n = (eye - Vector(center)).normalized()          # ekranın baktığı yön
    up = Vector((0, -n.z, n.y)).normalized()         # cihazın üstü (n'ye dik, öne-yukarı)
    y_ax = -n
    x_ax = y_ax.cross(up).normalized()
    m = Matrix((x_ax, y_ax, up)).transposed().to_4x4()
    m.translation = Vector(center)
    return m @ Matrix.Diagonal((CALAR_SCALE, CALAR_SCALE, CALAR_SCALE, 1.0))


def bud_matrix(ear, side):
    """Kulak içi: ızgara (model -Y) içe, boyun (+Z) aşağı."""
    inward = Vector((-side, 0, 0))
    y_ax = -inward
    z_ax = Vector((0, 0.15, -1.0)).normalized()
    x_ax = y_ax.cross(z_ax).normalized()
    z_ax = x_ax.cross(y_ax).normalized()
    m = Matrix((x_ax, y_ax, z_ax)).transposed().to_4x4()
    m.translation = ear
    return m @ Matrix.Diagonal((BUD_SCALE, BUD_SCALE, BUD_SCALE, 1.0))


def _new_child_bone(arm_obj, name, parent, matrix_arm):
    """matrix_arm: kemiğin dinlenme matrisi (iskelet uzayı, ölçeksiz)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_obj.data.edit_bones
    b = eb.new(name)
    b.head = (0, 0, 0)
    b.tail = (0, 0.04, 0)
    m = matrix_arm.normalized()
    b.matrix = m
    b.parent = eb[parent]
    b.use_deform = True
    bpy.ops.object.mode_set(mode='OBJECT')


def _helper_rest(arm_obj, pose, parent, desired):
    """Pozdaki ebeveyn kemiğe göre: o pozda 'desired' (iskelet uzayı) yerinde duran çocuğun dinlenmesi."""
    apply_pose(arm_obj, pose)
    bpy.context.view_layer.update()
    pp = arm_obj.pose.bones[parent].matrix.copy()
    pr = arm_obj.data.bones[parent].matrix_local.copy()
    return pr @ pp.inverted() @ desired


def _import_music_meshes():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=MUZIK_GLB)
    new = [o for o in bpy.data.objects if o not in before]
    found = {o.name.split(".")[0]: o for o in new if o.type == 'MESH'}
    for o in new:
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    return found


def _skinned_copy(src_objs, name, bone, rest_m, arm_obj):
    """Kaynak meshleri birleştirip kopya; dinlenmede rest_m'de durur, tamamı tek kemiğe bağlı."""
    copies = []
    for o in src_objs:
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.scene.collection.objects.link(c)
        mw = o.matrix_world.copy()
        c.parent = None
        c.data.transform(mw)            # içe aktarılan nesnenin dönüşümü veriye
        c.matrix_world = Matrix.Identity(4)
        copies.append(c)
    bpy.ops.object.select_all(action='DESELECT')
    for c in copies:
        c.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    if len(copies) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.transform(rest_m)
    obj.matrix_world = Matrix.Identity(4)
    vg = obj.vertex_groups.new(name=bone)
    vg.add([v.index for v in obj.data.vertices], 1.0, 'REPLACE')
    skin(obj, arm_obj)
    return obj


def add_music_bones(arm_obj):
    global BOARD_DOWN_HAND
    BOARD_DOWN_HAND = (STAND_HAND_R[0] - 0.02, STAND_HAND_R[1], 0.33)
    hold = music_hold_pose()
    center = Vector(((HOLD_L[0] + HOLD_R[0]) * 0.5, -0.335, 1.0))
    dev = device_matrix(center)
    dev_n = dev.normalized()
    jack_local = Vector((62 * 0.001 * 0.28, 0, 104 * 0.001 * 0.5 + 0.022))
    jack = dev @ jack_local
    rests = {}
    for sfx in ("L", "R"):
        rests["calar." + sfx] = _helper_rest(arm_obj, hold, "hand." + sfx, dev_n)
        jm = Matrix.Translation(jack)
        rests["jack." + sfx] = _helper_rest(arm_obj, hold, "hand." + sfx, jm)
    # Kulaklar (kafaya bağlı; dinlenme pozunda), parmak ucundaki kulaklık (kulağa değdiği karede)
    rest_pose = stand_pose(carry=0.0)
    ear_m = {"L": bud_matrix(EAR_L, 1), "R": bud_matrix(EAR_R, -1)}
    for sfx in ("L", "R"):
        rests["kulak." + sfx] = _helper_rest(arm_obj, rest_pose, "head", ear_m[sfx].normalized())
    at_ear = {"R": music_ear_pose("R"), "L": music_ear_pose("L")}
    for sfx in ("L", "R"):
        apply_pose(arm_obj, at_ear[sfx])
        bpy.context.view_layer.update()
        hp = arm_obj.pose.bones["head"].matrix.copy()
        hr = arm_obj.data.bones["head"].matrix_local.copy()
        ear_now = hp @ hr.inverted() @ ear_m[sfx]
        rests["kulaklik_el." + sfx] = _helper_rest(arm_obj, at_ear[sfx], "hand." + sfx, ear_now.normalized())
    rests["cep.L"] = _helper_rest(arm_obj, rest_pose, "hips", Matrix.Translation(Vector(POCKET_L) + Vector((0.01, -0.01, 0.03))))
    rests["ayirac"] = _helper_rest(arm_obj, rest_pose, "chest", Matrix.Translation(Vector((0, -0.16, 1.0))))
    parents = {"calar.L": "hand.L", "calar.R": "hand.R", "jack.L": "hand.L", "jack.R": "hand.R",
               "kulak.L": "head", "kulak.R": "head", "kulaklik_el.L": "hand.L", "kulaklik_el.R": "hand.R",
               "cep.L": "hips", "ayirac": "chest"}
    apply_pose(arm_obj, stand_pose())
    for name, m in rests.items():
        _new_child_bone(arm_obj, name, parents[name], m)
    bpy.ops.object.mode_set(mode='POSE')
    for name in rests:
        arm_obj.pose.bones[name].rotation_mode = 'XYZ'
    bpy.ops.object.mode_set(mode='OBJECT')
    rest_heads(arm_obj)
    # Meshler: dinlenme matrisi = kemiğin dinlenmesi, ölçek dahil (ölçek meshte kalır)
    src = _import_music_meshes()
    scale = Matrix.Diagonal((CALAR_SCALE, CALAR_SCALE, CALAR_SCALE, 1.0))
    bscale = Matrix.Diagonal((BUD_SCALE, BUD_SCALE, BUD_SCALE, 1.0))
    parts = [src[k] for k in ("Govde", "Ekran", "Tekerlek", "OrtaTus", "GucTus", "Fis") if k in src]
    for sfx in ("L", "R"):
        bone_rest = arm_obj.data.bones["calar." + sfx].matrix_local.copy()
        _skinned_copy(parts, "Calar_" + sfx, "calar." + sfx, bone_rest @ scale, arm_obj)
        for kind, bone in (("Kulak", "kulak." + sfx), ("El", "kulaklik_el." + sfx)):
            br = arm_obj.data.bones[bone].matrix_local.copy()
            _skinned_copy([src["Kulaklik"]], "Tomurcuk_%s_%s" % (kind, sfx), bone, br @ bscale, arm_obj)
    for o in src.values():
        bpy.data.objects.remove(o, do_unlink=True)


def music_ear_pose(sfx, **over):
    """Bir el kulağa kulaklık takarken; öbür el cihazı göğsün önünde tutar."""
    p = stand_pose(carry=0.0, head_rot=(4, 14 if sfx == "R" else -14, 0), **over)
    other = "L" if sfx == "R" else "R"
    side = 1 if sfx == "L" else -1
    p["hand." + sfx] = EAR_HAND_L if sfx == "L" else EAR_HAND_R
    p["hand_rot." + sfx] = (-160, 0, 12 * side)
    p["elbow." + sfx] = (0.46 * side, 0.08, 1.0)
    p["hand." + other] = (HOLD_L if other == "L" else HOLD_R)
    p["hand." + other] = (p["hand." + other][0] * 0.5, p["hand." + other][1], p["hand." + other][2])
    p["hand_rot." + other] = (-60, 0, -22 * side)
    p["elbow." + other] = (-0.34 * side, 0.22, 0.74)
    return p



def make_actions(arm_obj):
    acts = []

    def act(name):
        new_action(arm_obj, name)
        acts.append(name)

    # --- Kaykayda bekleme (yavaş, yan duruş): gevşek kollar, nefes ---
    act("ride_idle")
    for f, k in ((0, 0.0), (24, 1.0), (48, 0.0)):
        p = side_base(crouch=0.05 + 0.012 * k, chest_rot=(2 - 2 * k, -6, 0))
        arms(p, SIDE_YAW - 12, 0.05 + 0.012 * k, hand_R=(0.215, 0.03 + 0.01 * k, 0.0), hand_L=(-0.215, 0.02 - 0.01 * k, 0.0))
        key_pose(arm_obj, f, p)

    # --- Hızlı süzülme (yan duruş): daha alçak, kollar dengeye hafif açık ---
    act("ride_fast")
    for f, k in ((0, 0.0), (20, 1.0), (40, 0.0)):
        c = 0.11 + 0.01 * k
        p = side_base(crouch=c, spine_rot=(14, -6, 0), head_rot=(-10, -30, 0))
        arms(p, SIDE_YAW - 12, c, hand_R=(0.3, 0.1, 0.05 + 0.01 * k), hand_L=(-0.3, 0.08, 0.03 - 0.01 * k))
        p["hand_rot.L"] = (-25, 0, 20)
        p["hand_rot.R"] = (-25, 0, -20)
        key_pose(arm_obj, f, p)

    # --- Dönüşler: sola dönüş = parmak tarafı (gövdenin baktığı yön): dizler öne,
    #     gövde öne eğik, ön kol öne uzanır. Sağa dönüş = topuk tarafı: kalça geriye
    #     oturur, gövde dik, kollar öne denge kurar. ---
    for name, s in (("ride_turn_l", 1), ("ride_turn_r", -1)):
        act(name)
        for f in (0, 20):
            c = 0.13 if s > 0 else 0.15
            fwd, right = body_axes(SIDE_YAW)
            sh = fwd * (0.05 * s)
            p = side_base(crouch=c, spine_rot=(22 if s > 0 else 2, -6, 0), chest_rot=(6 if s > 0 else 0, -6, 0),
                          head_rot=(-12 if s > 0 else 2, -30, 0))
            p["hips"] = (sh.x, 0.015 + sh.y, D - c)
            if s > 0:
                arms(p, SIDE_YAW - 12, c, hand_R=(0.3, 0.28, 0.1), hand_L=(-0.32, 0.05, 0.04))
            else:
                arms(p, SIDE_YAW - 12, c, hand_R=(0.26, 0.34, 0.16), hand_L=(-0.24, 0.32, 0.12),
                     elbow_R=(0.4, -0.1, -0.2), elbow_L=(-0.4, -0.1, -0.2))
            p["hand_rot.L"] = (-25, 0, 20)
            p["hand_rot.R"] = (-25, 0, -20)
            key_pose(arm_obj, f, p)

    # --- İtişler arası (hızlanırken): gövde öne dönük, arka ayak kaykayda ön ayağın arkasında ---
    PUSH_YAW = 16.0
    PUSH_FRONT = (0.0, -0.13, 12.0)
    READY_BACK = (0.0, 0.16, 38.0)

    def ready_pose(k=0.0):
        c = 0.1 + 0.01 * k
        p = side_base(crouch=c, yaw=PUSH_YAW, front=PUSH_FRONT, back=READY_BACK,
                      spine_rot=(16, -4, 0), chest_rot=(4, -2, 0), neck_rot=(-6, -4, 0), head_rot=(-12, -6, 0))
        arms(p, PUSH_YAW - 6, c, hand_R=(0.24, 0.06, 0.02 + 0.01 * k), hand_L=(-0.24, 0.04, 0.02 - 0.01 * k))
        return p

    act("ride_ready")
    for f, k in ((0, 0.0), (20, 1.0), (40, 0.0)):
        key_pose(arm_obj, f, ready_pose(k))

    # --- İtme: güçlü ve derin. 0 = sol ayak kaykayın yanında havada, hemen yere basar;
    #     24 = bacak arkada gergin, parmak ucuyla yerden kalkıyor (parmakla senkron). Ön diz
    #     derin bükülür, gövde öne eğilir, kollar bacağa karşı geniş sallanır. ---
    def push_pose(t):
        e = t * t * (3 - 2 * t)
        c = 0.17 + 0.11 * min(t / 0.65, 1.0)
        p = side_base(crouch=c, yaw=PUSH_YAW, front=PUSH_FRONT, back=SIDE_BACK,
                      hips_rot=(10 + 12 * e, PUSH_YAW, 0), spine_rot=(14 + 8 * e, -4, 0), chest_rot=(4, -2, 0),
                      neck_rot=(-8, -4, 0), head_rot=(-18 - 10 * e, -6, 0))
        p["hips"] = (0.03, -0.05 + 0.02 * e, D - c)
        toe = max(0.0, (t - 0.82) / 0.18)
        drop = (1.0 - min(t / 0.12, 1.0)) ** 2           # kaykayın yanından inip yere basış
        p["foot.L"] = (0.19, -0.1 + 0.74 * e, 0.075 + 0.07 * toe + 0.09 * drop)
        p["foot_rot.L"] = (-50 * toe, 0, 6)
        p["knee.L"] = (0.24, -0.5, 0.45)
        p["knee.R"] = (-0.08, -0.7, 0.55)
        hz = 0.62 + D - c
        p["hand.L"] = (0.3, 0.24 - 0.56 * e, hz + 0.16 * e)
        p["hand.R"] = (-0.3, -0.22 + 0.5 * e, hz + 0.1 * (1 - e))
        p["elbow.L"] = lerp((0.3, 0.6, 0.7), (0.4, 0.35, 0.5), e)
        p["elbow.R"] = lerp((-0.4, 0.35, 0.5), (-0.3, 0.6, 0.7), e)
        p["hand_rot.L"] = (-30 + 20 * e, 0, 10)
        p["hand_rot.R"] = (-10 - 20 * e, 0, -10)
        return p

    act("push")
    for f in range(0, 25):
        key_pose(arm_obj, f, push_pose(f / 24.0))

    # --- İtmeden dönüş: arkadaki ayak yerden kalkar, kaykayın dışından yay çizip yukarıdan
    #     arka vidaların üstüne basar; gövde itişler arası duruşa döner (ride_ready'nin ilk karesi).
    #     Godot'ta itme bitince bir kez oynar (PUSH_RET_FRAMES / 30 sn). ---
    act("push_ret")
    p0, p1 = push_pose(1.0), ready_pose(0.0)
    f0, f1 = Vector(p0["foot.L"]), Vector(p1["foot.L"])
    for f in range(0, PUSH_RET_FRAMES + 1):
        u = f / PUSH_RET_FRAMES
        k = u * u * (3 - 2 * u)
        p = blend_pose(p0, p1, k)
        kx = min(max((u - 0.45) / 0.55, 0.0), 1.0)
        kx = kx * kx * (3 - 2 * kx)                      # kaykayın üstüne ancak yukarıdayken girer
        p["foot.L"] = (f0.x + (f1.x - f0.x) * kx, f0.y + (f1.y - f0.y) * k,
                       f0.z + (f1.z - f0.z) * u + 0.17 * math.sin(math.pi * u) ** 0.7)
        p["foot_rot.L"] = lerp(p0["foot_rot.L"], p1["foot_rot.L"], k)
        p["knee.L"] = lerp(p0["knee.L"], p1["knee.L"], k)
        key_pose(arm_obj, f, p)

    # --- Yüksek hız (dik yokuş aşağı): derin "tuck". Gövde neredeyse yatay, arka diz ön
    #     baldırın arkasına kilitli, eller sırtta birleşik, baş kalkık ileri bakar. ---
    act("ride_tuck")
    TY = 24.0
    for f, k in ((0, 0.0), (30, 1.0), (60, 0.0)):
        c = 0.3 + 0.008 * k
        p = side_base(crouch=c, yaw=TY, front=(0.0, -0.2, 26.0), back=(0.0, 0.13, 58.0),
                      hips_rot=(40, TY, 0), spine_rot=(18, -4, 0), chest_rot=(8, -4, 0),
                      neck_rot=(-30, -8, 0), head_rot=(-34, -8, 0))
        f_ax, _ = body_axes(TY)
        p["hips"] = (f_ax.x * 0.02, 0.04, D - c)
        p["knee.R"] = (0.12, -0.75, 0.6)
        p["knee.L"] = (0.16, -0.5, 0.15)
        arms(p, TY - 8, c, hand_R=(0.04, -0.16, 0.06 + 0.005 * k), hand_L=(-0.04, -0.16, 0.06 + 0.005 * k),
             elbow_R=(0.4, -0.45, 0.35), elbow_L=(-0.4, -0.45, 0.35))
        p["hand_rot.L"] = (40, 0, 30)
        p["hand_rot.R"] = (40, 0, -30)
        key_pose(arm_obj, f, p)

    # --- Fren: sol ayak arkada yerde sürtüyor, gövde geride, kollar öne denge ---
    act("brake")
    for f, k in ((0, 0.0), (6, 1.0), (12, 0.0)):
        key_pose(arm_obj, f, ride_base(
            crouch=0.09, hips=(0.0, 0.06, D - 0.09), spine_rot=(-6, 0, 0),
            **{"foot.L": (0.14, 0.42 + 0.01 * k, 0.075), "foot_rot.L": (12, 0, 0),
               "hand.L": (0.28, -0.06 - 0.01 * k, 0.72 + D - 0.09),
               "hand.R": (-0.28, -0.08 + 0.01 * k, 0.71 + D - 0.09),
               "hand_rot.L": (-35, 0, 15), "hand_rot.R": (-35, 0, -15)}))

    # --- İniş / ollie hazırlığı: derin çömelme (yan duruş), kollar aşağı-dışa ---
    act("crouch")
    for f in (0, 12):
        p = side_base(crouch=0.22, spine_rot=(26, -6, 0), head_rot=(-16, -30, 0))
        arms(p, SIDE_YAW - 12, 0.22, hand_R=(0.34, 0.2, -0.04), hand_L=(-0.34, 0.16, -0.04),
             elbow_R=(0.45, -0.2, -0.1), elbow_L=(-0.45, -0.2, -0.1))
        p["hand_rot.L"] = (-30, 0, 30)
        p["hand_rot.R"] = (-30, 0, -30)
        key_pose(arm_obj, f, p)

    # --- Havada (merdivenden iniş referansı): dizler toplu, arka kol başın üstüne kalkık,
    #     ön kol yana-öne açık, baş inişe bakar ---
    act("air")
    for f, k in ((0, 0.0), (12, 1.0), (24, 0.0)):
        c = 0.13
        p = side_base(crouch=c, dz=TUCK, spine_rot=(10, -6, 3 * k), head_rot=(4, -28, 0))
        arms(p, SIDE_YAW - 12, c, TUCK, hand_R=(0.42, 0.16, 0.12 + 0.02 * k), hand_L=(-0.5, -0.1, 0.5 - 0.03 * k),
             elbow_R=(0.45, -0.2, -0.05), elbow_L=(-0.45, -0.3, 0.05))
        p["hand_rot.L"] = (-15, 0, 35)
        p["hand_rot.R"] = (-15, 0, -35)
        key_pose(arm_obj, f, p)

    # --- Ollie (referans: eğil, zıpla, kuyruğa vur, ön ayağı buruna sürt, dizleri topla).
    #     Fiziksel sıçrama OLLIE_POP_FRAME'de başlar. ---
    act("ollie")
    ollie_keys = [
        # kare, çömelme, kaykay (y, z), burun açısı, arka ayak dz, ön ayak (dy, dz), kollar
        (0, 0.06, (0, 0.0), 0, 0.0, (0.0, 0.0), 0.0),
        (2, 0.19, (0, 0.0), 0, 0.0, (0.0, 0.0), -0.06),
        (3, 0.23, (0, 0.0), 0, 0.0, (0.0, 0.0), -0.08),      # en derin çökme -> pat!
        (4, 0.04, (0.02, 0.1), 26, 0.0, (-0.08, 0.33), 0.08),  # kuyruk vurdu, burun kalktı, ön ayak sürtüyor
        (5, 0.07, (0.0, 0.17), 13, 0.21, (-0.1, 0.28), 0.14),  # kaykay ayaklardan ayrık yükseliyor
        (6, 0.12, (0.0, 0.2), 3, 0.26, (-0.05, 0.27), 0.16),
        (7, 0.14, (0.0, 0.2), 0, 0.2, (0.0, 0.2), 0.15),      # ayaklar kaykayı yakaladı
        (12, 0.13, (0.0, TUCK), 0, TUCK, (0.0, TUCK), 0.12),  # havada toplu duruş (air'e yakın)
    ]
    # Her kare ayrı anahtar (doğrusal ara değer): kaykay ve ayak eğrileri farklı biçimlenip
    # ayak tahtaya gömülmesin
    dense = []
    for f in range(ollie_keys[-1][0] + 1):
        i = max(j for j in range(len(ollie_keys)) if ollie_keys[j][0] <= f)
        k0 = ollie_keys[i]
        k1 = ollie_keys[min(i + 1, len(ollie_keys) - 1)]
        t = 0.0 if k1[0] == k0[0] else (f - k0[0]) / float(k1[0] - k0[0])
        mix = lambda x, y: tuple(mix(xx, yy) for xx, yy in zip(x, y)) if isinstance(x, tuple) else x + (y - x) * t
        dense.append((f,) + tuple(mix(x, y) for x, y in zip(k0[1:], k1[1:])))
    for f, crouch, (by, bz), pitch, back_dz, (fdy, fdz), arm_up in dense:
        p = side_base(crouch=crouch, spine_rot=(10 + crouch * 70, -6, 0), head_rot=(-6 - crouch * 40, -30, 0),
                      board=(0, by, bz), board_rot=(pitch, 0, 0))
        fr, frr = foot_on((SIDE_FRONT[0], SIDE_FRONT[1] + fdy), SIDE_FRONT[2], fdz)
        bk, bkr = foot_on((SIDE_BACK[0], SIDE_BACK[1] + (0.06 if pitch > 15 else 0.0)), SIDE_BACK[2], back_dz)
        p["foot.R"], p["foot.L"] = fr, bk
        p["knee.R"] = knee_pole(fr, SIDE_YAW, along=-0.12, z=0.5 + fdz)
        p["knee.L"] = knee_pole(bk, SIDE_YAW, along=0.08, z=0.5 + back_dz)
        arms(p, SIDE_YAW - 12, crouch, hand_R=(0.3 + arm_up, 0.1, arm_up * 1.2), hand_L=(-0.3 - arm_up * 1.2, -0.03, arm_up * 2.4),
             elbow_R=(0.45, -0.25, -0.1), elbow_L=(-0.4, -0.25, 0.1))
        key_pose(arm_obj, f, p)

    # --- Double jump: daha yükseğe, ayaklar dizlere çekilir, kaykay kendi ekseninde
    #     360° döner (kickflip), ayaklar yakalar ---
    act("flip")
    n = 14
    for f in range(0, n + 1):
        t = f / n
        spin_k = min(max((f - 2) / 8.0, 0.0), 1.0)          # 2..10. karede tam tur
        spin = 360.0 * (spin_k * spin_k * (3 - 2 * spin_k))
        lift = math.sin(min(t / 0.8, 1.0) * math.pi)         # ayakların yukarı çekilmesi
        board_z = TUCK + 0.05 * math.sin(t * math.pi)
        feet_z = board_z + 0.2 * lift
        p = side_base(crouch=0.15, spine_rot=(18, -6, 0), head_rot=(4, -26, 0),
                      board=(0, 0, board_z), board_rot=(0, spin, 0))
        fr, _ = foot_on((SIDE_FRONT[0] + 0.04 * lift, SIDE_FRONT[1]), SIDE_FRONT[2], feet_z)
        bk, _ = foot_on((SIDE_BACK[0] + 0.04 * lift, SIDE_BACK[1]), SIDE_BACK[2], feet_z)
        p["foot.R"], p["foot.L"] = fr, bk
        p["knee.R"] = knee_pole(fr, SIDE_YAW, along=-0.12, z=0.6 + feet_z)
        p["knee.L"] = knee_pole(bk, SIDE_YAW, along=0.08, z=0.6 + feet_z)
        arms(p, SIDE_YAW - 12, 0.15, hand_R=(0.42, 0.12, 0.2), hand_L=(-0.5, -0.1, 0.45),
             elbow_R=(0.45, -0.2, -0.05), elbow_L=(-0.45, -0.3, 0.05))
        p["hand_rot.L"] = (-15, 0, 30)
        p["hand_rot.R"] = (-15, 0, -30)
        key_pose(arm_obj, f, p)

    # --- Grind (düz ray / kenar): alçak, gövde öne-rayın üstüne eğik, kollar iki yana
    #     açık (ön kol öne, arka kol arkaya), baş aşağı rayı izler, denge salınımı ---
    act("grind")
    for f, k in ((0, -1.0), (15, 1.0), (30, -1.0)):
        c = 0.18
        p = side_base(crouch=c, spine_rot=(26, -8, 4 * k), chest_rot=(6, -6, 0), head_rot=(-2, -26, 0))
        arms(p, SIDE_YAW - 14, c, hand_R=(0.48, 0.12, 0.06 + 0.04 * k), hand_L=(-0.46, 0.08, 0.08 - 0.04 * k),
             elbow_R=(0.5, -0.2, -0.05), elbow_L=(-0.5, -0.2, -0.05))
        p["hand_rot.L"] = (-10, 0, 40)
        p["hand_rot.R"] = (-10, 0, -40)
        key_pose(arm_obj, f, p)

    # --- Aşağı eğimli ray (merdiven korkuluğu): gövde dik ve hafif geride (ağırlık arka
    #     ayakta), arka kol başın üstüne kalkık, ön kol öne-aşağı, dizler yumuşak ---
    act("grind_down")
    for f, k in ((0, -1.0), (15, 1.0), (30, -1.0)):
        c = 0.13
        p = side_base(crouch=c, spine_rot=(4, -8, 5 * k), chest_rot=(-4, -8, 0), head_rot=(8, -30, 0))
        p["hips"] = (0.0, 0.05, D - c)
        arms(p, SIDE_YAW - 14, c, hand_R=(0.38, 0.22, -0.02 + 0.03 * k), hand_L=(-0.5, -0.12, 0.55 - 0.04 * k),
             elbow_R=(0.45, -0.2, -0.1), elbow_L=(-0.45, -0.3, 0.05))
        p["hand_rot.L"] = (-10, 0, 40)
        p["hand_rot.R"] = (-10, 0, -40)
        key_pose(arm_obj, f, p)

    # --- Yürüme (kaykay sağ elde): kollar omuzdan sarkaç (sol kol bacağın tersine), dirsek
    #     öne giderken biraz daha bükülür; kalça adımla döner, göğüs tersine; kalça adımda
    #     destek ayağına kayar. Kaykayı tutan sağ kol az sallanır. ---
    act("walk")
    n = WALK["frames"]
    for f in range(0, n + 1):
        u = f / n
        ph = math.tau * u
        c = math.cos(ph)
        hips = (0.012 * math.sin(ph), 0.0, -0.03 + 0.012 * math.cos(2 * ph))
        pose = stand_pose(hips=hips, hips_rot=(0, -6 * c, 0), spine_rot=(4, 4 * c, 0), chest_rot=(0, 3 * c, 0),
                          head_rot=(0, -1 * c, 0))
        pose.update(gait_pose(u, WALK))
        sw = -22 * c                                     # sol ayak öndeyken sol kol geride
        swing_arm(pose, "L", sw, 10 + 16 * max(sw, 0.0) / 22, out=0.06, hips=hips, lean=4, yaw=1 * c)
        swing_arm(pose, "R", 4 + 5 * c, 14, out=0.08, hips=hips, lean=4, yaw=1 * c)
        pose["hand_rot.L"] = (-12 - 8 * max(sw, 0.0) / 22, 0, 8)
        key_pose(arm_obj, f, pose)

    # --- Koşu: uçuş anlı adım, gövde öne eğik, kollar dirsekten ~80° bükük ve omuzdan güçlü
    #     sallanır (sol kol bacağın tersine), göğüs kalçanın tersine döner. ---
    act("run")
    n = RUN["frames"]
    for f in range(0, n + 1):
        u = f / n
        ph = math.tau * u
        c = math.cos(ph)
        # İki ayak havadayken (uçuş) kalça yükselir
        bob = 0.025 * math.cos(2 * math.tau * (u - RUN["duty"] * 0.5))
        hips = (0.008 * math.sin(ph), -0.025, -0.05 + bob)
        pose = stand_pose(hips=hips, hips_rot=(0, -9 * c, 0), spine_rot=(12, 6 * c, 0), chest_rot=(2, 5 * c, 0),
                          head_rot=(-6, -2 * c, 0))
        # Koşuda ayaklar neredeyse tek çizgiye basar, dizler düz öne kalkar
        pose.update(gait_pose(u, RUN, side_x=0.055))
        pose["knee.L"] = (0.07, -0.6, 0.5)
        pose["knee.R"] = (-0.07, -0.6, 0.5)
        sw = -38 * c
        swing_arm(pose, "L", sw, 70 + 15 * max(sw, 0.0) / 38, out=0.05, hips=hips, lean=14, yaw=2 * c)
        swing_arm(pose, "R", 2 + 10 * c, 24, out=0.09, hips=hips, lean=14, yaw=2 * c)
        pose["hand_rot.L"] = (-20, 0, 10)
        key_pose(arm_obj, f, pose)

    # --- Ayakta bekleme ---
    act("stand_idle")
    for f, k in ((0, 0.0), (30, 1.0), (60, 0.0)):
        key_pose(arm_obj, f, stand_pose(hips=(0, 0, -0.012 - 0.006 * k), chest_rot=(-2 * k, 0, 0)))

    # --- Binme (referans 1): kaykay elde yürürken öne eğilip onu yere bırakır, sağ (ön) ayakla
    #     üstüne basar, sol ayakla bir kez iter, ayağı kaykaya alır. Kök MOUNT_SPEED ile ilerler:
    #     yerdeki kaykay ve yere basan ayak köke göre geriye kayar (zeminde kaymazlar).
    #     Son kare itişler arası duruş (ride_ready): oyunda sürüşe dikişsiz geçer. ---
    act("mount")
    V = MOUNT_SPEED / FPS
    LAND, PLANT, PUSH_END = 8, 14, 20

    def board_y(f):
        if f <= LAND:
            return -0.17 - (LAND - f) * V                # yerde duruyor
        return -0.17 * (1.0 - (f - LAND) / float(MOUNT_FRAMES - LAND))   # gövde kaykayın üstüne geçer

    def shifted(p, dy):
        q = dict(p)
        for key in ("foot.R", "knee.R", "hips"):
            q[key] = (q[key][0], q[key][1] + dy, q[key][2])
        return q

    def sm(x):
        x = min(max(x, 0.0), 1.0)
        return x * x * (3 - 2 * x)

    walk0 = stand_pose(hips=(0.0, 0.0, -0.035), spine_rot=(6, 0, 0), hips_rot=(0, 0, 0))
    walk0["foot.L"] = (0.1, -0.18, 0.075)
    walk0["foot.R"] = (-0.1, 0.22, 0.075)
    walk0["foot_rot.R"] = (-25, 0, 0)
    walk0["foot_rot.L"] = (0, 0, 0)
    walk0.update({"chest_rot": (0, 0, 0), "neck_rot": (0, 0, 0), "head_rot": (0, 0, 0)})
    b0 = shifted(push_pose(0.0), board_y(LAND))
    l_lift = (0.1, -0.18 + 10 * V, 0.075)
    for f in range(0, MOUNT_FRAMES + 1):
        by = board_y(f)
        if f <= LAND:
            k = f / LAND
            e = sm(k)
            pose = blend_pose(walk0, b0, e)
            pose["foot.L"] = (0.1, -0.18 + f * V, 0.075)
            pose["foot_rot.L"] = (-30 * sm((f - 5) / 3.0), 0, 0)
            pose["knee.L"] = LIMB_POLES["knee.L"]
            r0, r1 = Vector(walk0["foot.R"]), Vector(b0["foot.R"])
            pr = r0.lerp(r1, e)
            pose["foot.R"] = (pr.x, pr.y, pr.z + 0.21 * math.sin(math.pi * k))
            # Eğilip kaykayı bırakış (2..6. kare)
            dip = math.sin(math.pi * min(max((f - 1) / 6.0, 0.0), 1.0))
            sp = pose["spine_rot"]
            pose["spine_rot"] = (sp[0] + 18 * dip, sp[1], sp[2])
            hp = pose["hips"]
            pose["hips"] = (hp[0], hp[1], hp[2] - 0.05 * dip)
            if f <= 2:
                pose["hand.R"] = STAND_HAND_R
            elif f <= 6:
                pose["hand.R"] = lerp(STAND_HAND_R, (-0.13, by - 0.02, 0.36), sm((f - 2) / 4.0))
            else:
                pose["hand.R"] = lerp((-0.13, board_y(6) - 0.02, 0.36), b0["hand.R"], sm((f - 6) / 2.0))
            pose["carry"] = 1.0 - sm((f - 3) / 3.0)
            swing_arm(pose, "L", -15 + 40 * e, 12 + 20 * e, out=0.08, hips=pose["hips"], lean=8)
        elif f <= PLANT:
            pose = shifted(push_pose(0.0), by)
            if f <= 10:
                pose["foot.L"] = (0.1, -0.18 + f * V, 0.075)
                pose["foot_rot.L"] = (-30 - 10 * (f - LAND), 0, 0)
            else:
                k = (f - 10) / float(PLANT - 10)
                a0, a1 = Vector(l_lift), Vector((0.19, -0.1, 0.075))
                pl = a0.lerp(a1, sm(k))
                pose["foot.L"] = (pl.x, pl.y, pl.z + 0.12 * math.sin(math.pi * k))
                pose["foot_rot.L"] = lerp((-50, 0, 0), (0, 0, 6), sm(k))
            pose["carry"] = 0.0
        elif f <= PUSH_END:
            t = (f - PLANT) / float(PUSH_END - PLANT)
            pose = shifted(push_pose(t), by)
            toe = max(0.0, (t - 0.75) / 0.25)
            pose["foot.L"] = (0.19, -0.1 + (f - PLANT) * V, 0.075 + 0.06 * toe)
            pose["foot_rot.L"] = (-45 * toe, 0, 6)
        else:
            k = (f - PUSH_END) / float(MOUNT_FRAMES - PUSH_END)
            p0 = shifted(push_pose(1.0), by)
            p0["foot.L"] = (0.19, -0.1 + (PUSH_END - PLANT) * V, 0.135)
            p0["foot_rot.L"] = (-45, 0, 6)
            p1 = ready_pose(0.0)
            pose = blend_pose(p0, p1, sm(k))
            f0, f1 = Vector(p0["foot.L"]), Vector(p1["foot.L"])
            kx = sm((k - 0.4) / 0.6)
            pose["foot.L"] = (f0.x + (f1.x - f0.x) * kx, f0.y + (f1.y - f0.y) * sm(k),
                              f0.z + (f1.z - f0.z) * k + 0.15 * math.sin(math.pi * k) ** 0.7)
        pose["board"] = (0.0, by, 0.0)
        if f > 6:
            pose["carry"] = 0.0
        key_pose(arm_obj, f, pose)

    # --- İnme: kaykaydan atla, eğil, kaykayı altından çekip ele al ---
    act("dismount")
    for f in range(0, DISMOUNT_FRAMES + 1):
        if f <= 3:
            k = f / 3.0
            pose = ride_base(crouch=0.06 - 0.06 * k)
            pose["foot.L"] = lerp(LEFT_ON_BOARD, (0.17, 0.08, 0.075 + 0.05), k)
            pose["foot.R"] = lerp(RIGHT_ON_BOARD, (-0.17, -0.06, 0.075 + 0.05), k)
        elif f <= 8:
            k = (f - 3) / 5.0
            pose = stand_pose(carry=0.0, hips=(0.0, 0.03, -0.012 - 0.17 * k), spine_rot=(30 * k, -10 * k, 0),
                              head_rot=(-15 * k, 0, 0))
            pose["foot.L"] = (0.17, 0.08, 0.075 + 0.05 * (1 - min(k * 2, 1)))
            pose["foot.R"] = (-0.17, -0.06, 0.075 + 0.05 * (1 - min(k * 2, 1)))
            pose["hand.R"] = lerp((-0.3, 0.0, 0.7), (-0.13, 0.0, D + 0.07), k)
            pose["hand_rot.R"] = (-40 * k, 0, 0)
        else:
            k = (f - 8) / float(DISMOUNT_FRAMES - 8)
            pose = stand_pose(carry=min(k * 2.2, 1.0), hips=(0.0, 0.03 * (1 - k), -0.012 - 0.17 * (1 - k)),
                              spine_rot=(30 * (1 - k), -10 * (1 - k), 0))
            pose["foot.L"] = lerp((0.17, 0.08, 0.075), (0.11, 0.01, 0.075), k)
            pose["foot.R"] = lerp((-0.17, -0.06, 0.075), (-0.11, 0.01, 0.075), k)
            pose["hand.R"] = lerp((-0.13, 0.0, D + 0.07), STAND_HAND_R, k)
        pose["board"] = (0.0, 0.0, 0.0)
        key_pose(arm_obj, f, pose)

    # --- Sarsılma: yayaya / duvara çarpınca. Gövde ataletle öne savrulur, arka (sol) ayak
    #     kaykaydan inip yana yere basar, gövde o ayağa yaslanıp dengeyi bulur, kollar
    #     çırpınır; sonra ayak kendiliğinden kaykaya geri biner. Kaykay yerinde kalır
    #     (oyunda bu sürede hızla yavaşlar, yere basan ayak kaymaz).
    #     Godot'ta o an oynayan her şeyin üstüne tek seferlik biner (SARSIL_FRAMES / 30 sn). ---
    act("sarsil")
    LB = LEFT_ON_BOARD
    ground = (0.24, 0.04, 0.075)                       # sol ayak: kaykayın solunda yerde
    lift_out = (0.15, 0.1, D + 0.075 + 0.09)           # inerken / binerken havada
    keys = [
        # kare, çömelme, kalça (dx, dy), gövde (öne, burgu, yana), kafa, sol el, sağ el, kollar kalkık, sol ayak
        (0, 0.05, (0.0, 0.02), (6, 0, 0), (0, 0, 0), (0.215, -0.02, 0.7), (-0.215, -0.02, 0.7), False, LB),
        (2, 0.12, (0.0, -0.03), (28, 4, 6), (16, 0, 0), (0.3, -0.24, 0.84), (-0.28, -0.22, 0.8), True, LB),
        (4, 0.1, (0.03, 0.0), (14, -4, -8), (4, -6, 6), (0.44, 0.0, 0.96), (-0.38, 0.06, 0.92), True, lift_out),
        (7, 0.16, (0.07, 0.03), (8, -8, -12), (-8, -6, 8), (0.46, 0.08, 0.9), (-0.4, 0.1, 0.98), True, ground),
        (10, 0.17, (0.08, 0.03), (12, -4, -9), (-2, 4, 4), (0.4, -0.04, 0.86), (-0.36, -0.06, 0.88), True, ground),
        (13, 0.14, (0.06, 0.03), (8, -2, -6), (0, 0, 2), (0.32, -0.04, 0.78), (-0.3, -0.04, 0.78), False, ground),
        (16, 0.09, (0.03, 0.02), (10, 0, -3), (0, 0, 0), (0.28, -0.03, 0.76), (-0.27, -0.03, 0.75), False, lift_out),
        (19, 0.08, (0.0, 0.02), (8, 0, 0), (0, 0, 0), (0.24, -0.02, 0.72), (-0.23, -0.02, 0.72), False, LB),
        (24, 0.05, (0.0, 0.02), (6, 0, 0), (0, 0, 0), (0.215, -0.02, 0.7), (-0.215, -0.02, 0.7), False, LB),
    ]
    for f, crouch, (hx, hy), spine, head, hl, hr, raised, foot_l in keys:
        pose = ride_base(crouch=crouch, hips=(hx, hy, D - crouch), spine_rot=spine, head_rot=head,
                         chest_rot=(spine[0] * 0.3, spine[1] * 0.5, spine[2] * 0.4))
        pose["hand.L"] = (hl[0], hl[1], hl[2] + D - crouch)
        pose["hand.R"] = (hr[0], hr[1], hr[2] + D - crouch)
        pose["foot.L"] = foot_l
        if foot_l is ground:
            pose["knee.L"] = (0.3, -0.55, 0.45)        # diz dışa-öne: yana basış
            pose["foot_rot.L"] = (0, 0, 12)
        elif foot_l is lift_out:
            pose["knee.L"] = (0.25, -0.6, 0.5)
            pose["foot_rot.L"] = (-10, 0, 8)
        if raised:
            pose.update(RAISED_ELBOWS)
            pose["hand_rot.L"] = (-20, 0, 35)
            pose["hand_rot.R"] = (-20, 0, -35)
        key_pose(arm_obj, f, pose)

    # --- Düşme: araba çarptı. Gövde geriye savrulur, ayaklar kaykaydan kopar, kaykayın
    #     arkasına poposunun üstüne düşer (eller geride yere dayanır), kafasını silker,
    #     kalkar, kaykaya adım atıp yeniden biner. Kaykay yerinde kalır (oyunda karakterin
    #     kökü kaykaydır). DUS_FRAMES / 30 sn; Godot'taki FALL_TIME ile aynı. ---
    act("dus")
    hz = REST["hips"].z
    sit = 0.13 - hz                       # oturuşta kalça yerden 13 cm; ayaklar kaykayın üstünde
    fall_keys = [
        # kare, kalça (dx, dy, dz mutlak delta), gövde, kafa, sol el, sağ el, sol ayak, sağ ayak, diz yukarı
        (0, (0.0, 0.02, D - 0.05), (6, 0, 0), (0, 0, 0),
         (0.215, -0.02, 0.65 + D), (-0.215, -0.02, 0.65 + D), LEFT_ON_BOARD, RIGHT_ON_BOARD, False),
        (3, (0.02, 0.1, D - 0.02), (-26, 6, 8), (-20, 0, 0),
         (0.42, 0.02, 1.0), (-0.4, 0.0, 1.02), (0.06, 0.1, D + 0.2), (-0.06, -0.2, D + 0.24), False),
        (7, (0.04, 0.32, -0.25), (-34, 8, 10), (-26, 10, 0),
         (0.46, 0.2, 0.8), (-0.44, 0.18, 0.84), (0.12, -0.05, 0.42), (-0.1, -0.22, 0.48), True),
        (11, (0.05, 0.5, sit), (-22, 4, 4), (10, 0, 0),
         (0.27, 0.78, 0.06), (-0.27, 0.78, 0.06), (0.07, 0.06, D + 0.075), (-0.07, -0.04, D + 0.075), True),
        (14, (0.05, 0.5, sit + 0.04), (-16, 0, 0), (6, 0, 0),
         (0.27, 0.78, 0.06), (-0.27, 0.78, 0.06), (0.07, 0.06, D + 0.075), (-0.07, -0.04, D + 0.075), True),
        (17, (0.05, 0.5, sit), (-18, 0, 0), (2, 0, 0),
         (0.27, 0.78, 0.06), (-0.27, 0.78, 0.06), (0.07, 0.06, D + 0.075), (-0.07, -0.04, D + 0.075), True),
        # kafa silkme (sağ el kafada)
        (22, (0.05, 0.5, sit), (-10, -6, 0), (8, -10, 16),
         (0.27, 0.78, 0.06), (-0.14, 0.38, 0.82), (0.07, 0.06, D + 0.075), (-0.07, -0.04, D + 0.075), True),
        (27, (0.05, 0.5, sit), (-10, 6, 0), (8, 12, -16),
         (0.27, 0.78, 0.06), (-0.14, 0.38, 0.82), (0.07, 0.06, D + 0.075), (-0.07, -0.04, D + 0.075), True),
        (32, (0.05, 0.5, sit), (-12, 0, 0), (4, 0, 8),
         (0.27, 0.78, 0.06), (-0.27, 0.74, 0.06), (0.07, 0.06, D + 0.075), (-0.07, -0.04, D + 0.075), True),
        # kalkış: öne eğil, ayaklar altına, eller dizlerde
        (38, (0.03, 0.42, sit + 0.12), (30, 0, 0), (-10, 0, 0),
         (0.2, 0.2, 0.3), (-0.2, 0.2, 0.3), (0.13, 0.42, 0.075), (-0.13, 0.4, 0.075), True),
        (44, (0.0, 0.44, -0.2), (34, 0, 0), (-16, 0, 0),
         (0.17, 0.3, 0.42), (-0.17, 0.3, 0.42), (0.12, 0.46, 0.075), (-0.12, 0.44, 0.075), False),
        (50, (0.0, 0.44, -0.03), (8, 0, 0), (0, 0, 0),
         (0.25, 0.44, 0.63), (-0.25, 0.44, 0.63), (0.11, 0.45, 0.075), (-0.11, 0.45, 0.075), False),
        # sağ ayak kaykaya, sonra sol ayak; gövde öne geçer
        (55, (0.0, 0.25, D - 0.04), (10, 0, 0), (0, 0, 0),
         (0.26, 0.2, 0.7), (-0.26, 0.2, 0.7), (0.11, 0.45, 0.075), (RIGHT_ON_BOARD[0], RIGHT_ON_BOARD[1], RIGHT_ON_BOARD[2] + 0.06), False),
        (60, (0.0, 0.08, D - 0.02), (8, 0, 0), (0, 0, 0),
         (0.24, 0.0, 0.7 + D), (-0.24, 0.0, 0.7 + D), (0.06, 0.25, D + 0.16), RIGHT_ON_BOARD, False),
        (66, (0.0, 0.02, D - 0.05), (6, 0, 0), (0, 0, 0),
         (0.215, -0.02, 0.65 + D), (-0.215, -0.02, 0.65 + D), LEFT_ON_BOARD, RIGHT_ON_BOARD, False),
    ]
    for f, hips, spine, head, hl, hr, fl, fr, knees_up in fall_keys:
        pose = ride_base(crouch=0.05, hips=hips, spine_rot=spine, head_rot=head,
                         chest_rot=(spine[0] * 0.3, spine[1] * 0.5, spine[2] * 0.4))
        pose["hand.L"], pose["hand.R"] = hl, hr
        pose["foot.L"], pose["foot.R"] = fl, fr
        if knees_up:
            pose["knee.L"] = (0.2, -0.9, 0.75)
            pose["knee.R"] = (-0.2, -0.9, 0.75)
        if hl[2] < 0.2 or hl[2] > 0.9:
            pose.update(RAISED_ELBOWS)
        if hl[2] < 0.2:
            pose["elbow.L"] = (0.4, 0.4, 0.5)
            pose["elbow.R"] = (-0.4, 0.4, 0.5)
            pose["hand_rot.L"] = (40, 0, 10)
            pose["hand_rot.R"] = (40, 0, -10)
        key_pose(arm_obj, f, pose)

    # --- Yaya zıplaması (sıçrayış): çömelik kalkış (kollar geride) -> bacaklar açılır, parmak
    #     uçları aşağı, kollar öne-yukarı savrulur -> dizler göğse toplanır. Godot'ta zıplama
    #     anında baştan oynar (YAYA_ZIPLA_FRAMES / 30), sonra yaya_hava döngüsüne geçer. ---
    def foot_air(lift_l, lift_r, fwd_l=-0.04, fwd_r=0.06, pitch=-20):
        return {"foot.L": (0.12, fwd_l, 0.075 + lift_l), "foot.R": (-0.12, fwd_r, 0.075 + lift_r),
                "foot_rot.L": (pitch, 0, 0), "foot_rot.R": (pitch * 0.6, 0, 0)}

    def air_pose(k=0.0):
        hips = (0.0, 0.0, -0.04 - 0.01 * k)
        p = stand_pose(hips=hips, spine_rot=(10, 0, 0), head_rot=(-6, 0, 0))
        p.update(foot_air(0.17 + 0.02 * k, 0.13 + 0.02 * k))
        p["knee.L"] = (0.15, -0.8, 0.6)
        p["knee.R"] = (-0.15, -0.8, 0.6)
        swing_arm(p, "L", 50 + 4 * k, 40, out=0.16, hips=hips, lean=10)
        swing_arm(p, "R", 12, 46, out=0.12, hips=hips, lean=10)        # kaykayı dizlerden kaldırır
        p["hand_rot.L"] = (-25, 0, 25)
        return p

    act("yaya_zipla")
    zip_keys = [
        # kare, kalça z, gövde öne, sol ayak / sağ ayak yükseklik, parmak eğimi, sol kol açısı, dirsek
        (0, -0.13, 16, 0.0, 0.0, 0, -35, 20),
        (2, -0.02, 8, 0.03, 0.0, -35, 20, 25),
        (4, 0.0, 4, 0.1, 0.06, -40, 60, 30),
        (7, -0.03, 8, 0.17, 0.13, -25, 56, 38),
    ]
    for f, hz, lean, ll, lr, pitch, sw, bend in zip_keys:
        hips = (0.0, 0.0, hz)
        pose = stand_pose(hips=hips, spine_rot=(lean, 0, 0), head_rot=(-lean * 0.4, 0, 0))
        pose.update(foot_air(ll, lr, pitch=pitch))
        if f >= 4:
            pose["knee.L"] = (0.15, -0.8, 0.6)
            pose["knee.R"] = (-0.15, -0.8, 0.6)
        swing_arm(pose, "L", sw, bend, out=0.1 + 0.06 * (f >= 4), hips=hips, lean=lean)
        swing_arm(pose, "R", sw * 0.15 + 6, 20 + 26 * (f >= 4), out=0.1 + 0.02 * (f >= 4), hips=hips, lean=lean)
        key_pose(arm_obj, f, pose)
    key_pose(arm_obj, YAYA_ZIPLA_FRAMES, air_pose(0.0))

    # --- Yayayken havada (döngü): dizler toplu, serbest kol yukarıda dengede, kaykay sağ elde ---
    act("yaya_hava")
    for f, k in ((0, 0.0), (10, 1.0), (20, 0.0)):
        key_pose(arm_obj, f, air_pose(k))

    # --- Yaya inişi: ayaklar yere değer, dizler yükü alır (derin çökme), kollar öne-aşağı,
    #     sonra doğrulur. Godot: iniş anında bir kez (YAYA_INIS_FRAMES / 30). ---
    act("yaya_inis")
    land_keys = [(0, -0.05, 8, 30, 30), (3, -0.17, 20, 18, 26), (6, -0.1, 12, 6, 16), (YAYA_INIS_FRAMES, -0.012, 0, 0, 10)]
    for f, hz, lean, sw, bend in land_keys:
        hips = (0.0, 0.01, hz)
        pose = stand_pose(hips=hips, spine_rot=(lean, 0, 0), head_rot=(-lean * 0.5, 0, 0))
        pose["foot.L"] = (0.12, -0.02, 0.075)
        pose["foot.R"] = (-0.12, 0.05, 0.075)
        pose["knee.L"] = (0.18, -0.7, 0.45)
        pose["knee.R"] = (-0.18, -0.7, 0.45)
        swing_arm(pose, "L", sw, bend, out=0.1, hips=hips, lean=lean)
        swing_arm(pose, "R", 4 + sw * 0.2, 14, out=0.09, hips=hips, lean=lean)
        key_pose(arm_obj, f, pose)

    # --- Yayayken araba çarpması: geriye savrulur, poposunun üstüne düşer (kaykay sağ elde
    #     kalır), kafasını silker, kalkar; yaya olarak devam eder. YAYA_DUS_FRAMES / 30 sn
    #     (Godot'taki FOOT_FALL_TIME ile aynı). ---
    act("yaya_dus")
    hz = REST["hips"].z
    sit = 0.13 - hz
    feet_fwd = ((0.13, -0.32, 0.075), (-0.13, -0.3, 0.075))
    foot_keys = [
        # kare, kalça delta, gövde, kafa, sol el, sağ el, ayaklar, diz yukarı
        (0, (0, 0.0, -0.012), (0, 0, 0), (0, 0, 0), STAND_HAND_L, STAND_HAND_R, ((0.11, 0.01, 0.075), (-0.11, 0.01, 0.075)), False),
        (3, (0.02, 0.1, -0.03), (-24, 6, 8), (-20, 0, 0), (0.42, 0.05, 0.95), (-0.3, 0.1, 0.72), ((0.12, -0.12, 0.2), (-0.1, -0.05, 0.075)), False),
        (7, (0.04, 0.32, -0.32), (-30, 8, 10), (-24, 10, 0), (0.46, 0.25, 0.75), (-0.32, 0.25, 0.55), ((0.13, -0.2, 0.36), (-0.1, -0.25, 0.3)), True),
        (11, (0.05, 0.42, sit), (-22, 4, 4), (10, 0, 0), (0.27, 0.72, 0.06), (-0.3, 0.55, 0.25), feet_fwd, True),
        (14, (0.05, 0.42, sit + 0.04), (-16, 0, 0), (6, 0, 0), (0.27, 0.72, 0.06), (-0.3, 0.55, 0.27), feet_fwd, True),
        (17, (0.05, 0.42, sit), (-18, 0, 0), (2, 0, 0), (0.27, 0.72, 0.06), (-0.3, 0.55, 0.25), feet_fwd, True),
        (22, (0.05, 0.42, sit), (-10, -6, 0), (8, -10, 16), (0.27, 0.72, 0.06), (-0.3, 0.5, 0.3), feet_fwd, True),
        (27, (0.05, 0.42, sit), (-10, 6, 0), (8, 12, -16), (0.27, 0.72, 0.06), (-0.3, 0.5, 0.3), feet_fwd, True),
        (32, (0.03, 0.34, sit + 0.12), (30, 0, 0), (-10, 0, 0), (0.2, 0.12, 0.32), (-0.3, 0.25, 0.4), ((0.13, 0.32, 0.075), (-0.13, 0.3, 0.075)), True),
        (38, (0.0, 0.3, -0.2), (34, 0, 0), (-16, 0, 0), (0.17, 0.2, 0.42), (-0.29, 0.2, 0.55), ((0.12, 0.34, 0.075), (-0.12, 0.32, 0.075)), False),
        (45, (0.0, 0.0, -0.012), (0, 0, 0), (0, 0, 0), STAND_HAND_L, STAND_HAND_R, ((0.11, 0.01, 0.075), (-0.11, 0.01, 0.075)), False),
    ]
    for f, hips, spine, head, hl, hr, (fl, fr), knees_up in foot_keys:
        # Kalça 0 karede ayakta, sonra ayakların gerisine (karakter geriye düşer, sonra öne kalkar)
        dy = hips[1]
        pose = stand_pose(hips=hips, spine_rot=spine, head_rot=head,
                          chest_rot=(spine[0] * 0.3, spine[1] * 0.5, spine[2] * 0.4))
        pose["hand.L"] = (hl[0], hl[1], hl[2])
        pose["hand.R"] = (hr[0], hr[1], hr[2])
        pose["foot.L"] = (fl[0], fl[1] + dy * 0.0, fl[2])
        pose["foot.R"] = (fr[0], fr[1] + dy * 0.0, fr[2])
        if knees_up:
            pose["knee.L"] = (0.2, -0.9, 0.75)
            pose["knee.R"] = (-0.2, -0.9, 0.75)
        if hl[2] < 0.2 or hl[2] > 0.9:
            pose["elbow.L"] = RAISED_ELBOWS["elbow.L"] if hl[2] > 0.9 else (0.4, 0.4, 0.5)
        if hl[2] < 0.2:
            pose["hand_rot.L"] = (40, 0, 10)
        key_pose(arm_obj, f, pose)

    # --- Çantaya atma (soygun): sol elle öndeki eşyaya uzanır (kaykay sağ elde), alır, omzunun
    #     üstünden sırt çantasına atar, toparlanır. Godot: CANTA_FRAMES / 30 sn; eşya elde
    #     CANTA_GRAB..CANTA_DROP arasında taşınır (soygun.gd ile aynı). ---
    act("cantaya_at")
    canta_keys = [
        # kare, kalça delta, gövde, kafa, sol el, sol el dönüşü, dirsek
        (0, (0, 0.0, -0.012), (0, 0, 0), (0, 0, 0), (0.25, 0.02, 0.63), (-12, 0, 8), None),
        (6, (0, -0.04, -0.06), (22, -10, 0), (-14, -8, 0), (0.24, -0.34, 0.74), (-60, 0, 20), (0.42, 0.1, 0.7)),
        (11, (0, -0.06, -0.08), (26, -12, 0), (-16, -10, 0), (0.2, -0.46, 0.8), (-80, 0, 20), (0.45, 0.0, 0.75)),
        (15, (0, -0.05, -0.06), (20, -8, 0), (-10, -6, 0), (0.2, -0.42, 0.82), (-80, 0, 20), (0.45, 0.0, 0.75)),
        (21, (0, 0.0, -0.02), (2, 14, 4), (6, 20, 0), (0.26, -0.05, 1.05), (-150, 0, 10), (0.4, 0.05, 0.85)),
        (26, (0, 0.02, -0.012), (-4, 22, 6), (8, 28, 0), (0.16, 0.2, 1.02), (-190, 0, 0), (0.38, 0.2, 0.95)),
        (30, (0, 0.02, -0.012), (-4, 22, 6), (6, 26, 0), (0.15, 0.22, 0.98), (-190, 0, 0), (0.38, 0.2, 0.95)),
        (36, (0, 0.0, -0.012), (2, 6, 0), (0, 8, 0), (0.26, 0.05, 0.7), (-30, 0, 10), None),
        (42, (0, 0.0, -0.012), (0, 0, 0), (0, 0, 0), (0.25, 0.02, 0.63), (-12, 0, 8), None),
    ]
    for f, hips, spine, head, hl, hrot, elbow in canta_keys:
        pose = stand_pose(hips=hips, spine_rot=spine, head_rot=head,
                          chest_rot=(spine[0] * 0.3, spine[1] * 0.5, spine[2] * 0.4))
        pose["hand.L"] = hl
        pose["hand_rot.L"] = hrot
        if elbow:
            pose["elbow.L"] = elbow
        key_pose(arm_obj, f, pose)

    # --- Çantayı aç: sol el omuzdaki askıya uzanır, çantayı sırttan çekip öne getirir, bakar ---
    act("canta_ac")
    ac_keys = [
        (0, stand_pose(), 0.0),
        (6, stand_pose(spine_rot=(2, -14, 0), head_rot=(0, -20, 0), **{"hand.L": (0.15, 0.1, 1.06), "hand_rot.L": (-150, 0, 10),
                                                                       "elbow.L": (0.4, 0.1, 0.95)}), 0.0),
        (9, stand_pose(spine_rot=(2, -16, 0), head_rot=(0, -22, 0), **{"hand.L": (0.15, 0.16, 1.05), "hand_rot.L": (-160, 0, 10),
                                                                       "elbow.L": (0.42, 0.12, 0.95)}), 0.0),
        (15, stand_pose(spine_rot=(4, -8, 0), head_rot=(10, -12, 0), **{"hand.L": (0.3, -0.1, 0.98), "hand_rot.L": (-60, 0, 30),
                                                                       "elbow.L": (0.42, 0.2, 0.8)}), 0.85),
        (20, bag_hold_pose(), 1.0),
        (24, bag_hold_pose(hips=(0, 0, -0.02)), 1.0),
    ]
    for f, pose, bag in ac_keys:
        pose["bag"] = bag
        key_pose(arm_obj, f, pose)
    # Çantayı kapat: tersi
    act("canta_kapat")
    for f, pose, bag in reversed(ac_keys):
        pose["bag"] = bag
        key_pose(arm_obj, 24 - f, pose)
    # Açık çantaya bakarken bekleme
    act("canta_acik")
    for f, k in ((0, 0.0), (20, 1.0), (40, 0.0)):
        pose = bag_hold_pose(hips=(0, 0, -0.02 - 0.006 * k))
        pose["hand.L"] = (BAG_HOLD_HAND[0], BAG_HOLD_HAND[1], BAG_HOLD_HAND[2] + 0.01 * k)
        pose["bag"] = 1.0
        key_pose(arm_obj, f, pose)

    # --- Eline al: sol elle öndeki eşyaya uzanır, alır, göğsünün önüne getirir (eşya elde kalır) ---
    HOLD_ITEM = (0.17, -0.27, 0.84)
    act("eline_al")
    al_keys = [
        (0, (0, 0.0, -0.012), (0, 0, 0), (0, 0, 0), (0.25, 0.02, 0.63), (-12, 0, 8), None),
        (6, (0, -0.04, -0.06), (22, -10, 0), (-14, -8, 0), (0.24, -0.34, 0.74), (-60, 0, 20), (0.42, 0.1, 0.7)),
        (10, (0, -0.06, -0.08), (26, -12, 0), (-16, -10, 0), (0.2, -0.46, 0.8), (-80, 0, 20), (0.45, 0.0, 0.75)),
        (13, (0, -0.05, -0.06), (20, -8, 0), (-10, -6, 0), (0.2, -0.42, 0.82), (-80, 0, 20), (0.45, 0.0, 0.75)),
        (20, (0, 0.0, -0.012), (4, 0, 0), (8, 0, 0), HOLD_ITEM, (-70, 0, 20), (0.36, 0.25, 0.72)),
    ]
    for f, hips, spine, head, hl, hrot, elbow in al_keys:
        pose = stand_pose(hips=hips, spine_rot=spine, head_rot=head, chest_rot=(spine[0] * 0.3, spine[1] * 0.5, spine[2] * 0.4))
        pose["hand.L"], pose["hand_rot.L"] = hl, hrot
        if elbow:
            pose["elbow.L"] = elbow
        key_pose(arm_obj, f, pose)
    # Elde tutma (yürürken sol kola bindirilir)
    act("elde_tut")
    for f in (0, 20):
        pose = stand_pose()
        pose["hand.L"], pose["hand_rot.L"], pose["elbow.L"] = HOLD_ITEM, (-70, 0, 20), (0.36, 0.25, 0.72)
        key_pose(arm_obj, f, pose)
    # Çantaya koy: göğüsteki eşyayı omzun üstünden sırt çantasına (14. karede çantada)
    act("cantaya_koy")
    koy_keys = [
        (0, (0, 0.0, -0.012), (4, 0, 0), (8, 0, 0), HOLD_ITEM, (-70, 0, 20), (0.36, 0.25, 0.72)),
        (8, (0, 0.0, -0.02), (2, 14, 4), (6, 20, 0), (0.26, -0.05, 1.05), (-150, 0, 10), (0.4, 0.05, 0.85)),
        (14, (0, 0.02, -0.012), (-4, 22, 6), (8, 28, 0), (0.16, 0.2, 1.02), (-190, 0, 0), (0.38, 0.2, 0.95)),
        (17, (0, 0.02, -0.012), (-4, 22, 6), (6, 26, 0), (0.15, 0.22, 0.98), (-190, 0, 0), (0.38, 0.2, 0.95)),
        (24, (0, 0.0, -0.012), (0, 0, 0), (0, 0, 0), (0.25, 0.02, 0.63), (-12, 0, 8), None),
    ]
    for f, hips, spine, head, hl, hrot, elbow in koy_keys:
        pose = stand_pose(hips=hips, spine_rot=spine, head_rot=head, chest_rot=(spine[0] * 0.3, spine[1] * 0.5, spine[2] * 0.4))
        pose["hand.L"], pose["hand_rot.L"] = hl, hrot
        if elbow:
            pose["elbow.L"] = elbow
        key_pose(arm_obj, f, pose)

    # --- Havada çırpınma: dükkan sahibi tişörtünden tutup kaldırmış; bacaklar tekmeler, kollar
    #     çırpınır (kaykay sağ elde). Kökü Godot'ta sahibin ellerine göre taşınır. ---
    act("havada_cirpin")
    n = 16
    for f in range(0, n + 1, 2):
        ph = math.tau * f / n
        pose = stand_pose(hips=(0, 0.0, -0.03), spine_rot=(-8, 6 * math.sin(ph), 0), head_rot=(-12, 18 * math.sin(ph * 2), 0))
        pose["foot.L"] = (0.1, -0.08 + 0.12 * math.sin(ph), 0.12 + 0.1 * max(0.0, math.sin(ph)))
        pose["foot.R"] = (-0.1, -0.08 - 0.12 * math.sin(ph), 0.12 + 0.1 * max(0.0, -math.sin(ph)))
        pose["knee.L"] = (0.15, -0.8, 0.5)
        pose["knee.R"] = (-0.15, -0.8, 0.5)
        pose["hand.L"] = (0.42, -0.05 + 0.12 * math.sin(ph * 2), 0.95 + 0.1 * math.cos(ph * 2))
        pose["hand_rot.L"] = (-20, 0, 40)
        pose.update({"elbow.L": RAISED_ELBOWS["elbow.L"]})
        key_pose(arm_obj, f, pose)

    # --- Tutunma (skitching): arabanın arkasına sağ elle tutunmuş, çömelik, sol kol dengede.
    #     El, kökün 0,6 m önünde tampon yüksekliğinde (Godot'ta SKITCH_GAP ile aynı) ---
    act("tutun")
    for f, k in ((0, 0.0), (15, 1.0), (30, 0.0)):
        c = 0.13 + 0.01 * k
        pose = ride_base(crouch=c, spine_rot=(20, -8, 0), chest_rot=(4, -6, 0), head_rot=(-12, 4, 0))
        pose["hand.R"] = (-0.1, -0.6, 0.52 + 0.005 * k)
        pose["hand_rot.R"] = (-70, 0, 0)
        pose["elbow.R"] = (-0.3, 0.2, 0.5)
        pose["hand.L"] = (0.4, 0.05, 0.78 + D - c + 0.02 * k)
        pose["hand_rot.L"] = (-15, 0, 35)
        pose["elbow.L"] = RAISED_ELBOWS["elbow.L"]
        key_pose(arm_obj, f, pose)

    # --- Bankta oturma (döngü): kalça oturağın üstünde (bank oturağı 0,66 m: kalça neredeyse
    #     ayaktaki yüksekliğinde), uyluklar öne yatay, ayaklar havada sallanır; sol el dizde,
    #     sağ el yanda kaykayı tutar. Godot'ta kök oturağın ortasına, bankın tabanı hizasına konur.
    act("otur")
    n = 80
    for f in range(0, n + 1, 4):
        ph = math.tau * f / n
        br = math.sin(ph * 2)
        pose = stand_pose(hips=(0, 0.02, -0.025 - 0.004 * br), spine_rot=(-4 - 1.5 * br, 0, 0),
                          chest_rot=(-3, 0, 0), head_rot=(4, 14 * math.sin(ph), 0))
        for sfx, side, off in (("L", 1, 0.0), ("R", -1, math.pi)):
            sw = math.sin(ph * 2 + off)
            pose[f"foot.{sfx}"] = (0.12 * side, -0.34 - 0.08 * sw, 0.39 + 0.05 * max(sw, 0.0))
            pose[f"foot_rot.{sfx}"] = (-20 + 14 * sw, 0, 6 * side)
            pose[f"knee.{sfx}"] = (0.13 * side, -0.9, 0.7)
        pose["hand.L"] = (0.13, -0.22, 0.72)
        pose["hand_rot.L"] = (-60, 0, 10)
        pose["elbow.L"] = (0.3, 0.2, 0.75)
        pose["hand.R"] = (-0.27, 0.0, 0.68)
        key_pose(arm_obj, f, pose)


    # --- Müzik çalar: kaykayı yere bırak, cepten çıkar, kulaklıkları tak (sağ, sonra sol), bak ---
    # Kaykay sağ bacağın yanında kuyruğu üstünde dik durur, burnu yukarıda, grip bacağa dönük,
    # üstü hafifçe bacağa yaslı. Elden bırakılırken taşıma kısıtının etkisi azalır: kaykay elde
    # yatay hâlden dik hâle döner, el burnunu tutar, sonra bırakır.
    board_rest = arm_obj.data.bones["board"].matrix_local.copy()
    rot = Matrix(((0, 0, 1), (-1, 0, 0), (0, -1, 0))).to_4x4()   # model X -> -Y, Y -> -Z, Z (grip) -> +X
    rot = Matrix.Rotation(math.radians(13), 4, 'Y') @ rot       # üstü bacağa doğru yatık
    tail_tip = Vector((0.0, 0.39, 0.03))                         # kuyruğun ucu (model)
    contact = Vector((-0.24, -0.1, 0.015))
    rot.translation = contact - (rot.to_3x3() @ tail_tip)
    stand_m = rot @ board_rest
    # Ebeveynsiz kemik: poz matrisi = dinlenme @ temel -> temel = dinlenme^-1 @ istenen
    basis = board_rest.inverted() @ stand_m
    BOARD_RAW = (tuple(basis.to_translation()), tuple(basis.to_euler('XYZ')))
    print("MUZIK kaykay dik:", BOARD_RAW)
    nose = rot @ Vector((0.0, -0.4, 0.06))
    NOSE_HAND = (nose.x - 0.03, nose.y + 0.01, nose.z + 0.05)
    # Burnu tutarken (kaykay dik, el üstünde)
    down = stand_pose(carry=0.0, spine_rot=(4, 0, -4), head_rot=(-4, 8, 0))
    down["hand.R"] = NOSE_HAND
    down["hand_rot.R"] = (-12, 0, -8)
    down["elbow.R"] = (-0.42, 0.45, 0.55)
    down["board_raw"] = BOARD_RAW

    def on_ground(p):
        p["carry"] = 0.0
        p["board_raw"] = BOARD_RAW
        return p

    def pocket_pose(k_in):
        p = stand_pose(carry=0.0, hips=(0, 0, -0.012 - 0.01 * k_in), spine_rot=(6, -6, 0), head_rot=(10, -10, 0))
        p["hand.L"] = (POCKET_L[0], POCKET_L[1] + 0.02 * k_in, POCKET_L[2] - 0.035 * k_in)
        p["hand_rot.L"] = (20, 0, 10)
        p["elbow.L"] = (0.36, 0.3, 0.75)
        return p

    act("muzik_cikar")
    up_r = stand_pose(carry=0.0)
    keys = [
        (0, stand_pose(), False),
        (3, dict(stand_pose(), board_raw=BOARD_RAW), False),
        (10, on_ground(dict(down)), True),
        (13, on_ground(dict(down)), True),
        (17, on_ground(stand_pose(carry=0.0, spine_rot=(4, -4, 0))), True),
        (19, on_ground(pocket_pose(0.0)), True),
        (MZ_CEPTEN, on_ground(pocket_pose(1.0)), True),
        (30, on_ground(dict(music_hold_pose(), **{"hand.R": up_r["hand.R"], "hand_rot.R": up_r["hand_rot.R"],
                                                  "elbow.R": up_r["elbow.R"]})), True),
        (MZ_SAG_AL, on_ground(dict(music_hold_pose(), **{"hand.R": (DEVICE_TOP[0] - 0.02, DEVICE_TOP[1], DEVICE_TOP[2]),
                                                         "hand_rot.R": (-90, 0, -10)})), True),
        (MZ_SAG_TAK - 2, on_ground(music_ear_pose("R")), True),
        (MZ_SAG_TAK + 2, on_ground(music_ear_pose("R", hips=(0, 0, -0.016))), True),
        (MZ_EL_DEGIS, on_ground(music_hold_pose()), True),
        (MZ_SOL_AL, on_ground(dict(music_hold_pose(), **{"hand.L": (DEVICE_TOP[0] + 0.02, DEVICE_TOP[1], DEVICE_TOP[2]),
                                                         "hand_rot.L": (-90, 0, 10)})), True),
        (MZ_SOL_TAK - 2, on_ground(music_ear_pose("L")), True),
        (MZ_SOL_TAK + 2, on_ground(music_ear_pose("L", hips=(0, 0, -0.016))), True),
        (MZ_IKI_EL, on_ground(music_hold_pose()), True),
        (MUZIK_FRAMES, on_ground(music_hold_pose(hips=(0, 0, -0.016))), True),
    ]
    for f, pose, _g in keys:
        key_pose(arm_obj, f, pose)

    # Bakma (döngü): iki elde, hafif nefes
    act("muzik_bak")
    for f, k in ((0, 0.0), (24, 1.0), (48, 0.0)):
        p = on_ground(music_hold_pose(hips=(0, 0, -0.016 - 0.006 * k)))
        p["hand.L"] = (HOLD_L[0], HOLD_L[1], HOLD_L[2] + 0.008 * k)
        p["hand.R"] = (HOLD_R[0], HOLD_R[1], HOLD_R[2] + 0.008 * k)
        key_pose(arm_obj, f, p)

    # Cebe koy: sol el cihazı cebe, sağ el kaykayı yerden alır, doğrulur (kulaklıklar kulakta kalır)
    act("muzik_koy")
    koy = [
        (0, on_ground(music_hold_pose())),
        (8, on_ground(pocket_pose(0.0))),
        (12, on_ground(pocket_pose(1.0))),
        (16, on_ground(stand_pose(carry=0.0))),
        (21, on_ground(dict(down))),
        (24, on_ground(dict(down))),
        (MUZIK_KOY_FRAMES - 3, dict(stand_pose(), board_raw=BOARD_RAW)),
        (MUZIK_KOY_FRAMES, stand_pose()),
    ]
    for f, pose in koy:
        key_pose(arm_obj, f, pose)

    # Kısa çıkarma (cihaz açık, kulaklıklar zaten kulakta): kaykayı diker, cepten çıkarır, bakar
    act("muzik_cikar_kisa")
    kisa = [
        (0, stand_pose()),
        (3, dict(stand_pose(), board_raw=BOARD_RAW)),
        (10, on_ground(dict(down))),
        (13, on_ground(dict(down))),
        (17, on_ground(stand_pose(carry=0.0, spine_rot=(4, -4, 0)))),
        (19, on_ground(pocket_pose(0.0))),
        (MZ_CEPTEN, on_ground(pocket_pose(1.0))),
        (30, on_ground(dict(music_hold_pose(), **{"hand.R": up_r["hand.R"], "hand_rot.R": up_r["hand_rot.R"],
                                                  "elbow.R": up_r["elbow.R"]}))),
        (MUZIK_KISA_FRAMES, on_ground(music_hold_pose(hips=(0, 0, -0.016)))),
    ]
    for f, pose in kisa:
        key_pose(arm_obj, f, pose)

    # Kapatma (güç düğmesi): sağ, sonra sol kulaklığı çıkarır; cihazı cebe koyar, kaykayı alır
    def pulled(sfx):
        p = music_ear_pose(sfx)
        h = EAR_HAND_L if sfx == "L" else EAR_HAND_R
        s = 1 if sfx == "L" else -1
        p["hand." + sfx] = (h[0] + 0.07 * s, h[1] - 0.03, h[2] - 0.05)
        return p

    act("muzik_kulaklik_cikar")
    kc = [
        (0, on_ground(music_hold_pose())),
        (KC_SAG_KULAK, on_ground(music_ear_pose("R"))),
        (KC_SAG_CEK, on_ground(pulled("R"))),
        (KC_SAG_BIT, on_ground(music_hold_pose())),
        (KC_SOL_KULAK, on_ground(music_ear_pose("L"))),
        (KC_SOL_CEK, on_ground(pulled("L"))),
        (KC_SOL_BIT, on_ground(music_hold_pose())),
        (KC_SOL_BIT + 2, on_ground(music_hold_pose())),
        (KC_CEBE - 4, on_ground(pocket_pose(0.0))),
        (KC_CEBE, on_ground(pocket_pose(1.0))),
        (KC_CEBE + 4, on_ground(stand_pose(carry=0.0))),
        (KC_CEBE + 9, on_ground(dict(down))),
        (KC_CEBE + 12, on_ground(dict(down))),
        (MUZIK_KC_FRAMES - 3, dict(stand_pose(), board_raw=BOARD_RAW)),
        (MUZIK_KC_FRAMES, stand_pose()),
    ]
    for f, pose in kc:
        key_pose(arm_obj, f, pose)
    return acts


# ---------------------------------------------------------------------------
def render_previews(arm_obj, acts):
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = 420
    scene.render.resolution_y = 560
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.18, 0.18, 0.19)
    cam_data = bpy.data.cameras.new("Kamera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 2.1
    cam = bpy.data.objects.new("Kamera", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    # KK_ACTS: yalnız bu eylemler; KK_VIEWS: açılar (0 = önden, 180 = arkadan, oyun kamerası)
    only = [x for x in os.environ.get("KK_ACTS", "").split(",") if x]
    views = [float(x) for x in os.environ.get("KK_VIEWS", "-50").split(",")]
    nfr = int(os.environ.get("KK_FRAMES", "3"))
    for name in acts:
        if only and name not in only:
            continue
        act = bpy.data.actions[name]
        arm_obj.animation_data.action = act
        f0, f1 = act.frame_range
        for vi, deg in enumerate(views):
            a = math.radians(deg)
            d = Vector((math.sin(a), -math.cos(a), 0.25)).normalized()
            cam.location = Vector((0, 0.0, 0.7)) + d * 4.0
            cam.rotation_euler = (math.radians(90 - 14.5), 0, a)
            for i in range(nfr):
                f = f0 + (f1 - f0) * (i / max(nfr - 1, 1))
                scene.frame_set(int(round(f)))
                scene.render.filepath = os.path.join(PREVIEW_DIR, f"poz_{name}_v{vi}_{i}.png")
                bpy.ops.render.render(write_still=True)


def main():
    arm_obj = build_armature()
    rest_heads(arm_obj)
    skin_character(arm_obj)
    skin_board(arm_obj)
    add_carry_bone(arm_obj)
    add_bag_bones(arm_obj)
    add_music_bones(arm_obj)
    acts = make_actions(arm_obj)
    bpy.context.scene.render.fps = FPS

    if PREVIEW_DIR:
        render_previews(arm_obj, acts)

    arm_obj.animation_data.action = bpy.data.actions["ride_idle"]
    bpy.context.scene.frame_set(0)
    blend_out = os.path.join(os.path.dirname(bpy.data.filepath), "karakter_rig.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_out)

    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format='GLB',
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_force_sampling=True,
        export_def_bones=True,
        export_yup=True,
        # Müzik çalar ve kulaklık meshleri köşe rengiyle boyalı
        export_vertex_color='ACTIVE',
    )
    print("GLB", OUT_GLB, "ANIM", acts)


main()
