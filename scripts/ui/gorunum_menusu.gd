extends Control
## Görünüm ön ayarları: göz ikonuna basınca açılan piksel liste. Seçince uygulanır ve kapanır.

signal picked

var look: Node
var _rows: Array[Rect2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open_at(top_left: Vector2) -> void:
	var vh := get_viewport_rect().size.y
	var px := maxf(floorf(vh / 160.0), 2.0)
	var names: Array = []
	for p in look.PRESETS:
		names.append(String(p.name))
	var row_h := px * 13.0
	var w := 0.0
	for n in names:
		w = maxf(w, PixelArt.text_width(n, px))
	size = Vector2(w + px * 14.0, row_h * names.size() + px * 6.0)
	position = top_left
	_rows.clear()
	for i in names.size():
		_rows.append(Rect2(px * 3.0, px * 3.0 + i * row_h, size.x - px * 6.0, row_h))
	visible = true
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _rows.size():
			if _rows[i].has_point(event.position):
				look.preset_index = i
				look.apply()
				visible = false
				picked.emit()
				accept_event()
				return


func _draw() -> void:
	var vh := get_viewport_rect().size.y
	var px := maxf(floorf(vh / 160.0), 2.0)
	var r := Rect2(Vector2.ZERO, size)
	PixelArt._stepped_rect(self, r, px, Color(1, 1, 1, 0.85))
	PixelArt._stepped_rect(self, r.grow(-px), px, Color(0.08, 0.09, 0.12, 0.88))
	for i in _rows.size():
		var row := _rows[i]
		var cur: bool = look.preset_index == i
		if cur:
			draw_rect(row.grow(-px * 0.5), Color(1.0, 0.82, 0.25, 0.25))
		var name := String(look.PRESETS[i].name)
		var col := Color(1.0, 0.86, 0.3) if cur else Color(1, 1, 1, 0.9)
		PixelArt.draw_text(self, name, row.position + Vector2(px * 4.0, (row.size.y - px * 7.0) * 0.5), px, col)
		if cur:
			draw_rect(Rect2(row.position + Vector2(px, row.size.y * 0.5 - px), Vector2(px * 2, px * 2)), col)
