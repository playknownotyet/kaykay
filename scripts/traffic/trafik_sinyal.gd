class_name TrafikSinyal
## Kavşak ışıklarının zamanlaması (tools/ada/trafik.js ile aynı düzen). Durum saatten hesaplanır:
## kimse bir şey güncellemez, ışık başları, arabalar ve yayalar aynı anda aynı şeyi görür.
##
## Bir döngü: kollar sırayla (yeşil, sarı, hepsi kırmızı), sonra tüm yayalara yeşil (o sırada
## bütün arabalar kırmızıda), yanıp sönen yeşil, hepsi kırmızı.

const DATA_PATH := "res://assets/ada/trafik.json"

enum { KIRMIZI = 1, SARI = 2, YESIL = 3, YESIL_YANIP = 4 }

static var data: Dictionary
static var _t: Dictionary
static var _junctions: Array


static func ensure() -> bool:
	if data.is_empty():
		if not FileAccess.file_exists(DATA_PATH):
			return false
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_t = data.timing
		_junctions = data.junctions
	return true


static func now() -> float:
	return Time.get_ticks_msec() * 0.001


## Kolun faz grubu: [başlangıç (döngü içinde), yeşil süresi]; ışıksız kol için boş
static func _slot(J: Dictionary, arm: int) -> Vector2:
	var t0 := 0.0
	for g in J.groups:
		var arms: Array = g.arms
		if arms.has(float(arm)) or arms.has(arm):
			return Vector2(t0, float(g.g))
		t0 += float(g.g) + _t.yellow + _t.allRed
	return Vector2(-1, 0)


## Kolun araç ışığı (KIRMIZI / SARI / YESIL).
static func car_state(j: int, arm: int, t: float) -> int:
	var J: Dictionary = _junctions[j]
	var sl := _slot(J, arm)
	if sl.x < 0.0:
		return YESIL
	var u := fposmod(t + float(J.offset), float(J.cycle)) - sl.x
	if u < 0.0 or u >= sl.y + _t.yellow:
		return KIRMIZI
	return YESIL if u < sl.y else SARI


## Işıklı kavşak mı? (ışıksızda ana yol öncelikli, yan yol yol verir)
static func is_signalized(j: int) -> bool:
	return not (_junctions[j].groups as Array).is_empty()


## Işıksız kavşakta bu kol yol vermeli mi?
static func must_yield(j: int, arm: int) -> bool:
	var y: Array = _junctions[j].get("yield", [])
	return y.has(float(arm)) or y.has(arm)


## Işıksız kavşağın öncelikli gelen kolları
static func main_arms(j: int) -> Array:
	var out := []
	for a in _junctions[j].get("main", []):
		out.append(int(a))
	return out


## Aynı fazda yeşil yanan diğer kollar (sola dönen bunlardan gelene yol verir).
## Işıksız kavşakta: öncelikli diğer kollar.
static func same_phase(j: int, arm: int) -> Array:
	if not is_signalized(j):
		var m := main_arms(j)
		if not m.has(arm):
			return []
		m.erase(arm)
		return m
	for g in _junctions[j].groups:
		var arms: Array = g.arms
		if arms.has(float(arm)) or arms.has(arm):
			var out := []
			for a in arms:
				if int(a) != arm:
					out.append(int(a))
			return out
	return []


static func _ped_start(J: Dictionary) -> float:
	var t0 := 0.0
	for g in J.groups:
		t0 += float(g.g) + _t.yellow + _t.allRed
	return t0


## Kavşağın yaya ışığı (KIRMIZI / YESIL / YESIL_YANIP). arm verilirse o kolun yaya geçidi.
static func ped_state(j: int, t: float, arm := -1) -> int:
	var left := ped_time_left(j, t, arm)
	if left <= 0.0:
		return KIRMIZI
	return YESIL if left > _t.pedFlash else YESIL_YANIP


## Yaya yeşilinin bitmesine kalan süre; kırmızıdaysa 0.
## Tüm yayalara yeşil fazında her geçit; ayrıca bir kolun kendi trafiği kırmızıyken, o anda yeşil
## yanan grubun yeşili boyunca o kolun geçidi (dönerek gelen arabalar yayaya yol verir).
static func ped_time_left(j: int, t: float, arm := -1) -> float:
	var J: Dictionary = _junctions[j]
	if (J.groups as Array).is_empty():
		return 99.0          # ışıksız: yaya geçidinde yaya önceliklidir, arabalar durur
	var u := fposmod(t + float(J.offset), float(J.cycle))
	var s0 := _ped_start(J)
	var s1: float = s0 + float(_t.get("pedAll", _t.pedWalk + _t.pedFlash))
	if u >= s0 and u < s1:
		return s1 - u
	if arm < 0:
		return 0.0
	var t0 := 0.0
	for g in J.groups:
		var arms: Array = g.arms
		var g_end: float = t0 + float(g.g)
		if u >= t0 and u < g_end:
			if arms.has(float(arm)) or arms.has(arm):
				return 0.0
			return g_end - u
		t0 = g_end + _t.yellow + _t.allRed
	return 0.0
