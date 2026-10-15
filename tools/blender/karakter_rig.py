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
MOUNT_FRAMES = 15        # 0.5 sn: Godot'taki MOUNT_TIME ile aynı
MOUNT_SPEED = 3.0        # binerken koşu hızı (m/sn): Godot ile aynı olmalı
DISMOUNT_FRAMES = 15
OLLIE_POP_FRAME = 3      # 0.1 sn hazırlık: Godot'taki ollie_windup ile aynı
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
            add("chest", v.index, 1.0)
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
    for sfx in ("L", "R"):
        if f"foot.{sfx}" in pose:
            set_target(arm_obj, f"ik_foot.{sfx}", pose[f"foot.{sfx}"])
        if f"foot_rot.{sfx}" in pose:
            pb[f"ik_foot.{sfx}"].rotation_euler = [math.radians(a) for a in pose[f"foot_rot.{sfx}"]]
        if f"hand.{sfx}" in pose:
            set_target(arm_obj, f"ik_hand.{sfx}", pose[f"hand.{sfx}"])
        if f"knee.{sfx}" in pose:
            set_target(arm_obj, f"pole_knee.{sfx}", pose[f"knee.{sfx}"])
        if f"elbow.{sfx}" in pose:
            set_target(arm_obj, f"pole_elbow.{sfx}", pose[f"elbow.{sfx}"])
    con = pb["board"].constraints.get("Tasima")
    if con:
        con.influence = pose.get("carry", 0.0)


def key_pose(arm_obj, frame, pose):
    apply_pose(arm_obj, pose)
    for p in arm_obj.pose.bones:
        p.keyframe_insert("location", frame=frame)
        p.keyframe_insert("rotation_euler", frame=frame)
    con = arm_obj.pose.bones["board"].constraints.get("Tasima")
    if con:
        con.keyframe_insert("influence", frame=frame)


def new_action(arm_obj, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    arm_obj.animation_data.action = act
    return act


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


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


def stand_pose(**over):
    p = {"hips": (0, 0, -0.012)}
    for sfx, side in (("L", 1), ("R", -1)):
        p[f"foot.{sfx}"] = (0.11 * side, 0.01, 0.075)
        p[f"hand.{sfx}"] = (0.25 * side, 0.02, 0.63)
    p["hand.R"] = (-0.27, 0.03, 0.66)   # kaykayı tutan el biraz yukarıda
    p.update(LIMB_POLES)
    p.update(HAND_RELAX)
    p["carry"] = 1.0
    p.update(over)
    return p


def add_carry_bone(arm_obj):
    """Ayakta duruş pozunda kaykay sağ yanda dik, grip yüzü vücuda dönük dursun.
    O pozda elin dönüşümünü ölçüp el kemiğine bağlı yardımcı kemiği buna göre koyar."""
    apply_pose(arm_obj, stand_pose(carry=0.0))
    bpy.context.view_layer.update()
    hand_pose = arm_obj.pose.bones["hand.R"].matrix.copy()
    hand_rest = arm_obj.data.bones["hand.R"].matrix_local.copy()
    board_rest = arm_obj.data.bones["board"].matrix_local.copy()
    # Kaykay modeli: boyu +Y... ucu -Y, üst yüz +Z. Elde: boyu dikey (+Z),
    # üst yüz (+Z) vücuda doğru (+X, sağ taraftan bakınca içeri), genişlik +Y.
    # Satırlar; sütunlar: model X -> +Y, Y -> +Z, Z (üst yüz) -> +X, konum son sütun
    rot = Matrix(((0, 0, 1, -0.43), (1, 0, 0, 0.03), (0, 1, 0, 0.56), (0, 0, 0, 1)))
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


def make_actions(arm_obj):
    acts = []

    def act(name):
        new_action(arm_obj, name)
        acts.append(name)

    # --- Kaykayda bekleme (yavaş): gevşek kollar, nefes ---
    act("ride_idle")
    for f, k in ((0, 0.0), (24, 1.0), (48, 0.0)):
        key_pose(arm_obj, f, ride_base(crouch=0.04 + 0.012 * k, chest_rot=(-2 * k, 0, 0),
                                       **{"hand.L": (0.215, -0.02 + 0.01 * k, 0.7 + D - 0.04),
                                          "hand.R": (-0.215, -0.02 - 0.01 * k, 0.7 + D - 0.04)}))

    # --- Hızlı sürüş: daha çömelik, kollar dengeye hafif açık ve geride ---
    act("ride_fast")
    for f, k in ((0, 0.0), (20, 1.0), (40, 0.0)):
        c = 0.1 + 0.01 * k
        key_pose(arm_obj, f, ride_base(
            crouch=c, spine_rot=(16, 0, 0), head_rot=(-10, 0, 0),
            **{"hand.L": (0.24, 0.06 + 0.01 * k, 0.71 + D - c),
               "hand.R": (-0.24, 0.04 - 0.01 * k, 0.72 + D - c),
               "hand_rot.L": (-25, 0, 20), "hand_rot.R": (-25, 0, -20)}))

    # --- Dönüşler (hızlıyken): gövde dönüşe bükülür, kollar karşı denge kurar ---
    for name, s in (("ride_turn_l", 1), ("ride_turn_r", -1)):
        act(name)
        for f in (0, 20):
            c = 0.09
            inner, outer = ("L", "R") if s > 0 else ("R", "L")
            pose = ride_base(
                crouch=c, hips=(0.02 * s, 0.02, D - c),
                spine_rot=(12, 12 * s, 5 * s), chest_rot=(0, 6 * s, 0), head_rot=(-6, 14 * s, 0))
            pose[f"hand.{inner}"] = (0.23 * s, 0.1, 0.64 + D - c)
            pose[f"hand.{outer}"] = (-0.31 * s, -0.06, 0.74 + D - c)
            pose[f"hand_rot.{outer}"] = (-15, 0, -15 * s)
            pose[f"elbow.{outer}"] = RAISED_ELBOWS[f"elbow.{outer}"]
            key_pose(arm_obj, f, pose)

    # --- İtme: 0 = sol ayak önde yere bastı, 24 = sol ayak arkada (parmakla senkron) ---
    act("push")
    for f in range(0, 25, 3):
        t = f / 24.0
        foot_y = -0.22 + 0.72 * t
        swing = math.sin(t * math.pi)
        key_pose(arm_obj, f, ride_base(
            crouch=0.11,
            hips=(0.01, -0.03, D - 0.11),
            spine_rot=(22 + 4 * swing, -6 + 12 * t, 3),
            head_rot=(-14, 4 - 8 * t, 0),
            **{"foot.L": (0.16, foot_y, 0.075 + (0.025 if t > 0.92 else 0.0)),
               "foot_rot.L": (-25 * t, 0, 0),
               "foot.R": RIGHT_ON_BOARD,
               # Kollar itmeye karşı sallanır: sol kol öne, sağ kol arkaya (ve tersi)
               "hand.L": (0.26, -0.08 + 0.2 * t, 0.63 + D - 0.11 + 0.02 * swing),
               "hand.R": (-0.26, 0.1 - 0.2 * t, 0.64 + D - 0.11 + 0.02 * swing),
               "hand_rot.L": (-30 + 30 * t, 0, 10), "hand_rot.R": (-30 * t, 0, -10)}))

    # --- Fren: sol ayak arkada yerde sürtüyor, gövde geride, kollar öne denge ---
    act("brake")
    for f, k in ((0, 0.0), (6, 1.0), (12, 0.0)):
        key_pose(arm_obj, f, ride_base(
            crouch=0.09, hips=(0.0, 0.06, D - 0.09), spine_rot=(-6, 0, 0),
            **{"foot.L": (0.14, 0.42 + 0.01 * k, 0.075), "foot_rot.L": (12, 0, 0),
               "hand.L": (0.28, -0.06 - 0.01 * k, 0.72 + D - 0.09),
               "hand.R": (-0.28, -0.08 + 0.01 * k, 0.71 + D - 0.09),
               "hand_rot.L": (-35, 0, 15), "hand_rot.R": (-35, 0, -15)}))

    # --- İniş / ollie hazırlığı: derin çömelme, kollar aşağı-dışa ---
    act("crouch")
    for f in (0, 12):
        key_pose(arm_obj, f, ride_base(
            crouch=0.2, spine_rot=(26, 0, 0), head_rot=(-18, 0, 0),
            **{"hand.L": (0.32, -0.18, 0.6 + D - 0.2), "hand.R": (-0.32, -0.16, 0.6 + D - 0.2),
               "hand_rot.L": (-30, 0, 30), "hand_rot.R": (-30, 0, -30)}))

    # --- Havada: dizler toplanmış, kollar açık ve yukarıda ---
    act("air")
    for f, k in ((0, 0.0), (12, 1.0), (24, 0.0)):
        pose = ride_base(crouch=0.12, spine_rot=(12, 0, 3 * k), board=(0, 0, TUCK))
        pose["foot.L"] = (LEFT_ON_BOARD[0], LEFT_ON_BOARD[1], LEFT_ON_BOARD[2] + TUCK)
        pose["foot.R"] = (RIGHT_ON_BOARD[0], RIGHT_ON_BOARD[1], RIGHT_ON_BOARD[2] + TUCK)
        pose["hand.L"] = (0.38, 0.0, 0.82 + D - 0.12 + 0.02 * k)
        pose["hand.R"] = (-0.37, 0.03, 0.8 + D - 0.12 - 0.01 * k)
        pose["hand_rot.L"] = (-15, 0, 35)
        pose["hand_rot.R"] = (-15, 0, -35)
        pose.update(RAISED_ELBOWS)
        key_pose(arm_obj, f, pose)

    # --- Ollie: dizler yay gibi çöker, kuyruk yere vurur, kaykay ayaklardan bir an
    #     ayrılıp havada geri gelir. Fiziksel sıçrama OLLIE_POP_FRAME'de başlar. ---
    act("ollie")
    LB, RB = LEFT_ON_BOARD, RIGHT_ON_BOARD

    def on_board(dz, front_dy=0.0, back_dy=0.0):
        return {"foot.L": (LB[0], LB[1] + back_dy, LB[2] + dz), "foot.R": (RB[0], RB[1] + front_dy, RB[2] + dz)}

    ollie_keys = [
        # kare, çömelme, kaykay (y, z), kaykay burun açısı, arka ayak dz, ön ayak (dy, dz), kollar z
        (0, 0.05, (0, 0.0), 0, 0.0, (0.0, 0.0), 0.0),
        (2, 0.15, (0, 0.0), 0, 0.0, (0.0, 0.0), -0.04),
        (3, 0.18, (0, 0.0), 0, 0.0, (0.0, 0.0), -0.05),     # en derin çökme -> pat!
        (4, 0.03, (0.02, 0.1), 24, 0.0, (-0.06, 0.16), 0.05),  # kuyruk vurdu, burun kalktı, ön ayak süzülüyor
        (5, 0.06, (0.0, 0.17), 12, 0.2, (-0.07, 0.27), 0.08),  # kaykay ayaklardan ayrık yükseliyor
        (6, 0.1, (0.0, 0.19), 3, 0.24, (-0.03, 0.25), 0.08),
        (7, 0.12, (0.0, 0.19), 0, 0.19, (0.0, 0.19), 0.07),     # ayaklar kaykayı yakaladı
        (12, 0.12, (0.0, TUCK), 0, TUCK, (0.0, TUCK), 0.05),    # havada toplu duruş (air ile aynı)
    ]
    for f, crouch, (by, bz), pitch, back_dz, (fdy, fdz), arm_dz in ollie_keys:
        pose = ride_base(crouch=crouch, spine_rot=(10 + crouch * 60, 0, 0), board=(0, by, bz),
                         board_rot=(pitch, 0, 0))
        pose["foot.L"] = (LB[0], LB[1] + (0.12 if pitch > 15 else 0.0), LB[2] + back_dz)
        pose["foot.R"] = (RB[0], RB[1] + fdy, RB[2] + fdz)
        pose["hand.L"] = (0.27 + arm_dz, -0.02, 0.7 + D - crouch + arm_dz * 2)
        pose["hand.R"] = (-0.27 - arm_dz, -0.02, 0.7 + D - crouch + arm_dz * 2)
        key_pose(arm_obj, f, pose)

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
        pose = ride_base(crouch=0.14, spine_rot=(16, 0, 0), board=(0, 0, board_z),
                         board_rot=(0, spin, 0))
        pose["foot.L"] = (LB[0] + 0.03 * lift, LB[1], LB[2] + feet_z)
        pose["foot.R"] = (RB[0] - 0.05 * lift, RB[1], RB[2] + feet_z)
        pose["hand.L"] = (0.36, 0.0, 0.84 + D - 0.14)
        pose["hand.R"] = (-0.35, 0.02, 0.82 + D - 0.14)
        pose["hand_rot.L"] = (-15, 0, 30)
        pose["hand_rot.R"] = (-15, 0, -30)
        pose.update(RAISED_ELBOWS)
        key_pose(arm_obj, f, pose)

    # --- Grind: çömelik, kollar iki yana açık, denge salınımı ---
    act("grind")
    for f, k in ((0, -1.0), (15, 1.0), (30, -1.0)):
        key_pose(arm_obj, f, ride_base(
            crouch=0.15, spine_rot=(16, 0, 4 * k),
            **RAISED_ELBOWS,
            **{"hand.L": (0.42, -0.02, 0.8 + D - 0.15 + 0.03 * k),
               "hand.R": (-0.42, -0.02, 0.8 + D - 0.15 - 0.03 * k),
               "hand_rot.L": (-10, 0, 40), "hand_rot.R": (-10, 0, -40)}))

    # --- Yürüme (kaykay sağ elde): sol kol sallanır, sağ kol az ---
    act("walk")
    n = WALK["frames"]
    for f in range(0, n + 1):
        u = f / n
        ph = math.tau * u
        pose = stand_pose(hips=(0.0, 0.0, -0.03 + 0.012 * math.cos(2 * ph)),
                          spine_rot=(4, 3 * math.cos(ph), 0))
        pose.update(gait_pose(u, WALK))
        # Kollar sarkık, bacağın tersine hafif sallanır (sol ayak öndeyken sol kol geride)
        pose["hand.L"] = (0.23, 0.1 * math.cos(ph), 0.635)
        pose["hand.R"] = (-0.27, 0.03 - 0.03 * math.cos(ph), 0.66)
        key_pose(arm_obj, f, pose)

    # --- Koşu: uçuş anlı adım, gövde öne eğik, kollar gevşek ve hafif bükük ---
    act("run")
    n = RUN["frames"]
    for f in range(0, n + 1):
        u = f / n
        ph = math.tau * u
        # İki ayak havadayken (uçuş) kalça yükselir
        bob = 0.025 * math.cos(2 * math.tau * (u - RUN["duty"] * 0.5))
        pose = stand_pose(hips=(0.0, -0.025, -0.05 + bob), spine_rot=(12, 4 * math.cos(ph), 0),
                          head_rot=(-6, -3 * math.cos(ph), 0))
        # Koşuda ayaklar neredeyse tek çizgiye basar, dizler düz öne kalkar
        pose.update(gait_pose(u, RUN, side_x=0.055))
        pose["knee.L"] = (0.07, -0.6, 0.5)
        pose["knee.R"] = (-0.07, -0.6, 0.5)
        pose["hand.L"] = (0.22, 0.14 * math.cos(ph), 0.7)
        pose["hand.R"] = (-0.28, 0.03 - 0.03 * math.cos(ph), 0.67)
        pose["hand_rot.L"] = (-15, 0, 8)
        key_pose(arm_obj, f, pose)

    # --- Ayakta bekleme ---
    act("stand_idle")
    for f, k in ((0, 0.0), (30, 1.0), (60, 0.0)):
        key_pose(arm_obj, f, stand_pose(hips=(0, 0, -0.012 - 0.006 * k), chest_rot=(-2 * k, 0, 0)))

    # --- Binme: koşarak kaykayı öne at, üstüne zıpla (karakter ileri MOUNT_SPEED ile gider) ---
    act("mount")
    release_f, land_f = 6, 14
    for f in range(0, MOUNT_FRAMES + 1):
        t = f / FPS
        if f <= land_f - 3:
            ph = math.tau * f / 10.0
            pose = stand_pose(hips=(0, -0.03, -0.04 + 0.03 * math.cos(2 * ph)), spine_rot=(16, 0, 0))
            pose.update(run_legs(ph, stride=0.3, lift=0.16))
            pose["hand.L"] = (0.22, 0.2 * math.cos(ph), 0.8)
        else:
            # Zıpla ve kaykaya in
            k = (f - (land_f - 3)) / 3.0
            jump = math.sin(min(k, 1.0) * math.pi) * 0.14
            pose = ride_base(crouch=0.1 - jump, spine_rot=(14, 0, 0))
            pose["hand.L"] = (0.36, 0.02, 0.85 + D - 0.1 + jump)
            pose["hand.R"] = (-0.36, 0.0, 0.85 + D - 0.1 + jump)
            if f < land_f:
                pose["foot.L"] = (0.035, 0.17, D + 0.075 + jump * 1.2)
                pose["foot.R"] = (-0.035, -0.11, D + 0.075 + jump * 1.2)
        # Kaykay: elde -> öne savrulur -> yere düşer, karakter yetişip üstüne çıkar
        if f < release_f - 2:
            pose["carry"] = 1.0
            pose["hand.R"] = (-0.27, 0.03 - 0.1 * f / release_f, 0.66)
        elif f < release_f:
            pose["carry"] = 1.0 - (f - (release_f - 2)) / 2.0
            pose["hand.R"] = (-0.28, -0.3, 0.6)
            pose["board"] = (0.0, -0.8, 0.12)
        else:
            pose["carry"] = 0.0
            if f <= land_f:
                y = -0.8 + MOUNT_SPEED * (t - release_f / FPS)
                y = min(y, 0.0)
            else:
                y = 0.0
            pose["board"] = (0.0, y, 0.05 if f == release_f else 0.0)
            if f <= land_f - 3:
                pose["hand.R"] = (-0.3, -0.1, 0.7)
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
            pose["hand.R"] = lerp((-0.13, 0.0, D + 0.07), (-0.27, 0.03, 0.66), k)
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
    a = math.radians(-50)
    d = Vector((math.sin(a), -math.cos(a), 0.25)).normalized()
    cam.location = Vector((0, -0.2, 0.75)) + d * 4.0
    cam.rotation_euler = (math.radians(90 - 14.5), 0, a)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for name in acts:
        act = bpy.data.actions[name]
        arm_obj.animation_data.action = act
        f0, f1 = act.frame_range
        for tag, f in (("a", f0), ("b", (f0 + f1) / 2), ("c", f1)):
            scene.frame_set(int(f))
            scene.render.filepath = os.path.join(PREVIEW_DIR, f"poz_{name}_{tag}.png")
            bpy.ops.render.render(write_still=True)


def main():
    arm_obj = build_armature()
    rest_heads(arm_obj)
    skin_character(arm_obj)
    skin_board(arm_obj)
    add_carry_bone(arm_obj)
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
    )
    print("GLB", OUT_GLB, "ANIM", acts)


main()
