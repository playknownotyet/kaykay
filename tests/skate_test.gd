extends Node
## Otomatik sürüş testi: ana sahneyi yükler, sanal parmak hareketleri gönderir
## ve sonuçları konsola yazar. Çalıştırma:
##   Godot --headless --path . res://tests/skate_test.tscn
## Ekran görüntüsü için (pencereli):
##   Godot --path . res://tests/skate_test.tscn -- --screenshot

var main: Node
var p: SkateController
var shots := false
var _held := {}


func _ready() -> void:
	shots = "--screenshot" in OS.get_cmdline_user_args()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	p = main.player
	await _run()
	get_tree().quit()


func _run() -> void:
	await _wait(0.5)
	_log("başlangıç")

	for i in 3:
		await _swipe_push(0.15, 2.0)
		await _wait(0.4)
		_log("itme %d (hızlı sürtme)" % (i + 1))
	await _swipe_push(0.6, 0.5)
	await _wait(0.2)
	_log("yavaş sürtme (yüksek hızda az etki beklenir)")

	if shots:
		await _wait(0.3)
		await _shot("01_surus")

	await _wait(3.0)
	_log("3 sn süzülme")

	var h0 := p.heading
	SkateInput.set_joystick(Vector2(1, 0))
	await _wait(1.0)
	SkateInput.set_joystick(Vector2.ZERO)
	_log("joystick 1 sn sağa, açı=%.0f° (negatif = sağ)" % rad_to_deg(h0.signed_angle_to(p.heading, Vector3.UP)))

	# Gerçek dokunuş olaylarıyla: aşağı it, sonra parmağı sağa kaydır -> sola dönmeli
	h0 = p.heading
	await _touch_path(0, [_sp(200, 200), _sp(200, 260), _sp(200, 320), _sp(200, 380)], 0.05, false)
	await _touch_path(0, [_sp(260, 380), _sp(320, 380)], 0.05, false)
	await _wait(0.8)
	await _touch_release(0, _sp(320, 380))
	_log("it + parmak sağa: açı=%.0f° (pozitif = sol)" % rad_to_deg(h0.signed_angle_to(p.heading, Vector3.UP)))

	var y0 := p.global_position.y
	SkateInput.request_ollie()
	var max_h := 0.0
	var air := 0.0
	for f in 120:
		await get_tree().physics_frame
		max_h = maxf(max_h, p.global_position.y - y0)
		if not p.grounded:
			air += 1.0 / 60.0
		if shots and f == 12:
			await _shot("02_ollie")
	_log("ollie: yükseklik=%.2f m, havada=%.2f sn" % [max_h, air])

	await _touch_path(0, [_sp(200, 400), _sp(200, 330), _sp(200, 280)], 0.05, false)
	await _wait(1.5)
	_log("yukarı sürt + basılı tut 1.5 sn: fren (hız 0)")
	await _wait(1.5)
	_log("basılı tutmaya devam: geri GİTMEMELİ (hız 0)")
	await _touch_release(0, _sp(200, 280))

	for i in 3:
		await _touch_path(0, [_sp(200, 500), _sp(200, 420), _sp(200, 340), _sp(200, 300)], 0.04, true)
		await _wait(0.35)
		_log("ayakla geri itme %d (hız < 0)" % (i + 1))
	await _wait(1.5)
	_log("geri süzülme 1.5 sn")

	# İtme anı (arkadan görünüm) ve yüksek hız efekti
	await _place(Vector3(0, 0.05, 0), Vector3.FORWARD, 2.0)
	await _wait(0.5)
	if shots:
		SkateInput.touch_gesture_begin(SkateInput.Gesture.PUSH)
		for i in 8:
			await get_tree().process_frame
			SkateInput.touch_push_update(0.45, 1.5)
		await _wait(0.15)
		await _shot("06_itme_arkadan")
		SkateInput.touch_gesture_end()
	await _place(Vector3(0, 0.05, 40), Vector3.FORWARD, 11.0)
	await _wait(1.5)
	_log("yüksek hız (efekt tam güç)")
	if shots:
		await _shot("07_yuksek_hiz")
		main.fx.enabled = false
		await _wait(0.05)
		await _shot("08_yuksek_hiz_efektsiz")
		main.fx.enabled = true

	await _place(Vector3(-28, 3.05, -40.5), Vector3.FORWARD, 0.0)
	await _wait(3.0)
	_log("tepeden 3 sn iniş (itmeden)")
	if shots:
		await _shot("03_tepe")

	await _place(Vector3(7, 0.05, -14), Vector3.FORWARD, 8.0)
	var max_y := 0.0
	var flew := 0.0
	for f in 150:
		await get_tree().physics_frame
		max_y = maxf(max_y, p.global_position.y)
		if not p.grounded:
			flew += 1.0 / 60.0
		if shots and f == 50:
			await _shot("04_kicker")
	_log("kicker: en yüksek=%.2f m, havada=%.2f sn" % [max_y, flew])

	await _place(Vector3(0, 0.05, -50), Vector3.FORWARD, 5.0)
	await _wait(2.5)
	_log("kaldırıma ollie'siz çarpma (z ~ -57.5'te durmalı)")

	await _place(Vector3(0, 0.05, -50), Vector3.FORWARD, 6.0)
	await _wait(1.05)
	SkateInput.request_ollie()
	await _wait(1.5)
	_log("kaldırım öncesi ollie (z < -58.5 olmalı)")

	await _place(Vector3(31, 0.05, -40), Vector3(1, 0, -0.3).normalized(), 7.0)
	await _wait(1.0)
	_log("bank'a çapraz giriş")
	if shots:
		await _shot("05_bank")

	# ---------- Grind ----------
	await _place(Vector3(4.5, 0.05, -2), Vector3.FORWARD, 6.0)
	await _wait(0.33)
	SkateInput.request_ollie()
	var r := await _watch_grind(3.0, "09_grind_5050")
	_log("50-50: süre=%.2f sn, stil=%s, çıkış z=%.1f (ray sonu -18)" % [r.time, r.style, r.exit_z])

	var dir := Vector3(sin(deg_to_rad(50)), 0, -cos(deg_to_rad(50)))
	await _place(Vector3(13, 0.05, -37), dir, 6.0)
	await _wait(0.25)
	SkateInput.request_ollie()
	r = await _watch_grind(3.0, "10_boardslide")
	_log("50° giriş: süre=%.2f sn, stil=%s (boardslide beklenir)" % [r.time, r.style])

	await _place(Vector3(4.5, 0.05, -2), Vector3.FORWARD, 6.0)
	await _wait(0.33)
	SkateInput.request_ollie()
	await _wait(0.6)
	var gx := p.global_position.x
	var was := p.grinding
	SkateInput.set_joystick(Vector2(1, 0))
	await _wait(0.05)
	SkateInput.request_ollie()
	await _wait(0.5)
	SkateInput.set_joystick(Vector2.ZERO)
	_log("grind ortasında ollie + sağ: grinddeydi=%s, x %.2f -> %.2f" % [was, gx, p.global_position.x])

	await _place(Vector3(-25.5, 3.05, -37), Vector3.FORWARD, 4.0)
	await _wait(0.85)
	SkateInput.request_ollie()
	r = await _watch_grind(5.0, "")
	_log("eğimli ray: süre=%.2f sn, en yüksek hız=%.1f m/s" % [r.time, r.max_speed])

	if shots:
		for i in main.look.PRESETS.size():
			main.look.preset_index = i
			await _place(Vector3(-3, 0.05, -44), Vector3(0.25, 0, -1).normalized(), 0.0)
			await _wait(0.6)
			await _shot("look_%d" % i)
		main.look.preset_index = 0


## Grind'i izler: süre, stil, çıkış konumu, en yüksek hız.
func _watch_grind(max_time: float, shot_name: String) -> Dictionary:
	var out := {"time": 0.0, "style": "-", "exit_z": 0.0, "max_speed": 0.0}
	var t := 0.0
	var started := false
	var shot_done := false
	while t < max_time:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if p.grinding:
			started = true
			out.time = p.grind_time
			out.style = "50-50" if p.grind_style == 0 else "boardslide"
			out.max_speed = maxf(out.max_speed, p.speed)
			if shots and shot_name != "" and not shot_done and p.grind_time > 0.5:
				shot_done = true
				await _shot(shot_name)
		elif started:
			out.exit_z = p.global_position.z
			break
	return out


## Sanal parmak: noktalar arasında sürükler. release=true ise sonunda bırakır.
func _touch_path(index: int, points: Array, step: float, release: bool) -> void:
	for i in points.size():
		var ev: InputEvent
		if i == 0 and not _held.has(index):
			ev = InputEventScreenTouch.new()
			ev.pressed = true
			_held[index] = true
		else:
			ev = InputEventScreenDrag.new()
		ev.index = index
		ev.position = points[i]
		Input.parse_input_event(ev)
		var t := 0.0
		while t < step:
			await get_tree().process_frame
			t += get_process_delta_time()
	if release:
		await _touch_release(index, points[-1])


## 1280x720 referans koordinatını gerçek ekran boyutuna çevirir.
func _sp(x: float, y: float) -> Vector2:
	var size := get_viewport().get_visible_rect().size
	# Olaylar pencere pikselinde verilir; oyun görüntü koordinatına çevirir.
	return get_viewport().get_final_transform() * Vector2(x / 1280.0 * size.x, y / 720.0 * size.y)


func _touch_release(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = false
	Input.parse_input_event(ev)
	_held.erase(index)
	await get_tree().process_frame


func _swipe_push(duration: float, finger_hps: float) -> void:
	SkateInput.touch_gesture_begin(SkateInput.Gesture.PUSH)
	var t := 0.0
	while t < duration:
		await get_tree().process_frame
		t += get_process_delta_time()
		SkateInput.touch_push_update(t / duration, finger_hps)
	SkateInput.touch_gesture_end()


func _place(pos: Vector3, heading: Vector3, speed: float) -> void:
	p.cancel_grind()
	p.grounded = true
	p.global_position = pos
	p.heading = heading
	p.speed = speed
	p.velocity = heading * speed
	p.reset_physics_interpolation()
	main.camera.snap()
	await get_tree().physics_frame


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/screens"))
	img.save_png("res://tests/screens/%s.png" % name)


func _log(label: String) -> void:
	var pos := p.global_position
	print("%-50s hız=%5.2f m/s  konum=(%.1f, %.2f, %.1f)  %s" % [
		label, p.speed, pos.x, pos.y, pos.z, "yerde" if p.grounded else "havada"])
