class_name MuzikCalar
extends Control
## Cep müzik çaları (2000'ler; model assets/muzikcalar/muzikcalar.glb, tools/blender/muzikcalar_build.py).
## Sol kenarda, çanta butonunun üstünde müzik çalar butonu; basınca cihaz ekranın alt ortasından
## yükselir. Ekran canlı: çalan şarkı, sanatçı, ilerleme çubuğu, döngü. Tıklama tekerleği:
##   üst (MENU): menü (Müzik: çalma listeleri / sanatçılar / albümler / şarkılar; Radyo; Şimdi çalıyor)
##   sağ: sonraki şarkı · sol: önceki (3 sn'den sonra başa sarar) · alt: oynat / durdur
##   orta düğme: döngü (şarkıyı tekrarla) aç / kapa
##   Menüde: parmağı tekerlekte çevirmek (ya da sağ / sol) seçimi kaydırır, orta düğme seçer, MENU geri.
## Müzik iPhone'da Apple Music (telefonun Müzik uygulaması), her yerde oyun içi radyo (MuzikServisi).
##   Sağ alt köşe: güç (kapatır). Cihazı cebe koymak: HUD'daki kulaklık butonu.
## Müzik iPhone'da telefonun Müzik uygulamasından gelir (Apple Music; MuzikServisi). Cihaz açılınca
## (güç) çalmaya başlar, güç düğmesiyle durur. Bilgisayarda örnek liste: ses yok, ekran ve tuşlar çalışır.

const GLB := preload("res://assets/muzikcalar/muzikcalar.glb")
const VC_SHADER := preload("res://shaders/toon_vc.gdshader")
const SCR_SIZE := Vector2i(320, 240)
## Cihazın ekrandaki kutusu (ekran yüksekliğine göre): alt ortada
const BOX_H := 0.40
const BOX_W := 0.43
## Cihazın üstünde kablonun yükselip silindiği boşluk (görüntü bu kadar uzar, dokunuşu almaz)
const CABLE_H := 0.2
const FOV := 22.0
const CAM_D := 0.285

var player: SkateController
var button: PixelButton
var is_open := false

var _k := 0.0                    # açılma (0..1)
var _view: TextureRect
var _hit: Control                # cihazın kutusu: dokunuşları alır, oyun kontrollerini kapatır
var _vp: SubViewport
var _cam: Camera3D
var _dev: Node3D
var _wheel: Node3D
var _center: Node3D
var _power: Node3D
var _scr_vp: SubViewport
var _scr: Control
var _press := ""                 # basılı tekerlek bölgesi (görsel geri bildirim)
var _press_t := 0.0

## Çalar: iPhone'da Apple Music, yoksa örnek liste (MuzikServisi); st: ekranın okuduğu güncel durum
var servis := MuzikServisi.new()
var st := {}
## Menü açık mı; sayfa yığını (her biri {id, sel, top}); ekranda görünen satır sayısı
var menu_open := false
var menu_stack: Array = []
const MENU_ROWS := 4
var _radio: AudioStreamPlayer
var _was_power := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vh := get_viewport_rect().size.y
	button = PixelButton.new()
	button.icon_name = "muzik"
	button.size = Vector2(vh * 0.11, vh * 0.11)
	button.pressed.connect(toggle)
	add_child(button)
	_build_view()
	_build_screen()
	# Oyun içi radyonun sesi (Apple Music telefonun Müzik uygulamasından çalar, bu düğüm kullanılmaz)
	_radio = AudioStreamPlayer.new()
	_radio.name = "Radyo"
	add_child(_radio)
	servis.set_radio_player(_radio)
	_layout()


## Buton / MENU: karakter cihazı çıkarır ya da cebine koyar (SkateController.toggle_music)
func toggle() -> void:
	if player:
		player.toggle_music()
	Haptics.pulse(15, 0.3)


# ---------- Kurulum ----------

func _build_view() -> void:
	_view = TextureRect.new()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.visible = false
	add_child(_view)
	_hit = Control.new()
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.visible = false
	_hit.gui_input.connect(_on_view_input)
	add_child(_hit)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_view.texture = _vp.get_texture()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.1
	_vp.add_child(sun)
	_cam = Camera3D.new()
	# Görüntü cihaz kutusundan CABLE_H kadar uzun: açı ona göre geniş, kamera yukarı kaydırılır
	# (v_offset: döndürmeden), cihaz ekranda yine kutunun içinde aynı boyda durur
	var hb := CAM_D * tan(deg_to_rad(FOV * 0.5))
	var hn := hb * (BOX_H + CABLE_H) / BOX_H
	_cam.fov = rad_to_deg(2.0 * atan(hn / CAM_D))
	_cam.v_offset = hn - hb
	_cam.near = 0.01
	_cam.far = 5.0
	_cam.position = Vector3(0, 0.0, CAM_D)
	_vp.add_child(_cam)
	_dev = Node3D.new()
	_vp.add_child(_dev)
	var model := GLB.instantiate()
	_dev.add_child(model)
	var mat := ShaderMaterial.new()
	mat.shader = VC_SHADER
	for n in ["Govde", "Tekerlek", "OrtaTus", "GucTus", "Fis"]:
		var mi := model.find_child(n, true, false) as MeshInstance3D
		if mi:
			mi.material_override = mat
	# Kablo: ucu saydamlaşır (köşe rengi alfası)
	var cable := model.find_child("Kablo", true, false) as MeshInstance3D
	if cable:
		var cm := StandardMaterial3D.new()
		cm.vertex_color_use_as_albedo = true
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.roughness = 0.6
		cable.material_override = cm
	_wheel = model.find_child("Tekerlek", true, false)
	_center = model.find_child("OrtaTus", true, false)
	_power = model.find_child("GucTus", true, false)
	var bud := model.find_child("Kulaklik", true, false) as Node3D
	if bud:
		bud.visible = false


func _build_screen() -> void:
	_scr_vp = SubViewport.new()
	_scr_vp.size = SCR_SIZE
	_scr_vp.disable_3d = true
	_scr_vp.transparent_bg = false
	_scr_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_scr_vp)
	_scr = preload("res://scripts/ui/muzik_ekran.gd").new()
	_scr.calar = self
	_scr.size = Vector2(SCR_SIZE)
	_scr_vp.add_child(_scr)
	var mi := _dev.find_child("Ekran", true, false) as MeshInstance3D
	if mi:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = _scr_vp.get_texture()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mi.material_override = m


## Buton çantanın üstünde; cihaz kutusu alt ortada
func _layout() -> void:
	var size := get_rect().size
	var vh := size.y
	var b := button.size.y
	button.position = Vector2(vh * 0.04, vh * 0.5 - b * 0.5 - b - vh * 0.03)
	var box := Vector2(vh * BOX_W, vh * (BOX_H + CABLE_H))
	_view.size = box
	_hit.size = Vector2(vh * BOX_W * 0.62, vh * BOX_H)
	var vp_size := Vector2i(int(box.x), int(box.y))
	if _vp.size != vp_size:
		_vp.size = vp_size


# ---------- Her kare ----------

func _process(delta: float) -> void:
	if not player:
		return
	_layout()
	button.visible = not player.held_in_air and not player.input_locked and not (IcMekan.instance and IcMekan.instance.is_inside())
	if not button.visible and player.music_open:
		player.close_music_now()
	# Yayayken cihaz, karakter kulaklıkları takıp cihaza bakmaya başlayınca ekrana gelir
	var taking_out := player.action_name.begins_with("muzik_cikar") and player.action_time > 0.25
	is_open = player.music_open and not taking_out
	if button.lit != player.music_open:
		button.lit = player.music_open
		button.queue_redraw()
	_k = move_toward(_k, 1.0 if is_open else 0.0, delta * 3.2)
	var shown := _k > 0.0
	_view.visible = shown
	_hit.visible = shown and _k > 0.9
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	_scr_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	# Çalar: güç açılınca (ilk seferde Müzik izni sorulur) çalar, kapanınca durur
	if player.music_power != _was_power:
		_was_power = player.music_power
		if _was_power:
			servis.ensure_access()
			servis.play()
		else:
			servis.pause()
	servis.update(delta)
	st = servis.state()
	if not shown:
		return
	# Ekranın alt ortasından yükselir; hafif yaylanarak oturur, hafif geriye eğik
	var size := get_rect().size
	var e := _ease_out_back(_k) if is_open else _k * _k
	var box := _view.size
	_view.position = Vector2((size.x - box.x) * 0.5, size.y - box.y * e)
	_hit.position = Vector2((size.x - _hit.size.x) * 0.5, _view.position.y + box.y - _hit.size.y)
	var t := Time.get_ticks_msec() / 1000.0
	_dev.rotation = Vector3(deg_to_rad(-8.0 + 4.0 * (1.0 - _k)), deg_to_rad(-13.0 + sin(t * 0.7) * 1.2), deg_to_rad(2.0 + sin(t * 0.5) * 0.6))
	_dev.position = Vector3(0, 0.004, 0)
	# Basılan bölge: tekerlek o yöne hafifçe batar
	_press_t = maxf(_press_t - delta, 0.0)
	var tilt := Vector2.ZERO
	if _press_t > 0.0:
		match _press:
			"ust": tilt = Vector2(-1, 0)
			"alt": tilt = Vector2(1, 0)
			"sag": tilt = Vector2(0, 1)
			"sol": tilt = Vector2(0, -1)
	if _wheel:
		var c := Vector3(0, -0.021, 0)
		var rot := Basis.from_euler(Vector3(tilt.x * 0.06, tilt.y * 0.06, 0))
		_wheel.transform = Transform3D(rot, c - rot * c)
	if _center:
		_center.position.z = -0.0004 if (_press == "orta" and _press_t > 0.0) else 0.0
	if _power:
		_power.position.z = -0.0004 if (_press == "guc" and _press_t > 0.0) else 0.0
	_scr.queue_redraw()


static func _ease_out_back(x: float) -> float:
	var c1 := 1.4
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


# ---------- Tıklama tekerleği ----------

## Tekerleğin ekrandaki yeri (görüntünün yerel koordinatı): merkez, yarıçap, orta düğme yarıçapı, güç düğmesi
func _wheel_geom() -> Dictionary:
	var k := _view.size / Vector2(_vp.size)
	var c := _cam.unproject_position(_dev.global_transform * Vector3(0, -0.021, 0.0055)) * k
	var edge := _cam.unproject_position(_dev.global_transform * Vector3(0.0195, -0.021, 0.0055)) * k
	var cr := _cam.unproject_position(_dev.global_transform * Vector3(0.0072, -0.021, 0.0055)) * k
	var gp := _cam.unproject_position(_dev.global_transform * Vector3(0.0215, -0.045, 0.0055)) * k
	return {"c": c, "R": c.distance_to(edge), "cr": c.distance_to(cr), "power": gp}


## Bir nokta tekerleğin hangi bölgesinde: "ust" (MENU), "sag", "alt", "sol", "orta", "guc" ya da ""
func _zone_at(p: Vector2, g: Dictionary) -> String:
	var R: float = g.R
	if p.distance_to(g.power) < R * 0.3:
		return "guc"
	var d: Vector2 = p - (g.c as Vector2)
	if d.length() > R * 1.08:
		return ""
	if d.length() <= float(g.cr) * 1.1:
		return "orta"
	var a := rad_to_deg(atan2(-d.y, d.x))
	if a > 45.0 and a <= 135.0:
		return "ust"
	elif a > -45.0 and a <= 45.0:
		return "sag"
	elif a > -135.0 and a <= -45.0:
		return "alt"
	return "sol"


var _touch_zone := ""
var _touch_ang := 0.0
var _spin := 0.0               # tekerlekte döndürülen açı (derece, saat yönü +)
var _spun := false

## Tekerlek: kısa dokunuş bırakınca bölgenin işi; menüdeyken parmağı tekerlekte çevirmek seçimi
## kaydırır (saat yönü aşağı, ~32°de bir satır), çevrildiyse bırakınca dokunuş sayılmaz
func _on_view_input(event: InputEvent) -> void:
	if _k < 0.9:
		return
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if mb == null and mm == null:
		return
	if mb and mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_hit.accept_event()
	var p := (event as InputEventMouse).position + _hit.position - _view.position
	var g := _wheel_geom()
	var d: Vector2 = p - (g.c as Vector2)
	if mb and mb.pressed:
		_touch_zone = _zone_at(p, g)
		_touch_ang = rad_to_deg(atan2(d.y, d.x))
		_spin = 0.0
		_spun = false
		if _touch_zone != "":
			_press = _touch_zone
			_press_t = 0.14
		return
	if mm:
		if _touch_zone == "" or _touch_zone == "orta" or _touch_zone == "guc" or d.length() < float(g.cr):
			return
		var ang := rad_to_deg(atan2(d.y, d.x))
		_spin += wrapf(ang - _touch_ang, -180.0, 180.0)
		_touch_ang = ang
		if menu_open:
			while absf(_spin) >= 32.0:
				var step := 1 if _spin > 0.0 else -1
				_spin -= 32.0 * step
				_spun = true
				_menu_move(step)
				Haptics.pulse(6, 0.15)
		return
	# Bırakıldı
	var zone := _touch_zone
	_touch_zone = ""
	if zone == "" or _spun:
		return
	_press = zone
	_press_t = 0.14
	if zone == "guc":
		Haptics.pulse(20, 0.4)
		menu_open = false
		player.music_power_off()
		return
	Haptics.pulse(12, 0.25)
	if menu_open:
		_menu_input(zone)
		return
	match zone:
		"ust":
			_open_menu()
		"sag":
			servis.next()
		"sol":
			servis.prev()
		"alt":
			servis.play_pause()
		"orta":
			servis.toggle_loop()


# ---------- Menü (MENU) ----------
# Sayfa yığını: her sayfa {id, sel, top}; MuzikServisi.page_* satırları verir.

func _open_menu() -> void:
	servis.refresh_library()
	menu_stack = [{"id": "kok", "sel": 0, "top": 0}]
	menu_open = true


func menu_page() -> Dictionary:
	return menu_stack[-1] if not menu_stack.is_empty() else {}


func _menu_move(step: int) -> void:
	var pg := menu_page()
	var n := servis.page_len(pg.id)
	if n <= 0:
		return
	pg.sel = clampi(int(pg.sel) + step, 0, n - 1)
	# Görünen pencere seçimi izler
	if pg.sel < pg.top:
		pg.top = pg.sel
	elif pg.sel >= int(pg.top) + MENU_ROWS:
		pg.top = int(pg.sel) - MENU_ROWS + 1


func _menu_input(zone: String) -> void:
	match zone:
		"ust":
			menu_stack.pop_back()
			if menu_stack.is_empty():
				menu_open = false
		"sag":
			_menu_move(1)
		"sol":
			_menu_move(-1)
		"orta", "alt":
			var pg := menu_page()
			var it := servis.page_item(pg.id, int(pg.sel))
			if not it.enabled:
				Haptics.pulse(40, 0.5)
			elif it.has("go"):
				menu_stack.append({"id": it.go, "sel": 0, "top": 0})
			elif it.has("act"):
				if servis.do_action(it.act):
					menu_open = false
					menu_stack.clear()


## Ekrana dokunma: oyundaki dokunmatik kontroller bu kutunun üstünde çalışmaz
func blocking_rect() -> Rect2:
	return _hit.get_global_rect() if _hit.visible else Rect2()
