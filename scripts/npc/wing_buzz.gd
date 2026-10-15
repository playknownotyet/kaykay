class_name WingBuzz
extends SkeletonModifier3D
## Sinek kanatları: ara ara (ve çarpılınca) çok hızlı vızıldar. Animasyonun üstüne
## eklenir; 30 kare/sn'lik animasyonla yakalanamayacak hızdaki çırpınma için.

## Kanat kök kemikleri (her biri kendi ekseninde çırpar)
var bones: PackedStringArray = []
## Vızıldamalar arası bekleme (sn) ve bir vızıldamanın süresi (sn)
var pause_range := Vector2(2.0, 6.0)
var burst_range := Vector2(0.25, 0.7)
var frequency := 70.0      # rad/sn
var amplitude := 0.55      # rad

var _ids: PackedInt32Array = []
var _t := 0.0
var _wait := 0.0
var _left := 0.0


func _ready() -> void:
	_wait = randf_range(pause_range.x, pause_range.y)


## Hemen vızılda (ör. çarpılınca).
func buzz(seconds := 0.8) -> void:
	_left = maxf(_left, seconds)


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if _ids.is_empty():
		for b in bones:
			var id := skel.find_bone(b)
			if id >= 0:
				_ids.append(id)
	_t += delta
	if _left <= 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_left = randf_range(burst_range.x, burst_range.y)
			_wait = randf_range(pause_range.x, pause_range.y)
		return
	_left -= delta
	var a := sin(_t * frequency) * amplitude
	for i in _ids.size():
		var id := _ids[i]
		var sgn := 1.0 if i % 2 == 0 else -1.0
		var q := skel.get_bone_pose_rotation(id) * Quaternion(Vector3.RIGHT, a * sgn)
		skel.set_bone_pose_rotation(id, q)
