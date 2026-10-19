extends Control
## İlk açılışta (el tercihi hiç seçilmediyse) sorar: kaykayda sağlak mı, solak mı?
## Seçim user://kontrol.cfg'ye yazılır (SkateInput.set_sag_el); sonra ayarlardan değiştirilebilir.
## Ekran açıkken karakter durur.

var player: SkateController
var _rects := {}                 # "sag" / "sol" -> Rect2
var _hover := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if player:
		player.input_locked = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for k in _rects:
			if (_rects[k] as Rect2).has_point(event.position):
				_hover = k
				queue_redraw()
	elif event is InputEventMouseButton and not event.pressed and _hover != "":
		var k := _hover
		_hover = ""
		if (_rects[k] as Rect2).has_point(event.position):
			_choose(k == "sag")
	accept_event()


func _choose(sag: bool) -> void:
	SkateInput.set_sag_el(sag)
	if player:
		player.input_locked = false
	Haptics.pulse(15, 0.3)
	queue_free()


func _draw() -> void:
	var size := get_rect().size
	var vh := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.09, 0.82))
	var s := maxf(roundf(vh * 0.006), 2.0)
	var t1 := "KAYKAYDA HANGİ ELİNİ KULLANIYORSUN?"
	PixelArt.draw_text(self, t1, Vector2((size.x - PixelArt.text_width(t1, s)) * 0.5, vh * 0.14), s, Color(1.0, 0.86, 0.3))
	var bw := minf(size.x * 0.36, vh * 0.75)
	var bh := vh * 0.42
	var gap := vh * 0.06
	var y := vh * 0.3
	var specs := [
		["sag", "SAĞLAK", ["İTME VE FREN SAĞ YARIDA", "DİREKSİYON SOL ALTTA", "SAĞ AYAKLA İTER"]],
		["sol", "SOLAK", ["İTME VE FREN SOL YARIDA", "DİREKSİYON SAĞ ALTTA", "SOL AYAKLA İTER"]],
	]
	var x0 := (size.x - bw * 2.0 - gap) * 0.5
	for i in specs.size():
		var sp: Array = specs[i]
		var r := Rect2(Vector2(x0 + i * (bw + gap), y), Vector2(bw, bh))
		_rects[sp[0]] = r
		var px := maxf(floorf(vh / 160.0), 2.0)
		var lit: bool = _hover == sp[0]
		PixelArt._stepped_rect(self, r, px, Color(1.0, 0.82, 0.25) if lit else Color(1, 1, 1, 0.85))
		PixelArt._stepped_rect(self, r.grow(-px), px, Color(0.12, 0.13, 0.18, 0.95))
		var big := s * 1.6
		var title: String = sp[1]
		PixelArt.draw_text(self, title, Vector2(r.position.x + (bw - PixelArt.text_width(title, big)) * 0.5, y + bh * 0.14), big,
			Color(1.0, 0.86, 0.3) if lit else Color(1, 1, 1))
		var lines: Array = sp[2]
		var ls := maxf(s * 0.7, 2.0)
		for j in lines.size():
			var tx: String = lines[j]
			PixelArt.draw_text(self, tx, Vector2(r.position.x + (bw - PixelArt.text_width(tx, ls)) * 0.5, y + bh * 0.48 + j * ls * 11.0), ls,
				Color(0.8, 0.84, 0.9))
	var t2 := "SONRA AYARLARDAN DEĞİŞTİREBİLİRSİN"
	var s2 := maxf(s * 0.7, 2.0)
	PixelArt.draw_text(self, t2, Vector2((size.x - PixelArt.text_width(t2, s2)) * 0.5, y + bh + vh * 0.07), s2, Color(0.7, 0.74, 0.8))
