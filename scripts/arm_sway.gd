class_name ArmSway
extends SkeletonModifier3D
## Kollara "ortam" hareketi ekler: animasyonun üstüne, üst kolları omuzdan döndürür.
## Kolların kendisi kas gücüyle değil; hız, rüzgâr, ivme, dönüş ve adımlarla sallanır.
## Açılar player_visual.gd'deki yay benzetiminden gelir.
##
## İskelet uzayı (glTF): yukarı +Y, karakterin önü +Z, karakterin solu +X.

## x: arkaya açı (radyan, + = el geriye), y: dışa açılma (+ = gövdeden uzağa)
var left := Vector2.ZERO
var right := Vector2.ZERO

var _upper := {}


func _ready() -> void:
	var skel := get_skeleton()
	if skel:
		_upper["L"] = skel.find_bone("upper_arm.L")
		_upper["R"] = skel.find_bone("upper_arm.R")


# Godot 4.4+ düzenleyici çağrısı. Not: etkisi geçicidir; kemik pozunu dışarıdan
# okurken iskeletin skeleton_updated sinyali beklenmeli (tests/kol_test.gd).
func _process_modification_with_delta(_delta: float) -> void:
	_apply_sway()


func _apply_sway() -> void:
	var skel := get_skeleton()
	if not skel or _upper.is_empty():
		return
	_rotate_arm(skel, _upper["L"], left, 1.0)
	_rotate_arm(skel, _upper["R"], right, -1.0)


func _rotate_arm(skel: Skeleton3D, idx: int, v: Vector2, side: float) -> void:
	if idx < 0 or v.length_squared() < 1e-8:
		return
	var parent := skel.get_bone_parent(idx)
	var g := skel.get_bone_global_pose(idx)
	# Arkaya: +X ekseni etrafında; dışa: sol kol +Z etrafında +, sağ kol -
	var q := Quaternion(Vector3(0, 0, 1), v.y * side) * Quaternion(Vector3(1, 0, 0), v.x)
	var new_basis := Basis(q) * g.basis
	var parent_basis := skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := (parent_basis.inverse() * new_basis).orthonormalized()
	skel.set_bone_pose_rotation(idx, local.get_rotation_quaternion())
