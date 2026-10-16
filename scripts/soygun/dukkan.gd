class_name Dukkan
extends Node3D
## Test dükkanı: çocuk soygunu / gizlilik akışının kamera ve oynanış denemesi (kâr-zarar yok).
##
## Akış:
##   - İçeride "göz" butonu: kamera kuş bakışına uçar, çatı kalkar; güvenlik kameralarının ve
##     kasadaki zürafanın görüş alanları zemine canlı çizilir (raflar görüşü keser; kameralar
##     tarar, zürafa etrafına bakınır). Kör noktaları ezberlemek için geri sayım ("hazır" ile
##     geçilir), sonra kamera üçüncü şahsa geri uçar.
##   - Kupanın yanında "al": sol eline alır; elde taşıyabilir, istediği yerde çantasına atar.
##   - Yakalanma yalnız çantaya atarken bir kamera ya da zürafa görüyorsa: ekran kararır,
##     "YAKALANDIN!", kamera sokaktan kapıya bakar; zürafa çocuğu tişörtünden tutup hafifçe
##     kaldırır ve dükkândan dışarı atar; çocuk kalkar, oyun sürer. Dükkândan aldıkları geri alınır.
##
## Yerel düzen: köken kapı ortası (zemin), -Z dükkanın içi, +X sağ (içeri bakınca).

enum Faz { NORMAL, KESIF_GIRIS, KESIF, KESIF_CIKIS, YAKALANDI }

const W := 10.0
const D := 8.0
const H := 3.2
const CHAR_SHADER := preload("res://shaders/toon_char.gdshader")
const KESIF_SURE := 10.0
const GECIS := 1.0
## karakter_rig.py "eline_al": 20 kare, eşya 10. karede elde
const AL_SURE := 20.0 / 30.0
const AL_GRAB := 10.0 / 30.0
## npc_ortak.py "disari_at": 60 kare; 12. karede tutar, 34. karede bırakır
const AT_TUT := 12.0 / 30.0
const AT_BIRAK := 34.0 / 30.0
const ITEM := "kupa"
const RAY_N := 30
const CONE_H := 1.2               # görüş ışınlarının yüksekliği: raflar keser, tezgâh kesmez

var player: SkateController
var follow_cam: Camera3D

var faz := Faz.NORMAL
var _t := 0.0
var _cam: Camera3D
var _from := Transform3D.IDENTITY
var _from_fov := 60.0
var _roof: Node3D
var _light: OmniLight3D
var _watchers: Array = []
var _owner: Node3D
var _owner_head := -1
var _owner_skel: Skeleton3D
var _owner_yaw := PI
var _owner_target := PI
var _owner_hold := 2.0
var _loot: Node3D
var _loot_home := Transform3D.IDENTITY
var _take_t := -1.0
var _stow_seen := false
var _owner_anim: AnimationPlayer
var _owner_mode := 0           # 0 tezgâhta, 1 sinematik, 2 tezgâha dönüyor
var _owner_path: Array[Vector3] = []
var _ct := 0.0                 # yakalanma sinematiği zamanı
var _released := false
var _back_t := -1.0
var _loot_held := false        # kupa oyuncunun elinde
var _stowing_loot := false
var _fade := 0.0
var _cine_from := Transform3D.IDENTITY
var _banner := ""
var _banner_t := 0.0
var _owns_buttons := false
var _ui: Control
var _mats := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_shell()
	_build_interior()
	_build_owner()
	_build_cameras()
	_build_loot()
	_cam = Camera3D.new()
	_cam.name = "KesifKamerasi"
	add_child(_cam)
	_cam.top_level = true
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	layer.add_child(_ui)
	if player:
		player.context_action.connect(_on_context)
		player.stow_started.connect(_on_stow_started)
		player.item_stowed.connect(_on_item_stowed)


# ---------- Yapı ----------

func _mat(c: Color) -> ShaderMaterial:
	var k := c.to_html()
	if not _mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = CHAR_SHADER
		m.set_shader_parameter("albedo", c)
		_mats[k] = m
	return _mats[k]


## Kutu: görüntü + (istenirse) çarpışma. pos: kutunun alt-orta noktası değil, merkezi
func _box(size: Vector3, pos: Vector3, color: Color, collide := true, parent: Node3D = null, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation.y = rot_y
	(parent if parent else self).add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.set_meta("surface", "beton")
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _build_shell() -> void:
	var wall := Color(0.93, 0.84, 0.66)
	var trim := Color(0.36, 0.22, 0.16)
	# Zemin (önde kaldırıma uzanan basamak)
	_box(Vector3(W, 0.12, D + 0.9), Vector3(0, -0.06, -D * 0.5 + 0.45), Color(0.82, 0.78, 0.7))
	# Karo çizgileri (zemin deseni, çarpışmasız)
	for i in range(1, int(W)):
		_box(Vector3(0.03, 0.005, D), Vector3(-W * 0.5 + i, 0.003, -D * 0.5), Color(0.68, 0.64, 0.58), false)
	for i in range(1, int(D)):
		_box(Vector3(W, 0.005, 0.03), Vector3(0, 0.003, -i), Color(0.68, 0.64, 0.58), false)
	# Duvarlar
	_box(Vector3(W + 0.2, H, 0.2), Vector3(0, H * 0.5, -D - 0.1), wall)
	_box(Vector3(0.2, H, D), Vector3(-W * 0.5 - 0.1, H * 0.5, -D * 0.5), wall)
	_box(Vector3(0.2, H, D), Vector3(W * 0.5 + 0.1, H * 0.5, -D * 0.5), wall)
	var door := 2.0
	var seg := (W - door) * 0.5
	_box(Vector3(seg, H, 0.2), Vector3(-door * 0.5 - seg * 0.5, H * 0.5, 0.1), wall)
	_box(Vector3(seg, H, 0.2), Vector3(door * 0.5 + seg * 0.5, H * 0.5, 0.1), wall)
	_box(Vector3(door, H - 2.4, 0.2), Vector3(0, 2.4 + (H - 2.4) * 0.5, 0.1), wall)
	# Vitrin camları (dekor) ve kapı çerçevesi
	for sx in [-1.0, 1.0]:
		_box(Vector3(2.2, 1.2, 0.04), Vector3(sx * 2.6, 1.5, 0.22), Color(0.45, 0.62, 0.72), false)
		_box(Vector3(2.4, 0.08, 0.1), Vector3(sx * 2.6, 0.86, 0.24), trim, false)
	_box(Vector3(0.12, 2.4, 0.26), Vector3(-door * 0.5, 1.2, 0.1), trim, false)
	_box(Vector3(0.12, 2.4, 0.26), Vector3(door * 0.5, 1.2, 0.1), trim, false)
	# Tente: çizgili
	for i in 10:
		_box(Vector3(W / 10.0, 0.06, 1.1), Vector3(-W * 0.5 + (i + 0.5) * W / 10.0, H - 0.25, 0.75),
			Color(0.85, 0.2, 0.2) if i % 2 == 0 else Color(0.96, 0.94, 0.9), false)
	# Çatı (keşifte kalkar)
	_roof = Node3D.new()
	_roof.name = "Cati"
	add_child(_roof)
	_box(Vector3(W + 0.6, 0.25, D + 0.6), Vector3(0, H + 0.12, -D * 0.5), Color(0.55, 0.32, 0.26), true, _roof)
	# Tabela
	var sign := Label3D.new()
	sign.text = "ZÜRAFA BAKKAL"
	sign.font_size = 72
	sign.outline_size = 14
	sign.modulate = Color(1.0, 0.86, 0.3)
	sign.outline_modulate = Color(0.25, 0.1, 0.05)
	sign.pixel_size = 0.006
	sign.position = Vector3(0, H + 0.55, 0.35)
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(sign)
	_box(Vector3(5.6, 0.7, 0.12), Vector3(0, H + 0.55, 0.26), Color(0.3, 0.16, 0.1), false)
	# İç ışık (çatı güneşi keser)
	_light = OmniLight3D.new()
	_light.position = Vector3(0, H - 0.4, -D * 0.5)
	_light.omni_range = 9.0
	_light.light_energy = 1.3
	_light.light_color = Color(1.0, 0.95, 0.85)
	add_child(_light)


func _build_interior() -> void:
	var wood := Color(0.5, 0.33, 0.2)
	var shelf := Color(0.7, 0.72, 0.75)
	# Tezgâh ve yazar kasa
	_box(Vector3(2.8, 1.0, 0.7), Vector3(3.0, 0.5, -5.3), wood)
	_box(Vector3(3.0, 0.06, 0.85), Vector3(3.0, 1.03, -5.3), Color(0.35, 0.22, 0.14), false)
	_box(Vector3(0.5, 0.3, 0.4), Vector3(2.4, 1.21, -5.3), Color(0.2, 0.22, 0.25), false)
	_box(Vector3(0.7, 1.0, 2.3), Vector3(4.25, 0.5, -6.15), wood)
	# Raflar: iki ada ve sol duvar boyunca
	var gondolas := [[Vector3(3.2, 1.7, 0.6), Vector3(-1.0, 0.85, -2.6)], [Vector3(3.2, 1.7, 0.6), Vector3(-1.0, 0.85, -4.9)],
		[Vector3(0.6, 1.9, 3.6), Vector3(-4.45, 0.95, -3.6)]]
	var prod := [Color(0.9, 0.3, 0.25), Color(0.25, 0.55, 0.9), Color(0.95, 0.8, 0.25), Color(0.35, 0.75, 0.4), Color(0.85, 0.5, 0.85)]
	for g in gondolas:
		var size: Vector3 = g[0]
		var c: Vector3 = g[1]
		_box(size, c, shelf)
		# Ürünler: her rafta renkli kutular (iki yüzde)
		var along_x := size.x > size.z
		var L := size.x if along_x else size.z
		for lvl in 3:
			var y := 0.35 + lvl * 0.5
			var n := int(L / 0.35)
			for k in n:
				var t := -L * 0.5 + (k + 0.5) * L / n
				for face in [-1.0, 1.0]:
					var off := (size.z if along_x else size.x) * 0.5 + 0.1
					var pp := Vector3(c.x + (t if along_x else off * face), y, c.z + (off * face if along_x else t))
					if not along_x and face > 0.0:
						continue   # duvar tarafı
					_box(Vector3(0.24, 0.3 + 0.05 * ((k + lvl) % 3), 0.18), pp, prod[(k * 3 + lvl) % prod.size()], false)


func _build_owner() -> void:
	var recipe := NpcCatalog.make_recipe(_rng, "zurafa")
	_owner = Node3D.new()
	_owner.name = "Zurafa"
	_owner.position = Vector3(3.2, 0, -6.7)
	add_child(_owner)
	var model := Npc.build_model(recipe, {})
	_owner.add_child(model)
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	_owner_anim = anim
	if anim:
		for n in ["idle_look", "walk", "idle"]:
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		anim.play("idle_look")
	_owner_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	_owner_head = _owner_skel.find_bone("head")
	_owner.rotation.y = _owner_yaw
	_watchers.append({"kind": "zurafa", "fov": deg_to_rad(80.0), "range": 6.5, "color": Color(1.0, 0.85, 0.2, 0.32)})


func _build_cameras() -> void:
	# Köşelerde tavan kameraları: sağa sola tarar
	var specs := [[Vector3(4.6, 2.85, -0.4), Vector2(-8.6, -6.6), 0.45, 0.0], [Vector3(-4.6, 2.85, -0.5), Vector2(8.0, -5.5), 0.4, 2.2]]
	for sp in specs:
		var p: Vector3 = sp[0]
		var aim: Vector2 = sp[1]
		var body := Node3D.new()
		body.position = p
		add_child(body)
		_box(Vector3(0.18, 0.16, 0.38), Vector3(0, 0, 0), Color(0.88, 0.88, 0.86), false, body)
		_box(Vector3(0.1, 0.1, 0.06), Vector3(0, 0, -0.21), Color(0.1, 0.1, 0.12), false, body)
		var led := _box(Vector3(0.04, 0.04, 0.02), Vector3(0.06, 0.05, -0.2), Color(1, 0.1, 0.1), false, body)
		var base_yaw := atan2(-aim.x, -aim.y)
		_watchers.append({"kind": "kamera", "node": body, "base": base_yaw, "sweep": sp[2], "phase": sp[3],
			"fov": deg_to_rad(50.0), "range": 9.5, "color": Color(1.0, 0.25, 0.2, 0.3), "led": led})
	# Görüş alanı meshleri
	for w in _watchers:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = w.color
		m.no_depth_test = false
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		w["mesh"] = mi
		w["mat"] = m
		w["dists"] = PackedFloat32Array()


func _build_loot() -> void:
	_box(Vector3(0.6, 0.9, 0.6), Vector3(-4.2, 0.45, -7.3), Color(0.3, 0.25, 0.35))
	_loot = Node3D.new()
	_loot.name = "AltinKupa"
	_loot.position = Vector3(-4.2, 0.9, -7.3)
	add_child(_loot)
	var gold := Color(1.0, 0.78, 0.2)
	var parts := [[CylinderMesh.new(), Vector3(0, 0.03, 0), Vector3(0.14, 0.06, 0.14)],
		[CylinderMesh.new(), Vector3(0, 0.12, 0), Vector3(0.04, 0.14, 0.04)],
		[SphereMesh.new(), Vector3(0, 0.27, 0), Vector3(0.16, 0.14, 0.16)]]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var mesh: PrimitiveMesh = pt[0]
		if mesh is CylinderMesh:
			mesh.top_radius = 0.5
			mesh.bottom_radius = 0.5
			mesh.height = 1.0
		else:
			mesh.radius = 0.5
			mesh.height = 1.0
		mi.mesh = mesh
		mi.position = pt[1]
		mi.scale = pt[2]
		mi.material_override = _mat(gold)
		_loot.add_child(mi)
	_loot_home = _loot.transform


# ---------- Her kare ----------

func _physics_process(delta: float) -> void:
	if not player:
		return
	if _owner_mode == 0:
		_update_owner(delta)
	elif _owner_mode == 2:
		_owner_walk_back(delta)
	_update_watchers()
	var lp := to_local(player.global_position)
	var inside := absf(lp.x) < W * 0.5 - 0.2 and lp.z < -0.3 and lp.z > -D + 0.2 and absf(lp.y) < 2.0
	var near := absf(lp.x) < W * 0.5 + 6.0 and lp.z < 8.0 and lp.z > -D - 4.0

	match faz:
		Faz.NORMAL:
			var list := []
			var free := player.on_foot and player.fall_time <= 0.0 and player.action_time <= 0.0 and not player.bag_open
			if inside and free and player.held_item == "":
				list.append({"id": "goz", "icon": "goz"})
				if _loot.visible and _take_t < 0.0 and player.global_position.distance_to(_loot.global_position) < 1.7:
					list.append({"id": "al", "icon": "al"})
			_set_buttons(list)
			# Alma: eşya 10. karede ele geçer
			if _take_t >= 0.0:
				_take_t += delta
				if _take_t < AL_GRAB:
					pass
				else:
					_take_t = -1.0
					player.hold_item(ITEM, _loot)
					_loot_held = true
			# Çalınmadan (elde ya da çantada değilken) dükkândan uzaklaşınca kupa yerine döner
			if not near and not _loot.visible and not _loot_held:
				_loot.transform = _loot_home
				_loot.visible = true
		Faz.KESIF_GIRIS:
			_t += delta
			var k := smoothstep(0.0, 1.0, _t / GECIS)
			_cam.global_transform = _from.interpolate_with(_top_transform(), k)
			_cam.fov = lerpf(_from_fov, 52.0, k)
			if _t >= GECIS:
				faz = Faz.KESIF
				_t = 0.0
		Faz.KESIF:
			_t += delta
			_set_buttons([{"id": "hazir", "icon": "tamam"}])
			if _t >= KESIF_SURE:
				_start_exit()
		Faz.KESIF_CIKIS:
			_t += delta
			var k := smoothstep(0.0, 1.0, _t / GECIS)
			_cam.global_transform = _top_transform().interpolate_with(follow_cam.global_transform, k)
			_cam.fov = lerpf(52.0, follow_cam.fov, k)
			_roof.visible = k > 0.55
			for w in _watchers:
				w.mat.albedo_color = Color(w.color.r, w.color.g, w.color.b, w.color.a * (1.0 - k))
			if _t >= GECIS:
				follow_cam.make_current()
				for w in _watchers:
					w.mesh.visible = false
					w.mat.albedo_color = w.color
				player.input_locked = false
				faz = Faz.NORMAL
		Faz.YAKALANDI:
			_caught_step(delta)
	_banner_t = maxf(_banner_t - delta, 0.0)
	_ui.queue_redraw()


func _set_buttons(list: Array) -> void:
	if list.is_empty():
		if _owns_buttons:
			player.context_buttons = []
			_owns_buttons = false
	else:
		player.context_buttons = list
		_owns_buttons = true


func _on_context(id: String) -> void:
	match id:
		"goz":
			if faz != Faz.NORMAL:
				return
			faz = Faz.KESIF_GIRIS
			_t = 0.0
			_set_buttons([])
			player.input_locked = true
			_from = follow_cam.global_transform
			_from_fov = follow_cam.fov
			_cam.global_transform = _from
			_cam.fov = _from_fov
			_cam.make_current()
			_roof.visible = false
			for w in _watchers:
				w.mesh.visible = true
				w.mat.albedo_color = w.color
		"hazir":
			if faz == Faz.KESIF:
				_start_exit()
		"al":
			if faz != Faz.NORMAL or _take_t >= 0.0 or player.held_item != "":
				return
			var to := _loot.global_position - player.global_position
			to.y = 0.0
			if to.length() > 0.01:
				player.heading = to.normalized()
			player.play_action("eline_al", AL_SURE)
			_take_t = 0.0
			_set_buttons([])


func _start_exit() -> void:
	faz = Faz.KESIF_CIKIS
	_t = 0.0
	_set_buttons([])


## Çantaya atmaya başladı: bu dükkânın eşyasıysa ve o an görülüyorsa yakalanacak
func _on_stow_started(_item: String) -> void:
	_stowing_loot = _loot_held
	_stow_seen = _loot_held and _player_seen()


func _on_item_stowed(_item: String) -> void:
	if _stowing_loot:
		_stowing_loot = false
		_loot_held = false
		_loot.visible = false
	if _stow_seen:
		_stow_seen = false
		_start_caught()


# ---------- Yakalanma sinematiği ----------

func _start_caught() -> void:
	faz = Faz.YAKALANDI
	_ct = 0.0
	_back_t = -1.0
	_released = false
	_set_buttons([])
	player.input_locked = true
	_cine_from = follow_cam.global_transform


func _caught_step(delta: float) -> void:
	_ct += delta
	var out := (to_global(Vector3(0, 0, 1)) - to_global(Vector3.ZERO)).normalized()
	# 0-0,45 kararma, 0,45-1,7 karanlık + yazı, 1,7-2,1 aydınlanma
	if _ct < 0.45:
		_fade = _ct / 0.45
	elif _ct < 1.7:
		_fade = 1.0
	elif _ct < 2.1:
		_fade = 1.0 - (_ct - 1.7) / 0.4
	else:
		_fade = 0.0
	if _ct >= 0.45 and _ct - delta < 0.45:
		_setup_caught_scene()
	var ot := _ct - 1.75                       # sahibinin animasyon zamanı
	if ot >= 0.0 and ot - delta < 0.0 and _owner_anim:
		_owner_anim.play("disari_at", 0.1)
	if ot >= AT_TUT and not _released:
		# Tişörtünden tutulmuş: kök, iki elin ortasının 0,86 m altında, sahibine dönük
		player.held_in_air = true
		var hands := _owner_hands()
		player.global_position = player.global_position.lerp(hands - Vector3.UP * 0.86 + out * 0.12, 1.0 - exp(-30.0 * delta))
	if ot >= AT_BIRAK and not _released:
		_released = true
		player.held_in_air = false
		player.knockdown(out * 4.2)
	# Sahibi işini bitirince tezgâha döner; çocuk kalkınca kamera oyuna geri döner
	if _released and ot > 2.1 and _owner_mode == 1:
		_owner_mode = 2
		_owner_path = [Vector3(0.6, 0, -1.6), Vector3(1.0, 0, -4.2), Vector3(1.1, 0, -6.4), Vector3(3.2, 0, -6.7)]
		if _owner_anim:
			_owner_anim.play("walk", 0.3)
	if _released and player.fall_time <= 0.0 and ot > AT_BIRAK + 0.5:
		if _back_t < 0.0:
			_back_t = 0.0
			_cine_from = _cam.global_transform
		_back_t += delta
		var k := smoothstep(0.0, 1.0, _back_t / GECIS)
		_cam.global_transform = _cine_from.interpolate_with(follow_cam.global_transform, k)
		_cam.fov = lerpf(48.0, follow_cam.fov, k)
		if _back_t >= GECIS:
			follow_cam.make_current()
			player.input_locked = false
			faz = Faz.NORMAL


func _setup_caught_scene() -> void:
	# Dükkândan alınanlar geri alınır, kupa yerine
	player.take_back([ITEM])
	player.bag_open = false
	player.action_time = 0.0
	player.action_name = ""
	_loot.transform = _loot_home
	_loot.visible = true
	_loot_held = false
	_take_t = -1.0
	# Sahibi kapının içinde dışarı bakar; çocuk önünde, sırtı kapıya
	_owner_mode = 1
	_owner_yaw = PI
	_owner.rotation.y = PI
	_owner.position = Vector3(0, 0, -1.05)
	if _owner_anim:
		_owner_anim.play("idle", 0.0)
	player.global_position = to_global(Vector3(0, 0.02, -0.5))
	player.heading = (to_global(Vector3(0, 0, -1)) - to_global(Vector3.ZERO)).normalized()
	player.velocity = Vector3.ZERO
	player.speed = 0.0
	player.reset_physics_interpolation()
	# Kamera sokakta, kapıya karşıdan bakar
	var cam_pos := to_global(Vector3(1.3, 1.4, 6.2))
	var look := to_global(Vector3(0, 1.25, -0.6))
	_cam.global_transform = Transform3D(Basis.looking_at(look - cam_pos, Vector3.UP), cam_pos)
	_cam.fov = 48.0
	_cam.make_current()
	_roof.visible = true
	for w in _watchers:
		w.mesh.visible = false


## Kuş bakışı: dükkanın ortasının üstünde, kapı ekranın altında
func _top_transform() -> Transform3D:
	var center := to_global(Vector3(0, 0, -D * 0.5))
	var into := (to_global(Vector3(0, 0, -1)) - to_global(Vector3.ZERO)).normalized()
	var pos := center + Vector3.UP * 11.5 - into * 0.8
	return Transform3D(Basis.looking_at(center - pos, into), pos)


func _owner_hands() -> Vector3:
	var l := _owner_skel.find_bone("hand.L")
	var r := _owner_skel.find_bone("hand.R")
	if l < 0 or r < 0:
		return _owner.global_position + Vector3.UP * 1.2
	var gl := _owner_skel.global_transform * _owner_skel.get_bone_global_pose(l).origin
	var gr := _owner_skel.global_transform * _owner_skel.get_bone_global_pose(r).origin
	return (gl + gr) * 0.5


## Sinematikten sonra tezgâhın arkasına yürür
func _owner_walk_back(delta: float) -> void:
	if _owner_path.is_empty():
		_owner_mode = 0
		_owner_yaw = PI
		_owner_target = PI
		if _owner_anim:
			_owner_anim.play("idle_look", 0.4)
		return
	var target: Vector3 = _owner_path[0]
	var to := target - _owner.position
	to.y = 0.0
	if to.length() < 0.15:
		_owner_path.pop_front()
		return
	var yaw := atan2(-to.x, -to.z)
	_owner_yaw = rotate_toward(_owner_yaw, yaw, deg_to_rad(240.0) * delta)
	_owner.rotation.y = _owner_yaw
	_owner.position += to.normalized() * minf(1.4 * delta, to.length())


# ---------- Görüş alanları ----------

## Zürafa: belli aralıklarla başka bir yöne döner (kapı, raflar, tezgâh); bakarken bekler
func _update_owner(delta: float) -> void:
	_owner_hold -= delta
	if _owner_hold <= 0.0:
		_owner_hold = _rng.randf_range(1.8, 3.6)
		_owner_target = PI + _rng.randf_range(-0.9, 0.75)
	_owner_yaw = rotate_toward(_owner_yaw, _owner_target, deg_to_rad(55.0) * delta)
	_owner.rotation.y = _owner_yaw


func _update_watchers() -> void:
	var space := get_world_3d().direct_space_state
	var t := Time.get_ticks_msec() * 0.001
	var excl: Array[RID] = []
	if player:
		excl.append(player.get_rid())
	for w in _watchers:
		var origin: Vector3
		var yaw: float
		if w.kind == "zurafa":
			var head := _owner.position + Vector3.UP * 2.0
			if _owner_head >= 0:
				head = to_local(_owner_skel.global_transform * _owner_skel.get_bone_global_pose(_owner_head).origin)
			origin = Vector3(head.x, CONE_H, head.z)
			yaw = _owner_yaw
		else:
			var body: Node3D = w.node
			yaw = w.base + w.sweep * sin(t * 0.55 + w.phase)
			body.rotation = Vector3(-0.45, yaw, 0.0)
			origin = Vector3(body.position.x, CONE_H, body.position.z)
			w.led.visible = fmod(t, 1.0) < 0.5
		w["origin"] = origin
		w["yaw"] = yaw
		var dists := PackedFloat32Array()
		dists.resize(RAY_N)
		var fov: float = w.fov
		var rng: float = w.range
		for i in RAY_N:
			var a := yaw - fov * 0.5 + fov * i / (RAY_N - 1)
			var dir := Vector3(-sin(a), 0.0, -cos(a))
			var from := to_global(origin)
			var to := to_global(origin + dir * rng)
			var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, excl)
			var hit := space.intersect_ray(q)
			dists[i] = from.distance_to(hit.position) if not hit.is_empty() else rng
		w["dists"] = dists
		var mi: MeshInstance3D = w.mesh
		if mi.visible:
			var im: ImmediateMesh = mi.mesh
			im.clear_surfaces()
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			var c := Vector3(origin.x, 0.04, origin.z)
			for i in RAY_N - 1:
				var a0 := yaw - fov * 0.5 + fov * i / (RAY_N - 1)
				var a1 := yaw - fov * 0.5 + fov * (i + 1) / (RAY_N - 1)
				im.surface_add_vertex(c)
				im.surface_add_vertex(c + Vector3(-sin(a0), 0, -cos(a0)) * dists[i])
				im.surface_add_vertex(c + Vector3(-sin(a1), 0, -cos(a1)) * dists[i + 1])
			im.surface_end()


## Oyuncu bir görüş alanının içinde mi? (yakalanma yok: yalnız uyarı)
func _player_seen() -> bool:
	var lp := to_local(player.global_position)
	for w in _watchers:
		if not w.has("origin"):
			continue
		var o: Vector3 = w.origin
		var rel := Vector2(lp.x - o.x, lp.z - o.z)
		var dist := rel.length()
		if dist > w.range or dist < 0.3:
			continue
		var a := atan2(-rel.x, -rel.y)
		var da := wrapf(a - float(w.yaw), -PI, PI)
		var fov: float = w.fov
		if absf(da) > fov * 0.5:
			continue
		var fi := (da + fov * 0.5) / fov * (RAY_N - 1)
		var dists: PackedFloat32Array = w.dists
		var dd := lerpf(dists[int(floor(fi))], dists[mini(int(floor(fi)) + 1, RAY_N - 1)], fi - floor(fi))
		if dist < dd:
			return true
	return false


# ---------- Ekran yazıları (piksel) ----------

func _draw_ui() -> void:
	var size := _ui.get_viewport_rect().size
	var px := maxf(floorf(size.y / 120.0), 2.0)
	var shadow := Color(0.05, 0.04, 0.08, 0.8)
	if faz == Faz.KESIF or faz == Faz.KESIF_GIRIS:
		var title := "KÖR NOKTALARI EZBERLE"
		var s := px
		PixelArt.draw_text(_ui, title, Vector2(size.x * 0.5 - PixelArt.text_width(title, s) * 0.5, px * 6.0), s, Color(1, 1, 1, 0.9), shadow)
		if faz == Faz.KESIF:
			var left := str(ceili(KESIF_SURE - _t))
			var bs := px * 2.0
			PixelArt.draw_text(_ui, left, Vector2(size.x * 0.5 - PixelArt.text_width(left, bs) * 0.5, px * 16.0), bs, Color(1.0, 0.85, 0.3), shadow)
		# Lejant
		var ls := maxf(floorf(px * 0.6), 1.0)
		var y := size.y - px * 14.0
		_ui.draw_rect(Rect2(px * 4.0, y, px * 3.0, px * 3.0), Color(1.0, 0.85, 0.2))
		PixelArt.draw_text(_ui, "ZÜRAFA", Vector2(px * 8.5, y), ls, Color(1, 1, 1, 0.85), shadow)
		_ui.draw_rect(Rect2(px * 4.0, y + px * 5.0, px * 3.0, px * 3.0), Color(1.0, 0.3, 0.25))
		PixelArt.draw_text(_ui, "KAMERA", Vector2(px * 8.5, y + px * 5.0), ls, Color(1, 1, 1, 0.85), shadow)
	if _banner_t > 0.0 and _banner != "":
		var a := clampf(_banner_t / 0.5, 0.0, 1.0)
		var s := px
		PixelArt.draw_text(_ui, _banner, Vector2(size.x * 0.5 - PixelArt.text_width(_banner, s) * 0.5, size.y * 0.2), s,
			Color(1.0, 0.9, 0.4, 0.85 * a), Color(0.08, 0.04, 0.12, 0.6 * a))
	# Yakalanma: kararma ve yazı
	if faz == Faz.YAKALANDI and _fade > 0.0:
		_ui.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, _fade))
		if _ct > 0.5 and _ct < 2.0:
			var txt := "YAKALANDIN!"
			var s := px * 2.0
			var a := clampf((_ct - 0.5) / 0.25, 0.0, 1.0) * clampf((2.0 - _ct) / 0.3, 0.0, 1.0)
			PixelArt.draw_text(_ui, txt, Vector2(size.x * 0.5 - PixelArt.text_width(txt, s) * 0.5, size.y * 0.45), s,
				Color(1.0, 0.3, 0.25, a), Color(0.2, 0.0, 0.0, a))
