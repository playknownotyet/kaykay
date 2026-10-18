extends Control
## Müzik çaların ekranı (320 x 240; MuzikCalar'ın SubViewport'unda çizilir, cihazın camına basılır).
## 2000'lerin renkli ekranı: üstte gri başlık şeridi (çalma durumu, pil), ortada kapak resmi,
## şarkı adı ve sanatçı, altta mavi ilerleme çubuğu ve süreler; döngü açıksa işareti.

var calar: MuzikCalar

const BG := Color(0.97, 0.97, 0.98)
const INK := Color(0.12, 0.12, 0.16)
const SOFT := Color(0.45, 0.47, 0.52)
const BLUE := Color(0.25, 0.5, 0.9)


func _draw() -> void:
	var W := size.x
	var H := size.y
	draw_rect(Rect2(0, 0, W, H), BG)
	if calar == null:
		return
	# Kapalı: kararmış cam (hafif yansıma). Açılırken: kısa açılış yazısı
	if not calar.player or not calar.player.music_power:
		draw_rect(Rect2(0, 0, W, H), Color(0.06, 0.07, 0.09))
		draw_colored_polygon(PackedVector2Array([Vector2(W * 0.55, 0), Vector2(W, 0), Vector2(W, H * 0.45)]), Color(1, 1, 1, 0.04))
		return
	if calar.boot_t > 0.0:
		var k := clampf((1.1 - calar.boot_t) / 0.35, 0.0, 1.0)
		draw_rect(Rect2(0, 0, W, H), Color(0.97, 0.97, 0.98).lerp(Color(0.06, 0.07, 0.09), 1.0 - k))
		var logo := "KAYPOD"
		PixelArt.draw_text(self, logo, Vector2((W - PixelArt.text_width(logo, 6.0)) * 0.5, H * 0.38), 6.0, Color(0.12, 0.12, 0.16, k))
		var bar := Rect2(W * 0.3, H * 0.66, W * 0.4, 8)
		draw_rect(bar, Color(0.8, 0.81, 0.84, k))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf((1.1 - calar.boot_t) / 1.0, 0.0, 1.0), bar.size.y)), Color(0.25, 0.5, 0.9, k))
		return
	if calar.st.is_empty():
		return
	var st: Dictionary = calar.st
	if calar.menu_open:
		_draw_menu(W, H)
		return
	var s := 2.0
	# Başlık şeridi (yukarıdan aşağı açılan gri)
	for i in 14:
		var t := i / 13.0
		draw_rect(Rect2(0, i * 2, W, 2), Color(0.86, 0.87, 0.9).lerp(Color(0.72, 0.74, 0.79), t))
	draw_rect(Rect2(0, 28, W, 2), Color(0.55, 0.57, 0.62))
	# Başlıkta çalan kaynak (Apple Music / Spotify / örnek liste)
	var head := String(st.get("source", "ŞİMDİ ÇALIYOR"))
	PixelArt.draw_text(self, head, Vector2((W - PixelArt.text_width(head, s)) * 0.5, 7), s, INK)
	# Sol üst: oynat / durdur
	if st.playing:
		draw_colored_polygon(PackedVector2Array([Vector2(10, 8), Vector2(22, 14), Vector2(10, 20)]), INK)
	else:
		draw_rect(Rect2(10, 8, 4, 12), INK)
		draw_rect(Rect2(17, 8, 4, 12), INK)
	# Sağ üst: pil
	draw_rect(Rect2(W - 34, 9, 22, 11), INK)
	draw_rect(Rect2(W - 12, 12, 3, 5), INK)
	draw_rect(Rect2(W - 32, 11, 18, 7), Color(0.4, 0.85, 0.35))
	# Kapak resmi: şarkının kapağı (Apple Music), yoksa şarkıya göre değişen piksel desen
	var art := Rect2(12, 40, 88, 88)
	if st.art is Texture2D:
		draw_rect(art, Color(0.3, 0.3, 0.34))
		draw_texture_rect(st.art, art.grow(-2), false)
	else:
		_cover(art, int(st.index))
	# Şarkı adı, sanatçı, sıra
	var x := 110.0
	_text_fit(String(st.title), Vector2(x, 44), W - x - 4, 3.5, INK)
	_text_fit(String(st.artist), Vector2(x, 80), W - x - 4, 3.0, SOFT)
	if int(st.count) > 0:
		PixelArt.draw_text(self, "%d/%d" % [int(st.index) + 1, int(st.count)], Vector2(x, 108), 3.0, SOFT)
	if st.get("shuffle", false):
		_shuffle_icon(Vector2(W - 62, 110))
	if st.loop:
		_loop_icon(Vector2(W - 34, 110))
	# İlerleme çubuğu
	var dur := float(st.dur)
	var pos := float(st.pos)
	var k := clampf(pos / dur, 0.0, 1.0) if dur > 0.0 else 0.0
	var bar := Rect2(12, 146, W - 24, 18)
	draw_rect(bar, Color(0.55, 0.57, 0.62))
	draw_rect(bar.grow(-2), Color(0.9, 0.91, 0.93))
	var fill := Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4) * k, bar.size.y - 4))
	for i in int(fill.size.y):
		draw_rect(Rect2(fill.position.x, fill.position.y + i, fill.size.x, 1), BLUE.lightened(0.35).lerp(BLUE, i / fill.size.y))
	var el := _mmss(pos)
	var rem := "-" + _mmss(dur - pos)
	PixelArt.draw_text(self, el, Vector2(12, 174), 3.5, INK)
	PixelArt.draw_text(self, rem, Vector2(W - 12 - PixelArt.text_width(rem, 3.5), 174), 3.5, INK)
	# Alt şerit: servis durumu
	var info := String(st.info)
	var hint := String(st.get("hint", ""))
	var iy := 214.0 if hint != "" else 218.0
	_text_fit(info, Vector2(maxf((W - PixelArt.text_width(info, 1.5)) * 0.5, 6.0), iy), W - 12, 1.5, SOFT)
	if hint != "":
		PixelArt.draw_text(self, hint, Vector2((W - PixelArt.text_width(hint, 1.0)) * 0.5, 229), 1.0, BLUE)


## Menü sayfası: başlık şeridi (sayfa adı), satırlar; seçili satır mavi şerit (beyaz yazı, alt sayfası
## varsa sağda ok), kullanılamayanlar gri ve notlu; uzun listelerde sağda kaydırma çubuğu
func _draw_menu(W: float, H: float) -> void:
	for i in 14:
		var t := i / 13.0
		draw_rect(Rect2(0, i * 2, W, 2), Color(0.86, 0.87, 0.9).lerp(Color(0.72, 0.74, 0.79), t))
	draw_rect(Rect2(0, 28, W, 2), Color(0.55, 0.57, 0.62))
	var pg := calar.menu_page()
	if pg.is_empty():
		return
	var sv: MuzikServisi = calar.servis
	var head := sv.page_title(pg.id)
	_text_fit(head, Vector2(maxf((W - PixelArt.text_width(head, 2.0)) * 0.5, 8.0), 7), W - 16, 2.0, INK)
	var n := sv.page_len(pg.id)
	var rows: int = MuzikCalar.MENU_ROWS
	var y := 34.0
	var rh := 44.0
	var bar_w := 8.0 if n > rows else 0.0
	for r in rows:
		var i := int(pg.top) + r
		if i >= n:
			break
		var it := sv.page_item(pg.id, i)
		var sel := i == int(pg.sel)
		if sel:
			for k in int(rh):
				draw_rect(Rect2(0, y + k, W - bar_w, 1), BLUE.lightened(0.3).lerp(BLUE.darkened(0.1), k / rh))
		var col := Color(1, 1, 1) if sel else (INK if it.enabled else SOFT.lightened(0.25))
		var sub := String(it.get("sub", ""))
		var ty := y + (7.0 if sub != "" else 14.0)
		_text_fit(String(it.label), Vector2(10, ty), W - bar_w - 34, 2.5, col)
		if sub != "":
			_text_fit(sub, Vector2(10, ty + 22), W - bar_w - 34, 1.5, col if sel else SOFT)
		if it.has("go"):
			var cy := y + rh * 0.5
			draw_colored_polygon(PackedVector2Array([Vector2(W - bar_w - 20, cy - 7), Vector2(W - bar_w - 12, cy), Vector2(W - bar_w - 20, cy + 7)]),
				col if sel else SOFT)
		draw_rect(Rect2(0, y + rh - 1, W - bar_w, 1), Color(0.85, 0.86, 0.89))
		y += rh
	if n > rows:
		var tr := Rect2(W - bar_w + 2, 34, bar_w - 4, rh * rows)
		draw_rect(tr, Color(0.86, 0.87, 0.9))
		var hh := maxf(tr.size.y * rows / n, 10.0)
		var yy := tr.position.y + (tr.size.y - hh) * (float(pg.top) / maxf(n - rows, 1))
		draw_rect(Rect2(tr.position.x, yy, tr.size.x, hh), BLUE)
	var help := "TEKERLEĞİ ÇEVİR: SEÇ   ORTA: TAMAM   MENU: GERİ"
	PixelArt.draw_text(self, help, Vector2((W - PixelArt.text_width(help, 1.0)) * 0.5, H - 12), 1.0, SOFT)


func _text_fit(t: String, p: Vector2, maxw: float, s: float, c: Color) -> void:
	while PixelArt.text_width(t, s) > maxw and t.length() > 3:
		t = t.left(t.length() - 2) + "."
	PixelArt.draw_text(self, t, p, s, c)


static func _mmss(sec: float) -> String:
	var v := maxi(int(sec), 0)
	return "%d:%02d" % [v / 60, v % 60]


func _shuffle_icon(c: Vector2) -> void:
	# Karışık: çapraz iki ok
	draw_line(c + Vector2(0, 2), c + Vector2(18, 16), BLUE, 3.0)
	draw_line(c + Vector2(0, 16), c + Vector2(18, 2), BLUE, 3.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(22, 0), c + Vector2(14, 0), c + Vector2(22, 8)]), BLUE)
	draw_colored_polygon(PackedVector2Array([c + Vector2(22, 18), c + Vector2(14, 18), c + Vector2(22, 10)]), BLUE)


func _loop_icon(c: Vector2) -> void:
	# Döngü: iki ok bir halkada
	draw_arc(c + Vector2(10, 7), 8.0, 0.4, PI - 0.4, 12, BLUE, 3.0)
	draw_arc(c + Vector2(10, 7), 8.0, PI + 0.4, TAU - 0.4, 12, BLUE, 3.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(15, -4), c + Vector2(21, 1), c + Vector2(13, 3)]), BLUE)
	draw_colored_polygon(PackedVector2Array([c + Vector2(5, 18), c + Vector2(-1, 13), c + Vector2(7, 11)]), BLUE)


## Kapak: gökyüzü rengi şarkıya göre; güneş, tepe ve küçük kaykay
func _cover(r: Rect2, i: int) -> void:
	var skies := [Color(1.0, 0.62, 0.35), Color(0.45, 0.7, 1.0), Color(0.25, 0.2, 0.45), Color(0.98, 0.82, 0.4), Color(0.4, 0.85, 0.85)]
	var sky: Color = skies[i % skies.size()]
	draw_rect(r, Color(0.3, 0.3, 0.34))
	var ir := r.grow(-2)
	for y in int(ir.size.y / 4):
		draw_rect(Rect2(ir.position.x, ir.position.y + y * 4, ir.size.x, 4), sky.lerp(sky.darkened(0.35), y / (ir.size.y / 4)))
	draw_circle(ir.position + Vector2(ir.size.x * 0.68, ir.size.y * 0.38), 13.0, Color(1.0, 0.95, 0.7))
	draw_colored_polygon(PackedVector2Array([ir.position + Vector2(0, ir.size.y * 0.72), ir.position + Vector2(ir.size.x * 0.45, ir.size.y * 0.55),
		ir.position + Vector2(ir.size.x, ir.size.y * 0.7), ir.end, ir.position + Vector2(0, ir.size.y)]), Color(0.18, 0.2, 0.26))
	var b := ir.position + Vector2(ir.size.x * 0.22, ir.size.y * 0.8)
	draw_rect(Rect2(b, Vector2(40, 6)), Color(0.98, 0.45, 0.12))
	draw_rect(Rect2(b + Vector2(-3, -3), Vector2(4, 4)), Color(0.98, 0.45, 0.12))
	draw_rect(Rect2(b + Vector2(39, -3), Vector2(4, 4)), Color(0.98, 0.45, 0.12))
	for wx in [6.0, 30.0]:
		draw_rect(Rect2(b + Vector2(wx, 6), Vector2(5, 5)), Color(0.35, 0.85, 0.55))
