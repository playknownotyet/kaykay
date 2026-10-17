class_name CocukParki
## Çocuk parkı (şehir öğesi "park"): ortada oyun alanı (kaydırak, salıncak, tahterevalli, kum havuzu,
## yaylı oyuncaklar), çevresinde kaykayla döngü halinde dönülen beton halka: rampa (kicker), üstü
## raylı kutu (funbox), grind kenarı (ledge), piramit, düz ray, manual kutusu; kenarda grind yapılabilen
## bordür, banklar (yetişkinler oturur) ve lambalar. Çocuklar (NpcCrowd) oyun alanında oynar.
##
## Yerel düzen: köken parkın ortası (zemin), x sağ, z ön (+Z kapı / sokak tarafı değil, simetrik).
## Halkada sürüş yönü: kuzey (−z) kenarında +x'e, doğuda +z'ye, güneyde −x'e, batıda −z'ye.

const W := 30.0
const D := 24.0
const FLOOR := 0.06                     # zeminin üstü (araziden)
const PLAY := Vector2(6.6, 5.0)         # oyun alanının yarı boyu (kauçuk)
const PROP_SCRIPT := preload("res://scripts/ada/prop_katmani.gd")
const BENCH := "res://assets/props/painted_wooden_bench.glb"
const LAMP := "res://assets/props/street_lamp_01.glb"


## Parkı kur; çocukların ve bankların kullanacağı yerleri döner
static func build(city: Sehir, it: Dictionary, xf: Transform3D, sk: SurfaceTool, sm: SurfaceTool, sd: SurfaceTool) -> Dictionary:
	var id := int(it.get("id", 0))
	var root := Node3D.new()
	root.name = "Park_%d" % id
	root.transform = xf
	city._built.add_child(root)
	var body := city._body("beton")
	var info := {"id": id, "xf": xf, "root": root, "swings": [], "seesaw": {}, "slide": {}, "spots": [], "benches": []}
	var hw := W * 0.5
	var hd := D * 0.5

	# --- Zemin: beton halka ve kauçuk oyun alanı (çarpışma tek kutu) ---
	var conc := Sehir._vc("#b9b6ae")
	var conc_d := Sehir._vc("#a19e96")
	_flat(sd, xf, -hw, -hd, hw, hd, FLOOR, conc)
	# Halkanın ortasında boyalı şerit (sürüş yolu)
	for z: float in [-hd + 3.6, hd - 3.6]:
		_flat(sd, xf, -hw + 3.0, z - 0.06, hw - 3.0, z + 0.06, FLOOR + 0.002, Sehir._vc("#f2d16b"))
	for x: float in [-hw + 3.6, hw - 3.6]:
		_flat(sd, xf, x - 0.06, -hd + 3.0, x + 0.06, hd - 3.0, FLOOR + 0.002, Sehir._vc("#f2d16b"))
	var rubber := Sehir._vc("#e0573f")
	var rubber_b := Sehir._vc("#3f7fc4")
	var n := 6
	for i in n:
		var x0 := -PLAY.x + PLAY.x * 2.0 * i / n
		_flat(sd, xf, x0, -PLAY.y, x0 + PLAY.x * 2.0 / n, PLAY.y, FLOOR + 0.004, rubber if i % 2 == 0 else rubber_b)
	city._shape_box(body, Vector3(W, 0.3, D), xf * Transform3D(Basis(), Vector3(0, FLOOR - 0.15, 0)))
	# Oyun alanının kenarı: alçak kauçuk set (çocuklar ve kaykay için)
	_ring(sk, xf, PLAY.x, PLAY.y, 0.12, 0.18, Sehir._vc("#3a3a3a"), body, city, sd)

	# --- Bordür (grind yapılabilir), dört yanda giriş ---
	var curb_h := 0.28
	var gap := 3.2
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			# x kenarı (z = ±hd)
			var a := sx * gap * 0.5
			var b := sx * hw
			_curb(city, body, sk, xf, Vector3(minf(a, b), 0, sz * hd), Vector3(maxf(a, b), 0, sz * hd), curb_h, true)
			# z kenarı (x = ±hw)
			var c := sz * gap * 0.5
			var d := sz * hd
			_curb(city, body, sk, xf, Vector3(sx * hw, 0, minf(c, d)), Vector3(sx * hw, 0, maxf(c, d)), curb_h, false)

	# --- Halkadaki kaykay parçaları ---
	var zn := -hd + 3.6          # kuzey hattı
	var zs := hd - 3.6
	var xe := hw - 3.6
	var xw := -hw + 3.6
	# Kuzey: kicker, sonra funbox (rampa / üstte ray / rampa)
	_wedge(city, body, sk, xf, -10.1, -8.8, zn - 0.9, zn + 0.9, 0.58, "+x", conc_d)
	_wedge(city, body, sk, xf, -3.6, -1.8, zn - 1.1, zn + 1.1, 0.5, "+x", conc_d)
	_block(city, body, sk, xf, -1.8, 1.8, zn - 1.1, zn + 1.1, 0.5, conc)
	_wedge(city, body, sk, xf, 1.8, 3.6, zn - 1.1, zn + 1.1, 0.5, "-x", conc_d)
	_pipe_rail(city, body, sm, xf, Vector3(-1.6, 0.5, zn), Vector3(1.6, 0.5, zn), 0.32)
	_block_rails(city, xf, -1.8, 1.8, zn - 1.1, zn + 1.1, 0.5)
	# Doğu: grind kenarı (ledge) ve önünde kicker
	_block(city, body, sk, xf, xe - 0.3, xe + 0.3, -4.8, 4.8, 0.42, conc)
	_block_rails(city, xf, xe - 0.3, xe + 0.3, -4.8, 4.8, 0.42)
	_wedge(city, body, sk, xf, xe - 0.8, xe + 0.8, 6.2, 7.4, 0.52, "+z", conc_d)
	# Güney: piramit ve düz ray
	_pyramid(city, body, sk, xf, Vector3(3.2, 0, zs), Vector2(4.4, 3.4), Vector2(1.8, 1.2), 0.5, conc_d, conc)
	_pipe_rail(city, body, sm, xf, Vector3(-3.5, 0.0, zs), Vector3(-8.5, 0.0, zs), 0.36)
	# Batı: manual kutusu ve kicker
	_block(city, body, sk, xf, xw - 0.7, xw + 0.7, -3.6, 3.6, 0.16, conc)
	_block_rails(city, xf, xw - 0.7, xw + 0.7, -3.6, 3.6, 0.16)
	_wedge(city, body, sk, xf, xw - 0.9, xw + 0.9, -7.6, -6.4, 0.52, "-z", conc_d)

	# --- Oyun alanı ---
	_slide(city, body, sd, xf, Vector3(-4.6, 0, -2.2), info)
	_swings(city, body, sd, sm, xf, Vector3(3.2, 0, -2.4), root, info)
	_seesaw(city, body, sd, xf, Vector3(0.4, 0, 2.6), root, info)
	_sandbox(city, body, sd, xf, Vector3(-3.9, 0, 2.7))
	_spring_rider(city, body, sd, xf, Vector3(3.3, 0, 2.9), "#f2c14e")
	_spring_rider(city, body, sd, xf, Vector3(4.8, 0, 2.2), "#7cc6b0")
	# Koşulacak boş yerler (oyun alanında, eşyaların arasında)
	for p: Vector2 in [Vector2(-1.5, -3.6), Vector2(1.0, -3.8), Vector2(-1.0, 0.2), Vector2(1.6, -0.4), Vector2(-5.6, 0.4),
			Vector2(5.6, 0.2), Vector2(-1.6, 4.0), Vector2(2.2, 4.2), Vector2(-5.8, -4.2), Vector2(5.8, -4.4), Vector2(0.0, -1.8)]:
		info.spots.append(xf * Vector3(p.x, FLOOR, p.y))

	# --- Banklar (oyun alanına dönük) ve lambalar ---
	var bench: Dictionary = PROP_SCRIPT._load(BENCH)
	var spots := [[Vector3(-8.0, 0, -hd + 1.0), Vector3(0, 0, 1)], [Vector3(7.0, 0, -hd + 1.0), Vector3(0, 0, 1)],
		[Vector3(-7.0, 0, hd - 1.0), Vector3(0, 0, -1)], [Vector3(8.0, 0, hd - 1.0), Vector3(0, 0, -1)],
		[Vector3(-hw + 1.0, 0, -5.0), Vector3(1, 0, 0)], [Vector3(-hw + 1.0, 0, 5.5), Vector3(1, 0, 0)],
		[Vector3(hw - 1.0, 0, -6.0), Vector3(-1, 0, 0)], [Vector3(hw - 1.0, 0, 5.0), Vector3(-1, 0, 0)]]
	for s in spots:
		var fw: Vector3 = (xf.basis * (s[1] as Vector3)).normalized()
		var pos: Vector3 = xf * ((s[0] as Vector3) + Vector3(0, FLOOR, 0))
		var tf := Transform3D(Basis.looking_at(-fw, Vector3.UP), pos)
		if not bench.is_empty():
			var mi := MeshInstance3D.new()
			mi.mesh = bench.mesh
			mi.material_override = bench.material
			mi.visibility_range_end = 170.0
			city._built.add_child(mi)
			mi.global_transform = tf
		city._shape_box(body, Vector3(1.16, 0.89, 0.5), tf * Transform3D(Basis(), Vector3(0, 0.445, 0)))
		if Banklar.instance:
			info.benches.append_array(Banklar.instance.add_bench(tf, "park_%d" % id))
	var lamp: Dictionary = PROP_SCRIPT._load(LAMP)
	if not lamp.is_empty():
		for c: Vector2 in [Vector2(-hw + 0.6, -hd + 0.6), Vector2(hw - 0.6, -hd + 0.6), Vector2(-hw + 0.6, hd - 0.6), Vector2(hw - 0.6, hd - 0.6)]:
			var mi := MeshInstance3D.new()
			mi.mesh = lamp.mesh
			mi.material_override = lamp.material
			mi.visibility_range_end = 300.0
			city._built.add_child(mi)
			mi.global_transform = xf * Transform3D(Basis(), Vector3(c.x, FLOOR, c.y))
			var cs := CylinderShape3D.new()
			cs.radius = 0.13
			cs.height = 3.8
			var shp := CollisionShape3D.new()
			shp.shape = cs
			shp.transform = xf * Transform3D(Basis(), Vector3(c.x, FLOOR + 1.9, c.y))
			body.add_child(shp)
	return info


# ---------- Yapı taşları (yerel koordinat, xf ile dünyaya) ----------

static func _flat(st: SurfaceTool, xf: Transform3D, x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
	Sehir._quad(st, [xf * Vector3(x0, y, z0), xf * Vector3(x1, y, z0), xf * Vector3(x1, y, z1), xf * Vector3(x0, y, z1)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], xf.basis * Vector3.UP, col)


static func _box_l(st: SurfaceTool, xf: Transform3D, c: Vector3, s: Vector3, col: Color) -> void:
	Sehir._box(st, xf, c, s, col)


## Kutu: görünen + çarpışma (üstü yy)
static func _block(city: Sehir, body: StaticBody3D, st: SurfaceTool, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, h: float, col: Color) -> void:
	var c := Vector3((x0 + x1) * 0.5, FLOOR + h * 0.5, (z0 + z1) * 0.5)
	var s := Vector3(x1 - x0, h, z1 - z0)
	Sehir._box(st, xf, c, s, col)
	city._shape_box(body, s, xf * Transform3D(Basis(), c))


## Kutunun üst kenarları grind rayı (beton)
static func _block_rails(city: Sehir, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, h: float) -> void:
	var y := FLOOR + h
	if x1 - x0 > z1 - z0:
		city._rail(xf * Vector3(x0, y, z0), xf * Vector3(x1, y, z0), "beton")
		city._rail(xf * Vector3(x0, y, z1), xf * Vector3(x1, y, z1), "beton")
	else:
		city._rail(xf * Vector3(x0, y, z0), xf * Vector3(x0, y, z1), "beton")
		city._rail(xf * Vector3(x1, y, z0), xf * Vector3(x1, y, z1), "beton")


## Rampa (kicker / funbox yanı): up yönüne doğru yükselir, yüksek uç dik
static func _wedge(city: Sehir, body: StaticBody3D, st: SurfaceTool, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, h: float, up: String, col: Color) -> void:
	var y0 := FLOOR
	var y1 := FLOOR + h
	# Taban köşeleri ve yüksek kenar
	var lo: Array
	var hi: Array
	match up:
		"+x":
			lo = [Vector3(x0, y0, z0), Vector3(x0, y0, z1)]
			hi = [Vector3(x1, y1, z0), Vector3(x1, y1, z1)]
		"-x":
			lo = [Vector3(x1, y0, z1), Vector3(x1, y0, z0)]
			hi = [Vector3(x0, y1, z1), Vector3(x0, y1, z0)]
		"+z":
			lo = [Vector3(x1, y0, z0), Vector3(x0, y0, z0)]
			hi = [Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
		_:
			lo = [Vector3(x0, y0, z1), Vector3(x1, y0, z1)]
			hi = [Vector3(x0, y1, z0), Vector3(x1, y1, z0)]
	var hb := [Vector3(hi[0].x, y0, hi[0].z), Vector3(hi[1].x, y0, hi[1].z)]
	var z := Vector2.ZERO
	var slope_n: Vector3 = (hi[0] - lo[0]).cross(lo[1] - lo[0]).normalized()
	if slope_n.y < 0.0:
		slope_n = -slope_n
	Sehir._quad(st, [xf * lo[0], xf * lo[1], xf * hi[1], xf * hi[0]], [z, z, z, z], xf.basis * slope_n, col)
	var back_n: Vector3 = (hi[0] - lo[0])
	back_n.y = 0.0
	back_n = back_n.normalized()
	Sehir._quad(st, [xf * hb[0], xf * hb[1], xf * hi[1], xf * hi[0]], [z, z, z, z], xf.basis * back_n, Color(col.r * 0.85, col.g * 0.85, col.b * 0.85, col.a))
	for k in 2:
		var side_n: Vector3 = (lo[k] - lo[1 - k])
		side_n.y = 0.0
		Sehir._tri(st, [xf * lo[k], xf * hb[k], xf * hi[k]], [z, z, z], xf.basis * side_n.normalized(), Color(col.r * 0.9, col.g * 0.9, col.b * 0.9, col.a))
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([lo[0], lo[1], hi[0], hi[1], hb[0], hb[1]])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)
	# Rampanın üst kenarı (koping) metal grind rayı
	city._rail(xf * hi[0], xf * hi[1], "metal")


## Piramit: alt dikdörtgen bottom, üst düzlük top, yükseklik h
static func _pyramid(city: Sehir, body: StaticBody3D, st: SurfaceTool, xf: Transform3D, c: Vector3, bottom: Vector2, top: Vector2, h: float, side: Color, top_col: Color) -> void:
	var y0 := FLOOR
	var y1 := FLOOR + h
	var b := [Vector3(c.x - bottom.x * 0.5, y0, c.z - bottom.y * 0.5), Vector3(c.x + bottom.x * 0.5, y0, c.z - bottom.y * 0.5),
		Vector3(c.x + bottom.x * 0.5, y0, c.z + bottom.y * 0.5), Vector3(c.x - bottom.x * 0.5, y0, c.z + bottom.y * 0.5)]
	var t := [Vector3(c.x - top.x * 0.5, y1, c.z - top.y * 0.5), Vector3(c.x + top.x * 0.5, y1, c.z - top.y * 0.5),
		Vector3(c.x + top.x * 0.5, y1, c.z + top.y * 0.5), Vector3(c.x - top.x * 0.5, y1, c.z + top.y * 0.5)]
	var z := Vector2.ZERO
	Sehir._quad(st, [xf * t[0], xf * t[1], xf * t[2], xf * t[3]], [z, z, z, z], xf.basis * Vector3.UP, top_col)
	for k in 4:
		var q := (k + 1) % 4
		var nrm: Vector3 = (b[q] - b[k]).cross(t[k] - b[k]).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		Sehir._quad(st, [xf * b[k], xf * b[q], xf * t[q], xf * t[k]], [z, z, z, z], xf.basis * nrm, side)
		city._rail(xf * t[k], xf * t[q], "beton")
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(b + t)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


## Bordür: a..b boyunca, üst kenarları grind rayı
static func _curb(city: Sehir, body: StaticBody3D, st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, h: float, along_x: bool) -> void:
	var t := 0.32
	var c := (a + b) * 0.5 + Vector3(0, FLOOR + h * 0.5, 0)
	var s := Vector3(absf(b.x - a.x) + (0.0 if along_x else t), h, absf(b.z - a.z) + (t if along_x else 0.0))
	if s.x < 0.2 or s.z < 0.2:
		return
	Sehir._box(st, xf, c, s, Sehir._vc("#d8d4cb"))
	city._shape_box(body, s, xf * Transform3D(Basis(), c))
	var y := FLOOR + h
	if along_x:
		city._rail(xf * Vector3(a.x, y, a.z), xf * Vector3(b.x, y, b.z), "beton")
	else:
		city._rail(xf * Vector3(a.x, y, a.z), xf * Vector3(b.x, y, b.z), "beton")


## Düz ray: iki ayak üstünde boru (h yükseklik), grind rayı
static func _pipe_rail(city: Sehir, body: StaticBody3D, st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, h: float) -> void:
	var y := a.y + FLOOR + h
	var mid := (a + b) * 0.5
	var L := a.distance_to(b)
	var dir := (b - a).normalized()
	var bx := Basis(dir, Vector3.UP, dir.cross(Vector3.UP).normalized())
	var rxf := xf * Transform3D(bx.orthonormalized(), Vector3(mid.x, y, mid.z))
	Sehir._box(st, rxf, Vector3.ZERO, Vector3(L, 0.06, 0.06), Sehir._vc("#5c6670"))
	for k: float in [-0.42, 0.42]:
		var p := mid + dir * (L * k)
		Sehir._box(st, xf, Vector3(p.x, a.y + FLOOR + h * 0.5, p.z), Vector3(0.05, h, 0.05), Sehir._vc("#4a525a"))
	city._shape_box(body, Vector3(L, 0.06, 0.06), rxf)
	city._rail(xf * Vector3(a.x, y + 0.03, a.z), xf * Vector3(b.x, y + 0.03, b.z), "metal")


## Oyun alanını çeviren alçak set
static func _ring(st: SurfaceTool, xf: Transform3D, hx: float, hz: float, h: float, t: float, col: Color, body: StaticBody3D, city: Sehir, sd: SurfaceTool) -> void:
	for sz: float in [-1.0, 1.0]:
		# Ortada giriş boşluğu (1,6 m)
		for sx: float in [-1.0, 1.0]:
			var x0 := sx * 0.8
			var x1 := sx * (hx + t * 0.5)
			var c := Vector3((x0 + x1) * 0.5, FLOOR + h * 0.5, sz * hz)
			var s := Vector3(absf(x1 - x0), h, t)
			Sehir._box(sd, xf, c, s, col)
			city._shape_box(body, s, xf * Transform3D(Basis(), c))
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * hx, FLOOR + h * 0.5, 0)
		var s := Vector3(t, h, hz * 2.0)
		Sehir._box(sd, xf, c, s, col)
		city._shape_box(body, s, xf * Transform3D(Basis(), c))


# ---------- Oyun alanı eşyaları ----------

## Kaydırak: merdiven (−x), platform, +x yönünde inen oluk. Çocuklar: merdivenden çıkar, kayar.
static func _slide(city: Sehir, body: StaticBody3D, st: SurfaceTool, xf: Transform3D, o: Vector3, info: Dictionary) -> void:
	var post := Sehir._vc("#3f7fc4")
	var plat_h := 1.35
	var y := FLOOR
	for p: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		Sehir._box(st, xf, o + Vector3(p.x, y + (plat_h + 0.9) * 0.5, p.y), Vector3(0.09, plat_h + 0.9, 0.09), post)
	Sehir._box(st, xf, o + Vector3(0, y + plat_h, 0), Vector3(1.1, 0.08, 1.1), Sehir._vc("#f2c14e"))
	# Çatı (üçgen tente yerine düz renkli kapak)
	Sehir._box(st, xf, o + Vector3(0, y + plat_h + 0.95, 0), Vector3(1.25, 0.1, 1.25), Sehir._vc("#e0573f"))
	# Korkuluk
	for sz: float in [-1.0, 1.0]:
		Sehir._box(st, xf, o + Vector3(0, y + plat_h + 0.45, sz * 0.5), Vector3(1.0, 0.05, 0.05), post)
	# Merdiven (−x tarafı)
	for k in 5:
		var hh := y + 0.27 * (k + 1)
		Sehir._box(st, xf, o + Vector3(-0.85 - 0.12 * (4 - k), hh, 0), Vector3(0.1, 0.05, 0.6), Sehir._vc("#d8d4cb"))
	for sz: float in [-0.32, 0.32]:
		Sehir._box(st, xf, o + Vector3(-1.1, y + plat_h * 0.5, sz), Vector3(0.06, plat_h + 0.3, 0.06), post)
	# Oluk: +x'e iner
	var a := o + Vector3(0.55, y + plat_h, 0)
	var b := o + Vector3(2.7, y + 0.28, 0)
	var dir := (b - a)
	var L := dir.length()
	var mid := (a + b) * 0.5
	var ang := atan2(-(a.y - b.y), b.x - a.x)
	var sxf := xf * Transform3D(Basis(Vector3(0, 0, 1), ang), mid)
	Sehir._box(st, sxf, Vector3.ZERO, Vector3(L, 0.05, 0.6), Sehir._vc("#e0573f"))
	for sz: float in [-0.3, 0.3]:
		Sehir._box(st, sxf, Vector3(0, 0.08, sz), Vector3(L, 0.14, 0.04), Sehir._vc("#f08f6c"))
	city._shape_box(body, Vector3(1.1, plat_h, 1.1), xf * Transform3D(Basis(), o + Vector3(0, y + plat_h * 0.5, 0)))
	city._shape_box(body, Vector3(L, 0.12, 0.6), sxf)
	info.slide = {"bottom": xf * (o + Vector3(-1.5, y, 0)), "top": xf * (o + Vector3(0.0, y + plat_h + 0.05, 0)),
		"start": xf * (o + Vector3(0.62, y + plat_h + 0.05, 0)), "end": xf * (o + Vector3(2.75, y + 0.3, 0)),
		"dir": (xf.basis * Vector3(1, 0, 0)).normalized()}


## Salıncak: A ayaklı çerçeve, iki oturak (asılı, sallanan düğümler)
static func _swings(city: Sehir, body: StaticBody3D, st: SurfaceTool, sm: SurfaceTool, xf: Transform3D, o: Vector3, root: Node3D, info: Dictionary) -> void:
	var frame := Sehir._vc("#3f7fc4")
	var top := FLOOR + 2.15
	for sx: float in [-1.5, 1.5]:
		for sz: float in [-0.55, 0.55]:
			var a := o + Vector3(sx, FLOOR, sz)
			var b := o + Vector3(sx, top, 0)
			var mid := (a + b) * 0.5
			var ang := atan2(-sz, top - FLOOR)
			Sehir._box(st, xf * Transform3D(Basis(Vector3(1, 0, 0), ang), mid), Vector3.ZERO, Vector3(0.08, (b - a).length(), 0.08), frame)
		city._shape_box(body, Vector3(0.12, 2.1, 1.2), xf * Transform3D(Basis(), o + Vector3(sx, FLOOR + 1.05, 0)))
	Sehir._box(st, xf, o + Vector3(0, top, 0), Vector3(3.1, 0.09, 0.09), Sehir._vc("#f2c14e"))
	for sx: float in [-0.75, 0.75]:
		var pivot := Node3D.new()
		pivot.position = o + Vector3(sx, top, 0)
		root.add_child(pivot)
		var mi := MeshInstance3D.new()
		var s2 := SurfaceTool.new()
		s2.begin(Mesh.PRIMITIVE_TRIANGLES)
		for cx: float in [-0.22, 0.22]:
			Sehir._box(s2, Transform3D.IDENTITY, Vector3(cx, -0.85, 0), Vector3(0.02, 1.7, 0.02), Sehir._vc("#7b7d80"))
		Sehir._box(s2, Transform3D.IDENTITY, Vector3(0, -1.72, 0), Vector3(0.5, 0.05, 0.22), Sehir._vc("#e0573f"))
		mi.mesh = s2.commit()
		mi.material_override = city._mats.get("vc")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 120.0
		pivot.add_child(mi)
		info.swings.append({"pivot": pivot, "seat": Vector3(0, -1.69, 0)})


## Tahterevalli: ortada ayak, üstünde dönen kiriş; iki ucunda oturak ve tutamak
static func _seesaw(city: Sehir, body: StaticBody3D, st: SurfaceTool, xf: Transform3D, o: Vector3, root: Node3D, info: Dictionary) -> void:
	Sehir._box(st, xf, o + Vector3(0, FLOOR + 0.22, 0), Vector3(0.3, 0.44, 0.4), Sehir._vc("#3f7fc4"))
	city._shape_box(body, Vector3(0.3, 0.44, 0.4), xf * Transform3D(Basis(), o + Vector3(0, FLOOR + 0.22, 0)))
	var pivot := Node3D.new()
	pivot.position = o + Vector3(0, FLOOR + 0.46, 0)
	root.add_child(pivot)
	var s2 := SurfaceTool.new()
	s2.begin(Mesh.PRIMITIVE_TRIANGLES)
	Sehir._box(s2, Transform3D.IDENTITY, Vector3.ZERO, Vector3(3.0, 0.07, 0.24), Sehir._vc("#f2c14e"))
	for sx: float in [-1.35, 1.35]:
		Sehir._box(s2, Transform3D.IDENTITY, Vector3(sx, 0.06, 0), Vector3(0.36, 0.05, 0.3), Sehir._vc("#e0573f"))
		Sehir._box(s2, Transform3D.IDENTITY, Vector3(sx * 0.82, 0.2, 0), Vector3(0.04, 0.3, 0.3), Sehir._vc("#7b7d80"))
	var mi := MeshInstance3D.new()
	mi.mesh = s2.commit()
	mi.material_override = city._mats.get("vc")
	mi.visibility_range_end = 120.0
	pivot.add_child(mi)
	info.seesaw = {"pivot": pivot, "ends": [Vector3(-1.35, 0.1, 0), Vector3(1.35, 0.1, 0)]}


static func _sandbox(city: Sehir, body: StaticBody3D, st: SurfaceTool, xf: Transform3D, o: Vector3) -> void:
	var wood := Sehir._vc("#a8744a")
	for sz: float in [-1.0, 1.0]:
		Sehir._box(st, xf, o + Vector3(0, FLOOR + 0.12, sz * 1.0), Vector3(2.6, 0.24, 0.14), wood)
		Sehir._box(st, xf, o + Vector3(sz * 1.25, FLOOR + 0.12, 0), Vector3(0.14, 0.24, 2.0), wood)
	_flat(st, xf, o.x - 1.2, o.z - 0.95, o.x + 1.2, o.z + 0.95, FLOOR + 0.14, Sehir._vc("#f0dca0"))
	# Kova ve kürek
	Sehir._box(st, xf, o + Vector3(0.4, FLOOR + 0.22, 0.3), Vector3(0.16, 0.16, 0.16), Sehir._vc("#e0573f"))
	Sehir._box(st, xf, o + Vector3(-0.3, FLOOR + 0.17, -0.2), Vector3(0.3, 0.04, 0.08), Sehir._vc("#3f7fc4"))


static func _spring_rider(city: Sehir, body: StaticBody3D, st: SurfaceTool, xf: Transform3D, o: Vector3, col: String) -> void:
	Sehir._box(st, xf, o + Vector3(0, FLOOR + 0.2, 0), Vector3(0.1, 0.4, 0.1), Sehir._vc("#7b7d80"))
	Sehir._box(st, xf, o + Vector3(0, FLOOR + 0.5, 0), Vector3(0.7, 0.3, 0.28), Sehir._vc(col))
	Sehir._box(st, xf, o + Vector3(0.35, FLOOR + 0.72, 0), Vector3(0.22, 0.26, 0.24), Sehir._vc(col))
	Sehir._box(st, xf, o + Vector3(0.18, FLOOR + 0.72, 0), Vector3(0.04, 0.12, 0.36), Sehir._vc("#3a3a3a"))
	city._shape_box(body, Vector3(0.7, 0.75, 0.3), xf * Transform3D(Basis(), o + Vector3(0, FLOOR + 0.38, 0)))
