extends Control
## Hız göstergesi (piksel yazı): büyük hız rakamı + KM/S, altında durum (grind süresi vb.),
## sağ üst köşede küçük FPS. Oyunun piksel görünümüyle aynı dil.

var player: SkateController
var _shown := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if player:
		_shown = lerpf(_shown, absf(player.speed) * 3.6, 1.0 - exp(-10.0 * delta))
	queue_redraw()


func _draw() -> void:
	if not player:
		return
	var size := get_viewport_rect().size
	var px := maxf(floorf(size.y / 120.0), 2.0)
	var shadow := Color(0.05, 0.05, 0.08, 0.85)

	# Hız: üst ortada küçük ve yarı saydam (yalnız kaykaydayken); birim daha da küçük
	var kmh := roundi(_shown)
	var num := str(kmh)
	var big := maxf(floorf(px * 0.75), 1.0)
	var unit_s := maxf(floorf(px * 0.5), 1.0)
	var w := PixelArt.text_width(num, big)
	var unit_w := PixelArt.text_width("KM/S", unit_s)
	var total := w + px * 1.5 + unit_w
	var x0 := size.x * 0.5 - total * 0.5
	var y0 := px * 4.0
	if not player.on_foot:
		var hot := clampf(_shown / 45.0, 0.0, 1.0)
		var col := Color(1.0, 0.97, 0.85, 0.7).lerp(Color(1.0, 0.65, 0.3, 0.8), hot)
		PixelArt.draw_text(self, num, Vector2(x0, y0), big, col, Color(0.05, 0.05, 0.08, 0.35))
		PixelArt.draw_text(self, "KM/S", Vector2(x0 + w + px * 1.5, y0 + big * 7.0 - unit_s * 7.0), unit_s, Color(1, 1, 1, 0.5))
	var big_h := big * 7.0

	# Durum satırı (yalnız anlamlıyken)
	var state := ""
	if player.grinding:
		state = "%s %.1f" % ["50-50" if player.grind_style == 0 else "BOARDSLIDE", player.grind_time]
	elif player.skitch_car:
		state = "TUTUNUYOR"
	if state != "":
		var ss := maxf(floorf(px * 0.5), 1.0)
		var sw := PixelArt.text_width(state, ss)
		PixelArt.draw_text(self, state, Vector2(size.x * 0.5 - sw * 0.5, y0 + big_h + px * 2.0), ss, Color(0.6, 0.95, 1.0, 0.6))

	# FPS: alt ortada küçük ve soluk
	var fps := "%d FPS" % Engine.get_frames_per_second()
	var fs := maxf(floorf(px * 0.5), 1.0)
	PixelArt.draw_text(self, fps, Vector2(size.x * 0.5 - PixelArt.text_width(fps, fs) * 0.5, size.y - fs * 11.0), fs, Color(1, 1, 1, 0.4), shadow)
