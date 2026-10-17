class_name SehirEditor
extends Node
## Oyun içi şehir editörü (bilgisayarda; Tab ile açılır / kapanır).
##
## Kamera adanın üstüne çıkar; araç çubuğundan seçilen şey haritaya yerleştirilir: süs binası,
## dükkân (tür ve tabela adıyla), Arnavut kaldırımlı ara sokak, merdiven, yükselti, korkuluk.
## Her değişiklik anında 3D'de kurulur (Sehir.rebuild); "Kaydet" assets/ada/sehir.json'a yazar
## (editörden çıkarken de kaydeder). Dünya ayrı bir düşük çözünürlüklü görüntüde (SubViewport)
## çizildiği için fare konumu ona ölçeklenip kameradan ışın atılır.
##
## Fare: sol tık yerleştir / seç ve sürükle; sağ ya da orta tuşla sürükle kaydır; tekerlek yakınlaştır.
## Klavye: WASD / oklar kaydır, Q / E döndür (Shift ile ince), Delete sil, Enter çizgiyi bitir,
## Esc vazgeç / seçimi bırak, Ctrl+Z geri al, Ctrl+S kaydet, T tepeden / eğik, Tab çık.

const TOOLS := [
	["sec", "Seç / taşı"], ["bina", "Bina"], ["dukkan", "Dükkân"], ["yol", "Ara sokak"],
	["merdiven", "Merdiven"], ["yukselti", "Yükselti"], ["korkuluk", "Korkuluk"], ["yesil", "Yeşil alan"], ["sil", "Sil"],
]
const COLORS := {
	"bina": Color(0.6, 0.85, 1.0), "dukkan": Color(1.0, 0.82, 0.3), "yol": Color(0.95, 0.75, 0.55),
	"merdiven": Color(1.0, 0.55, 0.25), "yukselti": Color(0.55, 1.0, 0.6), "korkuluk": Color(0.85, 0.85, 0.9),
	"yesil": Color(0.4, 0.9, 0.35),
}

var sehir: Sehir
var world: SubViewport
var player: SkateController
var follow_cam: Camera3D
var hide_while_open: Array[CanvasItem] = []

var is_open := false
var _cam: Camera3D
var _target := Vector3.ZERO          # kameranın baktığı yer (zeminde)
var _height := 60.0
var _top_down := false
var _lines: MeshInstance3D
var _line_mat: StandardMaterial3D
var _tool := "sec"
var _sel: Dictionary = {}
var _defaults := {}
var _temp: Array = []                # çizilmekte olan çizgi / merdivenin noktaları
var _hover := Vector3.INF
var _drag := false
var _drag_from := Vector2.ZERO
var _drag_orig := {}
var _pan := false
var _undo: Array[String] = []
var _dirty_t := -1.0
var _snap := true
## Yeni sıradan binalar karışık gelsin (stil, kat, çatı, zemin kat, ölçü): şehir tekrar etmesin
var _mixed := true
var _outline_cache := {}             # öğe kimliği -> PackedVector3Array
var _blocked := false                # sürüklenen öğe yol / kaldırımla çakışıyor (kırmızı)
var _rot_drag := false               # döndürme tutamacı sürükleniyor
var _rot_orig := 0.0
var _slider_drag := false
## Otomatik kayıt: her değişiklikten ~1 sn sonra dosyaya yazılır (pencere kapanınca iş kaybolmasın)
var _save_t := -1.0
## Mıknatıs: kenarlar bu kadar (m) yakınsa hizalanır / birleşir; açı bu kadar (derece) yakınsa eşitlenir
const MAGNET := 0.6
const MAGNET_DEG := 4.0
## Yol mıknatısı: kaldırıma bu açıdan (derece) yakınsa paralel olur, kenarı bu mesafeden (m) yakınsa yaslanır
const ROAD_DEG := 10.0
const ROAD_GAP := 1.8

var _layer: CanvasLayer
var _root: Control
var _tool_buttons := {}
var _props: VBoxContainer
var _status: Label
var _open_button: Button
var _font := 16


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.name = "EditorKamerasi"
	_cam.far = 2000.0
	_cam.fov = 55.0
	# Kare kare doğrudan taşınır: fizik ara değerlemesi tıklama ışınlarını eski konumdan atardı
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(_cam)
	_lines = MeshInstance3D.new()
	_lines.mesh = ImmediateMesh.new()
	_lines.visible = false
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.no_depth_test = true
	_line_mat.render_priority = 50
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_lines)
	for t in Sehir.VARSAYILAN:
		_defaults[t] = Sehir.VARSAYILAN[t].duplicate(true)
	_build_ui()


# ---------- Açma / kapama ----------

func open() -> void:
	if is_open:
		return
	is_open = true
	_target = player.global_position
	_height = 60.0
	player.input_locked = true
	_cam.make_current()
	_lines.visible = true
	_root.visible = true
	_open_button.visible = false
	for c in hide_while_open:
		c.visible = false
	_select({})
	_set_tool("sec")
	_update_camera()


func close(teleport := false) -> void:
	if not is_open:
		return
	if _dirty_t >= 0.0:
		_apply_rebuild()
	sehir.save()
	if teleport:
		var p := _ground_point_at_center()
		if p != Vector3.INF:
			player.global_position = p + Vector3.UP * 0.4
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
	is_open = false
	follow_cam.make_current()
	if follow_cam.has_method("snap"):
		follow_cam.snap()
	player.input_locked = false
	_lines.visible = false
	_root.visible = false
	_open_button.visible = true
	for c in hide_while_open:
		c.visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _save_t >= 0.0:
		sehir.save()


func _ground_point_at_center() -> Vector3:
	var vp := world.size
	return _ray_ground(Vector2(vp) * 0.5)


# ---------- Arayüz ----------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	var vh := get_viewport().get_visible_rect().size.y
	_font = int(maxf(vh * 0.022, 13.0))
	var theme := Theme.new()
	theme.default_font_size = _font
	_open_button = Button.new()
	_open_button.text = "Şehir editörü (Tab)"
	_open_button.theme = theme
	_open_button.focus_mode = Control.FOCUS_NONE
	# Sol üstteki HUD butonlarının sağında
	_open_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_open_button.offset_left = vh * 0.42
	_open_button.offset_top = vh * 0.06
	_open_button.pressed.connect(open)
	_open_button.visible = not OS.has_feature("mobile")
	_layer.add_child(_open_button)

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = theme
	_root.visible = false
	_layer.add_child(_root)

	# Sol: araçlar ve işlemler
	var left := PanelContainer.new()
	left.position = Vector2(vh * 0.02, vh * 0.02)
	_root.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	var title := Label.new()
	title.text = "ŞEHİR EDİTÖRÜ"
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	lv.add_child(title)
	var group := ButtonGroup.new()
	for t in TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if COLORS.has(t[0]):
			b.add_theme_color_override("font_color", COLORS[t[0]])
		b.pressed.connect(_set_tool.bind(t[0]))
		lv.add_child(b)
		_tool_buttons[t[0]] = b
	lv.add_child(HSeparator.new())
	var snap := CheckBox.new()
	snap.text = "Izgaraya otur (0,5 m)"
	snap.button_pressed = _snap
	snap.focus_mode = Control.FOCUS_NONE
	snap.toggled.connect(func(v: bool): _snap = v)
	lv.add_child(snap)
	for spec in [["Geri al (Ctrl+Z)", _do_undo], ["Kaydet (Ctrl+S)", _do_save], ["Burada oyna", close.bind(true)], ["Çık (Tab)", close.bind(false)]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		lv.add_child(b)

	# Sağ: seçili öğenin ya da yeni öğelerin özellikleri
	var right := PanelContainer.new()
	# Çapalara göre kenar boşlukları (ağaca eklenmeden önce de doğru)
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -vh * 0.46
	right.offset_right = -vh * 0.02
	right.offset_top = vh * 0.02
	_root.add_child(right)
	_props = VBoxContainer.new()
	right.add_child(_props)

	# Alt: durum ve kısa yardım
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = vh * 0.02
	bottom.offset_right = -vh * 0.02
	bottom.offset_top = -vh * 0.075
	bottom.offset_bottom = -vh * 0.015
	_root.add_child(bottom)
	_status = Label.new()
	bottom.add_child(_status)


func _set_tool(t: String) -> void:
	_tool = t
	_temp.clear()
	if _tool_buttons.has(t):
		_tool_buttons[t].button_pressed = true
	if t != "sec" and not (not _sel.is_empty() and String(_sel.t) == t):
		_select({})
	_refresh_props()
	_update_status()


func _update_status() -> void:
	var help := {
		"sec": "Sol tık: seç, sürükle: taşı (Alt: mıknatıssız) · Mavi çubuğun ucu: döndür (Shift: serbest) · Delete: sil",
		"bina": "Sol tık: bina koy / var olanı seç · Mavi çubuğun ucu: döndür · Q/E: yön · Alt: mıknatıssız",
		"dukkan": "Sol tık: dükkân koy (kapı tıkladığın yerde) / var olanı seç · Mavi çubuk: döndür",
		"yol": "Tıkla tıkla: sokak çiz · Enter / çift tık: bitir · Esc: vazgeç",
		"merdiven": "Alt uç ve üst ucu tıkla (yükseklikler zeminden)",
		"yukselti": "Sol tık: yükselti koy / var olanı seç · Mavi çubuk: döndür · Q/E: yön",
		"korkuluk": "Tıkla tıkla: korkuluk çiz · Enter / çift tık: bitir",
		"yesil": "Tıkla tıkla: çim alanın köşeleri · Enter / çift tık: bitir (en az 3 köşe)",
		"sil": "Sol tık: tıklanan öğeyi sil",
	}
	_status.text = "%s     |  Sağ / orta tuş: kaydır · Tekerlek: yakınlaştır · T: tepeden · Ctrl+S: kaydet · Tab: çık" % help.get(_tool, "")


## Özellik paneli: seçili öğe varsa onun, yoksa seçili aracın yeni öğe değerleri
func _refresh_props() -> void:
	for c in _props.get_children():
		c.queue_free()
	var it: Dictionary = _sel if not _sel.is_empty() else _defaults.get(_tool, {})
	var t: String = _sel.t if not _sel.is_empty() else _tool
	var head := Label.new()
	head.add_theme_color_override("font_color", COLORS.get(t, Color.WHITE))
	head.text = ("Seçili: " if not _sel.is_empty() else "Yeni: ") + _tool_name(t) if COLORS.has(t) else "Bir araç seç ya da öğeye tıkla"
	_props.add_child(head)
	if not COLORS.has(t):
		return
	match t:
		"bina":
			var kinds := []
			for kk in Sehir.BINA_TURLERI:
				kinds.append([kk, Sehir.BINA_TURLERI[kk].ad])
			_opt_str(it, "tur", "Tür", kinds, _set_bina_tur)
			var ev := String(it.get("tur", "ev")) == "ev"
			if ev:
				_opt(it, "s", "Stil", Sehir.STIL_ADLARI)
				_opt_str(it, "zemin", "Zemin kat", [["dukkan", "Dükkânlı (vitrin)"], ["konut", "Konut (pencere)"]])
			_text(it, "ad", "Tabela")
			_num(it, "w", "Genişlik (m)", 3.0, 40.0, 0.5)
			_num(it, "d", "Derinlik (m)", 3.0, 40.0, 0.5)
			_num(it, "k", "Kat", 1, 12, 1)
			_opt_str(it, "cati", "Çatı", [["duz", "Düz (parapet)"], ["besik", "Beşik (kiremit)"]])
			_num(it, "r", "Yön (derece)", -180.0, 180.0, 0.5)
			_rot_slider(it)
			if _sel.is_empty() and ev:
				var mx := CheckBox.new()
				mx.text = "Karışık (her yeni bina farklı)"
				mx.button_pressed = _mixed
				mx.focus_mode = Control.FOCUS_NONE
				mx.toggled.connect(func(v: bool): _mixed = v)
				_props.add_child(mx)
		"dukkan":
			var kinds := []
			for k in Sehir.DUKKAN_TURLERI:
				var tp: Dictionary = Sehir.DUKKAN_TURLERI[k]
				kinds.append([k, String(tp.ad) + ("" if tp.girilebilir else " (şimdilik dıştan)")])
			_opt_str(it, "tur", "Tür", kinds)
			_text(it, "ad", "Tabela")
			_num(it, "r", "Yön (derece)", -180.0, 180.0, 0.5)
			_rot_slider(it)
		"yol":
			_num(it, "w", "Genişlik (m)", 1.0, 8.0, 0.1)
		"merdiven":
			_num(it, "w", "Genişlik (m)", 1.0, 8.0, 0.1)
			_check(it, "korkuluk", "Korkuluk (grind)")
		"yukselti":
			_num(it, "w", "Genişlik (m)", 1.0, 40.0, 0.5)
			_num(it, "d", "Derinlik (m)", 1.0, 40.0, 0.5)
			_num(it, "h", "Yükseklik (m)", 0.2, 6.0, 0.1)
			_opt(it, "s", "Duvar", Sehir.STIL_ADLARI)
			_num(it, "r", "Yön (derece)", -180.0, 180.0, 0.5)
			_rot_slider(it)
		"korkuluk":
			_num(it, "h", "Yükseklik (m)", 0.3, 1.5, 0.05)
	if not _sel.is_empty():
		var del := Button.new()
		del.text = "Sil (Delete)"
		del.focus_mode = Control.FOCUS_NONE
		del.pressed.connect(_delete_selected)
		_props.add_child(del)


func _tool_name(t: String) -> String:
	for x in TOOLS:
		if x[0] == t:
			return x[1]
	return t


func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(_font * 7.5, 0)
	row.add_child(l)
	_props.add_child(row)
	return row


## Yön: sayı kutusunun altında kaydırma çubuğu (sürükledikçe döner)
func _rot_slider(it: Dictionary) -> void:
	var sl := HSlider.new()
	sl.min_value = -180.0
	sl.max_value = 180.0
	sl.step = 0.5
	sl.value = float(it.get("r", 0.0))
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(0, _font * 1.6)
	sl.drag_started.connect(func():
		_slider_drag = true
		if is_same(it, _sel):
			_push_undo())
	sl.drag_ended.connect(func(_c: bool):
		_slider_drag = false
		_refresh_props.call_deferred())
	sl.value_changed.connect(func(v: float):
		if not is_same(it, _sel):
			it["r"] = v
			return
		if not _slider_drag:
			_push_undo()
		var old: float = float(it.get("r", 0.0))
		it["r"] = v
		_magnet_rotation(it)
		_magnet_road(it)
		if sehir.overlaps_base(it):
			it["r"] = old
			_status.text = "Bu açıda yol / kaldırımla çakışıyor."
		_outline_cache.erase(int(it.id))
		_dirty_t = 0.0)
	_props.add_child(sl)


func _num(it: Dictionary, key: String, label: String, lo: float, hi: float, step: float) -> void:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = float(it.get(key, lo))
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(func(v: float): _set_prop(it, key, int(v) if step >= 1.0 and key == "k" else v))
	_row(label).add_child(sb)


func _opt(it: Dictionary, key: String, label: String, names: Array) -> void:
	var ob := OptionButton.new()
	for n in names:
		ob.add_item(n)
	ob.selected = clampi(int(it.get(key, 0)), 0, names.size() - 1)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.focus_mode = Control.FOCUS_NONE
	ob.item_selected.connect(func(i: int): _set_prop(it, key, i))
	_row(label).add_child(ob)


func _opt_str(it: Dictionary, key: String, label: String, pairs: Array, setter := Callable()) -> void:
	var ob := OptionButton.new()
	var cur := String(it.get(key, pairs[0][0]))
	for i in pairs.size():
		ob.add_item(pairs[i][1])
		if pairs[i][0] == cur:
			ob.selected = i
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.focus_mode = Control.FOCUS_NONE
	ob.item_selected.connect(func(i: int):
		if setter.is_valid():
			setter.call(it, pairs[i][0])
		else:
			_set_prop(it, key, pairs[i][0]))
	_row(label).add_child(ob)


## Bina türü değişince özel binanın ölçüleri ve çatısı gelir; panel yenilenir
func _set_bina_tur(it: Dictionary, v: String) -> void:
	if is_same(it, _sel):
		_push_undo()
	it["tur"] = v
	var spec: Dictionary = Sehir.BINA_TURLERI.get(v, {})
	for key in ["w", "d", "k", "cati"]:
		if spec.has(key):
			it[key] = spec[key]
	it["ad"] = ""
	if is_same(it, _sel):
		_dirty_t = 0.0
	_refresh_props.call_deferred()


func _text(it: Dictionary, key: String, label: String) -> void:
	var le := LineEdit.new()
	le.text = String(it.get(key, ""))
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_submitted.connect(func(s: String):
		_set_prop(it, key, s)
		le.release_focus())
	le.focus_exited.connect(func(): _set_prop(it, key, le.text))
	_row(label).add_child(le)


func _check(it: Dictionary, key: String, label: String) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = bool(it.get(key, true))
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(v: bool): _set_prop(it, key, v))
	_props.add_child(cb)


func _set_prop(it: Dictionary, key: String, v) -> void:
	if it.get(key) == v:
		return
	if is_same(it, _sel):
		_push_undo()
		var old = it.get(key)
		it[key] = v
		# Büyütünce / döndürünce yol, kaldırımla çakışırsa değişiklik geri alınır
		if sehir.overlaps_base(it):
			it[key] = old
			_undo.pop_back()
			_status.text = "Yol / kaldırım ile çakışıyor: değiştirilmedi."
			_refresh_props.call_deferred()
			return
		_dirty_t = 0.0
	else:
		it[key] = v


# ---------- Girdi ----------

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB and not OS.has_feature("mobile"):
			open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)


func _on_key(e: InputEventKey) -> void:
	var ctrl := e.ctrl_pressed or e.meta_pressed
	match e.physical_keycode:
		KEY_TAB:
			close(false)
		KEY_ESCAPE:
			if not _temp.is_empty():
				_temp.clear()
			else:
				_select({})
		KEY_ENTER, KEY_KP_ENTER:
			_finish_line()
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selected()
		KEY_Z:
			if ctrl:
				_do_undo()
		KEY_S:
			if ctrl:
				_do_save()
		KEY_T:
			_top_down = not _top_down
			_update_camera()
		KEY_Q, KEY_E:
			var step := 5.0 if e.shift_pressed else 15.0
			_rotate(-step if e.physical_keycode == KEY_Q else step)


func _rotate(deg: float) -> void:
	var it: Dictionary = _sel if not _sel.is_empty() else _defaults.get(_tool, {})
	if not it.has("r"):
		return
	if is_same(it, _sel):
		_push_undo()
	var old: float = float(it.get("r", 0.0))
	it["r"] = wrapf(old + deg, -180.0, 180.0)
	if is_same(it, _sel):
		if sehir.overlaps_base(it):
			it["r"] = old
			_undo.pop_back()
			_status.text = "Döndürünce yol / kaldırımla çakışıyor."
			return
		_outline_cache.erase(int(it.id))
		_dirty_t = 0.0
	_refresh_props()


func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
		_height = clampf(_height * 0.88, 8.0, 500.0)
		_update_camera()
	elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
		_height = clampf(_height / 0.88, 8.0, 500.0)
		_update_camera()
	elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
		_pan = e.pressed
		if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and not _temp.is_empty():
			_finish_line()
			_pan = false
	elif e.button_index == MOUSE_BUTTON_LEFT:
		var p := _ray_ground(_to_world(e.position))
		if e.pressed and _handle_hit(e.position):
			_push_undo()
			_rot_drag = true
			_rot_orig = float(_sel.get("r", 0.0))
			return
		if not e.pressed and _rot_drag:
			_rot_drag = false
			if sehir.overlaps_base(_sel):
				_sel["r"] = _rot_orig
				_status.text = "Döndürünce yol / kaldırımla çakışıyordu: eski açısına döndü."
			_blocked = false
			_outline_cache.erase(int(_sel.get("id", -1)))
			_dirty_t = 0.0
			_refresh_props()
			return
		if e.pressed:
			if p == Vector3.INF:
				return
			if e.double_click and (_tool == "yol" or _tool == "korkuluk" or _tool == "yesil"):
				_finish_line()
				return
			_click(p)
		else:
			if _drag:
				_drag = false
				# Yol / kaldırımın üstüne bırakıldıysa eski yerine döner
				if not _sel.is_empty() and sehir.overlaps_base(_sel):
					_move_item(_sel, _drag_orig, Vector2.ZERO)
					_status.text = "Yol / kaldırım ile çakışıyordu: eski yerine döndü."
				_blocked = false
				_outline_cache.erase(int(_sel.get("id", -1)))
				_dirty_t = 0.0


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if _pan:
		var k := _height / get_viewport().get_visible_rect().size.y * 1.15
		var fwd := Vector3(-_cam.global_basis.z.x, 0, -_cam.global_basis.z.z).normalized()
		if _top_down:
			fwd = Vector3(0, 0, -1)
		var right := Vector3(-fwd.z, 0, fwd.x)
		_target -= right * e.relative.x * k
		_target += fwd * e.relative.y * k
		_update_camera()
		return
	_hover = _ray_ground(_to_world(e.position))
	if _rot_drag and not _sel.is_empty() and _hover != Vector3.INF:
		var c := Sehir.v2(_sel.p)
		var ang := rad_to_deg(atan2(_hover.x - c.x, _hover.z - c.y))
		if not Input.is_key_pressed(KEY_SHIFT):
			ang = snappedf(ang, 1.0)
		_sel["r"] = wrapf(ang, -180.0, 180.0)
		if not Input.is_key_pressed(KEY_ALT):
			_magnet_rotation(_sel)
			_magnet_road(_sel)
		_outline_cache.erase(int(_sel.id))
		_blocked = sehir.overlaps_base(_sel)
		return
	if _drag and not _sel.is_empty() and _hover != Vector3.INF:
		var h := _snapped(_hover)
		var d := Vector2(h.x, h.z) - _drag_from
		_move_item(_sel, _drag_orig, d)
		if not Input.is_key_pressed(KEY_ALT):
			_magnet(_sel)
		_outline_cache.erase(int(_sel.id))
		_blocked = sehir.overlaps_base(_sel)


func _click(raw: Vector3) -> void:
	var p := _snapped(raw)
	var xz := Vector2(p.x, p.z)
	match _tool:
		"sec":
			var i := sehir.item_at(Vector2(raw.x, raw.z))
			_select(sehir.data.items[i] if i >= 0 else {})
			if i >= 0:
				_push_undo()
				_drag = true
				_drag_from = xz
				_drag_orig = _sel.duplicate(true)
		"sil":
			var i := sehir.item_at(Vector2(raw.x, raw.z))
			if i >= 0:
				_push_undo()
				sehir.remove(sehir.data.items[i])
				_outline_cache.clear()
		"bina", "dukkan", "yukselti":
			# Var olan bir öğeye tıklandıysa yenisini koyma: onu seç (taşı / özelliklerini değiştir)
			var hit := sehir.item_at(Vector2(raw.x, raw.z))
			if hit >= 0:
				_select(sehir.data.items[hit])
				_push_undo()
				_drag = true
				_drag_from = xz
				_drag_orig = _sel.duplicate(true)
				return
			_push_undo()
			var it := sehir.new_item(_tool)
			for k in _defaults[_tool]:
				it[k] = _defaults[_tool][k]
			if _tool == "bina" and _mixed and String(it.get("tur", "ev")) == "ev":
				_randomize_bina(it)
			it["p"] = [snappedf(xz.x, 0.01), snappedf(xz.y, 0.01)]
			if not Input.is_key_pressed(KEY_ALT):
				_magnet(it)
			# Hazır iskelet (asfalt, kaldırım...) baskın: üstüne konmaz
			if sehir.overlaps_base(it):
				_undo.pop_back()
				_status.text = "Buraya konamaz: yol / kaldırım ile çakışıyor. Boş araziye koy."
				return
			sehir.add(it)
			_outline_cache.clear()
			_select(it)
		"yol", "korkuluk", "yesil":
			_temp.append([snappedf(xz.x, 0.01), snappedf(xz.y, 0.01)])
		"merdiven":
			_temp.append([snappedf(xz.x, 0.01), snappedf(xz.y, 0.01)])
			if _temp.size() == 2:
				_push_undo()
				var it := sehir.new_item("merdiven")
				for k in _defaults.merdiven:
					it[k] = _defaults.merdiven[k]
				it["a"] = _temp[0]
				it["b"] = _temp[1]
				_temp.clear()
				sehir.add(it)
				_outline_cache.clear()
				_select(it)


# ---------- Mıknatıs (hafif hizalama) ----------

## Dikdörtgen öğenin dünyadaki gövdesi: merkez, yön, en, derinlik (dükkânda bina kısmı)
func _rect(it: Dictionary) -> Dictionary:
	match String(it.get("t", "")):
		"bina", "yukselti":
			return {"c": Sehir.v2(it.p), "r": float(it.get("r", 0.0)), "w": float(it.w), "d": float(it.d)}
		"dukkan":
			var b := sehir.shop_body_outline(it)
			return {"c": Sehir.v2(b.p), "r": float(b.r), "w": float(b.w), "d": float(b.d)}
	return {}


static func _axes(r_deg: float) -> Array:
	var r := deg_to_rad(r_deg)
	return [Vector2(cos(r), -sin(r)), Vector2(sin(r), cos(r))]     # yerel x ve z (dünya x, z düzleminde)


## Yakın komşunun açısına çok yakınsa (ya da 90°'nin katı farkla) aynı hizaya getir
func _magnet_rotation(it: Dictionary) -> void:
	var me := _rect(it)
	if me.is_empty():
		return
	var best := INF
	var fix := 0.0
	for o in sehir.data.items:
		if is_same(o, it):
			continue
		var ro := _rect(o)
		if ro.is_empty() or (ro.c as Vector2).distance_to(me.c) > 30.0:
			continue
		var dr := wrapf(float(ro.r) - float(me.r), -45.0, 45.0)
		if absf(dr) < MAGNET_DEG and absf(dr) > 0.001 and absf(dr) < best:
			best = absf(dr)
			fix = dr
	if best < INF:
		it["r"] = wrapf(float(it.get("r", 0.0)) + fix, -180.0, 180.0)


## Kenar mıknatısı: en yakın aynı hizadaki komşuya göre yan yana değme / kenar hizası / orta hizası
func _magnet(it: Dictionary) -> void:
	_magnet_rotation(it)
	var me := _rect(it)
	if me.is_empty():
		return
	var best_d := INF
	var shift := Vector2.ZERO
	for o in sehir.data.items:
		if is_same(o, it):
			continue
		var ro := _rect(o)
		if ro.is_empty():
			continue
		var rel: Vector2 = me.c - ro.c
		if rel.length() > 40.0:
			continue
		var diff := wrapf(float(me.r) - float(ro.r), -180.0, 180.0)
		var q := roundi(diff / 90.0)
		if absf(diff - q * 90.0) > 0.5:
			continue
		var ax: Array = _axes(float(ro.r))
		var lx := rel.dot(ax[0])
		var lz := rel.dot(ax[1])
		var mw := float(me.w) * 0.5
		var md := float(me.d) * 0.5
		if absi(q) % 2 == 1:
			var t := mw
			mw = md
			md = t
		var ow := float(ro.w) * 0.5
		var od := float(ro.d) * 0.5
		# Yalnız gerçekten yakın komşular (aralarında en çok birkaç metre)
		if absf(lx) > ow + mw + 3.0 or absf(lz) > od + md + 3.0:
			continue
		var dx := _snap_axis(lx, ow, mw)
		var dz := _snap_axis(lz, od, md)
		var score := minf(absf(dx), absf(dz))
		if score < best_d:
			best_d = score
			shift = (ax[0] as Vector2) * (dx if absf(dx) < MAGNET else 0.0) + (ax[1] as Vector2) * (dz if absf(dz) < MAGNET else 0.0)
	if best_d < MAGNET:
		for key in ["p"]:
			it[key] = [snappedf(float(it[key][0]) + shift.x, 0.01), snappedf(float(it[key][1]) + shift.y, 0.01)]
	_magnet_road(it)


## Yol mıknatısı: en yakın kaldırımın dış kenarına paralel döndür, en yakın kenarını boşluksuz yasla
func _magnet_road(it: Dictionary) -> void:
	var me := _rect(it)
	if me.is_empty():
		return
	var c: Vector2 = me.c
	var e := sehir.nearest_edge(c, maxf(float(me.w), float(me.d)) * 0.5 + ROAD_GAP + 2.0)
	if e.is_empty():
		return
	var t: Vector2 = (e.b - e.a).normalized()
	# Paralel: yerel z ya da x ekseni kenara paralel olacak en yakın açı
	var base := rad_to_deg(atan2(t.x, t.y))
	var r := float(it.get("r", 0.0))
	var best := INF
	var target := r
	for k in 4:
		var cand := base + k * 90.0
		var dr := wrapf(cand - r, -180.0, 180.0)
		if absf(dr) < absf(best):
			best = dr
			target = r + dr
	if absf(best) < ROAD_DEG:
		it["r"] = snappedf(wrapf(target, -180.0, 180.0), 0.01)
		me = _rect(it)
		c = me.c
	else:
		return
	# Yaslama: kenarın normali binaya doğru; merkezle kenar arası - binanın o yöndeki yarı boyu = boşluk
	var n := Vector2(-t.y, t.x)
	if (c - (e.a as Vector2)).dot(n) < 0.0:
		n = -n
	var ax: Array = _axes(float(me.r))
	var half := absf(n.dot(ax[0])) * float(me.w) * 0.5 + absf(n.dot(ax[1])) * float(me.d) * 0.5
	var ea: Vector2 = e.a
	var gap: float = (c - ea).dot(n) - half
	if gap > -0.6 and gap < ROAD_GAP:
		var mv: Vector2 = -n * (gap - 0.03)
		it["p"] = [snappedf(float(it.p[0]) + mv.x, 0.01), snappedf(float(it.p[1]) + mv.y, 0.01)]


## Bir eksende en yakın hedef: yan yana değme (±(o+m)), aynı kenar hizası (±(o-m)), ortalı (0)
static func _snap_axis(l: float, o: float, m: float) -> float:
	var best := INF
	for t in [o + m, -(o + m), o - m, -(o - m), 0.0]:
		var d: float = t - l
		if absf(d) < absf(best):
			best = d
	return best


# ---------- Döndürme tutamacı ----------

## Seçili öğenin döndürme tutamacı (ön yüzün ilerisinde): dünya konumu; yoksa INF
func _handle_pos() -> Vector3:
	if _sel.is_empty() or not _sel.has("r") or not _sel.has("p"):
		return Vector3.INF
	var c := Sehir.v2(_sel.p)
	var me := _rect(_sel)
	var R := maxf(float(me.get("w", 6.0)), float(me.get("d", 6.0))) * 0.5 + 2.0
	var r := deg_to_rad(float(_sel.r))
	var h := c + Vector2(sin(r), cos(r)) * R
	return Vector3(h.x, sehir.ground(h.x, h.y) + 0.3, h.y)


func _handle_hit(screen: Vector2) -> bool:
	var h := _handle_pos()
	if h == Vector3.INF or _cam.is_position_behind(h):
		return false
	var sp := _cam.unproject_position(h) * get_viewport().get_visible_rect().size / Vector2(world.size)
	return sp.distance_to(screen) < maxf(get_viewport().get_visible_rect().size.y * 0.035, 14.0)


## Karışık bina: stil, kat, çatı, zemin kat ve ölçü rastgele (yine de yakın aralıkta)
func _randomize_bina(it: Dictionary) -> void:
	it["s"] = randi() % Sehir.STIL_ADLARI.size()
	it["k"] = [1, 2, 2, 3, 3, 3, 4, 4, 5][randi() % 9]
	it["cati"] = "besik" if randf() < 0.45 else "duz"
	it["zemin"] = "dukkan" if randf() < 0.55 else "konut"
	it["w"] = snappedf(randf_range(6.5, 12.0), 0.5)
	it["d"] = snappedf(randf_range(6.5, 10.0), 0.5)


func _finish_line() -> void:
	if (_tool == "yol" or _tool == "korkuluk" or _tool == "yesil") and _temp.size() >= (3 if _tool == "yesil" else 2):
		_push_undo()
		var it := sehir.new_item(_tool)
		for k in _defaults[_tool]:
			it[k] = _defaults[_tool][k]
		it["pts"] = _temp.duplicate(true)
		sehir.add(it)
		_outline_cache.clear()
		_select(it)
	_temp.clear()


func _move_item(it: Dictionary, orig: Dictionary, d: Vector2) -> void:
	for key in ["p", "a", "b"]:
		if orig.has(key):
			it[key] = [snappedf(float(orig[key][0]) + d.x, 0.01), snappedf(float(orig[key][1]) + d.y, 0.01)]
	if orig.has("pts"):
		var pts := []
		for q in orig.pts:
			pts.append([snappedf(float(q[0]) + d.x, 0.01), snappedf(float(q[1]) + d.y, 0.01)])
		it["pts"] = pts


func _select(it: Dictionary) -> void:
	_sel = it
	_refresh_props()


func _delete_selected() -> void:
	if _sel.is_empty():
		return
	_push_undo()
	sehir.remove(_sel)
	_select({})
	_outline_cache.clear()


func _push_undo() -> void:
	_save_t = 0.0
	_undo.append(JSON.stringify(sehir.data.items))
	if _undo.size() > 60:
		_undo.pop_front()


func _do_undo() -> void:
	if _undo.is_empty():
		return
	var items = JSON.parse_string(_undo.pop_back())
	if items is Array:
		sehir.data.items = items
		_select({})
		_outline_cache.clear()
		sehir.rebuild()
		_save_t = 0.0


func _do_save() -> void:
	if _dirty_t >= 0.0:
		_apply_rebuild()
	if sehir.save():
		_status.text = "Kaydedildi: " + Sehir.DATA_PATH
	else:
		_status.text = "Kaydedilemedi!"


func _apply_rebuild() -> void:
	_dirty_t = -1.0
	_outline_cache.clear()
	sehir.rebuild()


# ---------- Kamera ve ışın ----------

func _to_world(screen: Vector2) -> Vector2:
	return screen * Vector2(world.size) / get_viewport().get_visible_rect().size


func _ray_ground(wp: Vector2) -> Vector3:
	var from := _cam.project_ray_origin(wp)
	var dir := _cam.project_ray_normal(wp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3000.0, 3)
	var hit := _cam.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit.position
	if absf(dir.y) > 0.001:
		var t := -from.y / dir.y
		if t > 0.0:
			return from + dir * t
	return Vector3.INF


func _snapped(p: Vector3) -> Vector3:
	if not _snap:
		return p
	return Vector3(snappedf(p.x, 0.5), p.y, snappedf(p.z, 0.5))


func _update_camera() -> void:
	if _top_down:
		_cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), _target + Vector3.UP * _height)
	else:
		var pos := _target + Vector3(0, _height, _height * 0.45)
		_cam.global_transform = Transform3D(Basis.looking_at(_target - pos, Vector3.UP), pos)


func _process(delta: float) -> void:
	if _save_t >= 0.0 and not _drag and not _rot_drag and not _slider_drag:
		_save_t += delta
		if _save_t > 1.0:
			_save_t = -1.0
			if _dirty_t >= 0.0:
				_apply_rebuild()
			sehir.save()
	if not is_open:
		return
	# Klavyeyle kaydırma (yazı kutusuna yazarken değil)
	var focus := _root.get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit):
		var mv := Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if mv != Vector2.ZERO:
			_target += Vector3(mv.x, 0, mv.y) * _height * 0.9 * delta
			_update_camera()
	if _dirty_t >= 0.0 and not _drag:
		_dirty_t += delta
		if _dirty_t > 0.12:
			_apply_rebuild()
	_draw_lines()


# ---------- Çizgiler (öğelerin sınırları) ----------

func _outline3(it: Dictionary) -> PackedVector3Array:
	var id := int(it.get("id", -1))
	if _outline_cache.has(id):
		return _outline_cache[id]
	var out := PackedVector3Array()
	for p in sehir.outline(it):
		out.append(Vector3(p.x, sehir.ground(p.x, p.y) + 0.15, p.y))
	_outline_cache[id] = out
	return out


func _draw_lines() -> void:
	var im: ImmediateMesh = _lines.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	var any := false
	for it in sehir.data.items:
		var ol := _outline3(it)
		var col: Color = COLORS.get(String(it.t), Color.WHITE)
		if is_same(it, _sel):
			col = Color(1, 0.25, 0.2) if _blocked else Color(1, 1, 0.2)
		else:
			col.a = 0.8
		for k in ol.size() - 1:
			im.surface_set_color(col)
			im.surface_add_vertex(ol[k])
			im.surface_set_color(col)
			im.surface_add_vertex(ol[k + 1])
			any = true
			if is_same(it, _sel):
				var up := Vector3.UP * 0.25
				im.surface_set_color(col)
				im.surface_add_vertex(ol[k] + up)
				im.surface_set_color(col)
				im.surface_add_vertex(ol[k + 1] + up)
	# Döndürme tutamacı: pivottan ön yüze doğru çubuk ve ucunda baklava
	var hp := _handle_pos()
	if hp != Vector3.INF:
		var c2 := Sehir.v2(_sel.p)
		var cp := Vector3(c2.x, sehir.ground(c2.x, c2.y) + 0.3, c2.y)
		var hc := Color(0.35, 0.95, 1.0)
		im.surface_set_color(hc)
		im.surface_add_vertex(cp)
		im.surface_set_color(hc)
		im.surface_add_vertex(hp)
		var s2 := maxf(_height * 0.015, 0.45)
		var ds := [Vector3(s2, 0, 0), Vector3(0, 0, s2), Vector3(-s2, 0, 0), Vector3(0, 0, -s2)]
		for q in 4:
			im.surface_set_color(hc)
			im.surface_add_vertex(hp + ds[q])
			im.surface_set_color(hc)
			im.surface_add_vertex(hp + ds[(q + 1) % 4])
		any = true
	# Çizilmekte olan çizgi ve fare imleci
	var pts: Array[Vector3] = []
	for q in _temp:
		var x := float(q[0])
		var z := float(q[1])
		pts.append(Vector3(x, sehir.ground(x, z) + 0.15, z))
	if _hover != Vector3.INF:
		pts.append(_snapped(_hover) + Vector3.UP * 0.15)
		var hc := _snapped(_hover) + Vector3.UP * 0.15
		var s := maxf(_height * 0.012, 0.3)
		for d in [Vector3(s, 0, 0), Vector3(0, 0, s)]:
			im.surface_set_color(Color(1, 1, 1))
			im.surface_add_vertex(hc - d)
			im.surface_set_color(Color(1, 1, 1))
			im.surface_add_vertex(hc + d)
			any = true
	if not _temp.is_empty():
		var col: Color = COLORS.get(_tool, Color.WHITE)
		for k in pts.size() - 1:
			im.surface_set_color(col)
			im.surface_add_vertex(pts[k])
			im.surface_set_color(col)
			im.surface_add_vertex(pts[k + 1])
			any = true
	if not any:
		im.surface_set_color(Color(0, 0, 0, 0))
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()
