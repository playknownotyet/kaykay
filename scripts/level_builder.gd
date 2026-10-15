@tool
extends Node3D
## Gri kutu test pisti. Tüm geometri koddan üretilir; editörde de görünür.
## Oyuncu (0, 0, 0) noktasında -Z yönüne bakarak başlar.

const GRID_SHADER := preload("res://shaders/grid.gdshader")
const COBBLE_SHADER := preload("res://shaders/cobble.gdshader")

const COL_GROUND := Color(0.62, 0.68, 0.78)
const COL_GRASS := Color(0.42, 0.78, 0.36)
const COL_RAMP := Color(1.0, 0.62, 0.25)
const COL_HILL := Color(0.95, 0.82, 0.35)
const COL_CURB := Color(0.95, 0.95, 0.95)
const COL_RAIL := Color(0.95, 0.3, 0.45)
const COL_LEDGE := Color(0.55, 0.45, 0.95)
const COL_BANK := Color(0.3, 0.75, 0.95)
const COL_CONE := Color(1.0, 0.45, 0.15)
const BUILDING_COLORS := [
	Color(0.98, 0.55, 0.6), Color(0.5, 0.8, 0.98), Color(0.98, 0.85, 0.4),
	Color(0.6, 0.9, 0.6), Color(0.8, 0.6, 0.95), Color(1.0, 0.7, 0.45),
]

var _materials := {}
## Bundan sonra eklenen parçaların yüzey türü (titreşim / kamera hissi için).
## Kaykay kontrolcüsü yerdeki gövdenin "surface" bilgisini okur.
var _surface := "asfalt"
var _ground_holes: Array[Vector4] = []   # zeminin çizilmeyeceği alanlar (arnavut kaldırımı altı)


func _ready() -> void:
	if get_child_count() > 0:
		return
	_build()


func _build() -> void:
	# Zemin: geniş meydan + etrafında çim halkası (üst üste binmez).
	# Karolara bölünmüş düzlemler: poligon titremesi (vertex snap) dev
	# üçgenlerde derinliği bozar, küçük karolarda bozmaz.
	_surface = "asfalt"
	_add_ground(Vector3(0, 0, 0), Vector2(200, 200), COL_GROUND, 2.0)
	_surface = "cim"
	_add_ground(Vector3(0, 0, 115), Vector2(260, 30), COL_GRASS, 4.0)
	_add_ground(Vector3(0, 0, -115), Vector2(260, 30), COL_GRASS, 4.0)
	_add_ground(Vector3(115, 0, 0), Vector2(30, 200), COL_GRASS, 4.0)
	_add_ground(Vector3(-115, 0, 0), Vector2(30, 200), COL_GRASS, 4.0)

	# Arnavut kaldırımı: başlangıcın solunda uzun şerit + kaldırımlardan sonra
	# yolu boydan boya kesen meydan (titreşim / kamera hissini denemek için)
	_add_cobble(Vector3(-15, 0, -20), Vector2(6, 60))
	_add_cobble(Vector3(0, 0, -86), Vector2(40, 12))
	_apply_ground_holes()

	_surface = "asfalt"
	# Başlangıç düzlüğü: slalom dubaları
	for i in range(6):
		var x := 1.2 if i % 2 == 0 else -1.2
		_add_cylinder(Vector3(x, 0, -14 - i * 6), 0.18, 0.7, COL_CONE)

	# Rampalar kontrplak (tahta)
	_surface = "tahta"
	# Küçük kicker rampa (ollie'siz uçmak için)
	_add_wedge(Vector3(7, 0, -22), 2.4, 0.55, 2.6, 0.0, COL_RAMP)

	# Funbox: çık - düzlük - in
	_add_wedge(Vector3(-9, 0, -26), 3.0, 0.8, 3.2, 0.0, COL_RAMP)
	_add_box(Vector3(-9, 0.4, -29.6), Vector3(3.0, 0.8, 4.0), COL_RAMP)
	_add_wedge(Vector3(-9, 0, -33.2), 3.0, 0.8, 3.2, 180.0, COL_RAMP)
	for x in [-10.5, -7.5]:
		_add_grind_line(Vector3(x, 0.8, -27.6), Vector3(x, 0.8, -31.6), "metal")   # rampa ağzı (coping)

	# Kaldırım ve bank sırası (ollie ile geçilecek): beton
	_surface = "beton"
	_add_box(Vector3(0, 0.075, -58), Vector3(10, 0.15, 0.4), COL_CURB)
	_add_box(Vector3(0, 0.075, -66), Vector3(10, 0.15, 0.4), COL_CURB)
	_add_box(Vector3(-5, 0.22, -74), Vector3(3, 0.45, 0.6), COL_LEDGE)
	_add_box(Vector3(5, 0.22, -74), Vector3(3, 0.45, 0.6), COL_LEDGE)
	for z in [-58.0, -66.0]:
		_add_grind_line(Vector3(-5, 0.15, z), Vector3(5, 0.15, z))
	for x in [-5.0, 5.0]:
		_add_grind_line(Vector3(x - 1.5, 0.445, -74), Vector3(x + 1.5, 0.445, -74))

	# Grind: korkuluk ve kenar
	_add_rail(Vector3(15, 0.38, -35), Vector3(15, 0.38, -45))
	_surface = "beton"
	_add_box(Vector3(20, 0.2, -40), Vector3(0.6, 0.4, 10), COL_LEDGE)
	_add_grind_line(Vector3(20, 0.4, -35), Vector3(20, 0.4, -45))

	# Başlangıca yakın, denemesi kolay düz korkuluk
	_add_rail(Vector3(4.5, 0.38, -6), Vector3(4.5, 0.38, -18))

	# Uzun tepe: yavaş tırmanış, düzlük, keyifli iniş
	_surface = "asfalt"
	_add_wedge(Vector3(-28, 0, -10), 8.0, 3.0, 30.0, 0.0, COL_HILL)
	_add_box(Vector3(-28, 1.5, -32.5), Vector3(8.0, 3.0, 15.0), COL_HILL)
	_add_wedge(Vector3(-28, 0, -55), 8.0, 3.0, 30.0, 180.0, COL_HILL)
	# İnişe paralel eğimli korkuluk: yerçekimiyle hızlanan grind
	_add_rail(Vector3(-25.5, 3.25, -41), Vector3(-25.5, 0.4, -69.5))

	# Eğimli duvar (bank)
	_surface = "beton"
	_add_wedge(Vector3(34, 0, -40), 30.0, 2.2, 3.5, -90.0, COL_BANK)
	_add_grind_line(Vector3(35.75, 2.2, -25.5), Vector3(35.75, 2.2, -54.5), "metal")

	# Uzaktaki renkli bloklar: yön bulmak ve hız hissi için
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(28):
		var angle := TAU * i / 28.0
		var r := rng.randf_range(70.0, 90.0)
		var size := Vector3(rng.randf_range(6, 14), rng.randf_range(5, 18), rng.randf_range(6, 14))
		var pos := Vector3(cos(angle) * r, size.y * 0.5, sin(angle) * r)
		_add_box(pos, size, BUILDING_COLORS[i % BUILDING_COLORS.size()], 3.0)

	# Dünya sınırı
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var along_x: bool = side.z != 0
		var size := Vector3(200 if along_x else 1, 3, 1 if along_x else 200)
		_add_box(side * 100.5 + Vector3(0, 1.5, 0), size, COL_CURB)


# ---------- Yardımcılar ----------

func _material(color: Color, cell := 1.0) -> Material:
	var key := "%s_%s" % [color.to_html(), cell]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("line_color", color.darkened(0.15))
	mat.set_shader_parameter("cell_size", cell)
	_materials[key] = mat
	return mat


func _add_body(pos: Vector3, yaw_deg: float, mesh: Mesh, shape: Shape3D, color: Color, cell: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = yaw_deg
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color, cell)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.set_meta("surface", _surface)
	add_child(body)
	return body


## Görünür korkuluk: ince kutu + ayaklar + grind çizgisi. a ve b üst yüzeyde.
func _add_rail(a: Vector3, b: Vector3) -> void:
	var dir := (b - a).normalized()
	var length := a.distance_to(b)
	var rb := Basis.looking_at(dir, Vector3.UP)
	var body := StaticBody3D.new()
	body.transform = Transform3D(rb, (a + b) * 0.5 - rb.y * 0.03)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.06, length)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(COL_RAIL, 0.5)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	col.shape = shape
	body.add_child(col)
	body.set_meta("surface", "metal")
	add_child(body)
	# Ayaklar: rayın 0.35 m altına kadar (zemine ya da eğime değer)
	var posts := maxi(int(length / 4.0), 1) + 1
	for i in posts:
		var p := a.lerp(b, (i + 0.5) / float(posts))
		_add_box(p - Vector3(0, 0.2, 0), Vector3(0.06, 0.34, 0.06), COL_RAIL, 0.5)
	_add_grind_line(a, b, "metal")


## surface boşsa o anki _surface (örn. beton kenar) kullanılır.
func _add_grind_line(a: Vector3, b: Vector3, surface := "") -> void:
	var rail := GrindRail.new()
	add_child(rail)
	rail.setup(a, b, surface if surface != "" else _surface)


## Zemin malzemesine delikleri ver: arnavut kaldırımının altındaki zemin çizilmez.
func _apply_ground_holes() -> void:
	var mat := _material(COL_GROUND, 2.0)
	var arr := PackedVector4Array()
	for h in _ground_holes:
		arr.append(h)
	while arr.size() < 8:
		arr.append(Vector4.ZERO)
	mat.set_shader_parameter("holes", arr)
	mat.set_shader_parameter("hole_count", _ground_holes.size())


## Arnavut kaldırımı alanı: zeminden 1.2 cm yüksek (girişte hafif bir sarsıntı da verir).
## Altındaki zemin çizilmez (bkz. _apply_ground_holes), böylece katmanlar titreşmez.
func _add_cobble(center: Vector3, size: Vector2) -> void:
	# Delik kaldırımdan 2 cm küçük: kenarda boşluk görünmesin
	_ground_holes.append(Vector4(center.x - size.x * 0.5 + 0.02, center.z - size.y * 0.5 + 0.02,
		center.x + size.x * 0.5 - 0.02, center.z + size.y * 0.5 - 0.02))
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = maxi(int(size.x / 3.0) - 1, 0)
	mesh.subdivide_depth = maxi(int(size.y / 3.0) - 1, 0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 0.2, size.y)
	var body := StaticBody3D.new()
	body.position = center + Vector3(0, 0.012, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = COBBLE_SHADER
	mi.material_override = mat
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -0.1
	body.add_child(col)
	body.set_meta("surface", "arnavut")
	add_child(body)


## Yatay zemin: görsel olarak ~5 m karolara bölünmüş düzlem, çarpışma için ince kutu.
func _add_ground(center: Vector3, size: Vector2, color: Color, cell: float) -> StaticBody3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = int(size.x / 5.0) - 1
	mesh.subdivide_depth = int(size.y / 5.0) - 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 1.0, size.y)
	var body := _add_body(center, 0.0, mesh, shape, color, cell)
	body.get_child(1).position.y = -0.5
	return body


func _add_box(pos: Vector3, size: Vector3, color: Color, cell := 1.0) -> StaticBody3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	return _add_body(pos, 0.0, mesh, shape, color, cell)


func _add_cylinder(base_pos: Vector3, radius: float, height: float, color: Color) -> StaticBody3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.4
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return _add_body(base_pos + Vector3(0, height * 0.5, 0), 0.0, mesh, shape, color, 0.5)


## Rampa (üçgen prizma). base_center: tabanın merkezi.
## Yerel olarak -Z yönüne doğru yükselir; yaw ile döndürülür.
func _add_wedge(base_center: Vector3, width: float, height: float, length: float, yaw_deg: float, color: Color) -> StaticBody3D:
	var hw := width * 0.5
	var hl := length * 0.5
	var a := Vector3(-hw, 0, hl)
	var b := Vector3(hw, 0, hl)
	var c := Vector3(-hw, 0, -hl)
	var d := Vector3(hw, 0, -hl)
	var e := Vector3(-hw, height, -hl)
	var f := Vector3(hw, height, -hl)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope_n := Vector3(0, length, height).normalized()
	_quad(st, a, b, f, e, slope_n)
	_quad(st, c, d, f, e, Vector3(0, 0, -1))
	_quad(st, a, b, d, c, Vector3(0, -1, 0))
	_tri(st, a, c, e, Vector3(-1, 0, 0))
	_tri(st, b, d, f, Vector3(1, 0, 0))
	var mesh := st.commit()

	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a, b, c, d, e, f])
	return _add_body(base_center, yaw_deg, mesh, shape, color, 1.0)


func _tri(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	# Godot ön yüzü saat yönünde sayar; dışarı bakan normale göre sırayı düzelt
	if (p2 - p1).cross(p3 - p1).dot(n) > 0.0:
		var tmp := p2
		p2 = p3
		p3 = tmp
	st.set_normal(n)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p3)


func _quad(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3, n: Vector3) -> void:
	_tri(st, p1, p2, p3, n)
	_tri(st, p1, p3, p4, n)
