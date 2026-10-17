class_name FootGuard
extends SkeletonModifier3D
## Ayak tabanı kaykayın tahtasına gömülmesin. İki poz arasındaki geçişte eklem açıları
## karıştığı için ayağın yolu tahtanın içinden geçebilir (yan duruş <-> öne dönük, itme,
## fren...). Her karede taban noktaları tahtanın üst yüzüyle karşılaştırılır; gömülen
## ayak kadar yukarı kaldırılır ve bacak (uyluk + baldır) iki kemikli IK ile yeniden
## bükülür (diz aynı yöne bakar, ayağın açısı değişmez).
##
## Ölçüler karakter_model.py'den: tahtanın üstü 0,09 m, yarı genişlik 0,105, yarı boy 0,40,
## kuyruk / burun kalkışı 0,27 m'den sonra 0,45 eğimle. İskelet uzayı (glTF): yukarı +Y.

const DECK_TOP := 0.09
const HALF_W := 0.115            # kenarda ayakkabı payı
const HALF_L := 0.41
const KICK_START := 0.27
const KICK_SLOPE := 0.45
const MARGIN := 0.004

## Test için: false iken yalnız ölçer, düzeltmez
var fix := true
## Son karede düzeltmeden önce ölçülen en büyük gömülme (m)
var last_pen := 0.0
var _bones := {}
## Ayakkabı tabanı noktaları (dinlenme duruşunda, iskelet uzayında; x sonra eklenir)
var _sole := [Vector3(0, 0, -0.07), Vector3(0, 0, 0.04), Vector3(0, 0, 0.15),
	Vector3(0.035, 0, 0.04), Vector3(-0.035, 0, 0.04)]


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for n in ["board", "hips", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"]:
		_bones[n] = skel.find_bone(n)


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty() or _bones["board"] < 0:
		return
	var board_idx: int = _bones["board"]
	var board_pose := skel.get_bone_global_pose(board_idx)
	var board_rest := skel.get_bone_global_rest(board_idx)
	# Tahtanın şimdiki yerinden dinlenme yerine götüren dönüşüm
	var to_rest := board_rest * board_pose.affine_inverse()
	var up := (board_pose.basis * board_rest.basis.inverse() * Vector3.UP).normalized()
	last_pen = 0.0
	if up.y < 0.6:
		return                  # elde taşınıyor ya da kickflip'te dönüyor
	for sfx in ["L", "R"]:
		_guard_leg(skel, sfx, to_rest, up)


func _guard_leg(skel: Skeleton3D, sfx: String, to_rest: Transform3D, up: Vector3) -> void:
	var fi: int = _bones["foot." + sfx]
	var ti: int = _bones["thigh." + sfx]
	var si: int = _bones["shin." + sfx]
	if fi < 0 or ti < 0 or si < 0:
		return
	var foot := skel.get_bone_global_pose(fi)
	var foot_rest := skel.get_bone_global_rest(fi)
	var from_rest := foot * foot_rest.affine_inverse()
	# Yalnız ayağın ortası tahtanın üstündeyken: yanında yere basan / sürtülen ayak (itme,
	# fren) tahtanın kenarına değse de kaldırılmaz
	var mid := to_rest * (from_rest * Vector3(foot_rest.origin.x, 0.0, foot_rest.origin.z + 0.04))
	if absf(mid.x) > 0.095 or absf(mid.z) > 0.38:
		return
	var pen := 0.0
	for o in _sole:
		var p_rest: Vector3 = Vector3(foot_rest.origin.x, 0.0, foot_rest.origin.z) + o
		var q := to_rest * (from_rest * p_rest)
		if absf(q.x) > HALF_W or absf(q.z) > HALF_L:
			continue
		var top := DECK_TOP + maxf(absf(q.z) - KICK_START, 0.0) * KICK_SLOPE + MARGIN
		var d := top - q.y
		if d > 0.0 and d < 0.22:
			pen = maxf(pen, d)
	last_pen = maxf(last_pen, pen)
	if pen <= 0.0 or not fix:
		return

	var thigh := skel.get_bone_global_pose(ti)
	var shin := skel.get_bone_global_pose(si)
	var h := thigh.origin
	var k := shin.origin
	var a := foot.origin
	var t := a + up * pen
	var la := (k - h).length()
	var lb := (a - k).length()
	var ht := t - h
	var dist := clampf(ht.length(), absf(la - lb) + 0.001, la + lb - 0.0005)
	var dir := ht.normalized()
	var pole := (k - h) - dir * (k - h).dot(dir)
	if pole.length_squared() < 1e-8:
		return
	pole = pole.normalized()
	var cos_a := clampf((la * la + dist * dist - lb * lb) / (2.0 * la * dist), -1.0, 1.0)
	var k2 := h + dir * la * cos_a + pole * la * sqrt(1.0 - cos_a * cos_a)
	var r1 := Quaternion((k - h).normalized(), (k2 - h).normalized())
	var a1 := h + r1 * (a - h)
	var r2 := Quaternion((a1 - k2).normalized(), (t - k2).normalized())
	var thigh_b := Basis(r1) * thigh.basis
	var shin_b := Basis(r2 * r1) * shin.basis
	var hips_i: int = skel.get_bone_parent(ti)
	var parent_b := skel.get_bone_global_pose(hips_i).basis if hips_i >= 0 else Basis.IDENTITY
	skel.set_bone_pose_rotation(ti, (parent_b.inverse() * thigh_b).orthonormalized().get_rotation_quaternion())
	skel.set_bone_pose_rotation(si, (thigh_b.inverse() * shin_b).orthonormalized().get_rotation_quaternion())
	skel.set_bone_pose_rotation(fi, (shin_b.inverse() * foot.basis).orthonormalized().get_rotation_quaternion())
