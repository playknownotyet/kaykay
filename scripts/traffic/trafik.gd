class_name Trafik
extends Node3D
## Araba trafiği. Şerit ağı tools/ada/trafik.js'ten (assets/ada/trafik.json): sağdan akan
## şeritler, kavşak içi geçişler (Bezier), çıkmazlarda U dönüşü.
##
## Her araba bir şeridin s metresinde; hızını "akıllı sürücü modeli" (IDM) belirler:
##   - önündeki yolun hız sınırı ve virajlar (yaklaşırken yavaşlar),
##   - öndeki araba (yolun izdüşümünde, kavşakta kesişen yollar dahil),
##   - kırmızı / sarı ışıkta dur çizgisi; çıkış şeridi tıkalıysa kavşağa girmez,
##   - yoldaki yaya (NPC) ve oyuncu: fren yapar; yine de çarparsa oyuncu düşer.
## Arabalar oyuncunun çevresinde (görünmeyen yerde) doğar, çok uzaklaşınca yeniden kullanılır.

@export var count := 40:
	set(value):
		count = value
		if _ready_lanes:
			_sync_count()
@export var spawn_min := 70.0
@export var spawn_max := 220.0
@export var recycle_distance := 280.0
## Bu mesafeden uzaktaki arabaların sürücü animasyonu durur
@export var detail_distance := 70.0
## Dağa doğru tırmanan şeritlerde hız sınırı bu kadar yüksek (tutunup hızlı çıkmak için)
@export var uphill_boost := 1.2

const A_MAX := 2.2        # en çok hızlanma (m/sn²)
const B_COMF := 3.5       # rahat fren
const S0 := 2.2           # durunca öndekine boşluk (m)
const T_HEAD := 1.1       # takip süresi (sn)
const LOOK_MIN := 30.0
const PATH_STEP := 2.5
const LANE_HALF := 1.8    # yol üstündeki bir şey bu yanal mesafedeyse önümde sayılır (araba)
const PED_HALF := 1.35    # yaya için

var player: SkateController
var camera: Camera3D
var crowd: NpcCrowd
var look: Node

var _lanes: Array = []        # [{pts, cum, v, next, w, len, j, arm, conn}]
var _cars: Array[Araba] = []
var _rng := RandomNumberGenerator.new()
var _npc_materials := {}
var _ready_lanes := false
var _frame := 0
var _spawnable: Array[int] = []
var _spawn_weight := 0.0
var _to_top := PackedFloat32Array()   # şeridin sonundan tepeye kalan yol (m)
var _skitched: Araba = null
var _peds: Array = []          # bu karenin yayaları [konum, hız] (her arabada yeniden toplanmasın)
## Oyuncudan bu kadar uzaktaki arabalar daha seyrek karar verir (telefonda işlemci)
const FAR_DECIDE := 90.0
const VERY_FAR_DECIDE := 160.0
## Bu mesafeden uzaktaki arabaların çarpışma gövdesi kapalı
const PHYS_NEAR := 45.0


func _ready() -> void:
	_rng.randomize()
	if not TrafikSinyal.ensure():
		set_physics_process(false)
		return
	for L in TrafikSinyal.data.lanes:
		var p: Array = L.p
		var pts := PackedVector3Array()
		for i in range(0, p.size(), 3):
			pts.append(Vector3(p[i], p[i + 1], p[i + 2]))
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		_lanes.append({
			"pts": pts, "cum": cum, "v": PackedFloat32Array(L.v), "next": PackedInt32Array(L.next),
			"w": PackedFloat32Array(L.w), "len": cum[cum.size() - 1], "j": int(L.j), "arm": int(L.arm),
			"conn": int(L.k) == 1, "turn": String(L.get("t", "")), "cj": int(L.get("cj", -1)), "fa": int(L.get("fa", -1)),
		})
	for i in _lanes.size():
		var L: Dictionary = _lanes[i]
		if not L.conn and L.len > 25.0 and L.next.size() > 0:
			_spawnable.append(i)
			_spawn_weight += L.len
	_mark_uphill()
	for i in _lanes.size():
		var L: Dictionary = _lanes[i]
		var lsp := PackedVector3Array()
		var lsl := PackedFloat32Array()
		var n := int(floor(L.len / PATH_STEP))
		for k in n + 1:
			lsp.append(_lane_point(i, k * PATH_STEP))
			lsl.append(_lane_limit(i, k * PATH_STEP))
		L.sp = lsp
		L.sl = lsl
	_ready_lanes = true
	# Kalabalık ve kamera hazır olsun
	await get_tree().physics_frame
	_sync_count()
	print("TRAFİK: %d şerit, %d araba" % [_lanes.size(), _cars.size()])


# ---------- Şerit geometrisi ----------

func _lane_point(li: int, s: float) -> Vector3:
	var L: Dictionary = _lanes[li]
	var cum: PackedFloat32Array = L.cum
	var pts: PackedVector3Array = L.pts
	s = clampf(s, 0.0, L.len)
	var lo := cum.bsearch(s) - 1
	lo = clampi(lo, 0, pts.size() - 2)
	var t := (s - cum[lo]) / maxf(cum[lo + 1] - cum[lo], 0.001)
	return pts[lo].lerp(pts[lo + 1], clampf(t, 0.0, 1.0))


func _lane_limit(li: int, s: float) -> float:
	var L: Dictionary = _lanes[li]
	var cum: PackedFloat32Array = L.cum
	var v: PackedFloat32Array = L.v
	var lo := clampi(cum.bsearch(s) - 1, 0, v.size() - 1)
	return v[lo] * (uphill_boost if L.up else 1.0)


## Tepeye yol: en yüksek şeritlerden geriye doğru (Dijkstra) her şeridin sonundan tepeye kalan
## mesafe. Tutunulan araba kavşaklarda bunu azaltan yönü seçer. Yükselen şeritler hızlı (L.up).
func _mark_uphill() -> void:
	var n := _lanes.size()
	var top_h := -1e9
	for L in _lanes:
		var pts: PackedVector3Array = L.pts
		top_h = maxf(top_h, pts[pts.size() - 1].y)
	var prev := []
	prev.resize(n)
	for i in n:
		prev[i] = []
	for i in n:
		for nx in _lanes[i].next:
			prev[nx].append(i)
	_to_top.resize(n)
	_to_top.fill(1e9)
	var open: Array[int] = []
	for i in n:
		var L: Dictionary = _lanes[i]
		var pts: PackedVector3Array = L.pts
		L.up = pts[pts.size() - 1].y - pts[0].y > maxf(0.5, L.len * 0.015)
		if pts[pts.size() - 1].y > top_h - 3.0:
			_to_top[i] = 0.0
			open.append(i)
	while not open.is_empty():
		var bi := 0
		for k in open.size():
			if _to_top[open[k]] < _to_top[open[bi]]:
				bi = k
		var u: int = open[bi]
		open.remove_at(bi)
		for p in prev[u]:
			var d: float = _to_top[u] + _lanes[u].len
			if d < _to_top[p]:
				_to_top[p] = d
				open.append(p)


## Tutunulan arabanın sonraki şeridi: tepeye en yakın yön (tepeye vardıysa rastgele)
func _choose_uphill(li: int) -> int:
	var nx: PackedInt32Array = _lanes[li].next
	if nx.is_empty():
		return -1
	if _to_top[li] <= 0.0:
		return _choose_next(li)
	var best := nx[0]
	for x in nx:
		if _to_top[x] + _lanes[x].len < _to_top[best] + _lanes[best].len:
			best = x
	return best


## Arabanın yolu üzerinde d metre ilerideki (d < 0: gerideki, şerit başında durur) nokta
func _path_point(car: Araba, d: float) -> Vector3:
	var s := car.s + d
	var li := car.lane
	if s < 0.0:
		return _lane_point(li, 0.0) + (_lane_point(li, 0.0) - _lane_point(li, 1.0)) * -s
	var k := 0
	while s > _lanes[li].len and k < car.route.size():
		s -= _lanes[li].len
		li = car.route[k]
		k += 1
	return _lane_point(li, s)


func _choose_next(li: int) -> int:
	var L: Dictionary = _lanes[li]
	var nx: PackedInt32Array = L.next
	if nx.is_empty():
		return -1
	var w: PackedFloat32Array = L.w
	var total := 0.0
	for x in w:
		total += x
	var r := _rng.randf() * total
	for i in nx.size():
		r -= w[i]
		if r <= 0.0:
			return nx[i]
	return nx[nx.size() - 1]


func _extend_route(car: Araba) -> void:
	var uphill := car == _skitched
	while car.route.size() < 4:
		var last := car.lane if car.route.is_empty() else car.route[car.route.size() - 1]
		var n := _choose_uphill(last) if uphill else _choose_next(last)
		if n < 0:
			break
		car.route.append(n)


## Rotayı ilk adımdan sonra yeniden seç (kavşağa çok yakınsa ilk geçiş korunur)
func _reroute(car: Araba) -> void:
	var keep := 1 if _lanes[car.lane].len - car.s < 25.0 else 0
	while car.route.size() > keep:
		car.route.pop_back()
	_extend_route(car)


# ---------- Doğma / geri çağırma ----------

func _sync_count() -> void:
	while _cars.size() > count:
		var c: Araba = _cars.pop_back()
		c.queue_free()
	var tries := 0
	while _cars.size() < count and tries < count * 4:
		tries += 1
		var car := Araba.new()
		add_child(car)
		var keys := Araba.MODELS.keys()
		var key: String = keys[0]
		var total := 0.0
		for k in keys:
			total += float(Araba.MODELS[k].weight)
		var r := _rng.randf() * total
		for k in keys:
			r -= float(Araba.MODELS[k].weight)
			if r <= 0.0:
				key = k
				break
		car.setup(key, _rng.randi() % 5, _rng, _npc_materials)
		_cars.append(car)
		if not _place(car, true):
			_cars.pop_back()
			car.queue_free()
	if look and look.has_method("add_root"):
		look.add_root(self)


## Arabayı oyuncunun çevresinde boş bir şeride koy. initial: açılışta kamera kontrolü yok
func _place(car: Araba, initial: bool) -> bool:
	var ppos := player.global_position if player else Vector3.ZERO
	for attempt in 24:
		var r := _rng.randf() * _spawn_weight
		var li := _spawnable[0]
		for x in _spawnable:
			r -= _lanes[x].len
			if r <= 0.0:
				li = x
				break
		var L: Dictionary = _lanes[li]
		var s := _rng.randf_range(6.0, L.len - 6.0)
		var p := _lane_point(li, s)
		var d := Vector2(p.x - ppos.x, p.z - ppos.z).length()
		if d < spawn_min * (0.5 if initial else 1.0) or d > spawn_max:
			continue
		if not initial and camera and d < 160.0 and camera.is_position_in_frustum(p):
			continue
		var crowded := false
		for o in _cars:
			if o != car and o.lane >= 0 and o.global_position.distance_squared_to(p) < 196.0:
				crowded = true
				break
		if crowded:
			continue
		car.lane = li
		car.s = s
		car.route.clear()
		_extend_route(car)
		car.speed = minf(_lane_limit(li, s), 8.0)
		car.hold = 0.0
		car.blocked_by = null
		car.cached_gap = 1e9
		car.decide_phase = _rng.randi() % 2
		car.visible = true
		_pose(car, 0.0)
		return true
	# Yer bulunamadı: gizli bekler (sonraki karelerde yeniden denenir)
	car.lane = -1
	car.visible = false
	car.global_position = Vector3(0, -200, 0)
	return false


# ---------- Her kare ----------

func _physics_process(delta: float) -> void:
	if not _ready_lanes or _cars.is_empty():
		return
	_frame += 1
	var t := TrafikSinyal.now()
	var ppos := player.global_position if player else Vector3(1e6, 0, 0)
	_peds.clear()
	if player:
		_peds.append([player.global_position, maxf(player.velocity.length(), 0.0), true])
	if crowd:
		for n in crowd.npc_list():
			_peds.append([n.global_position, 0.0, false])
	var cam_pos := camera.global_position if camera else ppos
	var candidate: Araba = null
	var cand_d := 1e9
	var recycled := 0
	for car in _cars:
		if car.lane < 0:
			if recycled < 2 and _place(car, false):
				recycled += 1
			continue
		# Karar: yakındakiler iki karede bir, uzaktakiler dört, çok uzaktakiler sekiz karede bir
		var d2 := car.global_position.distance_squared_to(ppos)
		var every := 2 if d2 < FAR_DECIDE * FAR_DECIDE else (4 if d2 < VERY_FAR_DECIDE * VERY_FAR_DECIDE else 8)
		if _frame % every == (car.decide_phase * every) / 2:
			_decide(car, t, every > 2)
		car.set_physics_near(d2 < PHYS_NEAR * PHYS_NEAR or (player != null and player.skitch_car == car))
		# Uzaktaki arabaların konumu seyrek güncellenir (her güncelleme modelin tüm parçalarını taşır)
		var pose_every := 1 if d2 < 80.0 * 80.0 else (2 if d2 < 150.0 * 150.0 else 4)
		car.pose_acc += delta
		var do_pose := (_frame + car.decide_phase) % pose_every == 0
		_drive(car, delta, do_pose)
		car.set_far(car.global_position.distance_to(cam_pos) > detail_distance)
		# Oyuncuya çarpma ve tutunma
		if player:
			var dp := car.global_position.distance_to(ppos)
			if dp < 6.0:
				_check_hit(car)
				var a := car.skitch_anchor()
				var da := Vector2(a.x - ppos.x, a.z - ppos.z).length()
				if da < 1.5 and absf(a.y - ppos.y) < 1.0 and player.heading.dot(car.fwd) > 0.75 and da < cand_d:
					candidate = car
					cand_d = da
			if dp > recycle_distance and player.skitch_car != car:
				if recycled < 2 and _place(car, false):
					recycled += 1
	if player:
		player.skitch_candidate = candidate
		# Tutunma başladı / bitti: yolu yeniden seç (tutunulan tepeye gider, bırakılınca rastgele)
		var sk: Araba = player.skitch_car
		if sk != _skitched:
			var old := _skitched
			_skitched = sk
			for c in [old, sk]:
				if c and is_instance_valid(c) and c.lane >= 0:
					_reroute(c)


## Sürüş kararı (iki karede bir): önümdeki yolun hız sınırı, ışık, öndeki araba ve yayalar.
func _decide(car: Araba, t: float, coarse := false) -> void:
	var v := car.speed
	var horizon := maxf(LOOK_MIN, v * v / (2.0 * B_COMF) + 18.0)
	var vmax := _lane_limit(car.lane, car.s)
	var gap := 1e9
	var lead_v := 0.0
	var blocker: Araba = null
	var why := ""

	# Yol örnekleri ve hız sınırı (virajdan önce yavaşla). Şerit örnekleri önceden hesaplı
	# (L.sp / L.sl, PATH_STEP aralıkla); uzaktaki arabalar ikide bir örneğe bakar.
	var sd := PackedFloat32Array()      # örneğin yol boyunca uzaklığı
	var sp := PackedVector3Array()      # örnek noktası
	var stride := 2 if coarse else 1
	var li := car.lane
	var s := car.s
	var dist := 0.0
	var k := 0
	var signal_done := false
	while dist < horizon:
		var L: Dictionary = _lanes[li]
		var lsp: PackedVector3Array = L.sp
		var lsl: PackedFloat32Array = L.sl
		var base := dist - s                     # şeridin başının yol boyunca uzaklığı
		var i := int(s / PATH_STEP) + 1
		while i < lsp.size():
			var dd := base + i * PATH_STEP
			if dd >= horizon:
				break
			sd.append(dd)
			sp.append(lsp[i])
			var lim := lsl[i]
			vmax = minf(vmax, sqrt(lim * lim + 2.0 * B_COMF * 0.7 * maxf(dd - car.half.z, 0.0)))
			i += stride
		dist = base + float(L.len)
		if dist >= horizon:
			break
		# Şerit sonu: ışıklı kavşağa geldik mi?
		if not signal_done and int(L.j) >= 0:
			signal_done = true
			var stop_d: float = dist - car.half.z - 0.4
			if stop_d > -1.0:
				var stv := TrafikSinyal.car_state(L.j, L.arm, t)
				var must_stop := stv == TrafikSinyal.KIRMIZI
				if stv == TrafikSinyal.SARI and stop_d > v * v / (2.0 * 4.5):
					must_stop = true
				if not must_stop and TrafikSinyal.must_yield(int(L.j), int(L.arm)) and _priority_traffic(car, int(L.j)):
					must_stop = true
					stv = TrafikSinyal.KIRMIZI
				if not must_stop and k < car.route.size() and _exit_blocked(car, k):
					must_stop = true
				if not must_stop and k < car.route.size() and _lanes[car.route[k]].turn == "sol" \
						and _oncoming(car, int(L.j), int(L.arm), t):
					must_stop = true
				if must_stop and stop_d < gap:
					gap = maxf(stop_d, 0.05)
					lead_v = 0.0
					blocker = null
					why = "ışık" if stv != TrafikSinyal.YESIL else "çıkış dolu"
		if k >= car.route.size():
			break
		li = car.route[k]
		k += 1
		s = 0.0

	# Öndeki arabalar. Yol boyunca uzaklık kuş uçuşundan kısa olamaz: yalnız kuş uçuşu
	# uzaklığın çevresindeki örneklere bakılır (her örneği her arabayla karşılaştırmak pahalı)
	var pos := car.global_position
	var n_s := sd.size()
	var far2 := (horizon + 8.0) * (horizon + 8.0)
	for o in _cars:
		if o == car or o.lane < 0:
			continue
		var op := o.global_position
		var rel := op - pos
		var r2 := rel.length_squared()
		if r2 > far2 or rel.dot(car.fwd) < 0.0:
			continue
		if o.blocked_by == car and o.get_instance_id() < car.get_instance_id():
			continue   # karşılıklı kilitlenme: biri yol verir
		var i0 := maxi(sd.bsearch(sqrt(r2) - 4.0) - 1, 0)
		for i in range(i0, mini(i0 + 12, n_s)):
			var q := sp[i]
			if absf(q.y - op.y) < 2.5 and (q.x - op.x) * (q.x - op.x) + (q.z - op.z) * (q.z - op.z) < LANE_HALF * LANE_HALF:
				var g: float = sd[i] - o.half.z - car.half.z
				if g < gap:
					gap = maxf(g, 0.05)
					lead_v = o.speed * maxf(o.fwd.dot(car.fwd), 0.0)
					blocker = o
					why = "araba"
				break

	# Yayalar: oyuncu ve NPC'ler (yaya geçidinde, yolda)
	var h2 := horizon * horizon
	for pd in _peds:
		if pd[2] and player.skitch_car == car:
			continue
		var pp: Vector3 = pd[0]
		var rel := pp - pos
		var r2 := rel.length_squared()
		if r2 > h2 or rel.dot(car.fwd) < 0.0:
			continue
		var i0 := maxi(sd.bsearch(sqrt(r2) - 4.0) - 1, 0)
		for i in range(i0, mini(i0 + 12, n_s)):
			var q := sp[i]
			if absf(q.y - pp.y) < 2.0 and (q.x - pp.x) * (q.x - pp.x) + (q.z - pp.z) * (q.z - pp.z) < PED_HALF * PED_HALF:
				var g: float = sd[i] - car.half.z - 1.0
				if g < gap:
					gap = maxf(g, 0.05)
					lead_v = float(pd[1]) * (maxf(player.velocity.normalized().dot(car.fwd), 0.0) if pd[2] else 0.0)
					blocker = null
					why = "yaya"
				break

	car.cached_vmax = vmax
	car.cached_gap = gap
	car.cached_lead_v = lead_v
	car.blocked_by = blocker
	car.reason = why


## Sola dönüş: aynı fazda karşıdan gelen (dur çizgisine yakın ya da kavşağın içinde) araba var mı?
func _oncoming(car: Araba, j: int, arm: int, t: float) -> bool:
	var opp := TrafikSinyal.same_phase(j, arm)
	if opp.is_empty():
		return false
	for o in _cars:
		if o == car or o.lane < 0 or o.speed < 0.8:
			continue
		var L: Dictionary = _lanes[o.lane]
		if not L.conn and int(L.j) == j and opp.has(int(L.arm)) and L.len - o.s < 32.0 				and TrafikSinyal.car_state(j, int(L.arm), t) != TrafikSinyal.KIRMIZI:
			return true
		if L.conn and int(L.cj) == j and opp.has(int(L.fa)) and L.turn != "sol":
			return true
	return false


## Işıksız kavşakta yan yoldan gelen için: kavşağın içinde başka araba ya da öncelikli
## kollardan yaklaşan (dur çizgisine 30 m'den yakın, hareket eden) araba var mı?
func _priority_traffic(car: Araba, j: int) -> bool:
	var main := TrafikSinyal.main_arms(j)
	for o in _cars:
		if o == car or o.lane < 0:
			continue
		var L: Dictionary = _lanes[o.lane]
		if L.conn and int(L.cj) == j:
			return true
		if not L.conn and int(L.j) == j and main.has(int(L.arm)) and L.len - o.s < 30.0 and (o.speed > 1.0 or L.len - o.s < 8.0):
			return true
	return false


## Kavşaktan sonraki çıkış şeridinin başı dolu mu (kavşağı tıkamamak için)?
func _exit_blocked(car: Araba, k: int) -> bool:
	var conn: int = car.route[k]
	var nx: PackedInt32Array = _lanes[conn].next
	if nx.is_empty():
		return false
	var out := nx[0]
	var start := _lane_point(out, 0.0)
	for o in _cars:
		if o == car or o.lane < 0:
			continue
		if (o.lane == out and o.s < 9.0 and o.speed < 1.5) or (o.lane == conn and o.speed < 0.5 and o.global_position.distance_to(start) < 10.0):
			return true
	return false


func _drive(car: Araba, delta: float, do_pose := true) -> void:
	var v := car.speed
	var a: float
	if car.hold > 0.0:
		car.hold -= delta
		a = -8.0
	else:
		var v0 := maxf(car.cached_vmax, 0.1)
		var free := 1.0 - pow(minf(v / v0, 2.0), 4.0)
		var inter := 0.0
		if car.cached_gap < 1e8:
			var sstar := S0 + v * T_HEAD + v * (v - car.cached_lead_v) / (2.0 * sqrt(A_MAX * B_COMF))
			inter = pow(maxf(sstar, 0.0) / maxf(car.cached_gap, 0.05), 2.0)
		a = clampf(A_MAX * (free - inter), -9.0, A_MAX)
	v = maxf(v + a * delta, 0.0)
	car.speed = v
	var adv := v * delta
	if car.cached_gap < 1e8:
		car.cached_gap -= maxf(v - car.cached_lead_v, 0.0) * delta
	car.s += adv
	while car.s > _lanes[car.lane].len:
		if car.route.is_empty():
			car.s = _lanes[car.lane].len
			car.speed = 0.0
			break
		car.s -= _lanes[car.lane].len
		car.lane = car.route.pop_front()
		_extend_route(car)
	if do_pose:
		_pose(car, car.pose_acc, a < -1.2 or (v < 0.3 and car.cached_gap < 6.0))
		car.pose_acc = 0.0


func _pose(car: Araba, delta: float, braking := false) -> void:
	var front := _path_point(car, car.half.z * 0.6)
	var back := _path_point(car, -car.half.z * 0.6)
	var mid := (front + back) * 0.5
	var f := front - back
	if f.length_squared() < 0.0001:
		return
	f = f.normalized()
	var ahead := _path_point(car, car.half.z * 0.6 + 2.0) - front
	var steer := 0.0
	if ahead.length_squared() > 0.0001:
		steer = clampf(Vector3(f.x, 0, f.z).signed_angle_to(Vector3(ahead.x, 0, ahead.z), Vector3.UP) * 1.6, -0.6, 0.6)
	var up := Vector3.UP - f * f.dot(Vector3.UP)
	car.drive_to(mid, f, up.normalized(), steer, braking, delta)


## Araba oyuncuya çarptı mı? (gövde kutusu + oyuncunun yarıçapı)
func _check_hit(car: Araba) -> void:
	if car.speed < 1.5 or player.skitch_car == car or player.fall_time > 0.0:
		return
	var lp := car.global_transform.affine_inverse() * (player.global_position + Vector3.UP * 0.6)
	var h := car.half
	# Yalnız araba kendisi oyuncunun üstüne sürerken çarpar. Oyuncunun kendi hızı sayılmaz:
	# duran / yanaşmayan arabaya oyuncu çarparsa bu duvar çarpmasıdır (kontrolcü halleder)
	var to_p := player.global_position - car.global_position
	to_p.y = 0.0
	var toward := (car.fwd * car.speed).dot(to_p.normalized()) if to_p.length() > 0.01 else 0.0
	if toward < SkateController.CAR_HIT_SPEED:
		return
	if absf(lp.x) < h.x + 0.3 and absf(lp.z) < h.z + 0.3 and lp.y > -0.2 and lp.y < h.y * 2.0 + 0.4:
		var push := car.fwd * (car.speed * 0.9 + 1.5)
		# Yandan sıyırdıysa biraz da yana savrulur
		push += car.global_basis.x * signf(lp.x) * 1.5
		player.knockdown(push)
		car.hold = 2.5
		car.speed *= 0.4


func car_list() -> Array[Araba]:
	return _cars
