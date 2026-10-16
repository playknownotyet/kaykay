extends Node
## Autoload: tüm oyuncu girdilerini (dokunmatik, klavye, jiroskop) tek yerde toplar.
## Kaykay kontrolcüsü yalnızca bu düğümdeki değerleri okur; girdinin nereden
## geldiğini bilmez.
##
## Sol taraf (ayak):
##   aşağı sürt          = ileri it (ayak parmağı izler)
##   yukarı sürt (hızlı) = fren
##   yukarı sürt (dururken / geri giderken) = ayakla geri it (daha çok efor)
##   iterken parmağı sağa/sola kaydır = ters yöne dön
## Sağ taraf: analog joystick (kaykayda direksiyon, ileride yürüme),
##   joystick'i hızlıca yukarı fırlat = ollie

enum SteerMode { JOYSTICK, GYRO }
enum Gesture { NONE, PUSH, BRAKE, REVERSE }

# --- Ayarlanabilir değerler (ayar panelinden değişir) ---
var steer_mode: int = SteerMode.JOYSTICK
## Tam bir itme için parmağın gitmesi gereken mesafe (ekran yüksekliği oranı).
var stroke_length := 0.5
## Fren tam güce ulaşmadan önce parmağın yukarı gitmesi gereken mesafe.
var brake_length := 0.15
## Parmak hızı (ekran yüksekliği/sn) -> ayak hızı (m/sn) çarpanı.
var swipe_to_mps := 7.9
var max_foot_speed := 9.5
## Bu hızın (m/sn) altında yukarı sürtmek fren değil, geri itmedir.
var reverse_threshold := 0.4
## İterken tam dönüş için parmağın yana gitmesi gereken mesafe (ekran genişliği oranı).
var foot_steer_range := 0.07
var joystick_deadzone := 0.1
## 1 = doğrusal, büyük değer = merkezde daha hassas.
var joystick_curve := 1.4
## Jiroskopta tam dönüş için gereken eğim açısı.
var gyro_max_tilt_deg := 19.0
var gyro_invert := false
var gyro_use_y := false

# --- Çıktılar (kontrolcü okur) ---
var steer_target := 0.0          # -1 sol, +1 sağ
var steer_is_digital := false    # klavyede yumuşak rampa uygulanır
var move_vector := Vector2.ZERO  # joystick (x sağ, y ileri); yürüme için de kullanılacak
## Yayayken kamera joystick'i (x sağa dön, y yukarı bak), ölü bölge ve eğri uygulanmış
var cam_stick := Vector2.ZERO
var _cam_raw := Vector2.ZERO
var gesture: int = Gesture.NONE
var push_progress := 0.0         # 0..1 itme vuruşunun neresindeyiz (ayak animasyonu)
var foot_contact := false        # ayak şu an yere basıp itiyor mu
var foot_speed := 0.0            # ayağın yere göre hızı (m/sn), itme yönünde pozitif
var brake := 0.0                 # 0..1

# --- Kontrolcü yazar ---
var board_speed := 0.0
var on_foot := false             # yürürken ayak hareketleri ve klavye itme kapalı

var _ollie_requested := false
var _board_toggle_requested := false
var _skitch_requested := false
var _finger_hps := 0.0           # parmak hızı, ekran yüksekliği/sn (itme yönünde +)
var _last_finger_update := 0.0
var _joystick := Vector2.ZERO
var _foot_steer := 0.0
var _touch_active := false
var _gyro_neutral := Vector3.ZERO

# Klavye ile otomatik itme vuruşu
var _kb_stroke_t := -1.0
var _kb_cooldown := 0.0
const KB_STROKE_TIME := 0.28
const KB_RECOVER_TIME := 0.3
const KB_FOOT_SPEED := 9.0


# ---------- Dokunmatik arayüzün çağırdığı fonksiyonlar ----------

## Sol taraf yukarı hareketin fren mi geri itme mi olacağına karar verir.
func up_gesture_kind() -> int:
	return Gesture.BRAKE if board_speed > reverse_threshold else Gesture.REVERSE


func touch_gesture_begin(kind: int) -> void:
	_touch_active = true
	gesture = kind
	push_progress = 0.0
	brake = 0.0
	foot_contact = kind == Gesture.PUSH or kind == Gesture.REVERSE


## progress: vuruşun ilerlemesi (0..1), finger_hps: itme yönündeki parmak hızı.
func touch_push_update(progress: float, finger_hps: float) -> void:
	push_progress = clampf(progress, 0.0, 1.0)
	_finger_hps = lerpf(_finger_hps, maxf(finger_hps, 0.0), 0.6)
	_last_finger_update = _now()
	# Vuruş sonuna gelince ayak yerden kalkar; parmak kaldırılana kadar itme biter.
	if push_progress >= 1.0:
		foot_contact = false


func touch_brake_update(amount: float) -> void:
	brake = clampf(amount, 0.0, 1.0)


func touch_gesture_end() -> void:
	_touch_active = false
	gesture = Gesture.NONE
	foot_contact = false
	brake = 0.0
	_finger_hps = 0.0
	_foot_steer = 0.0


func set_foot_steer(value: float) -> void:
	_foot_steer = clampf(value, -1.0, 1.0)


func set_joystick(v: Vector2) -> void:
	_joystick = v.limit_length(1.0)


func request_ollie() -> void:
	_ollie_requested = true


func consume_ollie() -> bool:
	var r := _ollie_requested
	_ollie_requested = false
	return r


func request_board_toggle() -> void:
	_board_toggle_requested = true


func consume_board_toggle() -> bool:
	var r := _board_toggle_requested
	_board_toggle_requested = false
	return r


func set_cam_stick(v: Vector2) -> void:
	_cam_raw = v.limit_length(1.0)


## Arabanın arkasına tutun / bırak
func request_skitch() -> void:
	_skitch_requested = true


func consume_skitch() -> bool:
	var r := _skitch_requested
	_skitch_requested = false
	return r


func set_on_foot(value: bool) -> void:
	on_foot = value
	touch_gesture_end()
	_kb_stroke_t = -1.0


func calibrate_gyro() -> void:
	_gyro_neutral = Input.get_gravity()


# ---------- Her kare ----------

func _process(delta: float) -> void:
	_update_keyboard(delta)

	# Parmak durduysa (drag olayı gelmiyorsa) hız sönümlenir.
	if _now() - _last_finger_update > 0.05:
		_finger_hps = move_toward(_finger_hps, 0.0, 12.0 * delta)
	if _kb_stroke_t < 0.0:
		foot_speed = minf(_finger_hps * swipe_to_mps, max_foot_speed)

	# Joystick: ölü bölge + hassasiyet eğrisi
	var j := _joystick
	var mag := j.length()
	if mag < joystick_deadzone:
		j = Vector2.ZERO
	else:
		var m := pow((mag - joystick_deadzone) / (1.0 - joystick_deadzone), joystick_curve)
		j = j / mag * m
	move_vector = j
	# Kamera joystick'i: küçük ölü bölge, ince ayar için kuvvetli eğri (ucunda hızlı döner)
	var c := _cam_raw
	var cm := c.length()
	cam_stick = Vector2.ZERO if cm < 0.08 else c / cm * pow((cm - 0.08) / 0.92, 1.7)
	var kc := Vector2(
		float(Input.is_physical_key_pressed(KEY_L)) - float(Input.is_physical_key_pressed(KEY_J)),
		float(Input.is_physical_key_pressed(KEY_I)) - float(Input.is_physical_key_pressed(KEY_K)))
	if kc != Vector2.ZERO:
		cam_stick = kc * 0.8
	if on_foot:
		# Yürürken klavye: W A S D / oklar
		var kb := Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
				- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
				- float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)))
		if kb != Vector2.ZERO:
			# Klavye: tuşlar koşturur, Shift basılıyken yürür
			var walk := Input.is_physical_key_pressed(KEY_SHIFT)
			move_vector = kb.normalized() * (0.65 if walk else 1.0)

	var kb_steer := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		kb_steer -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		kb_steer += 1.0

	if kb_steer != 0.0:
		steer_target = kb_steer
		steer_is_digital = true
	else:
		var hand := _gyro_steer() if steer_mode == SteerMode.GYRO else move_vector.x
		steer_target = clampf(hand + _foot_steer, -1.0, 1.0)
		steer_is_digital = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			request_ollie()
		elif event.physical_keycode == KEY_E:
			request_board_toggle()
		elif event.physical_keycode == KEY_Q:
			request_skitch()


func _update_keyboard(delta: float) -> void:
	if _touch_active or on_foot:
		return
	var push_key := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var back_key := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)

	# S: ilerlerken fren, dururken / geri giderken ayakla geri itme
	if back_key and _kb_stroke_t < 0.0 and up_gesture_kind() == Gesture.BRAKE:
		gesture = Gesture.BRAKE
		brake = 1.0
		foot_contact = false
		return
	elif gesture == Gesture.BRAKE:
		gesture = Gesture.NONE
		brake = 0.0

	_kb_cooldown = maxf(_kb_cooldown - delta, 0.0)
	if _kb_stroke_t < 0.0 and _kb_cooldown <= 0.0 and (push_key or back_key):
		_kb_stroke_t = 0.0
		gesture = Gesture.PUSH if push_key else Gesture.REVERSE
		foot_contact = true

	if _kb_stroke_t >= 0.0:
		_kb_stroke_t += delta
		push_progress = clampf(_kb_stroke_t / KB_STROKE_TIME, 0.0, 1.0)
		foot_speed = KB_FOOT_SPEED
		if push_progress >= 1.0:
			_kb_stroke_t = -1.0
			_kb_cooldown = KB_RECOVER_TIME
			gesture = Gesture.NONE
			foot_contact = false
			foot_speed = 0.0


func _gyro_steer() -> float:
	var g := Input.get_gravity() - _gyro_neutral
	var axis := g.y if gyro_use_y else g.x
	var tilt := axis / 9.81 / sin(deg_to_rad(gyro_max_tilt_deg))
	if gyro_invert:
		tilt = -tilt
	return clampf(tilt, -1.0, 1.0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
