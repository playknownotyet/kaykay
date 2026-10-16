extends Control
## Numara yazısı (OLLIE!, KICKFLIP!, 50-50 ...): piksel yazı; büyük patlayıp yerine oturur,
## hafif sallanır, yukarı süzülerek söner. Art arda numaralar alt alta dizilir.

var player: SkateController
var _items: Array = []        # [{text, t, color, slot}]
const LIFE := 1.1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if player:
		player.ollied.connect(func():
			if not player.on_foot and not player.grinding:
				show_text("OLLIE!", Color(1.0, 0.86, 0.25)))
		player.double_jumped.connect(func(): show_text("KICKFLIP!", Color(0.45, 1.0, 0.6)))
		player.grind_started.connect(func():
			show_text("50-50!" if player.grind_style == 0 else "BOARDSLIDE!", Color(0.5, 0.85, 1.0)))
		player.skitch_changed.connect(func(on: bool):
			if on:
				show_text("TUTUN!", Color(1.0, 0.6, 0.3)))
		player.knocked_down.connect(func(): show_text("AHH!", Color(1.0, 0.35, 0.3)))


func show_text(text: String, color: Color) -> void:
	# Hâlâ görünen yazıların altına
	var slot := 0
	for it in _items:
		slot = maxi(slot, it.slot + 1)
	_items.append({"text": text, "t": 0.0, "color": color, "slot": slot % 3})


func _process(delta: float) -> void:
	for it in _items:
		it.t += delta
	_items = _items.filter(func(it): return it.t < LIFE)
	queue_redraw()


func _draw() -> void:
	var size := get_rect().size
	var px := maxf(floorf(size.y / 110.0), 2.0)
	for it in _items:
		var t: float = it.t
		# Küçük ve yarı saydam: kısa bir "pıt" büyümesiyle belirir, yukarı süzülüp söner
		var pop := 1.0 + 0.35 * exp(-t * 16.0)
		var s := maxf(floorf(px * 0.7 * pop), 1.0)
		var a := clampf((LIFE - t) / 0.35, 0.0, 1.0) * 0.72
		var rise := t * size.y * 0.035
		var text: String = it.text
		var w := PixelArt.text_width(text, s)
		var pos := Vector2(size.x * 0.5 - w * 0.5, size.y * 0.24 + it.slot * px * 7.0 - rise)
		var col: Color = it.color
		col.a = a
		PixelArt.draw_text(self, text, pos, s, col, Color(0.08, 0.04, 0.12, a * 0.6))
