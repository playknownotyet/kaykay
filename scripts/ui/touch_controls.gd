extends Control
## Mobil dokunmatik kontroller (çoklu dokunuş: ham ScreenTouch / ScreenDrag olayları).
##
## Kaykaydayken:
##   Sol yarı (ayak): aşağı sürt = it, iterken yana kaydır = dön, yukarı sürt = fren / geri it
##   Sağ yarı (el): yüzen joystick (x = direksiyon); hızlıca yukarı fırlat = ollie
##   İkon butonlar: kaykaydan in (sağ üst), arabaya tutun / bırak (yalnız uygunken)
## Yayayken:
##   Sol yarı: yüzen yürüme joystick'i (yarıya kadar yürü, sonuna kadar koş)
##   Sağ yarı: kamera joystick'i (sapma = dönüş hızı; bırakınca kamera karakterin arkasına
##   yavaşça kendiliğinden döner), zıpla ve etkileşim (kaykaya bin) butonları
##
## Butonlar burada çizilir ve dokunuşları burada işlenir: bir parmak yürürken öbürü zıplayabilir.

## Bu kontrollerin üstündeki dokunuşlar oyun girdisi sayılmaz (ayar paneli vb.).
var blockers: Array[Control] = []
var player: SkateController

const DECIDE_DIST := 0.02       # ekran yüksekliği oranı: it mi fren mi kararı
const OLLIE_DIST := 0.07
const OLLIE_TIME := 0.35
const BRAKE_MIN := 0.35
const FOOT_STEER_DEADZONE := 0.012
const FLICK_TIME := 0.18
const FLICK_FROM := 0.35
const FLICK_TO := 0.85

enum Zone { LEFT, RIGHT, BUTTON }
const ROUND := ["zipla", "bin", "koy"]


func _is_round(name: String) -> bool:
	return name in ROUND or name.begins_with("ctx:")

var _touches := {}               # index -> Dictionary
var _gesture_owner := -1          # sol: ayak hareketi (kaykay) ya da yürüme joystick'i (yaya)
var _joy_owner := -1              # sağ: direksiyon (kaykay) ya da kamera joystick'i (yaya)
var _joy_base := Vector2.ZERO
var _joy_knob := Vector2.ZERO     # -1..1 (y yukarı +)
var _move_base := Vector2.ZERO    # yaya: yürüme joystick'inin merkezi
var _move_knob := Vector2.ZERO
var _flick_low_time := -10.0
var _flick_armed := true
var _pressed := {}                # buton adı -> dokunuş indeksi


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		if player and not player.context_buttons.is_empty():
			player.press_context(player.context_buttons[0].id)
		return
	if event is InputEventKey and event.pressed and not event.echo and player:
		if event.physical_keycode == KEY_G:
			player.stow_held()
			return
		if event.physical_keycode == KEY_B:
			player.toggle_bag()
			return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position)


# ---------- Butonlar ----------

## Görünür butonlar: ad -> [dikdörtgen, ikon]
func _buttons() -> Dictionary:
	var size := get_viewport_rect().size
	var h := size.y
	var m := h * 0.04
	var out := {}
	if player == null:
		return out
	var busy := player.board_anim != SkateController.BoardAnim.NONE or player.fall_time > 0.0
	# Bağlam butonları (soygun, al, hazır...): sağda, zıplamanın üstünde dizilir
	if not player.context_buttons.is_empty():
		var cd := h * 0.15
		var r0 := _joy_radius()
		var base := Vector2(size.x - m - cd * 0.5, size.y * 0.5 - r0 * 1.6 if player.on_foot else size.y * 0.42)
		for i in player.context_buttons.size():
			var cb: Dictionary = player.context_buttons[i]
			var c := base - Vector2((cd + h * 0.03) * i, 0)
			out["ctx:" + String(cb.id)] = [Rect2(c - Vector2(cd, cd) * 0.5, Vector2(cd, cd)), cb.icon]
	if player.input_locked or player.held_in_air:
		return out
	if player.on_foot:
		# Kamera joystick'i sağ altta; zıplama onun üstünde, kaykaya binme zıplamanın sağında (yuvarlak)
		var r := _joy_radius()
		var stick := _joy_rest()
		var jd := h * 0.17
		var jc := Vector2(stick.x - r * 0.35, stick.y - r - h * 0.04 - jd * 0.5)
		out["zipla"] = [Rect2(jc - Vector2(jd, jd) * 0.5, Vector2(jd, jd)), "zipla"]
		var bd := h * 0.13
		var bc := Vector2(minf(jc.x + jd * 0.5 + h * 0.03 + bd * 0.5, size.x - m - bd * 0.5), jc.y + (jd - bd) * 0.5)
		if player.held_item != "":
			# Elde eşya varken binme yerine "çantaya at"
			if player.action_time <= 0.0 and not player.bag_open:
				out["koy"] = [Rect2(bc - Vector2(bd, bd) * 0.5, Vector2(bd, bd)), "koy"]
		elif not player.bag_open:
			out["bin"] = [Rect2(bc - Vector2(bd, bd) * 0.5, Vector2(bd, bd)), "bin"]
	else:
		var b := h * 0.12
		if not busy:
			out["in"] = [Rect2(size.x - m - b, m, b, b), "in"]
		var can_skitch := player.skitch_car != null or (player.skitch_candidate != null and player.grounded)
		if can_skitch and not busy:
			var s := h * 0.15
			out["tutun"] = [Rect2(size.x - m - s, m + b + h * 0.04, s, s), "birak" if player.skitch_car else "tutun"]
	return out


func _press_button(name: String) -> void:
	if name.begins_with("ctx:"):
		player.press_context(name.substr(4))
		return
	match name:
		"zipla":
			SkateInput.request_ollie()
		"bin", "in":
			SkateInput.request_board_toggle()
		"tutun":
			SkateInput.request_skitch()
		"koy":
			player.stow_held()


# ---------- Dokunuş olayları ----------

func _on_press(index: int, pos: Vector2) -> void:
	if _is_blocked(pos):
		return
	var btns := _buttons()
	for name in btns:
		var r: Rect2 = btns[name][0]
		var hit := pos.distance_to(r.get_center()) < r.size.x * 0.5 + get_viewport_rect().size.y * 0.015 if _is_round(name) 			else r.grow(get_viewport_rect().size.y * 0.012).has_point(pos)
		if hit:
			_pressed[name] = index
			_touches[index] = {"zone": Zone.BUTTON, "start": pos, "pos": pos, "time": _now(), "last_time": _now()}
			_press_button(name)
			return
	var size := get_viewport_rect().size
	var t := {
		"zone": Zone.LEFT if pos.x < size.x * 0.5 else Zone.RIGHT,
		"start": pos,
		"pos": pos,
		"time": _now(),
		"last_time": _now(),
		"mode": SkateInput.Gesture.NONE,
		"anchor_x": pos.x,
		"ollie_done": false,
	}
	_touches[index] = t
	if t.zone == Zone.LEFT and _gesture_owner == -1:
		_gesture_owner = index
		if SkateInput.on_foot:
			_move_base = _clamp_left(pos)
			_move_knob = Vector2.ZERO
			SkateInput.set_joystick(Vector2.ZERO)
	elif t.zone == Zone.RIGHT and _joy_owner == -1:
		_joy_owner = index
		_joy_base = _clamp_base(pos)
		_joy_knob = Vector2.ZERO
		_flick_low_time = _now()
		_flick_armed = true
		_update_joystick()


func _on_release(index: int) -> void:
	if not _touches.has(index):
		return
	_touches.erase(index)
	for name in _pressed.keys():
		if _pressed[name] == index:
			_pressed.erase(name)
	if index == _gesture_owner:
		_gesture_owner = -1
		SkateInput.touch_gesture_end()
		if SkateInput.on_foot:
			_move_knob = Vector2.ZERO
			SkateInput.set_joystick(Vector2.ZERO)
	if index == _joy_owner:
		_joy_owner = -1
		_joy_knob = Vector2.ZERO
		if SkateInput.on_foot:
			SkateInput.set_cam_stick(Vector2.ZERO)
		else:
			SkateInput.set_joystick(Vector2.ZERO)


func _on_drag(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	if t.zone == Zone.BUTTON:
		return
	var h := get_viewport_rect().size.y
	var now := _now()
	var dt := maxf(now - t.last_time, 0.001)
	var finger_hps: float = (pos.y - t.pos.y) / h / dt
	t.pos = pos
	t.last_time = now

	if index == _gesture_owner:
		if SkateInput.on_foot:
			var r := _joy_radius()
			var d: Vector2 = (pos - _move_base) / r
			# Parmak halkadan çok uzaklaşırsa joystick peşinden gelir (yönü kaybetmeden)
			if d.length() > 1.4:
				_move_base = pos - d.normalized() * r * 1.4
				d = (pos - _move_base) / r
			_move_knob = Vector2(d.x, -d.y).limit_length(1.0)
			SkateInput.set_joystick(_move_knob)
		else:
			_left_drag(t, finger_hps)
	elif index == _joy_owner:
		_update_joystick()
	elif t.zone == Zone.RIGHT and not SkateInput.on_foot:
		_swipe_ollie(t)


func _left_drag(t: Dictionary, finger_hps: float) -> void:
	var size := get_viewport_rect().size
	var dy: float = (t.pos.y - t.start.y) / size.y
	if t.mode == SkateInput.Gesture.NONE:
		if dy > DECIDE_DIST:
			t.mode = SkateInput.Gesture.PUSH
		elif dy < -DECIDE_DIST:
			t.mode = SkateInput.up_gesture_kind()
		if t.mode != SkateInput.Gesture.NONE:
			t.anchor_x = t.pos.x
			SkateInput.touch_gesture_begin(t.mode)

	if t.mode == SkateInput.Gesture.PUSH:
		SkateInput.touch_push_update(dy / SkateInput.stroke_length, finger_hps)
		var dx: float = (t.pos.x - t.anchor_x) / size.x
		var steer := 0.0
		if absf(dx) > FOOT_STEER_DEADZONE:
			steer = -(dx - signf(dx) * FOOT_STEER_DEADZONE) / SkateInput.foot_steer_range
		SkateInput.set_foot_steer(steer)
	elif t.mode == SkateInput.Gesture.REVERSE:
		SkateInput.touch_push_update(-dy / SkateInput.stroke_length, -finger_hps)
	elif t.mode == SkateInput.Gesture.BRAKE:
		var amount := clampf(-dy / SkateInput.brake_length, 0.0, 1.0)
		SkateInput.touch_brake_update(maxf(amount, BRAKE_MIN))


func _update_joystick() -> void:
	var t: Dictionary = _touches[_joy_owner]
	var r := _joy_radius()
	var d: Vector2 = (t.pos - _joy_base) / r
	_joy_knob = Vector2(d.x, -d.y).limit_length(1.0)
	if SkateInput.on_foot:
		SkateInput.set_cam_stick(_joy_knob)
		return
	SkateInput.set_joystick(_joy_knob)
	# Hızlı yukarı fırlatma = ollie. Yavaşça yukarı itmek ollie yapmaz.
	var now := _now()
	if _joy_knob.y < FLICK_FROM:
		_flick_low_time = now
		_flick_armed = true
	elif _flick_armed and _joy_knob.y > FLICK_TO and now - _flick_low_time < FLICK_TIME:
		_flick_armed = false
		SkateInput.request_ollie()


func _swipe_ollie(t: Dictionary) -> void:
	if t.ollie_done:
		return
	var h := get_viewport_rect().size.y
	var d: Vector2 = t.pos - t.start
	if -d.y / h > OLLIE_DIST and absf(d.y) > absf(d.x) * 1.2 and _now() - t.time < OLLIE_TIME:
		t.ollie_done = true
		SkateInput.request_ollie()


# ---------- Joystick yerleşimi ----------

func _joy_radius() -> float:
	return get_viewport_rect().size.y * 0.13


func _joy_rest() -> Vector2:
	var size := get_viewport_rect().size
	var r := _joy_radius()
	if SkateInput.on_foot:
		# Kamera joystick'i sağ altta dinlenir (butonlar üstünde)
		return Vector2(size.x - r * 1.6, size.y - r * 1.4)
	return Vector2(size.x - r * 1.9, size.y - r * 1.7)


func _move_rest() -> Vector2:
	var size := get_viewport_rect().size
	var r := _joy_radius()
	return Vector2(r * 1.9, size.y - r * 1.7)


func _clamp_base(pos: Vector2) -> Vector2:
	var size := get_viewport_rect().size
	var r := _joy_radius()
	return Vector2(clampf(pos.x, size.x * 0.5 + r, size.x - r * 1.1), clampf(pos.y, r * 1.1, size.y - r * 1.1))


func _clamp_left(pos: Vector2) -> Vector2:
	var size := get_viewport_rect().size
	var r := _joy_radius()
	return Vector2(clampf(pos.x, r * 1.1, size.x * 0.5 - r), clampf(pos.y, r * 1.1, size.y - r * 1.1))


func _is_blocked(pos: Vector2) -> bool:
	for c in blockers:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


# ---------- Çizim ----------

func _draw() -> void:
	var r := _joy_radius()
	if player and player.input_locked:
		var bl := _buttons()
		for name in bl:
			PixelArt.draw_round_button(self, bl[name][0], bl[name][1], _pressed.has(name))
		return
	if SkateInput.on_foot:
		var mb := _move_base if _gesture_owner != -1 else _move_rest()
		_draw_stick(mb, _move_knob, _gesture_owner != -1, r)
		var cb := _joy_base if _joy_owner != -1 else _joy_rest()
		_draw_stick(cb, _joy_knob, _joy_owner != -1, r * 0.85, true)
	else:
		# Ayak hareketi göstergesi
		if _gesture_owner != -1 and _touches.has(_gesture_owner):
			var t: Dictionary = _touches[_gesture_owner]
			var col := Color(1, 1, 1, 0.5)
			if t.mode == SkateInput.Gesture.PUSH:
				col = Color(0.4, 1.0, 0.6, 0.8)
			elif t.mode == SkateInput.Gesture.BRAKE:
				col = Color(1.0, 0.5, 0.4, 0.8)
			elif t.mode == SkateInput.Gesture.REVERSE:
				col = Color(0.5, 0.7, 1.0, 0.8)
			draw_circle(t.start, 14.0, Color(1, 1, 1, 0.3))
			draw_line(t.start, t.pos, col, 6.0)
			draw_circle(t.pos, 22.0, col)
			if t.mode == SkateInput.Gesture.PUSH or t.mode == SkateInput.Gesture.REVERSE:
				var dir := 1.0 if t.mode == SkateInput.Gesture.PUSH else -1.0
				var end: Vector2 = t.start + Vector2(0, dir * SkateInput.stroke_length * get_viewport_rect().size.y)
				draw_line(end - Vector2(24, 0), end + Vector2(24, 0), Color(1, 1, 1, 0.5), 3.0)
		if SkateInput.steer_mode == SkateInput.SteerMode.JOYSTICK or _joy_owner != -1:
			var base := _joy_base if _joy_owner != -1 else _joy_rest()
			_draw_stick(base, _joy_knob, _joy_owner != -1, r)
	var btns := _buttons()
	for name in btns:
		if _is_round(name):
			PixelArt.draw_round_button(self, btns[name][0], btns[name][1], _pressed.has(name))
		else:
			PixelArt.draw_button(self, btns[name][0], btns[name][1], _pressed.has(name))


## Joystick: halka, ölü bölge, topuz. Kamera joystick'inde dört yön oku (dönmeyi anlatır)
func _draw_stick(base: Vector2, knob: Vector2, active: bool, r: float, camera := false) -> void:
	var faint := Color(1, 1, 1, 0.3)
	var strong := Color(1, 1, 1, 0.8)
	draw_circle(base, r, Color(1, 1, 1, 0.14 if active else 0.07))
	draw_arc(base, r, 0, TAU, 40, strong if active else faint, 3.0)
	if camera:
		for a in [0.0, PI * 0.5, PI, PI * 1.5]:
			var tip := base + Vector2(cos(a), sin(a)) * r * 0.82
			var side := Vector2(-sin(a), cos(a)) * r * 0.09
			var back := base + Vector2(cos(a), sin(a)) * r * 0.66
			draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), faint)
	var k := base + Vector2(knob.x, -knob.y) * r
	draw_circle(k, r * 0.38, Color(1, 1, 1, 0.55 if active else 0.22))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
