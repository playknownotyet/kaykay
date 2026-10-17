class_name ElTut
extends SkeletonModifier3D
## El ele tutuşma: bir kolu (üst kol + ön kol, iki kemikli IK) dünyadaki bir noktaya uzatır.
## Ebeveyn ile çocuk aynı noktaya uzanır (NpcCrowd her kare hedefi verir). Dirsek animasyondaki
## bükülme düzleminde kalır; weight ile animasyona karışır.

var side := "R"
var target := Vector3.ZERO
var weight := 0.0

var _ua := -1
var _fa := -1
var _ha := -1


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	_ua = skel.find_bone("upper_arm." + side)
	_fa = skel.find_bone("forearm." + side)
	_ha = skel.find_bone("hand." + side)


## Omzun dünyadaki yeri (hedef hesaplamak için)
func shoulder_world() -> Vector3:
	var skel := get_skeleton()
	if skel == null or _ua < 0:
		return Vector3.ZERO
	return skel.global_transform * skel.get_bone_global_pose(_ua).origin


func _process_modification_with_delta(_delta: float) -> void:
	if weight <= 0.001 or _ua < 0 or _fa < 0 or _ha < 0:
		return
	var skel := get_skeleton()
	var ua := skel.get_bone_global_pose(_ua)
	var fa := skel.get_bone_global_pose(_fa)
	var ha := skel.get_bone_global_pose(_ha)
	var h := ua.origin
	var k := fa.origin
	var a := ha.origin
	var t := skel.global_transform.affine_inverse() * target
	var la := (k - h).length()
	var lb := (a - k).length()
	var ht := t - h
	var dist := clampf(ht.length(), absf(la - lb) + 0.001, la + lb - 0.002)
	var dir := ht.normalized()
	var pole := (k - h) - dir * (k - h).dot(dir)
	if pole.length_squared() < 1e-8:
		pole = Vector3(0, -1, 0).cross(dir).cross(dir)
		if pole.length_squared() < 1e-8:
			return
	pole = pole.normalized()
	var cos_a := clampf((la * la + dist * dist - lb * lb) / (2.0 * la * dist), -1.0, 1.0)
	var k2 := h + dir * la * cos_a + pole * la * sqrt(1.0 - cos_a * cos_a)
	var t2 := h + dir * dist
	var r1 := Quaternion((k - h).normalized(), (k2 - h).normalized())
	var a1 := h + r1 * (a - h)
	var r2 := Quaternion((a1 - k2).normalized(), (t2 - k2).normalized())
	var ua_b := Basis(r1) * ua.basis
	var fa_b := Basis(r2 * r1) * fa.basis
	var par := skel.get_bone_parent(_ua)
	var par_b := skel.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
	var cur_ua := skel.get_bone_pose_rotation(_ua)
	var cur_fa := skel.get_bone_pose_rotation(_fa)
	var new_ua := (par_b.inverse() * ua_b).orthonormalized().get_rotation_quaternion()
	var new_fa := (ua_b.inverse() * fa_b).orthonormalized().get_rotation_quaternion()
	skel.set_bone_pose_rotation(_ua, cur_ua.slerp(new_ua, weight))
	skel.set_bone_pose_rotation(_fa, cur_fa.slerp(new_fa, weight))
