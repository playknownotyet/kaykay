class_name NpcCrowd
extends Node3D
## Hayvan NPC kalabalığı.
##
## Yol bulma: açılışta haritanın çarpışma nesnelerinden otomatik bir yürüme ağı
## çıkarılır (ızgara noktaları; engel içinde ya da eğimde olanlar atılır, aralarında
## engel olmayan komşular bağlanır). NPC'ler bu ağ üzerinde A* (AStar3D) ile rastgele
## hedeflere yürür. Harita değişse de ayrı bir iş gerekmez.
##
## Kalabalık: NPC'ler birbirinden ve yaya oyuncudan kaçınır, ara sıra durup bekler /
## etrafa bakar. Kaykayla çarpınca NPC affallar, oyuncu sendeler.

@export var count := 20:
	set(value):
		count = value
		if _ready_graph:
			respawn()
@export var area_min := Vector2(-62, -98)     # yürüme ağı alanı (x, z)
@export var area_max := Vector2(62, 18)
@export var cell := 4.0
## Bu mesafeden uzak NPC'ler gizlenir, animasyonları durur
@export var visible_distance := 42.0
## Kaykayla çarpışma: en düşük hız ve mesafe
@export var bump_speed := 1.5
@export var bump_radius := 0.55

var player: SkateController
var camera: Camera3D
var look: Node                        # görünüm ayarları yeni NPC'lere de uygulansın

var _astar := AStar3D.new()
var _points: Array[Vector3] = []
var _npcs: Array[Npc] = []
var _materials := {}                  # renk -> paylaşılan malzeme
var _rng := RandomNumberGenerator.new()
var _ready_graph := false


func _ready() -> void:
	_rng.randomize()
	# Statik çarpışma gövdelerinin fizik dünyasına girmesi için birkaç kare bekle
	for i in 3:
		await get_tree().physics_frame
	_build_graph()
	_ready_graph = true
	respawn()
	print("NPC: yürüme ağı %d nokta, %d bağlantı, %d NPC" % [_points.size(), _edge_count(), _npcs.size()])


## NPC'leri yeniden oluştur (sayı panelden değişince de çağrılır).
func respawn() -> void:
	for n in _npcs:
		n.queue_free()
	_npcs.clear()
	if _points.is_empty():
		return
	for i in count:
		_spawn()
	if look and look.has_method("add_root"):
		look.add_root(self)


# ---------- Yürüme ağı ----------

func _build_graph() -> void:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	var shape_q := PhysicsShapeQueryParameters3D.new()
	shape_q.shape = sphere
	var ids := {}
	var nx := int((area_max.x - area_min.x) / cell) + 1
	var nz := int((area_max.y - area_min.y) / cell) + 1
	for ix in nx:
		for iz in nz:
			var x := area_min.x + ix * cell
			var z := area_min.y + iz * cell
			# Zemin: düz ve alçak (meydan / kaldırım) olmalı; rampa, tepe, kutu üstü değil
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 6.0, z), Vector3(x, -1.0, z))
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or hit.position.y > 0.05 or hit.normal.y < 0.97:
				continue
			# Gövde yüksekliğinde engel olmamalı
			shape_q.transform = Transform3D(Basis(), Vector3(x, 0.9, z))
			if not space.intersect_shape(shape_q, 1).is_empty():
				continue
			var id := _points.size()
			var p := Vector3(x, hit.position.y, z)
			_points.append(p)
			_astar.add_point(id, p)
			ids[Vector2i(ix, iz)] = id
	# Komşuları bağla (8 yön), arada engel yoksa
	for key in ids:
		var a: int = ids[key]
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var k2: Vector2i = key + d
			if ids.has(k2) and _clear_between(space, _points[a], _points[ids[k2]]):
				_astar.connect_points(a, ids[k2])


func _clear_between(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var side := (b - a).cross(Vector3.UP).normalized() * 0.3
	for h in [0.35, 1.0]:
		for off in [Vector3.ZERO, side, -side]:
			var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, h, 0) + off, b + Vector3(0, h, 0) + off)
			if not space.intersect_ray(q).is_empty():
				return false
	return true


func _edge_count() -> int:
	var c := 0
	for id in _astar.get_point_ids():
		c += _astar.get_point_connections(id).size()
	return c / 2


func _random_point() -> int:
	return _rng.randi() % _points.size()


func _new_destination(n: Npc) -> void:
	var from := _astar.get_closest_point(n.global_position)
	for attempt in 6:
		var to := _random_point()
		if from == to or _points[to].distance_to(_points[from]) < 12.0:
			continue
		var route := _astar.get_point_path(from, to)
		if route.size() > 1:
			n.set_path(route)
			return
	n.idle_for(_rng.randf_range(1.0, 3.0))


func _spawn() -> void:
	var recipe := NpcCatalog.make_recipe(_rng, NpcCatalog.pick_species(_rng))
	var n := Npc.new()
	add_child(n)
	n.setup(recipe, _materials)
	var p := _points[_random_point()]
	for attempt in 8:
		if player == null or p.distance_to(player.global_position) > 8.0:
			break
		p = _points[_random_point()]
	n.global_position = p
	_npcs.append(n)
	if _rng.randf() < 0.3:
		n.idle_for(_rng.randf_range(0.5, 4.0))
	else:
		_new_destination(n)


# ---------- Her kare ----------

func _physics_process(delta: float) -> void:
	if not _ready_graph:
		return
	var ppos := player.global_position if player else Vector3(1e6, 0, 0)
	var cam_pos := camera.global_position if camera else ppos
	var riding := player != null and not player.on_foot and player.board_anim == SkateController.BoardAnim.NONE

	for i in _npcs.size():
		var n := _npcs[i]
		# Durum geçişleri
		if n.stumble_done():
			_new_destination(n)
		elif n.idle_done():
			_new_destination(n)
		elif n.reached_end():
			if _rng.randf() < 0.4:
				n.idle_for(_rng.randf_range(2.0, 6.0))
			else:
				_new_destination(n)

		# Kaçınma: diğer NPC'ler ve oyuncu
		var steer := n.desired_velocity()
		if steer != Vector3.ZERO:
			var sep := Vector3.ZERO
			for j in _npcs.size():
				if i == j:
					continue
				var d := n.global_position - _npcs[j].global_position
				d.y = 0.0
				var dist := d.length()
				if dist < 1.0 and dist > 0.001:
					sep += d / dist * (1.0 - dist) * 1.8
			var dp := n.global_position - ppos
			dp.y = 0.0
			var pd := dp.length()
			if pd < 1.3 and pd > 0.001:
				sep += dp / pd * (1.3 - pd) * 2.0
			steer = (steer + sep).limit_length(n.speed * 1.3)

		# Kaykayla çarpışma
		if riding and absf(player.speed) > bump_speed and not n.is_busy():
			var hd := n.global_position - ppos
			if absf(hd.y) < 1.2:
				hd.y = 0.0
				if hd.length() < bump_radius + 0.15:
					n.stumble(ppos)
					player.stumble(hd)

		n.tick(delta, steer)
		n.set_far(n.global_position.distance_to(cam_pos) > visible_distance)
