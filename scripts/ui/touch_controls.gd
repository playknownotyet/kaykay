extends Control
## Mobil dokunmatik kontroller.
##
## Sol yarı (ayak):
##   aşağı sürt = it (ayak parmağı izler)
##   iterken parmağı sağa kaydır = sola dön, sola kaydır = sağa dön
##   yukarı sürt = ilerlerken fren / dururken veya geri giderken ayakla geri it
## Sağ yarı (el):
##   yüzen analog joystick: dokunduğun yerde açılır; x = direksiyon
##   joystick'i hızlıca yukarı fırlat = ollie (ikinci parmakla yukarı kaydırmak da olur)
##
## Çoklu dokunuş için _input içinde ham ScreenTouch/ScreenDrag olaylarını
## işliyoruz. Ayar paneli gibi arayüz öğelerinin üstündeki dokunuşlar yok sayılır.

## Bu kontrollerin üstündeki dokunuşlar oyun girdisi sayılmaz.
var blockers: Array[Control] = []

const DECIDE_DIST := 0.02       # ekran yüksekliği oranı: it mi fren mi kararı
const OLLIE_DIST := 0.07
const OLLIE_TIME := 0.35
const BRAKE_MIN := 0.35
const FOOT_STEER_DEADZONE := 0.012
## Joystick ollie: bu kadar kısa sürede (sn) aşağıdan/ortadan yukarıya fırlatma
const FLICK_TIME := 0.18
const FLICK_FROM := 0.35
const FLICK_TO := 0.85

enum Zone { LEFT, RIGHT }

var _touches := {}               # index -> Dictionary
var _gesture_owner := -1          # sol tarafta ayak hareketini yöneten dokunuş
var _joy_owner := -1              # sağ tarafta joystick dokunuşu
var _joy_base := Vector2.ZERO
var _joy_knob := Vector2.ZERO     # -1..1 (y yukarı +)
var _flick_low_time := -10.0      # joystick en son aşağıda/ortada olduğu an
var _flick_armed := true
var _ollie_flash := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_ollie_flash = maxf(_ollie_flash - delta, 0.0)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position)


# ---------- Dokunuş olayları ----------

func _on_press(index: int, pos: Vector2) -> void:
	if _is_blocked(pos):
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
	if index == _gesture_owner:
		_gesture_owner = -1
		SkateInput.touch_gesture_end()
	if index == _joy_owner:
		_joy_owner = -1
		_joy_knob = Vector2.ZERO
		SkateInput.set_joystick(Vector2.ZERO)


func _on_drag(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	var h := get_viewport_rect().size.y
	var now := _now()
	var dt := maxf(now - t.last_time, 0.001)
	var finger_hps: float = (pos.y - t.pos.y) / h / dt
	t.pos = pos
	t.last_time = now

	if index == _gesture_owner:
		_left_drag(t, finger_hps)
	elif index == _joy_owner:
		_update_joystick()
	elif t.zone == Zone.RIGHT:
		_swipe_ollie(t)


func _left_drag(t: Dictionary, finger_hps: float) -> void:
	if SkateInput.on_foot:
		return  # yürürken ayak hareketi yok
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
		# İterken parmak sağa gidince sola, sola gidince sağa dön
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
	SkateInput.set_joystick(_joy_knob)

	# Hızlı yukarı fırlatma = ollie. Yavaşça yukarı itmek ollie yapmaz.
	var now := _now()
	if _joy_knob.y < FLICK_FROM:
		_flick_low_time = now
		_flick_armed = true
	elif _flick_armed and _joy_knob.y > FLICK_TO and now - _flick_low_time < FLICK_TIME:
		_flick_armed = false
		_fire_ollie()


func _swipe_ollie(t: Dictionary) -> void:
	if t.ollie_done:
		return
	var h := get_viewport_rect().size.y
	var d: Vector2 = t.pos - t.start
	if -d.y / h > OLLIE_DIST and absf(d.y) > absf(d.x) * 1.2 and _now() - t.time < OLLIE_TIME:
		t.ollie_done = true
		_fire_ollie()


func _fire_ollie() -> void:
	_ollie_flash = 0.25
	SkateInput.request_ollie()


# ---------- Joystick yerleşimi ----------

func _joy_radius() -> float:
	return get_viewport_rect().size.y * 0.13


func _joy_rest() -> Vector2:
	var size := get_viewport_rect().size
	var r := _joy_radius()
	return Vector2(size.x - r * 1.9, size.y - r * 1.7)


func _clamp_base(pos: Vector2) -> Vector2:
	var size := get_viewport_rect().size
	var r := _joy_radius()
	return Vector2(clampf(pos.x, size.x * 0.5 + r, size.x - r * 1.1), clampf(pos.y, r * 1.1, size.y - r * 1.1))


func _is_blocked(pos: Vector2) -> bool:
	for c in blockers:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


# ---------- Çizim ----------

func _draw() -> void:
	var size := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var fs := int(size.y * 0.026)
	var faint := Color(1, 1, 1, 0.35)
	var strong := Color(1, 1, 1, 0.8)

	var hint := "joystick: YÜRÜ" if SkateInput.on_foot else "aşağı: İT  ·  iterken yana: DÖN  ·  yukarı: FREN / GERİ"
	draw_string(font, Vector2(size.x * 0.04, size.y * 0.93), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, faint)

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
			var end: Vector2 = t.start + Vector2(0, dir * SkateInput.stroke_length * size.y)
			draw_line(end - Vector2(24, 0), end + Vector2(24, 0), Color(1, 1, 1, 0.5), 3.0)

	# Joystick
	var r := _joy_radius()
	if SkateInput.steer_mode == SkateInput.SteerMode.JOYSTICK or _joy_owner != -1:
		var base := _joy_base if _joy_owner != -1 else _joy_rest()
		var active := _joy_owner != -1
		draw_circle(base, r, Color(1, 1, 1, 0.14 if active else 0.08))
		draw_arc(base, r, 0, TAU, 40, strong if active else faint, 3.0)
		var dz := r * SkateInput.joystick_deadzone
		draw_arc(base, dz, 0, TAU, 20, Color(1, 1, 1, 0.2), 2.0)
		var knob := base + Vector2(_joy_knob.x, -_joy_knob.y) * r
		draw_circle(knob, r * 0.38, Color(1, 1, 1, 0.55 if active else 0.25))
		draw_string(font, base + Vector2(-r, -r - 12), "yukarı fırlat: OLLIE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, faint)
	if SkateInput.steer_mode == SkateInput.SteerMode.GYRO:
		draw_string(font, Vector2(size.x * 0.6, size.y * 0.5), "telefonu eğ: DÖN", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, faint)

	if _ollie_flash > 0.0:
		draw_string(font, Vector2(size.x * 0.62, size.y * 0.4), "OLLIE!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs * 2, Color(1, 0.9, 0.3, _ollie_flash * 4.0))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
