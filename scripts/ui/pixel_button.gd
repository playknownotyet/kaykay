class_name PixelButton
extends Button
## Yazısız, piksel ikonlu küçük buton (ayarlar, başa dön, görünüm).

@export var icon_name := "ayar"
@export var accent := Color(1.0, 0.82, 0.25)
## Açık/kapalı durumu gösteren butonlarda (görünüm menüsü) vurgulu çizilir
var lit := false


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	PixelArt.draw_button(self, Rect2(Vector2.ZERO, size), icon_name, is_pressed() or lit, accent)
