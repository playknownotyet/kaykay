class_name NpcCrowd
extends Node3D
## Hayvan NPC kalabalığı.
##
## Yol bulma: açılışta haritanın çarpışma nesnelerinden otomatik bir yürüme ağı
## çıkarılır (ızgara noktaları; engel içinde ya da eğimde olanlar atılır, aralarında
## engel olmayan komşular bağlanır). NPC'ler bu ağ üzerinde A* (AStar3D) ile rastgele
## hedeflere yürür. Harita değişse de ayrı bir iş gerekmez.
##
## Ada: seviye bir yaya ağı verirse (walk_source meta "walk_nodes" / "walk_edges", kaldırımlar
## ve kavşak geçitleri) o kullanılır. NPC'ler oyuncunun çevresinde doğar; çok uzakta kalanlar
## yeniden yakına alınır: koca adada kalabalık hep oyuncunun etrafında yaşar.
##
## Kalabalık: NPC'ler birbirinden ve yaya oyuncudan kaçınır, ara sıra durup bekler /
## etrafa bakar. Kaykayla çarpınca NPC affallar, oyuncu sendeler.

@export var count := 40:
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

## Ada: oyuncunun çevresinde doğma halkası ve geri çağırma mesafesi (m)
@export var spawn_min := 45.0
@export var spawn_max := 130.0
@export var recycle_distance := 160.0
## Yükseklikle seyrelme: bu yüksekliğe (m) kadar tam kalabalık, density_top'ta en seyrek
@export var density_full_h := 10.0
@export var density_top_h := 80.0
@export var density_min := 0.06
## Engelden kaçınma: önüne bakış mesafesi (m) ve bakış yüksekliği
@export var probe_len := 1.4
@export var probe_h := 0.5

var player: SkateController
var camera: Camera3D
var walk_source: Node                 # yaya ağını veren seviye (ada)
var look: Node                        # görünüm ayarları yeni NPC'lere de uygulansın
var benches: Banklar                  # NPC'ler ara sıra banka oturur
## Yeni hedef seçerken banka gitme olasılığı ve oturma süresi (sn)
@export var bench_chance := 0.2
@export var sit_time := Vector2(10.0, 30.0)

@export_group("Çocuklar")
## Sokakta doğan NPC'nin elinden tuttuğu çocukla doğma olasılığı: uzakta family_far, parkın
## yanında family_near (park_reach metrede uzaktakine iner)
@export var family_far := 0.08
@export var family_near := 0.45
@export var park_reach := 170.0
## Park: oyuncu bu kadar yakınken parkta oynayan çocuklar ve banklarda oturanlar kurulur
@export var park_on := 90.0
@export var park_off := 130.0
@export var park_kids := 6
@export var park_adults := 3
var _parks := {}                      # park kimliği -> {"kids": [Npc], "adults": [Npc], "t": zaman}
var _park_t := 0.0

var _astar := AStar3D.new()
var _points: Array[Vector3] = []
var _npcs: Array[Npc] = []
var _materials := {}                  # renk -> paylaşılan malzeme
var _rng := RandomNumberGenerator.new()
var _ready_graph := false
var _cross := {}                      # yaya geçidi kenarı (küçük id, büyük id) -> (kavşak, kol)


func _ready() -> void:
	_rng.randomize()
	# Statik çarpışma gövdelerinin fizik dünyasına girmesi için birkaç kare bekle
	for i in 3:
		await get_tree().physics_frame
	if walk_source and walk_source.has_meta("walk_nodes"):
		_build_graph_from(walk_source.get_meta("walk_nodes"), walk_source.get_meta("walk_edges"))
		if walk_source.has_meta("walk_cross") and TrafikSinyal.ensure():
			var c: PackedInt32Array = walk_source.get_meta("walk_cross")
			for k in range(0, c.size() - 3, 4):
				_cross[_edge_key(c[k], c[k + 1])] = Vector2i(c[k + 2], c[k + 3])
	else:
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
		if _npcs.size() >= count:
			break
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


func _build_graph_from(nodes: PackedVector3Array, edges: PackedInt32Array) -> void:
	for i in nodes.size():
		_points.append(nodes[i])
		_astar.add_point(i, nodes[i])
	for k in range(0, edges.size() - 1, 2):
		if edges[k] != edges[k + 1]:
			_astar.connect_points(edges[k], edges[k + 1])


## Oyuncunun çevresinde (rmin..rmax) rastgele bir ağ noktası; bulunamazsa herhangi biri.
func _point_near(center: Vector3, rmin: float, rmax: float) -> int:
	for attempt in 40:
		var id := _random_point()
		var d := Vector2(_points[id].x - center.x, _points[id].z - center.z).length()
		if d >= rmin and d <= rmax:
			return id
	return _astar.get_closest_point(center)


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


## Bu yükseklikte kalabalığın yoğunluğu (0..1): dağa çıktıkça azalır
func _density(h: float) -> float:
	return clampf(1.0 - (h - density_full_h) / (density_top_h - density_full_h) * (1.0 - density_min), density_min, 1.0)


func _random_point() -> int:
	return _rng.randi() % _points.size()


func _new_destination(n: Npc) -> void:
	_leave_bench(n)
	var from := _astar.get_closest_point(n.global_position)
	if benches and n.kid == null and n.can_sit(Banklar.SEAT_Y) and _rng.randf() < bench_chance and _go_to_bench(n, from):
		return
	for attempt in 10:
		# Büyük adada hedef yakın olsun (30-140 m): yürüyüş oyuncunun çevresinde kalır
		var to := _point_near(n.global_position, 30.0, 140.0) if _points.size() > 600 else _random_point()
		if from == to or _points[to].distance_to(_points[from]) < 12.0:
			continue
		# Dağın yukarısı seyrek: yüksekteki hedefler daha az seçilir
		if _rng.randf() > _density(_points[to].y):
			continue
		var ids := _astar.get_id_path(from, to)
		if ids.size() > 1:
			var route := PackedVector3Array()
			for id in ids:
				route.append(_points[id])
			n.set_path(route, ids)
			return
	n.idle_for(_rng.randf_range(1.0, 3.0))


## Yakındaki boş bir bankın önüne yol: yaya ağıyla en yakın düğüme, oradan bankın önüne.
func _go_to_bench(n: Npc, from: int) -> bool:
	var id := benches.free_seat_near(n.global_position, 45.0, _rng)
	if id < 0:
		return false
	var front := benches.front_point(id)
	var to := _astar.get_closest_point(front)
	var ids := _astar.get_id_path(from, to)
	if ids.is_empty():
		return false
	var route := PackedVector3Array()
	for k in ids:
		route.append(_points[k])
	route.append(front)
	benches.reserve(id, n)
	n.bench_seat = id
	n.set_path(route, ids)
	return true


## Banktan kalk (ya da gitmekten vazgeç): yeri boşalt; oturuyorsa bankın önüne çık
func _leave_bench(n: Npc) -> void:
	if n.bench_seat < 0:
		return
	if benches:
		if n.is_sitting():
			n.global_position = benches.front_point(n.bench_seat)
		benches.release(n.bench_seat, n)
	n.bench_seat = -1


## Doğma noktası: oyuncudan en az spawn_min uzakta ve yakınsa (90 m) kameranın görmediği bir yer.
## Uygun yer yoksa Vector3.INF (NPC görünmez bekler, sonra yeniden dener). Eskiden bulunamayınca
## oyuncuya en yakın noktaya düşüyordu: sürerken önüne birden NPC çıkıyordu.
func _spawn_point(allow_view := false) -> Vector3:
	if player == null:
		return _points[_random_point()]
	var pp := player.global_position
	var big := _points.size() > 600
	for attempt in 80:
		var p := _points[_random_point()]
		var d := Vector2(p.x - pp.x, p.z - pp.z).length()
		if d < spawn_min or (big and d > spawn_max):
			continue
		if _rng.randf() > _density(p.y):
			continue
		if not allow_view and camera and d < 90.0 and camera.is_position_in_frustum(p + Vector3.UP):
			continue
		return p
	return Vector3.INF


func _spawn() -> void:
	var recipe := NpcCatalog.make_recipe(_rng, NpcCatalog.pick_species(_rng))
	var n := Npc.new()
	if player:
		n.ground_exclude = [player.get_rid()]
	add_child(n)
	n.setup(recipe, _materials)
	var sp := _spawn_point()
	if sp == Vector3.INF:
		sp = _spawn_point(true)
	if sp == Vector3.INF:
		sp = player.global_position + Vector3(0, -300, 0) if player else _points[_random_point()]
	n.global_position = sp
	_npcs.append(n)
	# Çocuklu aile (parka yakınsa daha olası): aynı türden çocuk ebeveyninin sağında, el ele
	if _npcs.size() < count and _rng.randf() < family_chance(sp):
		_add_kid(n)
	if _rng.randf() < 0.3:
		n.idle_for(_rng.randf_range(0.5, 4.0))
	else:
		_new_destination(n)


## Bu noktada çocuklu aile olasılığı: parka yaklaştıkça artar
func family_chance(p: Vector3) -> float:
	var d := park_distance(p)
	var k := 1.0 - clampf((d - 25.0) / park_reach, 0.0, 1.0)
	return lerpf(family_far, family_near, k)


## En yakın parkın uzaklığı (çocuk parkları ve büyük yeşil alanlar)
func park_distance(p: Vector3) -> float:
	var best := INF
	if Sehir.instance:
		for pk in Sehir.instance.parks:
			var c: Vector3 = (pk.xf as Transform3D).origin
			best = minf(best, Vector2(p.x - c.x, p.z - c.z).length())
	return best


func _add_kid(par: Npc) -> Npc:
	var recipe := NpcCatalog.make_recipe(_rng, String(par.recipe.species))
	var k := Npc.new()
	if player:
		k.ground_exclude = [player.get_rid()]
	add_child(k)
	k.setup(recipe, _materials, true)
	var yaw := par.rotation.y
	k.global_position = par.global_position + Vector3(cos(yaw), 0, -sin(yaw)) * 0.5
	k.parent = par
	par.kid = k
	par.speed = minf(par.speed, 1.0)
	par.add_hand("R")
	k.add_hand("L")
	_npcs.append(k)
	return k


## Elinden tutulan çocuk: ebeveyninin sağında yürür; iki el ortada buluşur
func _follow_parent(k: Npc, delta: float) -> void:
	var par := k.parent
	var yaw := par.rotation.y
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var target := par.global_position + right * 0.5
	var to := target - k.global_position
	to.y = 0.0
	var steer := Vector3.ZERO
	if to.length() > 0.08:
		steer = to.normalized() * minf(to.length() * 4.0, maxf(par.speed, 0.6) * 1.8)
	if k.state == Npc.State.STUMBLE:
		steer = Vector3.ZERO
	k.move(delta, steer)
	if to.length() < 0.3 and par.velocity.length() < 0.2:
		k.rotation.y = lerp_angle(k.rotation.y, yaw, 1.0 - exp(-6.0 * delta))
	k.set_far(par.far)
	# El ele: yakınken ve ikisi de ayaktayken
	var ok := not k.far and to.length() < 0.6 and not par.is_busy() and not k.is_busy()
	var w := 1.0 if ok else 0.0
	if par.hand and k.hand:
		par.hand.weight = move_toward(par.hand.weight, w, delta * 4.0)
		k.hand.weight = par.hand.weight
		if par.hand.weight > 0.0:
			var a := par.hand.shoulder_world()
			var b := k.hand.shoulder_world()
			var m := (a + b) * 0.5 + fwd * 0.1
			m.y = b.y + 0.06
			par.hand.target = m
			k.hand.target = m


# ---------- Her kare ----------

func _physics_process(delta: float) -> void:
	if not _ready_graph:
		return
	var ppos := player.global_position if player else Vector3(1e6, 0, 0)
	var cam_pos := camera.global_position if camera else ppos
	var riding := player != null and not player.on_foot and player.board_anim == SkateController.BoardAnim.NONE

	_park_step(delta, ppos, cam_pos, riding)
	for i in _npcs.size():
		var n := _npcs[i]
		if n.parent:
			if is_instance_valid(n.parent):
				_follow_parent(n, delta)
				continue
			n.parent = null
		# Durum geçişleri
		if n.stumble_done():
			_new_destination(n)
		elif n.idle_done():
			_new_destination(n)
		elif n.sit_done():
			_leave_bench(n)
			n.idle_for(_rng.randf_range(0.5, 1.5))
		elif n.reached_end() and n.bench_seat >= 0 and benches:
			n.sit_at(benches.seat_point(n.bench_seat), benches.facing(n.bench_seat), _rng.randf_range(sit_time.x, sit_time.y))
		elif n.reached_end():
			if _rng.randf() < 0.4:
				n.idle_for(_rng.randf_range(2.0, 6.0))
			else:
				_new_destination(n)

		# Kaçınma: diğer NPC'ler ve oyuncu
		var steer := n.desired_velocity()
		# Yaya geçidi: yaya ışığı yeşilken ve geçmeye yetecek süre varken geçilir; yoksa kaldırımda bekle
		if not _cross.is_empty() and steer != Vector3.ZERO and n.path_index >= 1 and n.path_index < n.path_ids.size() 				and n.cross_index != n.path_index:
			var key := _edge_key(n.path_ids[n.path_index - 1], n.path_ids[n.path_index])
			if _cross.has(key):
				var start := n.path[n.path_index - 1]
				var need := n.path[n.path_index].distance_to(start) / maxf(n.speed, 0.5) + 1.0
				var jc: Vector2i = _cross[key]
				if TrafikSinyal.ped_time_left(jc.x, TrafikSinyal.now(), jc.y) >= need:
					n.cross_index = n.path_index
				else:
					var back := start - n.global_position
					back.y = 0.0
					steer = back.limit_length(n.speed) if back.length() > 0.4 else Vector3.ZERO
		# Bankın önüne son yaklaşmada bankı engel sayma
		var to_bench := n.bench_seat >= 0 and n.path_index >= n.path.size() - 1
		if steer != Vector3.ZERO and not n.far and not to_bench:
			steer = _avoid_obstacles(n, steer, delta)
		if steer != Vector3.ZERO:
			var sep := Vector3.ZERO
			for j in _npcs.size():
				if i == j or _npcs[j] == n.kid:
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
		# Çok uzakta kalan NPC oyuncunun çevresine geri gelir (görünmezken)
		if player and _points.size() > 600 and n.far and n.global_position.distance_to(ppos) > recycle_distance:
			_leave_bench(n)
			var sp := _spawn_point()
			if sp != Vector3.INF:
				n.global_position = sp
				if n.kid and is_instance_valid(n.kid):
					n.kid.global_position = sp + Vector3(0.5, 0, 0)
			_new_destination(n)


## Önündeki engele (bank, lamba, çöp kovası, araba...) bakar: araba ise bekler, değilse
## engelin açık tarafından dolanır. Seçilen yan bir süre korunur (sağ-sol arasında titremesin).
func _avoid_obstacles(n: Npc, steer: Vector3, delta: float) -> Vector3:
	n.avoid_t = maxf(n.avoid_t - delta, 0.0)
	var dir := steer.normalized()
	var hit := _probe(n, dir, probe_len)
	if hit.is_empty():
		if n.avoid_t > 0.0:
			# Engelin yanından geçerken yolu biraz daha dışarıdan sürdür
			var side_dir := dir.rotated(Vector3.UP, n.avoid_side * deg_to_rad(35.0))
			if _probe(n, side_dir, probe_len * 0.7).is_empty():
				return side_dir * steer.length()
		return steer
	if hit.collider is Araba:
		return Vector3.ZERO
	if n.avoid_t <= 0.0:
		# Engelin daha açık tarafı
		var l := _probe(n, dir.rotated(Vector3.UP, deg_to_rad(50.0)), probe_len)
		var r := _probe(n, dir.rotated(Vector3.UP, deg_to_rad(-50.0)), probe_len)
		n.avoid_side = 1.0 if (r.size() > 0 and l.is_empty()) or (l.is_empty() == r.is_empty() and _rng.randf() < 0.5) else -1.0
	n.avoid_t = 0.9
	for a in [55.0, 85.0, 120.0]:
		var d2 := dir.rotated(Vector3.UP, n.avoid_side * deg_to_rad(a))
		if _probe(n, d2, probe_len * 0.8).is_empty():
			return d2 * steer.length() * 0.8
	n.avoid_side = -n.avoid_side
	return Vector3.ZERO


## Diz hizasından yatay ışın: yer / kaldırım değil, dik bir engel bulursa sonucu döner
func _probe(n: Npc, dir: Vector3, length: float) -> Dictionary:
	var from := n.global_position + Vector3.UP * probe_h
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length)
	if player:
		q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y > 0.6:
		return {}
	return hit


func npc_list() -> Array[Npc]:
	return _npcs


static func _edge_key(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


# ---------- Çocuk parkı: oynayan çocuklar, banklarda oturan yetişkinler ----------

## Oyuncu parka yaklaşınca kurulur, uzaklaşınca kaldırılır (görünür mesafenin dışında)
func _park_step(delta: float, ppos: Vector3, cam_pos: Vector3, riding: bool) -> void:
	if Sehir.instance == null:
		return
	_park_t -= delta
	var parks: Array = Sehir.instance.parks
	if _park_t <= 0.0:
		_park_t = 0.5
		var alive := {}
		for pk in parks:
			var id := int(pk.id)
			alive[id] = true
			var c: Vector3 = (pk.xf as Transform3D).origin
			var d := Vector2(ppos.x - c.x, ppos.z - c.z).length()
			if d < park_on and not _parks.has(id):
				_parks[id] = _open_park(pk)
			elif d > park_off and _parks.has(id):
				_close_park(id)
		for id in _parks.keys():
			if not alive.has(id):
				_close_park(id)
	for pk in parks:
		var id := int(pk.id)
		if not _parks.has(id):
			continue
		var st: Dictionary = _parks[id]
		st.t += delta
		var t: float = st.t
		# Salıncaklar ve tahterevalli: üstünde çocuk varsa hareket eder
		var swings: Array = pk.swings
		for si in swings.size():
			var sw: Dictionary = swings[si]
			var piv: Node3D = sw.pivot
			var on := false
			for k in st.kids:
				if k.role == "salincak" and int(k.role_data.get("i", -1)) == si:
					on = true
			piv.rotation.x = lerpf(piv.rotation.x, sin(t * 2.2 + si * 1.3) * 0.55 if on else 0.0, 1.0 - exp(-3.0 * delta))
		var ss: Dictionary = pk.seesaw
		var sp_piv: Node3D = ss.get("pivot")
		var ss_on := 0
		for k in st.kids:
			if k.role == "tahterevalli":
				ss_on += 1
		if sp_piv:
			sp_piv.rotation.z = lerpf(sp_piv.rotation.z, sin(t * 1.7) * 0.22 if ss_on >= 2 else 0.0, 1.0 - exp(-3.0 * delta))
		for k in st.kids:
			_kid_play(k, pk, st, delta)
			k.set_far(k.global_position.distance_to(cam_pos) > visible_distance)
			if riding and absf(player.speed) > bump_speed and not k.is_busy():
				var hd: Vector3 = k.global_position - ppos
				if absf(hd.y) < 1.2:
					hd.y = 0.0
					if hd.length() < bump_radius + 0.1:
						k.stumble(ppos)
						player.stumble(hd)
		for a in st.adults:
			a.tick(delta, Vector3.ZERO)
			a.set_far(a.global_position.distance_to(cam_pos) > visible_distance)


func _open_park(pk: Dictionary) -> Dictionary:
	var st := {"kids": [], "adults": [], "t": 0.0}
	var roles := ["salincak", "salincak", "tahterevalli", "tahterevalli", "kaydirak", "kos", "kos", "kos"]
	for i in park_kids:
		var recipe := NpcCatalog.make_recipe(_rng, NpcCatalog.pick_species(_rng))
		var k := Npc.new()
		if player:
			k.ground_exclude = [player.get_rid()]
		add_child(k)
		k.setup(recipe, _materials, true)
		var spots: Array = pk.spots
		k.global_position = spots[_rng.randi() % spots.size()]
		st.kids.append(k)
		_set_role(k, pk, st, roles[i % roles.size()])
	# Yetişkinler park banklarında (oturabilenler)
	var seats: Array = pk.benches.duplicate()
	seats.shuffle()
	var placed := 0
	for id in seats:
		if placed >= park_adults or benches == null:
			break
		if not benches.is_free(id):
			continue
		for attempt in 4:
			var recipe := NpcCatalog.make_recipe(_rng, NpcCatalog.pick_species(_rng))
			var a := Npc.new()
			add_child(a)
			a.setup(recipe, _materials)
			if not a.can_sit(Banklar.SEAT_Y):
				a.queue_free()
				continue
			benches.reserve(id, a)
			a.bench_seat = id
			a.sit_at(benches.seat_point(id), benches.facing(id), 1e6)
			st.adults.append(a)
			placed += 1
			break
	if look and look.has_method("add_root"):
		look.add_root(self)
	return st


func _close_park(id: int) -> void:
	var st: Dictionary = _parks[id]
	for k in st.kids:
		if is_instance_valid(k):
			k.queue_free()
	for a in st.adults:
		if is_instance_valid(a):
			if benches and a.bench_seat >= 0:
				benches.release(a.bench_seat, a)
			a.queue_free()
	_parks.erase(id)


## Çocuğa iş ver: salıncak / tahterevalli yeri boşsa onu alır, yoksa koşar
func _set_role(k: Npc, pk: Dictionary, st: Dictionary, want: String) -> void:
	k.stand_up()
	k.role_t = 0.0
	k.role_data = {}
	if want == "salincak":
		for si in (pk.swings as Array).size():
			var used := false
			for o in st.kids:
				if o != k and o.role == "salincak" and int(o.role_data.get("i", -1)) == si:
					used = true
			if not used:
				k.role = "salincak"
				k.role_data = {"i": si, "phase": 0}
				return
		want = "kos"
	if want == "tahterevalli" and not (pk.seesaw as Dictionary).is_empty():
		for e in 2:
			var used := false
			for o in st.kids:
				if o != k and o.role == "tahterevalli" and int(o.role_data.get("i", -1)) == e:
					used = true
			if not used:
				k.role = "tahterevalli"
				k.role_data = {"i": e, "phase": 0}
				return
		want = "kos"
	if want == "kaydirak" and not (pk.slide as Dictionary).is_empty():
		k.role = "kaydirak"
		k.role_data = {"phase": 0}
		return
	k.role = "kos"
	k.role_data = {"to": (pk.spots as Array)[_rng.randi() % (pk.spots as Array).size()]}


## Oyun: önce yere yürür / koşar, oturur, sallanır, kayar...
func _kid_play(k: Npc, pk: Dictionary, st: Dictionary, delta: float) -> void:
	k.role_t += delta
	var run := 2.1 * Npc.CHILD_SCALE + 0.9
	match k.role:
		"kos":
			var to: Vector3 = k.role_data.get("to", k.global_position)
			var d := to - k.global_position
			d.y = 0.0
			if k.state == Npc.State.STUMBLE:
				k.move(delta, Vector3.ZERO)
			elif d.length() > 0.4 and not k.hopping():
				k.move(delta, _kid_sep(k, st, d.normalized() * run))
			else:
				k.move(delta, Vector3.ZERO)
				if not k.hopping():
					var r := _rng.randf()
					if r < 0.35:
						k.hop(0.22 + _rng.randf() * 0.1, 0.42)
					elif r < 0.7 or k.role_t > 18.0:
						# Başka bir oyuna geç (boş eşya varsa)
						_set_role(k, pk, st, ["salincak", "tahterevalli", "kaydirak", "kos"][_rng.randi() % 4])
					else:
						k.role_data["to"] = (pk.spots as Array)[_rng.randi() % (pk.spots as Array).size()]
		"salincak":
			var sw: Dictionary = (pk.swings as Array)[int(k.role_data.i)]
			var piv: Node3D = sw.pivot
			var seat: Vector3 = piv.global_transform * (sw.seat as Vector3)
			if int(k.role_data.phase) == 0:
				# Salıncağın önüne yürü
				var front := seat + (pk.xf as Transform3D).basis.z * 0.0
				var d := front - k.global_position
				d.y = 0.0
				if d.length() > 0.35 and k.role_t < 8.0:
					k.move(delta, _kid_sep(k, st, d.normalized() * run))
					return
				k.role_data.phase = 1
				k.role_t = 0.0
			var facing: Vector3 = (pk.xf as Transform3D).basis.z
			k.place_sit(seat, facing)
			k.move(delta, Vector3.ZERO)
			if k.role_t > 14.0 + _rng.randf() * 4.0:
				_set_role(k, pk, st, "kos")
		"tahterevalli":
			var ss: Dictionary = pk.seesaw
			var piv: Node3D = ss.pivot
			var end: Vector3 = piv.global_transform * ((ss.ends as Array)[int(k.role_data.i)] as Vector3)
			if int(k.role_data.phase) == 0:
				var d := end - k.global_position
				d.y = 0.0
				if d.length() > 0.4 and k.role_t < 8.0:
					k.move(delta, _kid_sep(k, st, d.normalized() * run))
					return
				k.role_data.phase = 1
				k.role_t = 0.0
			var to_c: Vector3 = piv.global_position - end
			to_c.y = 0.0
			k.place_sit(end, to_c.normalized())
			k.move(delta, Vector3.ZERO)
			if k.role_t > 16.0 + _rng.randf() * 4.0:
				_set_role(k, pk, st, "kos")
		"kaydirak":
			var sl: Dictionary = pk.slide
			var ph := int(k.role_data.phase)
			if ph == 0:
				var d: Vector3 = (sl.bottom as Vector3) - k.global_position
				d.y = 0.0
				if d.length() > 0.35 and k.role_t < 10.0:
					k.move(delta, _kid_sep(k, st, d.normalized() * run))
					return
				k.role_data.phase = 1
				k.role_t = 0.0
			elif ph == 1:
				# Merdivenden çıkış
				var u := clampf(k.role_t / 1.3, 0.0, 1.0)
				k.global_position = (sl.bottom as Vector3).lerp(sl.top, u)
				k.velocity = ((sl.top as Vector3) - (sl.bottom as Vector3)) / 1.3
				var dd: Vector3 = (sl.top as Vector3) - (sl.bottom as Vector3)
				k.rotation.y = atan2(-dd.x, -dd.z)
				if u >= 1.0:
					k.role_data.phase = 2
					k.role_t = 0.0
			elif ph == 2:
				# Oturup kay
				var u := clampf(k.role_t / 0.9, 0.0, 1.0)
				k.place_sit((sl.start as Vector3).lerp(sl.end, u * u), sl.dir)
				k.move(delta, Vector3.ZERO)
				if u >= 1.0:
					k.stand_up()
					k.role_data.phase = 3
					k.role_t = 0.0
			else:
				# İnip biraz uzaklaş, sonra yine kay ya da başka oyun
				k.move(delta, (sl.dir as Vector3) * run * (1.0 if k.role_t < 0.6 else 0.0))
				if k.role_t > 1.2:
					_set_role(k, pk, st, "kaydirak" if _rng.randf() < 0.5 else "kos")


## Çocuklar birbirine girmesin
func _kid_sep(k: Npc, st: Dictionary, steer: Vector3) -> Vector3:
	var sep := Vector3.ZERO
	for o in st.kids:
		if o == k:
			continue
		var d: Vector3 = k.global_position - o.global_position
		d.y = 0.0
		var dist := d.length()
		if dist < 0.6 and dist > 0.001:
			sep += d / dist * (0.6 - dist) * 2.5
	return (steer + sep).limit_length(steer.length() * 1.2 + 0.2)

