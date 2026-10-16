extends Control
## Sırt çantası: sol kenarda çanta butonu; basınca karakter çantasını sırtından alıp açar ve
## envanter paneli gelir (4 göz, eşyaların piksel ikonları). Paneldeki çarpı ya da butona tekrar
## basmak kapatır (karakter çantayı sırtına takar). Kaykaydayken yalnız panel açılır.

var player: SkateController
var button: PixelButton
var _panel_rect := Rect2()
var _close_rect := Rect2()
var _anim := 0.0              # panel açılma (0..1)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vh := get_rect().size.y
	button = PixelButton.new()
	button.icon_name = "canta"
	var b := vh * 0.11
	button.size = Vector2(b, b)
	button.position = Vector2(vh * 0.04, vh * 0.5 - b * 0.5)
	button.pressed.connect(func(): player.toggle_bag())
	add_child(button)


func _process(delta: float) -> void:
	if not player:
		return
	# Panel, çanta açma animasyonu bitince gelir
	var show := player.bag_open and (not player.on_foot or player.action_time <= 0.0)
	_anim = move_toward(_anim, 1.0 if show else 0.0, delta * 6.0)
	# Sol kenarın ortası (güvenli alan içinde; telefon döndürülünce de)
	var vh := get_rect().size.y
	button.position = Vector2(vh * 0.04, vh * 0.5 - button.size.y * 0.5)
	button.lit = player.bag_open
	button.visible = not player.held_in_air and not player.input_locked
	mouse_filter = Control.MOUSE_FILTER_STOP if _anim > 0.5 else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _close_rect.grow(8).has_point(event.position):
			player.toggle_bag()
		accept_event()


func _draw() -> void:
	if _anim <= 0.0 or not player:
		_panel_rect = Rect2()
		return
	var size := get_rect().size
	var px := maxf(floorf(size.y / 140.0), 2.0)
	var slot := floorf(size.y * 0.15)
	var gap := px * 3.0
	var n := player.inventory.size()
	var w := slot * n + gap * (n - 1) + px * 12.0
	var h := slot + px * 22.0
	var k := ease(_anim, 0.5)
	var pos := Vector2(size.x * 0.5 - w * 0.5, size.y - h - px * 8.0 + (1.0 - k) * h * 0.6)
	_panel_rect = Rect2(pos, Vector2(w, h))
	var a := k
	PixelArt._stepped_rect(self, _panel_rect, px, Color(1, 1, 1, 0.85 * a))
	PixelArt._stepped_rect(self, _panel_rect.grow(-px), px, Color(0.1, 0.08, 0.12, 0.9 * a))
	PixelArt.draw_text(self, "ÇANTA", pos + Vector2(px * 6.0, px * 4.0), px, Color(1.0, 0.86, 0.3, a))
	# Kapat
	var cs := px * 9.0
	_close_rect = Rect2(pos + Vector2(w - cs - px * 4.0, px * 3.0), Vector2(cs, cs))
	PixelArt.draw_icon(self, "kapat", _close_rect.get_center(), cs, Color(1, 1, 1, 0.85 * a))
	for i in n:
		var r := Rect2(pos + Vector2(px * 6.0 + i * (slot + gap), px * 15.0), Vector2(slot, slot))
		PixelArt._stepped_rect(self, r, px, Color(1, 1, 1, 0.35 * a))
		PixelArt._stepped_rect(self, r.grow(-px), px, Color(0.18, 0.15, 0.22, 0.95 * a))
		var item: String = player.inventory[i]
		if item != "":
			var ic := Urunler.color(item)
			PixelArt.draw_icon(self, item, r.get_center(), slot * 0.7, Color(ic.r, ic.g, ic.b, a))
