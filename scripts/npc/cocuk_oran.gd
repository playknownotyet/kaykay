class_name CocukOran
extends SkeletonModifier3D
## Çocuk NPC: yetişkin modelinin aynısı küçültülür (Npc.CHILD_SCALE), burada baş ve eller
## büyütülür: çocuk oranı (büyük baş, kısa gövde). Animasyonlar (yürüme, oturma) aynen çalışır.

const HEAD := 1.42
const HAND := 1.15

var _head := -1
var _hands: Array[int] = []


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	_head = skel.find_bone("head")
	for n in ["hand.L", "hand.R"]:
		var i := skel.find_bone(n)
		if i >= 0:
			_hands.append(i)


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _head >= 0:
		skel.set_bone_pose_scale(_head, Vector3.ONE * HEAD)
	for i in _hands:
		skel.set_bone_pose_scale(i, Vector3.ONE * HAND)
