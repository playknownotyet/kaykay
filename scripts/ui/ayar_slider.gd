class_name AyarSlider
extends HSlider
## Ayar paneli kaydırıcısı: panelde aşağı kaydırırken yanlışlıkla değer değişmesin.
## Dokunuş önce yön seçer: belirgin yatay sürükleme değeri değiştirir; dikey sürükleme paneli
## kaydırır; dokunup bırakmak hiçbir şeyi değiştirmez.

const DECIDE_PX := 14.0

var _down := false
var _mode := 0            # 0 karar yok, 1 değer, 2 kaydırma
var _start := Vector2.ZERO
var _grab_value := 0.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_down = event.pressed
		if _down:
			_mode = 0
			_start = event.position
			_grab_value = value
		accept_event()
	elif event is InputEventMouseMotion and _down:
		var d: Vector2 = event.position - _start
		if _mode == 0 and d.length() > DECIDE_PX:
			_mode = 1 if absf(d.x) > absf(d.y) * 1.3 else 2
		if _mode == 1:
			# Göreli: parmağın kaydığı kadar (tutulan yerden atlamadan)
			var span := maxf(size.x, 1.0)
			value = clampf(_grab_value + (d.x / span) * (max_value - min_value), min_value, max_value)
		elif _mode == 2:
			var sc := _scroll_parent()
			if sc:
				sc.scroll_vertical -= int(event.relative.y)
		accept_event()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var sc := _scroll_parent()
		if sc:
			sc.scroll_vertical += 40 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -40
		accept_event()


func _scroll_parent() -> ScrollContainer:
	var n := get_parent()
	while n and not (n is ScrollContainer):
		n = n.get_parent()
	return n as ScrollContainer
