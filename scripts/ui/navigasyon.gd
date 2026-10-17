class_name Navigasyon
extends Control
## Navigasyon: harita (HUD'daki harita butonu ya da M tuşu) ve hedef noktası.
## Haritada bir yere dokununca orası hedef olur; oyunda hedefin üstünde, binaların arkasından da
## görünen saydam bir konum işareti ve altında kalan mesafe çizilir. Hedef ekran dışındaysa
## işaret ekranın kenarında, hedefin yönünü gösteren okla durur. Hedefe varınca kendiliğinden kalkar.
## Harita açıkken oyun durur (Harita: PROCESS_MODE_ALWAYS).

static var instance: Navigasyon

const VARIS := 7.0              # bu kadar yaklaşınca hedefe varılmış sayılır (m)
const ISARET_Y := 2.4           # işaret zeminden bu kadar yüksekte (m)
const SAYDAM := 0.72

var player: SkateController
var camera: Camera3D
var world: SubViewport
## Harita açılınca kapanması gereken oyun girdisi (dokunmatik kontroller)
var touch_controls: Control

var has_dest := false
var dest := Vector3.ZERO        # zemin noktası (dünya)
var _map_layer: CanvasLayer
var _map: Control
var _arrive_t := 0.0

static var _pin_tex: ImageTexture


func _ready() -> void:
	instance = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func set_destination(xz: Vector2) -> void:
	var y := 0.0
	if Sehir.instance:
		y = Sehir.instance.ground(xz.x, xz.y)
	dest = Vector3(xz.x, y, xz.y)
	has_dest = true
	_arrive_t = 0.0


func clear_destination() -> void:
	has_dest = false


func is_map_open() -> bool:
	return _map != null


func open_map() -> void:
	if _map != null or not player:
		return
	if IcMekan.instance and (IcMekan.instance.is_inside() or IcMekan.instance.busy):
		return
	if touch_controls and touch_controls.has_method("release_all"):
		touch_controls.release_all()
	_map_layer = CanvasLayer.new()
	_map_layer.layer = 10
	_map_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_map_layer)
	_map = preload("res://scripts/ui/harita.gd").new()
	_map.nav = self
	_map_layer.add_child(_map)
	get_tree().paused = true


func close_map() -> void:
	if _map == null:
		return
	_map_layer.queue_free()
	_map_layer = null
	_map = null
	get_tree().paused = false
	if touch_controls and touch_controls.has_method("release_all"):
		touch_controls.release_all()


## Oyuncunun düz (yatay) mesafesi hedefe
func distance() -> float:
	if not has_dest or not player:
		return 0.0
	var d := dest - player.global_position
	return Vector2(d.x, d.z).length()


static func format_distance(m: float) -> String:
	if m >= 1000.0:
		return "%.1f KM" % (m / 1000.0)
	return "%d M" % int(roundf(m))


## Türkçe büyük harf (i -> İ, ı -> I)
static func upper_tr(s: String) -> String:
	return s.replace("i", "İ").replace("ı", "I").to_upper()


## Piksel konum işareti (11 x 15): turuncu-sarı damla, koyu kenar, beyaz göbek
static func pin_texture() -> ImageTexture:
	if _pin_tex:
		return _pin_tex
	var rows := [
		"...ooooo...",
		"..o#####o..",
		".o#######o.",
		"o###www###o",
		"o##wwwww##o",
		"o##wwwww##o",
		"o###www###o",
		".o#######o.",
		".o#######o.",
		"..o#####o..",
		"...o###o...",
		"...o###o...",
		"....o#o....",
		"....o#o....",
		".....o.....",
	]
	var img := Image.create(11, 15, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cols := {"o": Color(0.13, 0.1, 0.08), "#": Color(1.0, 0.72, 0.2), "w": Color(1, 1, 1)}
	for y in rows.size():
		var r: String = rows[y]
		for x in r.length():
			if cols.has(r[x]):
				img.set_pixel(x, y, cols[r[x]])
	_pin_tex = ImageTexture.create_from_image(img)
	return _pin_tex


## İşareti ucu tip noktasına gelecek şekilde çiz (yükseklik h piksel)
static func draw_pin(ci: CanvasItem, tip: Vector2, h: float, alpha := 1.0) -> void:
	var tex := pin_texture()
	var px := maxf(floorf(h / 15.0), 1.0)
	var size := Vector2(11, 15) * px
	ci.draw_texture_rect(tex, Rect2(Vector2(roundf(tip.x - size.x * 0.5), roundf(tip.y - size.y)), size), false, Color(1, 1, 1, alpha))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		if is_visible_in_tree():
			open_map()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if has_dest and player and distance() < VARIS and not is_map_open():
		has_dest = false
		_arrive_t = 2.2
	_arrive_t = maxf(_arrive_t - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var vh := size.y
	var s := maxf(roundf(vh * 0.0042), 2.0)
	if _arrive_t > 0.0:
		var t := "HEDEFE VARDIN!"
		var a := clampf(_arrive_t / 0.4, 0.0, 1.0)
		PixelArt.draw_text(self, t, Vector2((size.x - PixelArt.text_width(t, s * 1.4)) * 0.5, vh * 0.2), s * 1.4,
			Color(1.0, 0.82, 0.3, a), Color(0.05, 0.05, 0.08, a))
	if not has_dest or not camera or not world or not player:
		return
	if IcMekan.instance and IcMekan.instance.is_inside():
		return
	var p := dest + Vector3(0, ISARET_Y, 0)
	var scale := get_viewport_rect().size / Vector2(world.size)
	var behind := camera.is_position_behind(p)
	var sp := camera.unproject_position(p) * scale - global_position
	var pin_h := maxf(roundf(vh * 0.075 / 15.0), 2.0) * 15.0
	# Ekranda kalacağı alan: üstte HUD butonlarının altı, altta dokunmatik butonların üstü
	var lo := Vector2(vh * 0.08, vh * 0.16 + pin_h)
	var hi := Vector2(size.x - vh * 0.08, size.y * 0.42)
	var edge := 0.0                 # ekran dışı: -1 sol kenar, +1 sağ kenar
	if behind or sp.x < lo.x or sp.x > hi.x:
		# Görüş dışında: hedef kameranın hangi yanındaysa o kenarda (arkadaysa da yanına göre)
		var rel := camera.global_transform.affine_inverse() * p
		edge = 1.0 if rel.x >= 0.0 else -1.0
		sp.x = hi.x if edge > 0.0 else lo.x
		if behind:
			sp.y = size.y * 0.32
	sp.y = clampf(sp.y, lo.y, hi.y if edge != 0.0 else size.y - vh * 0.08)
	var bob := sin(Time.get_ticks_msec() * 0.004) * vh * 0.006
	draw_pin(self, sp + Vector2(0, bob), pin_h, SAYDAM)
	var t := format_distance(distance())
	var ts := maxf(s - 1.0, 2.0)
	PixelArt.draw_text(self, t, Vector2(roundf(sp.x - PixelArt.text_width(t, ts) * 0.5), roundf(sp.y + ts * 3.0)), ts,
		Color(1, 1, 1, 0.9), Color(0.05, 0.05, 0.08, 0.8))
	if edge != 0.0:
		# Kenar oku: işaretin yanında, hedefe doğru (dönülmesi gereken yan)
		var dir := Vector2(edge, 0.0)
		var tip := sp - Vector2(0, pin_h * 0.55) + dir * pin_h * 0.62
		var side := Vector2(-dir.y, dir.x)
		var k := pin_h * 0.16
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * k * 1.6 + side * k, tip - dir * k * 1.6 - side * k]),
			Color(1.0, 0.72, 0.2, SAYDAM))
