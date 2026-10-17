extends Control
## Tam ekran harita (Navigasyon.open_map). Kuzey yukarı: ekran x = dünya x, ekran y = dünya z.
## Taban resim: assets/ada/harita.png (tools/ada/harita_bake.py); yollar ve yer adları harita.json;
## binalar, dükkânlar, yeşil alanlar, parklar canlı şehir verisinden (editörde değişince de doğru).
##
## Tek parmak: kaydır. İki parmak: yakınlaştır / uzaklaştır (pinch). Fare: sürükle, tekerlek.
## Kısa dokunuş: hedef koy (önemli bir yerin adına yakınsa tam oraya). Butonlar: kapat, beni
## ortala, hedefi kaldır.

const TEX := preload("res://assets/ada/harita.png")
const DATA_PATH := "res://assets/ada/harita.json"
const TAP_TIME := 0.35
const MIN_FIT := 1.0            # en uzak: ada ekrana sığar (çarpan)
const MAX_PX_PER_M := 14.0      # en yakın (ekran yüksekliği 720'ye göre)

const COL_BG := Color(0.15, 0.4, 0.58)
const COL_ROAD := Color(0.36, 0.35, 0.35)
const COL_ROAD_EDGE := Color(0.93, 0.92, 0.88)
const COL_ALLEY := Color(0.74, 0.66, 0.56)
const COL_HOUSE := Color(0.83, 0.72, 0.64)
const COL_HOUSE_EDGE := Color(0.55, 0.45, 0.4)
const COL_SHOP := Color(1.0, 0.74, 0.28)
const COL_SPECIAL := Color(0.58, 0.68, 0.98)
const COL_GREEN := Color(0.42, 0.72, 0.34)
const COL_PARK := Color(0.98, 0.62, 0.78)
const COL_PLAT := Color(0.7, 0.7, 0.72)

var nav: Navigasyon

static var _data: Dictionary = {}

var _center := Vector2.ZERO     # haritanın ekran ortasındaki dünya noktası (x, z)
var _zoom := 1.0                # ekran pikseli / metre
static var _last_zoom := -1.0

var _touches := {}              # index -> {pos, start, t, moved}
var _tap_ok := false
var _mouse_drag := false
var _mouse_last := Vector2.ZERO

# Canlı şehir verisinden bir kez hazırlanan çizimler
var _polys: Array = []          # [{pts: PackedVector2Array, col, edge}]
var _lines: Array = []          # [{pts, w, col}]
var _labels: Array = []         # [{p: Vector2, text, kind, pri}]
var _road_labels: Array = []    # [{p, text}]

var _close_btn: PixelButton
var _me_btn: PixelButton
var _clear_btn: PixelButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _data.is_empty():
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = j if j is Dictionary else {"origin": -608.5, "px": 1.0, "roads": [], "places": []}
	_prepare()
	var vs := get_viewport_rect().size
	var vh := vs.y
	_zoom = _last_zoom if _last_zoom > 0.0 else vh / 380.0
	_zoom = clampf(_zoom, _min_zoom(), _max_zoom())
	var pp := nav.player.global_position
	_center = Vector2(pp.x, pp.z)
	_clamp_center()
	var b := vh * 0.1
	var m := vh * 0.04
	var ins := GuvenliAlan.insets(get_viewport())
	_close_btn = _button("kapat", Vector2(m + ins.x, m + ins.y), b)
	_close_btn.pressed.connect(func(): nav.close_map())
	_me_btn = _button("ortala", Vector2(vs.x - ins.z - m - b, vs.y - ins.w - m - b), b)
	_me_btn.pressed.connect(func():
		var q := nav.player.global_position
		_center = Vector2(q.x, q.z)
		_clamp_center()
		queue_redraw())
	_clear_btn = _button("pinsil", Vector2(vs.x - ins.z - m - b, vs.y - ins.w - m * 1.5 - b * 2.0), b)
	_clear_btn.pressed.connect(func():
		nav.clear_destination()
		queue_redraw())


func _exit_tree() -> void:
	_last_zoom = _zoom


func _button(icon: String, pos: Vector2, side: float) -> PixelButton:
	var btn := PixelButton.new()
	btn.icon_name = icon
	btn.position = pos
	btn.size = Vector2(side, side)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(btn)
	return btn


# ---------- Veri ----------

func _prepare() -> void:
	for r in _data.get("roads", []):
		var f: Array = r.pts
		var pts := PackedVector2Array()
		for i in range(0, f.size() - 1, 2):
			pts.append(Vector2(float(f[i]), float(f[i + 1])))
		_lines.append({"pts": pts, "w": float(r.w), "col": COL_ROAD, "road": true})
		var rname := String(r.get("name", ""))
		if rname != "" and pts.size() >= 2:
			_add_road_labels(pts, Navigasyon.upper_tr(rname))
	for pl in _data.get("places", []):
		_labels.append({"p": Vector2(float(pl.p[0]), float(pl.p[1])), "text": Navigasyon.upper_tr(String(pl.name)),
			"kind": String(pl.kind), "pri": 2})
	var city := Sehir.instance
	if city == null:
		return
	var greens: Array = []
	var others: Array = []
	for it in city.data.items:
		var t := String(it.t)
		match t:
			"yesil":
				var o := city.outline(it)
				if o.size() >= 4:
					o.remove_at(o.size() - 1)
					greens.append({"pts": o, "col": COL_GREEN, "edge": Color(0, 0, 0, 0)})
			"park":
				var o := city.outline(it)
				o.remove_at(o.size() - 1)
				others.append({"pts": o, "col": COL_PARK.lerp(COL_GREEN, 0.35), "edge": COL_PARK.darkened(0.3)})
				_labels.append({"p": Sehir.v2(it.p), "text": "ÇOCUK PARKI", "kind": "park", "pri": 1})
			"bina":
				var o := city.outline(it)
				o.remove_at(o.size() - 1)
				var tur := String(it.get("tur", "ev"))
				var special := tur != "ev" and Sehir.BINA_TURLERI.has(tur)
				others.append({"pts": o, "col": COL_SPECIAL if special else COL_HOUSE,
					"edge": COL_SPECIAL.darkened(0.4) if special else COL_HOUSE_EDGE})
				if special:
					_labels.append({"p": Sehir.v2(it.p), "text": String(Sehir.BINA_TURLERI[tur].get("tabela", tur)),
						"kind": "bina", "pri": 1})
			"dukkan":
				var o := city.outline(it)
				o.remove_at(o.size() - 1)
				others.append({"pts": o, "col": COL_SHOP, "edge": COL_SHOP.darkened(0.45)})
				var c := Vector2.ZERO
				for q in o:
					c += q
				_labels.append({"p": c / o.size(), "text": Navigasyon.upper_tr(String(it.get("ad", "DÜKKAN"))), "kind": "dukkan", "pri": 0})
			"yukselti":
				var o := city.outline(it)
				o.remove_at(o.size() - 1)
				others.append({"pts": o, "col": COL_PLAT, "edge": COL_PLAT.darkened(0.3)})
			"yol":
				var o := city.outline(it)
				if o.size() >= 2:
					_lines.append({"pts": o, "w": float(it.get("w", 2.6)), "col": COL_ALLEY, "road": false})
	_polys = greens + others
	_labels.sort_custom(func(a, b): return a.pri < b.pri)


## Yol adı: yol boyunca her ~260 m'de bir aday nokta (ekranda en uygun olanlar çizilir)
func _add_road_labels(pts: PackedVector2Array, text: String) -> void:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var n := maxi(int(total / 260.0), 1)
	for k in n:
		var want := total * (k + 0.5) / n
		var acc := 0.0
		for i in pts.size() - 1:
			var l := pts[i].distance_to(pts[i + 1])
			if acc + l >= want:
				_road_labels.append({"p": pts[i].lerp(pts[i + 1], (want - acc) / maxf(l, 0.001)), "text": text})
				break
			acc += l


# ---------- Görünüm ----------

func _min_zoom() -> float:
	var span := TEX.get_width() * float(_data.get("px", 1.0)) * 0.82
	return minf(size.x, size.y) / span * MIN_FIT


func _max_zoom() -> float:
	return get_viewport_rect().size.y / 720.0 * MAX_PX_PER_M


func _clamp_center() -> void:
	var o := float(_data.get("origin", -608.5))
	var span := TEX.get_width() * float(_data.get("px", 1.0))
	_center = _center.clamp(Vector2(o, o) + Vector2(span, span) * 0.12, Vector2(o, o) + Vector2(span, span) * 0.88)


func to_screen(w: Vector2) -> Vector2:
	return (w - _center) * _zoom + size * 0.5


func to_world(s: Vector2) -> Vector2:
	return (s - size * 0.5) / _zoom + _center


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := to_world(screen_pos)
	_zoom = clampf(_zoom * factor, _min_zoom(), _max_zoom())
	_center += before - to_world(screen_pos)
	_clamp_center()
	queue_redraw()


# ---------- Girdi ----------

func _over_button(pos: Vector2) -> bool:
	for b in [_close_btn, _me_btn, _clear_btn]:
		if b and b.visible and b.get_global_rect().grow(4.0).has_point(pos):
			return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.physical_keycode == KEY_M:
			nav.close_map()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _over_button(event.position):
				return
			_touches[event.index] = {"pos": event.position, "start": event.position, "t": Time.get_ticks_msec() / 1000.0}
			_tap_ok = _touches.size() == 1
		elif _touches.has(event.index):
			var t: Dictionary = _touches[event.index]
			_touches.erase(event.index)
			var dt := Time.get_ticks_msec() / 1000.0 - float(t.t)
			if _tap_ok and _touches.is_empty() and dt < TAP_TIME \
					and (event.position as Vector2).distance_to(t.start) < get_viewport_rect().size.y * 0.025:
				_tap(event.position)
			if _touches.size() != 1:
				_tap_ok = false
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		var old: Vector2 = _touches[event.index].pos
		var newp: Vector2 = event.position
		if (_touches[event.index].start as Vector2).distance_to(newp) > get_viewport_rect().size.y * 0.025:
			_tap_ok = false
		if _touches.size() == 1:
			_center -= (newp - old) / _zoom
			_clamp_center()
		else:
			# İki parmak: öbür parmağa göre uzaklık oranı = yakınlaştırma, orta nokta kayması = kaydırma
			var other: Vector2 = old
			for k in _touches:
				if k != event.index:
					other = _touches[k].pos
					break
			var d0 := old.distance_to(other)
			var d1 := newp.distance_to(other)
			var m0 := (old + other) * 0.5
			var m1 := (newp + other) * 0.5
			if d0 > 8.0:
				_zoom_at(m0, d1 / d0)
			_center -= (m1 - m0) / _zoom
			_clamp_center()
		_touches[event.index].pos = newp
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.15)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		_center += event.delta * 8.0 / _zoom
		_clamp_center()
		queue_redraw()


## Kısa dokunuş: hedef. Bir yer adına (dükkân, park, meydan...) yakınsa tam oraya.
func _tap(pos: Vector2) -> void:
	var w := to_world(pos)
	var best := -1
	var best_d := get_viewport_rect().size.y * 0.05
	for i in _labels.size():
		var d := to_screen(_labels[i].p).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		w = _labels[best].p
	nav.set_destination(w)
	queue_redraw()


# ---------- Çizim ----------

func _draw() -> void:
	var vh := get_viewport_rect().size.y
	_clear_btn.visible = nav.has_dest
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var o := float(_data.get("origin", -608.5))
	var span := TEX.get_width() * float(_data.get("px", 1.0))
	draw_set_transform(size * 0.5 - _center * _zoom, 0.0, Vector2(_zoom, _zoom))
	draw_texture_rect(TEX, Rect2(Vector2(o, o), Vector2(span, span)), false)
	var view := Rect2(to_world(Vector2.ZERO), size / _zoom).grow(20.0)
	# Yeşil alanlar, binalar
	var edge_w := 1.0 / _zoom
	for p in _polys:
		var pts: PackedVector2Array = p.pts
		if not view.has_point(pts[0]) and not view.intersects(_bounds(pts)):
			continue
		draw_colored_polygon(pts, p.col)
		if p.edge.a > 0.0 and _zoom > 0.9:
			var loop := pts.duplicate()
			loop.append(pts[0])
			draw_polyline(loop, p.edge, edge_w * 1.5)
	# Yollar: önce açık kenar, sonra asfalt (kavşaklar düzgün birleşsin diye köşelere daire)
	for pass_i in 2:
		for l in _lines:
			var pts: PackedVector2Array = l.pts
			var w: float = l.w + (2.4 / _zoom if pass_i == 0 else 0.0)
			var col: Color = COL_ROAD_EDGE if pass_i == 0 else l.col
			if pass_i == 0 and not l.road:
				col = COL_ALLEY.darkened(0.25)
			draw_polyline(pts, col, w)
			for q in pts:
				if view.has_point(q):
					draw_circle(q, w * 0.5, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var s := maxf(roundf(vh * 0.0034), 2.0)
	var placed: Array[Rect2] = []
	# Oyuncu ve hedef önce yer kaplasın (yazılar üstlerine binmesin)
	var pp := nav.player.global_position
	var ps := to_screen(Vector2(pp.x, pp.z))
	placed.append(Rect2(ps - Vector2(vh, vh) * 0.035, Vector2(vh, vh) * 0.07))
	var pin_h := maxf(roundf(vh * 0.07 / 15.0), 2.0) * 15.0
	if nav.has_dest:
		var ds := to_screen(Vector2(nav.dest.x, nav.dest.z))
		placed.append(Rect2(ds - Vector2(pin_h * 0.4, pin_h), Vector2(pin_h * 0.8, pin_h)))
	# Önemli yerler (dükkân, özel bina, park, meydan...): nokta ve ad
	for lb in _labels:
		var sp := to_screen(lb.p)
		if not Rect2(Vector2.ZERO, size).grow(40.0).has_point(sp):
			continue
		var col := _kind_color(lb.kind)
		_dot(sp, s * 2.2, col)
		var ts := s
		var tw := PixelArt.text_width(lb.text, ts)
		var r := Rect2(Vector2(sp.x - tw * 0.5, sp.y - ts * 11.0), Vector2(tw, ts * 7.0)).grow(ts)
		if _free(r, placed):
			placed.append(r)
			PixelArt.draw_text(self, lb.text, r.position + Vector2(ts, ts), ts, Color(1, 1, 1), Color(0.06, 0.06, 0.1))
	# Yol adları: yakınlaşınca
	if _zoom > vh / 720.0 * 1.1:
		var rs := maxf(s - 1.0, 2.0)
		for rl in _road_labels:
			var sp := to_screen(rl.p)
			if not Rect2(Vector2.ZERO, size).has_point(sp):
				continue
			var tw := PixelArt.text_width(rl.text, rs)
			var r := Rect2(Vector2(sp.x - tw * 0.5, sp.y - rs * 3.5), Vector2(tw, rs * 7.0)).grow(rs)
			if _free(r, placed):
				placed.append(r)
				PixelArt.draw_text(self, rl.text, r.position + Vector2(rs, rs), rs, Color(1.0, 0.95, 0.75), Color(0.2, 0.18, 0.16))
	# Hedef
	if nav.has_dest:
		Navigasyon.draw_pin(self, to_screen(Vector2(nav.dest.x, nav.dest.z)), pin_h)
	# Oyuncu: yönünü gösteren ok
	_player_arrow(ps, vh * 0.032)
	_scale_bar(vh, s)
	# Alt yazı
	var hint := "HEDEF KOYMAK İÇİN HARİTAYA DOKUN"
	if nav.has_dest:
		hint = "HEDEF: " + Navigasyon.format_distance(nav.distance())
	var ins := GuvenliAlan.insets(get_viewport())
	var hs := s
	PixelArt.draw_text(self, hint, Vector2(roundf((size.x - PixelArt.text_width(hint, hs)) * 0.5), size.y - ins.w - vh * 0.075), hs,
		Color(1, 1, 1), Color(0.05, 0.05, 0.08))


func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	return r


func _free(r: Rect2, placed: Array[Rect2]) -> bool:
	if not Rect2(Vector2.ZERO, size).encloses(r):
		return false
	for q in placed:
		if q.intersects(r):
			return false
	return true


func _kind_color(kind: String) -> Color:
	match kind:
		"dukkan":
			return COL_SHOP
		"park":
			return COL_PARK
		"bina":
			return COL_SPECIAL
		"meydan":
			return Color(1.0, 0.95, 0.7)
		"tepe":
			return Color(0.75, 0.55, 0.35)
		"iskele":
			return Color(0.6, 0.85, 1.0)
	return Color.WHITE


func _dot(c: Vector2, r: float, col: Color) -> void:
	var px := maxf(floorf(r / 2.5), 1.0)
	PixelArt._pixel_disc(self, c.round(), r + px, px, Color(0.06, 0.06, 0.1))
	PixelArt._pixel_disc(self, c.round(), r, px, col)


func _player_arrow(c: Vector2, r: float) -> void:
	var h := nav.player.heading
	var f := Vector2(h.x, h.z)
	if f.length() < 0.01:
		f = Vector2(0, -1)
	f = f.normalized()
	var sd := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([c + f * r, c - f * r * 0.7 + sd * r * 0.75, c - f * r * 0.3, c - f * r * 0.7 - sd * r * 0.75])
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
	draw_circle(c, r * (1.25 + pulse * 0.2), Color(0.3, 0.75, 1.0, 0.25))
	var outline := PackedVector2Array()
	for q in pts:
		outline.append(c + (q - c) * 1.25)
	draw_colored_polygon(outline, Color(0.06, 0.06, 0.1))
	draw_colored_polygon(pts, Color(0.35, 0.82, 1.0))


## Ölçek çubuğu (sol alt): 10 / 25 / 50 / 100 / 250 / 500 m
func _scale_bar(vh: float, s: float) -> void:
	var want := size.x * 0.16 / _zoom
	var m := 10.0
	for v in [10.0, 25.0, 50.0, 100.0, 250.0, 500.0]:
		if v <= want:
			m = v
	var ins := GuvenliAlan.insets(get_viewport())
	var x0 := ins.x + vh * 0.05
	var y0 := size.y - ins.w - vh * 0.06
	var w := m * _zoom
	draw_rect(Rect2(x0 - s, y0 - s * 3.0, w + s * 2.0, s * 4.0), Color(0.06, 0.06, 0.1))
	draw_rect(Rect2(x0, y0 - s * 2.0, w, s * 2.0), Color(1, 1, 1))
	var t := "%d M" % int(m)
	PixelArt.draw_text(self, t, Vector2(x0, y0 - s * 12.0), s, Color(1, 1, 1), Color(0.06, 0.06, 0.1))
