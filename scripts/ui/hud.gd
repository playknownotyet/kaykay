extends Control
## Ekran üstü bilgiler + canlı ayar paneli.
## Ayar panelindeki değerler telefonda kalıcı olarak saklanır (user://tuning.cfg).
## "Değerleri kopyala" butonu tüm ayarları panoya JSON olarak kopyalar;
## beğendiğin ayarları bana yapıştırırsan varsayılan yaparım.

const SAVE_PATH := "user://tuning.cfg"
## Kontrol şeması değişince eski kayıtlar yok sayılır.
const SAVE_VERSION := 3

var player: SkateController
var camera: Node
var visual: Node
var fx: Node
var look: Node
var touch_controls: Control
var _look_button: Button

var _speed_label: Label
var _panel: PanelContainer
var _settings_button: Button
var _respawn_button: Button
var _sliders := []        # [{obj, prop, slider, label, fmt}]
var _defaults := {}
var _mode_option: OptionButton
var _checks := []         # [{obj, prop, check}]


func setup(p_player: SkateController, p_camera: Node, p_visual: Node, p_fx: Node, p_look: Node, p_touch: Control) -> void:
	player = p_player
	camera = p_camera
	visual = p_visual
	fx = p_fx
	look = p_look
	touch_controls = p_touch
	_build()
	_capture_defaults()
	_load()
	_sync_widgets()
	touch_controls.blockers.assign([_panel, _settings_button, _respawn_button, _look_button])
	look.changed.connect(func(n: String):
		_look_button.text = "Görünüm: %s" % n
		_sync_widgets())
	_look_button.text = "Görünüm: %s" % look.preset_name()


func _specs() -> Array:
	# [nesne, özellik, min, max, adım, etiket]
	return [
		["İTME", null],
		[SkateInput, "stroke_length", 0.1, 0.5, 0.01, "Vuruş mesafesi (ekran oranı)"],
		[SkateInput, "swipe_to_mps", 1.0, 10.0, 0.1, "Parmak hızı → ayak hızı"],
		[SkateInput, "max_foot_speed", 4.0, 18.0, 0.5, "En yüksek ayak hızı (m/sn)"],
		[player, "push_grip", 0.5, 12.0, 0.1, "İtme kavrama gücü"],
		[SkateInput, "foot_steer_range", 0.02, 0.25, 0.005, "İterken yana kaydırma: tam dönüş mesafesi"],
		["SÜRÜŞ", null],
		[player, "rolling_resistance", 0.0, 1.5, 0.01, "Yuvarlanma direnci"],
		[player, "air_drag", 0.0, 0.05, 0.001, "Hava direnci"],
		[player, "max_speed", 6.0, 25.0, 0.5, "Azami hız (m/sn)"],
		[player, "gravity", 8.0, 25.0, 0.5, "Yerçekimi"],
		["FREN", null],
		[SkateInput, "brake_length", 0.05, 0.4, 0.01, "Tam fren mesafesi"],
		[player, "brake_strength", 1.0, 15.0, 0.1, "Fren gücü"],
		["GERİ İTME", null],
		[player, "reverse_efficiency", 0.1, 1.0, 0.05, "Geri itme verimi (düşük = daha çok efor)"],
		[player, "reverse_max_speed", 0.5, 6.0, 0.1, "En yüksek geri hız (m/sn)"],
		[SkateInput, "reverse_threshold", 0.0, 2.0, 0.05, "Bu hızın altında yukarı sürtme = geri it"],
		["DİREKSİYON", null],
		[player, "turn_radius", 1.0, 8.0, 0.1, "Dönüş yarıçapı (m)"],
		[player, "min_turn_rate", 0.2, 3.0, 0.05, "Yavaşken dönüş hızı"],
		[player, "max_turn_rate", 1.0, 5.0, 0.05, "En hızlı dönüş"],
		[SkateInput, "joystick_deadzone", 0.0, 0.5, 0.01, "Joystick ölü bölge"],
		[SkateInput, "joystick_curve", 1.0, 3.0, 0.05, "Joystick hassasiyet eğrisi"],
		[player, "steer_response", 1.0, 20.0, 0.5, "Klavye tepki hızı"],
		[player, "steer_return", 1.0, 20.0, 0.5, "Bırakınca düzelme hızı"],
		[visual, "lean_angle", 0.0, 35.0, 1.0, "Dönüşte eğilme (°)"],
		[SkateInput, "gyro_max_tilt_deg", 8.0, 45.0, 1.0, "Jiroskop: tam dönüş açısı"],
		["OLLIE / HAVA", null],
		[player, "ollie_speed", 2.0, 7.0, 0.1, "Ollie gücü"],
		[player, "air_steer_rate", 0.0, 5.0, 0.1, "Havada dönüş"],
		["GRIND", null],
		[player, "grind_latch_radius", 0.2, 1.5, 0.05, "Raya tutunma mesafesi (m)"],
		[player, "grind_max_angle", 20.0, 89.0, 1.0, "En dik giriş açısı (°)"],
		[player, "boardslide_angle", 5.0, 80.0, 1.0, "Bu açıdan dik = boardslide (°)"],
		[player, "grind_friction", 0.0, 4.0, 0.05, "Ray sürtünmesi"],
		[player, "grind_min_speed", 0.0, 8.0, 0.1, "En düşük grind hızı (m/sn)"],
		[player, "grind_exit_pop", 0.0, 4.0, 0.1, "Ray sonunda sıçrama"],
		[player, "grind_side_jump", 0.0, 6.0, 0.1, "Raydan yana atlama"],
		["KAMERA", null],
		[camera, "distance_slow", 1.2, 8.0, 0.1, "Mesafe (yavaş)"],
		[camera, "distance_fast", 1.5, 10.0, 0.1, "Mesafe (hızlı)"],
		[camera, "height_slow", 0.5, 4.0, 0.05, "Yükseklik (yavaş)"],
		[camera, "height_fast", 0.5, 4.0, 0.05, "Yükseklik (hızlı)"],
		[camera, "look_height", 0.3, 2.0, 0.05, "Bakış yüksekliği"],
		[camera, "fov_slow", 40.0, 90.0, 1.0, "Görüş açısı (yavaş)"],
		[camera, "fov_fast", 50.0, 110.0, 1.0, "Görüş açısı (hızlı)"],
		[camera, "fast_speed", 4.0, 16.0, 0.5, "Etkilerin tam güç hızı (m/sn)"],
		[camera, "follow_sharpness", 2.0, 20.0, 0.5, "Takip sıkılığı"],
		[camera, "vibration", 0.0, 0.05, 0.001, "Yol titreşimi"],
		["GÖRÜNÜM (ön ayarı değiştirince sıfırlanır)", null],
		[look.env, "adjustment_contrast", 0.5, 2.0, 0.01, "Kontrast"],
		[look.env, "adjustment_brightness", 0.5, 1.5, 0.01, "Parlaklık"],
		[look.env, "adjustment_saturation", 0.0, 2.5, 0.01, "Doygunluk"],
		[look.env, "tonemap_exposure", 0.3, 2.0, 0.01, "Pozlama"],
		[look, "pixel_size", 1.0, 8.0, 0.5, "Piksel boyutu"],
		[look, "posterize", 0.0, 64.0, 1.0, "Renk kademesi (0 = kapalı)"],
		[look, "dither", 0.0, 2.0, 0.05, "Dither"],
		[look, "vertex_snap", 0.0, 8.0, 0.5, "Poligon titremesi (0 = kapalı)"],
		["HIZ EFEKTİ", null],
		[fx, "warp", -1.0, 1.0, 0.01, "Bükülme (+ dıştan içe, - balıkgözü)"],
		[fx, "blur", 0.0, 0.2, 0.005, "Kenar bulanıklığı"],
		[fx, "aberration", 0.0, 0.03, 0.001, "Renk ayrışması"],
		[fx, "vignette", 0.0, 1.0, 0.01, "Kenar kararması"],
		[fx, "start", 0.0, 0.9, 0.01, "Efektin başladığı hız oranı"],
	]


func _process(_delta: float) -> void:
	if not player:
		return
	var kmh := absf(player.speed) * 3.6
	var state := "yerde" if player.grounded else "havada"
	if player.grinding:
		state = "%s %.1f sn" % ["50-50" if player.grind_style == 0 else "BOARDSLIDE", player.grind_time]
	_speed_label.text = "%d km/s  ·  %s  ·  %d FPS" % [roundi(kmh), state, Engine.get_frames_per_second()]


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


# ---------- Arayüz kurulumu ----------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vh := get_viewport_rect().size.y
	var theme_res := Theme.new()
	theme_res.default_font_size = int(vh * 0.03)
	theme = theme_res

	_speed_label = Label.new()
	_speed_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_speed_label.offset_top = 18
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_speed_label.add_theme_constant_override("outline_size", 6)
	add_child(_speed_label)

	var top := HBoxContainer.new()
	top.position = Vector2(12, 12)
	add_child(top)
	_settings_button = Button.new()
	_settings_button.text = "Ayarlar"
	_settings_button.custom_minimum_size = Vector2(0, vh * 0.08)
	_settings_button.pressed.connect(_toggle_panel)
	top.add_child(_settings_button)
	_respawn_button = Button.new()
	_respawn_button.text = "Başa dön"
	_respawn_button.custom_minimum_size = Vector2(0, vh * 0.08)
	_respawn_button.pressed.connect(func(): player.respawn(); camera.snap())
	top.add_child(_respawn_button)
	_look_button = Button.new()
	_look_button.custom_minimum_size = Vector2(0, vh * 0.08)
	_look_button.pressed.connect(func(): look.next(); _save())
	top.add_child(_look_button)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.position = Vector2(12, 12 + vh * 0.1)
	_panel.size = Vector2(get_viewport_rect().size.x * 0.46, vh * 0.86)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	# Direksiyon modu
	var mode_row := HBoxContainer.new()
	box.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "Direksiyon:"
	mode_row.add_child(mode_label)
	_mode_option = OptionButton.new()
	_mode_option.add_item("Joystick", SkateInput.SteerMode.JOYSTICK)
	_mode_option.add_item("Jiroskop", SkateInput.SteerMode.GYRO)
	_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_option.item_selected.connect(func(i: int):
		SkateInput.steer_mode = _mode_option.get_item_id(i)
		if SkateInput.steer_mode == SkateInput.SteerMode.GYRO:
			SkateInput.calibrate_gyro())
	mode_row.add_child(_mode_option)

	var gyro_row := HBoxContainer.new()
	box.add_child(gyro_row)
	var calib := Button.new()
	calib.text = "Jiroskop sıfırla"
	calib.pressed.connect(SkateInput.calibrate_gyro)
	gyro_row.add_child(calib)
	_add_check(gyro_row, SkateInput, "gyro_invert", "Ters")
	_add_check(gyro_row, SkateInput, "gyro_use_y", "Y ekseni")
	_add_check(gyro_row, fx, "enabled", "Hız efekti")

	var action_row := HBoxContainer.new()
	box.add_child(action_row)
	var copy := Button.new()
	copy.text = "Değerleri kopyala"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(JSON.stringify(_values(), "  ")))
	action_row.add_child(copy)
	var reset := Button.new()
	reset.text = "Varsayılana dön"
	reset.pressed.connect(_reset_defaults)
	action_row.add_child(reset)

	for spec in _specs():
		if spec[1] == null:
			var header := Label.new()
			header.text = "— %s —" % spec[0]
			header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			box.add_child(header)
			continue
		_add_slider(box, spec)


func _add_slider(box: VBoxContainer, spec: Array) -> void:
	var label := Label.new()
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = spec[2]
	slider.max_value = spec[3]
	slider.step = spec[4]
	slider.custom_minimum_size = Vector2(0, get_viewport_rect().size.y * 0.06)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(slider)
	var entry := {"obj": spec[0], "prop": spec[1], "slider": slider, "label": label, "name": spec[5]}
	_sliders.append(entry)
	slider.value_changed.connect(func(v: float):
		entry.obj.set(entry.prop, v)
		_update_label(entry))


func _add_check(row: HBoxContainer, obj: Object, prop: String, text: String) -> void:
	var check := CheckBox.new()
	check.text = text
	check.toggled.connect(func(on: bool): obj.set(prop, on))
	row.add_child(check)
	_checks.append({"obj": obj, "prop": prop, "check": check})


func _update_label(entry: Dictionary) -> void:
	entry.label.text = "%s: %s" % [entry.name, str(snappedf(entry.obj.get(entry.prop), 0.001))]


func _toggle_panel() -> void:
	_panel.visible = not _panel.visible
	if not _panel.visible:
		_save()


# ---------- Değer yönetimi ----------

func _key(obj: Object, prop: String) -> String:
	var owners := {SkateInput: "input", player: "player", camera: "camera", visual: "visual", fx: "fx", look: "look", look.env: "env"}
	return "%s.%s" % [owners[obj], prop]


func _all_entries() -> Array:
	# Ön ayar önce uygulanmalı, yoksa üstüne yazılan görünüm ayarlarını ezer
	var out := [[look, "preset_index"]]
	for e in _sliders:
		out.append([e.obj, e.prop])
	for c in _checks:
		out.append([c.obj, c.prop])
	out.append([SkateInput, "steer_mode"])
	return out


func _values() -> Dictionary:
	var d := {}
	for e in _all_entries():
		d[_key(e[0], e[1])] = e[0].get(e[1])
	return d


func _capture_defaults() -> void:
	_defaults = _values()


func _apply(values: Dictionary) -> void:
	for e in _all_entries():
		var k := _key(e[0], e[1])
		if values.has(k):
			e[0].set(e[1], values[k])


func _sync_widgets() -> void:
	for e in _sliders:
		e.slider.set_value_no_signal(e.obj.get(e.prop))
		_update_label(e)
	for c in _checks:
		c.check.set_pressed_no_signal(c.obj.get(c.prop))
	for i in _mode_option.item_count:
		if _mode_option.get_item_id(i) == SkateInput.steer_mode:
			_mode_option.select(i)


func _reset_defaults() -> void:
	_apply(_defaults)
	_sync_widgets()
	_save()


## Sadece varsayılandan farklı (oyuncunun değiştirdiği) değerler saklanır;
## böylece koddaki varsayılanlar güncellenince eski kayıt onları ezmez.
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	var values := _values()
	for k in values:
		if not _defaults.has(k) or not is_equal_approx(float(values[k]), float(_defaults[k])):
			cfg.set_value("tuning", k, values[k])
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if cfg.get_value("meta", "version", 0) != SAVE_VERSION:
		return
	var values := {}
	if not cfg.has_section("tuning"):
		return
	for k in cfg.get_section_keys("tuning"):
		values[k] = cfg.get_value("tuning", k)
	_apply(values)
