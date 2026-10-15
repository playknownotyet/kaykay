class_name GrindRail
extends Node3D
## Grind yapılabilecek bir çizgi (korkuluk, kenar, kaldırım, rampa ağzı).
## a ve b dünya koordinatında, kaykayın oturacağı üst yüzeydeki iki uç nokta.
## Kontrolcü "grind_rails" grubundaki tüm rayları tarar.

var a := Vector3.ZERO
var b := Vector3.ZERO
var length := 0.0
var direction := Vector3.FORWARD


func setup(p_a: Vector3, p_b: Vector3) -> GrindRail:
	a = p_a
	b = p_b
	length = a.distance_to(b)
	direction = (b - a) / maxf(length, 0.001)
	add_to_group("grind_rails")
	return self


func point_at(s: float) -> Vector3:
	return a + direction * s


## a'dan itibaren, p noktasına en yakın noktanın ray üzerindeki uzaklığı.
func closest_s(p: Vector3) -> float:
	return clampf((p - a).dot(direction), 0.0, length)
