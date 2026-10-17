class_name YuklemeEkrani
extends Control
## Yükleme / kararma ekranı: bütün ekranı kaplar (iPhone çentiği ve köşeler dahil; güvenli alan
## yalnız yazılar için). Ortada piksel bir kaykay sallanarak yuvarlanır, altında "YÜKLENİYOR".
## Yakalanınca: kırmızı şerit ve "YAKALANDIN!" (sarsılarak), altında açıklama.

var alpha := 0.0
var loading := false            # kaykay ve yazı görünsün mü (yalnız kararmada değil)
var caught := false
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Kararmayı hedefe götür (await edilebilir). show_loading: kaykay animasyonu da çıksın
func fade_to(target: float, time: float, show_loading := false) -> void:
	if show_loading:
		loading = true
	visible = true
	var start := alpha
	var t := 0.0
	while t < time:
		await get_tree().process_frame
		t += get_process_delta_time()
		alpha = lerpf(start, target, clampf(t / time, 0.0, 1.0))
	alpha = target
	if target <= 0.0:
		visible = false
		loading = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	if alpha <= 0.0:
		return
	# Tam ekran (güvenli alan dışı da): kenardan sahne görünmesin
	var full := get_viewport_rect()
	var bg := Color(0.07, 0.06, 0.1, alpha) if not caught else Color(0.05, 0.0, 0.02, alpha)
	draw_rect(Rect2(full.position - Vector2(64, 64), full.size + Vector2(128, 128)), bg)
	var size := full.size
	var px := maxf(floorf(size.y / 120.0), 2.0)
	var a := clampf(alpha * 1.4 - 0.4, 0.0, 1.0)
	if a <= 0.0:
		return
	if caught:
		_draw_caught(size, px, a)
		return
	if not loading:
		return
	# Kaykay: tahta, kuyruk / burun kalkık, dönen tekerlekler; zıplayarak yuvarlanır
	var c := Vector2(size.x * 0.5, size.y * 0.47)
	var bob := absf(sin(_t * 6.0)) * px * 3.0
	var tilt := sin(_t * 3.0) * px * 0.8
	var deck := Color(0.93, 0.36, 0.3, a)
	var grip := Color(0.15, 0.13, 0.18, a)
	var wl := px * 12.0
	for i in range(-6, 7):
		var y := c.y - bob + tilt * i / 6.0
		if absf(i) == 6:
			y -= px
		draw_rect(Rect2(c.x + i * px * 2.0 - px, y - px, px * 2.0, px), grip)
		draw_rect(Rect2(c.x + i * px * 2.0 - px, y, px * 2.0, px), deck)
	for sx: float in [-1.0, 1.0]:
		var wc := Vector2(c.x + sx * wl * 0.62, c.y - bob + tilt * sx * 0.6 + px * 2.5)
		draw_rect(Rect2(wc - Vector2(px * 1.5, px * 1.5), Vector2(px * 3.0, px * 3.0)), Color(0.95, 0.9, 0.75, a))
		# Tekerlek dönüşü: tek koyu piksel çevrede döner
		var ang := _t * 12.0
		draw_rect(Rect2(wc + Vector2(cos(ang), sin(ang)) * px - Vector2(px * 0.5, px * 0.5), Vector2(px, px)), Color(0.4, 0.35, 0.3, a))
	# Gölge
	var sh := 1.0 - bob / (px * 3.0) * 0.4
	draw_rect(Rect2(c.x - wl * sh, c.y + px * 5.0, wl * 2.0 * sh, px), Color(0, 0, 0, 0.35 * a))
	var dots := ".".repeat(int(_t * 3.0) % 4)
	var txt := "YÜKLENİYOR" + dots
	var s := px
	PixelArt.draw_text(self, txt, Vector2(size.x * 0.5 - PixelArt.text_width("YÜKLENİYOR", s) * 0.5, c.y + px * 12.0), s,
		Color(1, 1, 1, 0.85 * a), Color(0, 0, 0, 0.5 * a))


func _draw_caught(size: Vector2, px: float, a: float) -> void:
	var band_h := px * 34.0
	var y0 := size.y * 0.45 - band_h * 0.5
	draw_rect(Rect2(-64, y0, size.x + 128, band_h), Color(0.62, 0.08, 0.1, 0.92 * a))
	for i in range(int(-64 / (px * 8.0)), int((size.x + 64) / (px * 8.0)) + 1):
		var x := i * px * 8.0 + fmod(_t * px * 30.0, px * 8.0)
		draw_rect(Rect2(x, y0, px * 4.0, px * 2.0), Color(1.0, 0.85, 0.2, 0.9 * a))
		draw_rect(Rect2(x, y0 + band_h - px * 2.0, px * 4.0, px * 2.0), Color(1.0, 0.85, 0.2, 0.9 * a))
	var txt := "YAKALANDIN!"
	var s := px * 2.0
	var shake := Vector2(sin(_t * 47.0), cos(_t * 39.0)) * px * maxf(0.0, 1.0 - _t * 0.0) * 0.6
	PixelArt.draw_text(self, txt, Vector2(size.x * 0.5 - PixelArt.text_width(txt, s) * 0.5, y0 + px * 8.0) + shake, s,
		Color(1.0, 0.95, 0.85, a), Color(0.25, 0.0, 0.0, a))
	var sub := "ALDIKLARIN GERİ ALINDI"
	var ss := maxf(floorf(px * 0.75), 1.0)
	PixelArt.draw_text(self, sub, Vector2(size.x * 0.5 - PixelArt.text_width(sub, ss) * 0.5, y0 + band_h - px * 9.0), ss,
		Color(1, 1, 1, 0.85 * a), Color(0, 0, 0, 0.5 * a))
