class_name Banklar
extends Node
## Sokaktaki banklar: her bankta iki oturma yeri. Oyuncu bankın önüne gelince "otur" butonu
## çıkar; NPC'ler ara sıra boş bir yere yürüyüp oturur. Yerler kimin oturduğunu (ya da yolda
## olduğunu) tutar, iki kişi aynı yere oturmaz.
##
## Banklar adanın eşya çarpışmalarından okunur (ada_builder "EsyaCarpisma_painted_wooden_bench_*",
## kutu çarpışma: bankın ortası, BENCH_H / 2 yukarıda). Bank modelinde oturak +Z'ye bakar.

const BENCH_H := 0.89
## Oturak yüksekliği (bank tabanından) ve oturağın ortası (bankın yerel z'si)
const SEAT_Y := 0.66
const SEAT_Z := -0.03
## İki oturma yeri (yerel x) ve önündeki ayakta durma noktası (yerel z)
const SEAT_X := [-0.27, 0.27]
const FRONT_Z := 0.78
## Oyuncu bu kadar yakındaysa "otur" butonu
const PLAYER_REACH := 1.4

var player: SkateController
var level: Node

## Her yer: {base: bankın tabanı (dünya), basis, x}
static var instance: Banklar
var seats: Array[Dictionary] = []
var _owner := {}                   # yer -> oturan / yoldaki (Node)
var _grid := {}                    # 16 m hücre -> yer listesi
var _owns_buttons := false
var _near := -1


func _ready() -> void:
	instance = self
	# Ada hazır sahneden gelir; çarpışma düğümleri zaten yerinde
	if level:
		_collect(level)
	if player:
		player.context_action.connect(_on_context)


func _collect(root: Node) -> void:
	for body in root.get_children():
		if not (body is StaticBody3D and String(body.name).begins_with("EsyaCarpisma_painted_wooden_bench")):
			continue
		for cs in body.get_children():
			if not cs is CollisionShape3D:
				continue
			var xf: Transform3D = (body as Node3D).global_transform * (cs as CollisionShape3D).transform
			var base := xf.origin - Vector3.UP * BENCH_H * 0.5
			for x in SEAT_X:
				var id := seats.size()
				seats.append({"base": base, "basis": xf.basis.orthonormalized(), "x": x})
				var key := _cell(base)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(id)


## Dışarıdan bank ekle (şehirdeki parklar): tf adadaki bankların dönüşümüyle aynı (köken tabanda,
## -Z sırt yönü). tag ile sonradan toplu silinir. Yer kimliklerini döner.
func add_bench(tf: Transform3D, tag: String) -> Array[int]:
	var ids: Array[int] = []
	for x in SEAT_X:
		var id := seats.size()
		seats.append({"base": tf.origin, "basis": tf.basis.orthonormalized(), "x": x, "tag": tag})
		var key := _cell(tf.origin)
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(id)
		ids.append(id)
	return ids


## tag'li bankları kaldır (yerler kimlik kaymasın diye boş bırakılır)
func remove_tagged(tag: String) -> void:
	for id in seats.size():
		if seats[id].get("tag", "") == tag:
			seats[id]["base"] = Vector3(0, -1000, 0)
			for key in _grid:
				(_grid[key] as Array).erase(id)
			_owner.erase(id)


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))


## Oturanın baktığı yön (yatay)
func facing(id: int) -> Vector3:
	var z: Vector3 = seats[id].basis.z
	return Vector3(z.x, 0.0, z.z).normalized()


## Oturağın üstündeki kalça noktası (dünya)
func seat_point(id: int) -> Vector3:
	var s: Dictionary = seats[id]
	return s.base + s.basis * Vector3(s.x, SEAT_Y, SEAT_Z)


## Yerin önünde ayakta durulacak nokta (dünya, bank tabanı yüksekliğinde)
func front_point(id: int) -> Vector3:
	var s: Dictionary = seats[id]
	return s.base + s.basis * Vector3(s.x, 0.0, FRONT_Z)


func is_free(id: int) -> bool:
	return not _owner.has(id) or not is_instance_valid(_owner[id])


func reserve(id: int, who: Node) -> void:
	_owner[id] = who


func release(id: int, who: Node) -> void:
	if _owner.get(id) == who:
		_owner.erase(id)


## pos çevresinde (radius m) boş bir yer; yoksa -1
func free_seat_near(pos: Vector3, radius: float, rng: RandomNumberGenerator) -> int:
	var c := _cell(pos)
	var r := int(ceilf(radius / 16.0))
	var found: Array[int] = []
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for id in _grid.get(c + Vector2i(dx, dz), []):
				if is_free(id) and front_point(id).distance_to(pos) <= radius:
					found.append(id)
	if found.is_empty():
		return -1
	return found[rng.randi() % found.size()]


# ---------- Oyuncu ----------

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	_near = -1
	var can := player.on_foot and not player.sitting and player.is_on_floor() and player.action_time <= 0.0 \
		and player.fall_time <= 0.0 and not player.bag_open and not player.input_locked and not player.held_in_air
	if can:
		var p := player.global_position
		var best := PLAYER_REACH
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for id in _grid.get(_cell(p) + Vector2i(dx, dz), []):
					var f := front_point(id)
					var d := Vector2(f.x - p.x, f.z - p.z).length()
					if d < best and absf(f.y - p.y) < 0.6 and is_free(id):
						best = d
						_near = id
	if _near >= 0:
		player.context_buttons = [{"id": "otur", "icon": "otur"}]
		_owns_buttons = true
	elif player.sitting:
		player.context_buttons = [{"id": "kalk", "icon": "kalk"}]
		_owns_buttons = true
	elif _owns_buttons:
		player.context_buttons = []
		_owns_buttons = false


var _player_seat := -1


func _on_context(id: String) -> void:
	match id:
		"otur":
			if _near < 0 or not is_free(_near):
				return
			# Karakterin kökü: oturma pozunda kalça kökün 0,675 m üstünde, oturağın ~6 cm üstüne gelsin
			var seat := seat_point(_near) - Vector3.UP * 0.615
			if player.sit(front_point(_near), facing(_near), seat):
				_player_seat = _near
				reserve(_near, player)
				if not player.stood_up.is_connected(_on_player_stood):
					player.stood_up.connect(_on_player_stood)
		"kalk":
			player.stand_up()


func _on_player_stood() -> void:
	if _player_seat >= 0:
		release(_player_seat, player)
		_player_seat = -1
