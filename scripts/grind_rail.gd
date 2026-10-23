class_name GrindRail
extends Node3D
## Grind yapılabilecek bir çizgi (korkuluk, kenar, kaldırım, rampa ağzı).
## a ve b dünya koordinatında, kaykayın oturacağı üst yüzeydeki iki uç nokta.
## Kontrolcü "grind_rails" grubundaki tüm rayları tarar.
## Değerler kaydedilir: hazır sahnelerden (ör. scenes/ada.scn) yüklenince de çalışır.

@export var a := Vector3.ZERO
@export var b := Vector3.ZERO
## "metal" (korkuluk, rampa ağzı) ya da "beton" (kenar, kaldırım): grind hissi buna göre
@export var surface := "metal"
var length := 0.0
var direction := Vector3.FORWARD

## Yakındaki rayları hızlı bulmak için ızgara (16 m hücre): kontrolcü her havada karede binlerce rayı
## taramasın, yalnız çevresindeki hücrelere baksın
const HUCRE := 16.0
static var _grid := {}
var _cells: Array[Vector2i] = []


func _ready() -> void:
	setup(a, b, surface)


func setup(p_a: Vector3, p_b: Vector3, p_surface := "metal") -> GrindRail:
	surface = p_surface
	a = p_a
	b = p_b
	length = a.distance_to(b)
	direction = (b - a) / maxf(length, 0.001)
	if not is_in_group("grind_rails"):
		add_to_group("grind_rails")
	_unregister()
	var n := int(ceilf(length / (HUCRE * 0.5))) + 1
	for i in n + 1:
		var q := a.lerp(b, float(i) / n)
		var c := Vector2i(floori(q.x / HUCRE), floori(q.z / HUCRE))
		if not _cells.has(c):
			_cells.append(c)
			if not _grid.has(c):
				_grid[c] = []
			(_grid[c] as Array).append(self)
	return self


func _exit_tree() -> void:
	_unregister()


func _unregister() -> void:
	for c in _cells:
		if _grid.has(c):
			(_grid[c] as Array).erase(self)
	_cells.clear()


## p çevresindeki (3x3 hücre) raylar
static func near(p: Vector3) -> Array:
	var cx := floori(p.x / HUCRE)
	var cz := floori(p.z / HUCRE)
	var out := []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var c := Vector2i(cx + dx, cz + dz)
			if _grid.has(c):
				for r in _grid[c]:
					if not out.has(r):
						out.append(r)
	return out


func point_at(s: float) -> Vector3:
	return a + direction * s


## a'dan itibaren, p noktasına en yakın noktanın ray üzerindeki uzaklığı.
func closest_s(p: Vector3) -> float:
	return clampf((p - a).dot(direction), 0.0, length)
