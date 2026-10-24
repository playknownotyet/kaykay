extends Node
## Şehre kaykaylanabilir sokak eşyalarını şehrin doğal düzeninde yerleştirir: sahil yolunda denize
## bakan bank dizileri (aralarında atlanabilir), meydanda çeşme ve çevresinde oturak saksılar,
## yeşil alanların kaldırıma bakan kenarlarında alçak taş duvar, ana caddelerde otobüs durakları.
## Her öğe çakışma / zemin denetiminden geçer. Çıktı: assets/ada/esyalar.json
##   godot --headless --path . res://tools/sehir/esya_yerlestir.tscn

const OUT := "res://assets/ada/esyalar.json"
## Tür: ayak izi (en x, derinlik z) ve yükseklik; model önü yerel +Z
const TURLER := {
	"bank": [Vector2(1.6, 0.6), 0.85],
	"cop_kutusu": [Vector2(0.55, 0.55), 0.95],
	"tas_duvar": [Vector2(2.0, 0.4), 0.45],
	"oturak_saksi": [Vector2(2.6, 0.9), 0.5],
	"otobus_duragi": [Vector2(3.6, 1.5), 2.6],
	"cesme": [Vector2(3.2, 3.2), 1.8],
	"saksi": [Vector2(0.95, 0.45), 0.75],
	"kafe_seti": [Vector2(1.8, 1.8), 2.3],
	"yuvarlak_saksi": [Vector2(1.3, 1.3), 1.1],
	"sezlong_semsiye": [Vector2(2.2, 2.2), 2.4],
	"simit_arabasi": [Vector2(1.4, 0.8), 1.8],
	"elektrik_kutusu": [Vector2(0.9, 0.4), 1.2],
	"cati_klima": [Vector2(1.1, 0.7), 0.8],
	"su_deposu": [Vector2(1.2, 1.2), 1.5],
	"posta_kutusu": [Vector2(0.5, 0.45), 1.25],
	"bufe": [Vector2(2.2, 1.8), 2.7],
	"trafik_konisi": [Vector2(0.4, 0.4), 0.6],
	"cop_konteyneri": [Vector2(1.4, 1.0), 1.3],
	"icecek_otomati": [Vector2(0.9, 0.8), 1.9],
	"halat_babasi": [Vector2(0.45, 0.45), 0.55],
	"balikci_kasasi": [Vector2(1.2, 0.8), 0.7],
	"sandal": [Vector2(4.0, 1.6), 1.0],
	"bisiklet": [Vector2(1.7, 0.5), 1.0],
	"iskele_modul": [Vector2(4.0, 4.8), 3.5],
	"iskele_uc": [Vector2(4.0, 4.8), 3.5],
	"varil": [Vector2(0.62, 0.62), 0.93],
	"manav_tezgahi": [Vector2(1.6, 0.8), 1.0],
	"cicekci_standi": [Vector2(1.4, 0.6), 1.1],
	"kiyafet_askisi": [Vector2(1.4, 0.5), 1.6],
	"menu_tahtasi": [Vector2(0.6, 0.55), 1.0],
	"firin_standi": [Vector2(1.2, 0.6), 1.0],
	"kitap_standi": [Vector2(1.2, 0.6), 1.2],
	"gazete_standi": [Vector2(0.6, 0.6), 1.6],
}
## Zemin katı dükkân olan binalara sabit tür (bina kimliğinden) ve önüne konan teşhir eşyası
const DUKKAN_TURU := ["manav", "cicekci", "butik", "kafe", "firin", "kitapci", "bakkal"]
const TESHIR := {"manav": "manav_tezgahi", "cicekci": "cicekci_standi", "butik": "kiyafet_askisi",
	"kafe": "menu_tahtasi", "firin": "firin_standi", "kitapci": "kitap_standi", "bakkal": "gazete_standi"}
## Yeni iskele (modüllerle): en ve döşeme yüksekliği (modelin kazık altından döşeme üstüne)
const ISKELE_EN := 4.8
const ISKELE_DOSEME := 2.5
## Üstüne eşya konabilecek zeminler (yol / kavşak değil)
const ZEMIN := ["KaldirimCarpisma", "MeydanCarpisma", "AraziCarpisma", "Iskele_0", "Iskele_1"]
const DUZ_ZEMIN := ["KaldirimCarpisma", "MeydanCarpisma", "Iskele_0", "Iskele_1"]

var space: PhysicsDirectSpaceState3D
var placed: Array = []          # [tur, Vector3, yaw]
var sayac := {}
var ret := {}


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 150:
		await get_tree().physics_frame
	space = main.player.get_world_3d().direct_space_state
	# Önceki üretimin eşyaları sayılmasın; adanın eski eşya yerleri (yenisiyle değişenler) dolu kabul edilir
	var es: Esyalar = Esyalar.instance
	if es:
		for it in es.items:
			if it.get("eski", false) and TURLER.has(it.t):
				placed.append([it.t, Vector3(it.p[0], it.p[1], it.p[2]), deg_to_rad(float(it.r)), true])
		es.queue_free()
		for i in 3:
			await get_tree().physics_frame
	var ada: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ada/ada.json"))
	var sehir: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ada/sehir.json"))
	_meydan(ada)
	_sahil(ada)
	_duraklar(ada)
	_bahce_duvarlari(ada)
	_dukkan_onleri(sehir)
	_kumsal(ada)
	_kaldirim_susleri(ada)
	_meydan_tezgahlari(ada)
	_catilar(sehir)
	_iskeleler(ada)
	_sokak_ayrintilari(ada, sehir)
	var out := []
	for p in placed:
		if p.size() > 3:
			continue
		var v: Vector3 = p[1]
		out.append({"t": p[0], "p": [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)], "r": snappedf(rad_to_deg(p[2]), 0.1)})
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "items": out}, "\t"))
	f.close()
	print("ESYA yerlestirildi: ", sayac, " reddedilen: ", ret)
	get_tree().quit()


static func ap(x: float, y: float, h := 0.0) -> Vector3:
	return Vector3(x, h, -y)


## Zemin noktası (eşya konabilecek ilk yüzey) ya da INF
func _zemin(x: float, z: float, duz := false) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -50, z))
	var h := space.intersect_ray(q)
	if h.is_empty():
		return Vector3.INF
	var nm := String((h.collider as Node).name)
	if not nm in (DUZ_ZEMIN if duz else ZEMIN):
		return Vector3.INF
	return h.position


## Türü bu yere (taban ortası, yaw) koyabilir miyim? Zemin düz ve izinli, içinde başka gövde yok,
## önceden konanlarla çakışmıyor
func _koy(tur: String, x: float, z: float, yaw: float, duz := false, pay := 0.15) -> bool:
	var spec: Array = TURLER[tur]
	var fp: Vector2 = spec[0]
	var b := Basis(Vector3.UP, yaw)
	var c := _zemin(x, z, duz)
	if c == Vector3.INF:
		return _red(tur, "zemin")
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var k: Vector3 = c + b * Vector3(s.x * fp.x * 0.5, 0, s.y * fp.y * 0.5)
		var g := _zemin(k.x, k.z, duz)
		if g == Vector3.INF or absf(g.y - c.y) > 0.18:
			return _red(tur, "egim")
	var sh := BoxShape3D.new()
	sh.size = Vector3(fp.x + pay * 2.0, float(spec[1]) - 0.1, fp.y + pay * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(b, c + Vector3.UP * (0.1 + sh.size.y * 0.5))
	for h in space.intersect_shape(q, 4):
		var nm := String((h.collider as Node).name)
		if not nm in ZEMIN:
			return _red(tur, nm.left(12))
	var r := fp.length() * 0.5
	for p in placed:
		var o: Vector3 = p[1]
		var ofp: Vector2 = TURLER[p[0]][0]
		# Aynı yöne bakan dizi elemanları yakın durabilir; farklı yönlüler arasında yürüme payı
		var ayni := absf(angle_difference(float(p[2]), yaw)) < 0.2
		if Vector2(o.x - c.x, o.z - c.z).length() < r + ofp.length() * 0.5 + (-0.1 if ayni else 1.0):
			return _red(tur, "esya")
	placed.append([tur, c, yaw])
	sayac[tur] = int(sayac.get(tur, 0)) + 1
	return true


func _red(tur: String, neden: String) -> bool:
	var k := tur + ":" + neden
	ret[k] = int(ret.get(k, 0)) + 1
	return false


## Yön vektöründen yaw: model önü (+Z) bu yöne baksın
static func _yaw(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


# ---------- Meydan: çeşme, çevresinde iki yay oturak saksı, çeşmeye bakan banklar ----------

func _meydan(ada: Dictionary) -> void:
	var pl: Dictionary = ada.plaza
	var c := ap(pl.x, pl.y)
	_koy("cesme", c.x, c.z, 0.0, true)
	var R := 9.5
	# Kuzey ve güney yayında üçer oturak saksı: aralarında ~2,6 m boşluk, birinden ötekine atlanır
	var adim := (2.6 + 2.6) / R
	for merkez: float in [PI * 0.5, -PI * 0.5]:
		for k in [-1, 0, 1]:
			var a: float = merkez + k * adim
			var radial := Vector3(cos(a), 0, sin(a))
			var p := c + radial * R
			_koy("oturak_saksi", p.x, p.z, _yaw(radial), true)
	# Doğu ve batıda çeşmeye bakan iki bank
	for merkez: float in [0.0, PI]:
		for k in [-1, 1]:
			var a: float = merkez + k * 0.32
			var radial := Vector3(cos(a), 0, sin(a))
			var p := c + radial * 6.5
			_koy("bank", p.x, p.z, _yaw(-radial), true)


# ---------- Sahil yolu: denize bakan bank dizileri (üçlü, 2,8 m arayla), sonunda çöp kutusu ----------

func _sahil(ada: Dictionary) -> void:
	var merkez := _ada_merkezi(ada)
	for run in ada.sidewalks:
		if String(run.road) != "ring":
			continue
		var pts: Array = run.pts
		if pts.size() < 4:
			continue
		# Deniz tarafı kaldırım: dış kenarı ada merkezine iç kenardan uzak
		var p0: Array = pts[pts.size() / 2]
		var ic := Vector2(p0[0], p0[1]).distance_to(merkez)
		var dis := Vector2(p0[2], p0[3]).distance_to(merkez)
		if dis <= ic:
			continue
		var line := []        # dış kenardan 0,75 m içeride çizgi (dünya) ve dışa yön
		for p: Array in pts:
			var a := ap(p[0], p[1])
			var b := ap(p[2], p[3])
			var out := (b - a)
			out.y = 0
			if out.length() < 0.5:
				continue
			out = out.normalized()
			# Dış kenarda deniz bariyeri var: bank kenardan 1,3 m içeride
			line.append([b - out * 1.3, out])
		var s := 12.0
		var L := _uzunluk(line)
		while s + 13.0 < L:
			var ok := 0
			var yon0: Vector3 = _nokta(line, s)[1]
			var yon1: Vector3 = _nokta(line, s + 9.0)[1]
			if yon0.dot(yon1) > 0.96:      # düzce bir kesimde
				for k in 3:
					var np: Array = _nokta(line, s + k * 4.4)
					var pos: Vector3 = np[0]
					if _koy("bank", pos.x, pos.z, _yaw(np[1])):
						ok += 1
				if ok > 0:
					var cp: Array = _nokta(line, s + 11.6)
					var cpos: Vector3 = cp[0] - (cp[1] as Vector3) * 0.1
					_koy("cop_kutusu", cpos.x, cpos.z, _yaw(cp[1]))
			s += 46.0 if ok > 0 else 8.0


static func _ada_merkezi(ada: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for r in ada.roads:
		if String(r.id) == "ring":
			var rib: Array = r.rib
			for i in range(0, rib.size()):
				var row: Array = rib[i]
				sum += Vector2(row[3], row[4]) if row.size() > 4 else Vector2(row[0], row[1])
				n += 1
	return sum / maxf(n, 1)


static func _uzunluk(line: Array) -> float:
	var L := 0.0
	for i in range(1, line.size()):
		L += (line[i][0] as Vector3).distance_to(line[i - 1][0])
	return L


static func _nokta(line: Array, s: float) -> Array:
	var acc := 0.0
	for i in range(1, line.size()):
		var a: Vector3 = line[i - 1][0]
		var b: Vector3 = line[i][0]
		var d := a.distance_to(b)
		if acc + d >= s:
			var t := (s - acc) / maxf(d, 0.001)
			var o: Vector3 = (line[i - 1][1] as Vector3).lerp(line[i][1], t).normalized()
			return [a.lerp(b, t), o]
		acc += d
	return [line[line.size() - 1][0], line[line.size() - 1][1]]


# ---------- Otobüs durakları: ana caddelerin kaldırımlarında, yola bakar ----------

func _duraklar(ada: Dictionary) -> void:
	for run in ada.sidewalks:
		var rid := String(run.road)
		if not rid.begins_with("av") or int(run.get("side", 1)) != 1:
			continue
		var pts: Array = run.pts
		var line := []
		for p: Array in pts:
			var a := ap(p[0], p[1])
			var b := ap(p[2], p[3])
			var out := b - a
			out.y = 0
			if out.length() < 0.5:
				continue
			out = out.normalized()
			# Durağın ortası dış kenardan derinliğin yarısı + pay kadar içeride; önü yola (içe)
			line.append([b - out * 1.0, -out])
		var L := _uzunluk(line)
		var s := 60.0
		while s < L - 30.0:
			var np: Array = _nokta(line, s)
			var pos: Vector3 = np[0]
			if _koy("otobus_duragi", pos.x, pos.z, _yaw(np[1]), true):
				s += 420.0
			else:
				s += 15.0


# ---------- Bahçe duvarları: kaldırımın dış kenarı çime / araziye bakıyorsa alçak taş duvar ----------

func _bahce_duvarlari(ada: Dictionary) -> void:
	var toplam := 0
	for run in ada.sidewalks:
		var rid := String(run.road)
		if rid == "ada" or rid == "plaza":
			continue
		var pts: Array = run.pts
		var line := []
		for p: Array in pts:
			var a := ap(p[0], p[1])
			var b := ap(p[2], p[3])
			var out := b - a
			out.y = 0
			if out.length() < 0.5:
				continue
			out = out.normalized()
			line.append([b - out * 0.22, out])
		var L := _uzunluk(line)
		var s := 6.0
		var dizi := 0
		var bu_run := 0
		while s + 2.0 < L and toplam < 520 and bu_run < 24:
			var np0: Array = _nokta(line, s)
			var np1: Array = _nokta(line, s + 2.0)
			var p0: Vector3 = np0[0]
			var p1: Vector3 = np1[0]
			var m := (p0 + p1) * 0.5
			var along := p1 - p0
			along.y = 0
			var out: Vector3 = (np0[1] as Vector3)
			# Duvarın arkası arazi (çim) olmalı, kaldırımla aşağı yukarı aynı yükseklikte
			var arka := _zemin(m.x + out.x * 1.0, m.z + out.z * 1.0)
			var yer := _zemin(m.x - out.x * 0.6, m.z - out.z * 0.6, true)
			var ok := false
			# Arkası en az 5 m açık olmalı (bina cephesinin önüne, binalar arası dar boşluğa değil)
			var acik := false
			# Arka çim olmalı: şehrin taşla boyadığı arazi (bina önü, ara sokak) değil
			var cim := arka != Vector3.INF and Sehir.instance and not Sehir.instance.paved_at(arka.x, arka.z) \
				and not Sehir.instance.paved_at(arka.x + out.x * 2.0, arka.z + out.z * 2.0)
			if cim:
				var from := arka + Vector3.UP * 1.0
				var rq := PhysicsRayQueryParameters3D.create(from, from + out * 5.0)
				acik = space.intersect_ray(rq).is_empty()
			if acik and yer != Vector3.INF and absf(arka.y - yer.y) < 0.6 and along.length() > 1.6 \
					and (out as Vector3).dot((np1[1] as Vector3)) > 0.98:
				# Modül uzun ekseni kaldırımın gidişine hizalı, önü (+Z) kaldırıma: uç uca düzgün otursun
				var nrm := along.normalized().cross(Vector3.UP)
				if nrm.dot(out) > 0.0:
					nrm = -nrm
				var yaw := _yaw(nrm)
				ok = _koy("tas_duvar", m.x, m.z, yaw, false, 0.02)
			if ok:
				dizi += 1
				toplam += 1
				bu_run += 1
				s += 2.0
				if dizi % 8 == 0:
					s += 4.0      # giriş boşluğu
			else:
				dizi = 0
				s += 2.0


# ---------- Dükkân önleri: zemin katı dükkân olan binaların önünde iki çiçek saksısı ----------

func _dukkan_onleri(sehir: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for it in sehir.items:
		if String(it.t) != "bina" or String(it.get("zemin", "")) != "dukkan":
			continue
		var id := int(it.get("id", 0))
		var tur: String = DUKKAN_TURU[(id * 2654435761) % DUKKAN_TURU.size()]
		var c := Vector2(float(it.p[0]), float(it.p[1]))
		var b := Basis(Vector3.UP, deg_to_rad(float(it.get("r", 0.0))))
		var w := float(it.get("w", 9.0))
		var d := float(it.get("d", 8.0))
		var onde := func(lx: float, uz: float) -> Vector2:
			var lp: Vector3 = b * Vector3(lx, 0, d * 0.5 + uz)
			return Vector2(c.x + lp.x, c.y + lp.z)
		if tur == "kafe":
			# Kafe: masa seti ve kapı yanında menü tahtası
			var kp: Vector2 = onde.call(-0.3 * w, 1.5)
			_koy("kafe_seti", kp.x, kp.y, _yaw(b.z), true, 0.1)
			var mp: Vector2 = onde.call(0.3 * w, 0.6)
			_koy("menu_tahtasi", mp.x, mp.y, _yaw(b.z), true, 0.05)
			continue
		# Diğerleri: bir vitrinin önünde türünün teşhiri, ötekinin önünde saksı
		var sx := -1.0 if rng.randf() < 0.5 else 1.0
		var model: String = TESHIR[tur]
		var derin: float = (TURLER[model][0] as Vector2).y
		var tp: Vector2 = onde.call(sx * 0.3 * w, 0.35 + derin * 0.5)
		_koy(model, tp.x, tp.y, _yaw(b.z), true, 0.05)
		if rng.randf() < 0.6:
			var sp: Vector2 = onde.call(-sx * 0.32 * w, 0.55)
			_koy("saksi", sp.x, sp.y, _yaw(b.z), true, 0.05)


# ---------- Kumsal: sahil yolunun altında denize bakan şezlong + şemsiye sıraları ----------

func _kumsal(ada: Dictionary) -> void:
	var merkez := _ada_merkezi(ada)
	var toplam := 0
	for run in ada.sidewalks:
		if String(run.road) != "ring":
			continue
		var pts: Array = run.pts
		if pts.size() < 4:
			continue
		var p0: Array = pts[pts.size() / 2]
		if Vector2(p0[2], p0[3]).distance_to(merkez) <= Vector2(p0[0], p0[1]).distance_to(merkez):
			continue
		var line := []
		for p: Array in pts:
			var a := ap(p[0], p[1])
			var b := ap(p[2], p[3])
			var out := b - a
			out.y = 0
			if out.length() < 0.5:
				continue
			out = out.normalized()
			line.append([b, out])
		var L := _uzunluk(line)
		var s := 10.0
		while s < L - 10.0 and toplam < 60:
			var np: Array = _nokta(line, s)
			var out: Vector3 = np[1]
			var konan := false
			for uz: float in [9.0, 12.0, 15.0]:
				var pos: Vector3 = (np[0] as Vector3) + out * uz
				var g := _zemin(pos.x, pos.z)
				# Kum: arazi, deniz seviyesinin biraz üstünde (yükseltilmiş arazi değil)
				if g == Vector3.INF or g.y > 2.2 or g.y < 0.25:
					continue
				if _koy("sezlong_semsiye", pos.x, pos.z, _yaw(out), false, 0.3):
					toplam += 1
					konan = true
					# Her dördüncü setin biraz ilerisine kıyıya çekilmiş bir sandal
					if toplam % 4 == 0:
						var sp: Vector3 = pos + out.cross(Vector3.UP) * 6.0 + out * 1.0
						_koy("sandal", sp.x, sp.z, _yaw(out.cross(Vector3.UP)), false, 0.3)
					break
			s += 14.0 if konan else 6.0


# ---------- Kaldırım süsleri: geniş kaldırımlarda yuvarlak saksı, köşelerde elektrik kutusu ----------

func _kaldirim_susleri(ada: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for run in ada.sidewalks:
		var rid := String(run.road)
		if rid == "ada" or rid == "ring" or rid == "plaza":
			continue
		var pts: Array = run.pts
		var line := []
		for p: Array in pts:
			var a := ap(p[0], p[1])
			var b := ap(p[2], p[3])
			var out := b - a
			out.y = 0
			var w := out.length()
			if w < 0.5:
				continue
			out = out.normalized()
			line.append([b - out * 0.85, out, w])
		var L := _uzunluk(line)
		var s := 18.0 + rng.randf() * 20.0
		while s < L - 10.0:
			var np: Array = _nokta(line, s)
			var pos: Vector3 = np[0]
			if rng.randf() < 0.7:
				_koy("yuvarlak_saksi", pos.x, pos.z, 0.0, true, 0.1)
			else:
				var ep: Vector3 = pos - (np[1] as Vector3) * 0.65 + (np[1] as Vector3) * 0.6
				_koy("elektrik_kutusu", ep.x, ep.z, _yaw(-(np[1] as Vector3)), true, 0.05)
			s += 34.0 + rng.randf() * 18.0


# ---------- Meydan ve iskele çevresinde simit arabaları ----------

func _meydan_tezgahlari(ada: Dictionary) -> void:
	var pl: Dictionary = ada.plaza
	var c := ap(pl.x, pl.y)
	for a: float in [0.6, 2.4, 4.1]:
		var radial := Vector3(cos(a), 0, sin(a))
		var p := c + radial * 15.5
		_koy("simit_arabasi", p.x, p.z, _yaw(-radial), true, 0.3)
	for pier in ada.get("piers", []):
		var base := ap(pier.x, pier.y)
		var p := base + Vector3(3.5, 0, 2.0)
		_koy("simit_arabasi", p.x, p.z, 0.0, false, 0.3)
	# Meydanın kenarında büfeler (kaldırımlar dar; meydan geniş)
	for a: float in [1.45, 3.3, 5.3]:
		var radial := Vector3(cos(a), 0, sin(a))
		var p := c + radial * 21.0
		_koy("bufe", p.x, p.z, _yaw(-radial), true, 0.3)


# ---------- Düz çatılarda klima üniteleri (rampayla çatıya çıkılabiliyor) ----------

func _catilar(sehir: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var toplam := 0
	for it in sehir.items:
		if String(it.t) != "bina" or String(it.get("cati", "duz")) != "duz" or toplam > 400:
			continue
		var w := float(it.get("w", 9.0))
		var d := float(it.get("d", 8.0))
		if w < 5.0 or d < 5.0:
			continue
		var c := Vector2(float(it.p[0]), float(it.p[1]))
		var b := Basis(Vector3.UP, deg_to_rad(float(it.get("r", 0.0))))
		var n := 1 + int(rng.randf() * 2.2)
		var depo := rng.randf() < 0.35
		for k in n + (1 if depo else 0):
			var tur := "su_deposu" if depo and k == n else "cati_klima"
			var lx := rng.randf_range(-w * 0.5 + 1.2, w * 0.5 - 1.2)
			var lz := rng.randf_range(-d * 0.5 + 1.0, d * 0.5 - 1.0)
			var lp: Vector3 = b * Vector3(lx, 0, lz)
			var x := c.x + lp.x
			var z := c.y + lp.z
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -50, z))
			var h := space.intersect_ray(q)
			if h.is_empty() or (h.normal as Vector3).y < 0.95 or (h.position as Vector3).y < 5.0:
				continue
			var yaw := deg_to_rad(float(it.get("r", 0.0))) + (PI * 0.5 if rng.randf() < 0.5 else 0.0)
			var pos: Vector3 = h.position
			var ok := true
			for pp in placed:
				if (pp[1] as Vector3).distance_to(pos) < (2.0 if tur == "su_deposu" else 1.6):
					ok = false
			if ok:
				placed.append([tur, pos, yaw])
				sayac[tur] = int(sayac.get(tur, 0)) + 1
				toplam += 1


# ---------- İskele: kumsal kıyısından denize 4 m'lik modüller, ucunda uç parçası; üstünde kasalar,
# kara ucunda halat babaları ve kıyıya çekilmiş sandallar ----------

func _iskeleler(ada: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var excl: Array[RID] = []
	for n in get_tree().root.find_children("Iskele_*", "StaticBody3D", true, false):
		excl.append((n as CollisionObject3D).get_rid())
	for pier in ada.get("piers", []):
		var a := float(pier.angle)
		var ax := Vector3(cos(a), 0, -sin(a))
		var az := Vector3(sin(a), 0, cos(a))
		var c := ap(pier.x, pier.y)
		var L := float(pier.length)
		var h := float(pier.h)
		# Kara ucu: iskelenin altında (iskele sayılmadan) yüksek zemin olan uç
		var u0: Vector3 = c - ax * (L * 0.5)
		var u1: Vector3 = c + ax * (L * 0.5)
		var y0 := _alt_zemin(u0, excl)
		var y1 := _alt_zemin(u1, excl)
		var kara := u0 if y0 > y1 else u1
		var deniz_yon := ax if y0 > y1 else -ax
		# Karadan denize: yol / kaldırım / meydan bitene kadar ilerle
		var s0 := 0.0
		var son_yol := -1.0
		var k := 0.0
		while k < L * 0.6:
			var p: Vector3 = kara + deniz_yon * k
			var nm := _alt_zemin_adi(p, excl)
			if nm.begins_with("Yol") or nm.begins_with("Kavsak") or nm == "KaldirimCarpisma" or nm == "MeydanCarpisma" or nm.begins_with("Bariyer"):
				son_yol = k
			k += 0.5
		s0 = son_yol + 1.0
		var yaw := atan2(-deniz_yon.z, deniz_yon.x)
		var n := int(floorf((L - s0) / 4.0))
		for m in n:
			var mc: Vector3 = kara + deniz_yon * (s0 + 2.0 + m * 4.0)
			var tur := "iskele_uc" if m == n - 1 else "iskele_modul"
			placed.append([tur, Vector3(mc.x, h - ISKELE_DOSEME, mc.z), yaw])
			sayac[tur] = int(sayac.get(tur, 0)) + 1
		var bas: Vector3 = kara + deniz_yon * s0
		# Üstünde balıkçı kasaları (döşemenin ilk yarısında)
		for i in 3:
			var p: Vector3 = bas + deniz_yon * rng.randf_range(3.0, (L - s0) * 0.5) + az * rng.randf_range(-1.2, 1.2)
			placed.append(["balikci_kasasi", Vector3(p.x, h, p.z), yaw + rng.randf_range(-0.4, 0.4)])
			sayac["balikci_kasasi"] = int(sayac.get("balikci_kasasi", 0)) + 1
		# Döşemenin kenarına yakın birkaç varil
		for i in 2:
			var p: Vector3 = bas + deniz_yon * rng.randf_range(6.0, (L - s0) * 0.8) + az * (1.6 if i == 0 else -1.6)
			placed.append(["varil", Vector3(p.x, h, p.z), rng.randf() * TAU])
			sayac["varil"] = int(sayac.get("varil", 0)) + 1
		# Kara ucunda, iskele başının iki yanında halat babaları
		for sg: float in [-1.0, 1.0]:
			for j in 2:
				var p: Vector3 = bas - deniz_yon * (0.6 + j * 1.8) + az * sg * (ISKELE_EN * 0.5 + 0.6)
				_koy("halat_babasi", p.x, p.z, 0.0, false, 0.02)
		# Kıyıya çekilmiş sandallar: iskele başının iki yanında kumsalda
		for sg: float in [-1.0, 1.0]:
			for j in 2:
				var p: Vector3 = bas + az * sg * (ISKELE_EN * 0.5 + 4.0 + j * 3.2) + deniz_yon * rng.randf_range(1.0, 5.0)
				_koy("sandal", p.x, p.z, yaw + rng.randf_range(-0.3, 0.3), false, 0.3)


func _alt_zemin(p: Vector3, excl: Array[RID]) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 300, p.z), Vector3(p.x, -50, p.z), 0xFFFFFFFF, excl)
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else -10.0


func _alt_zemin_adi(p: Vector3, excl: Array[RID]) -> String:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 300, p.z), Vector3(p.x, -50, p.z), 0xFFFFFFFF, excl)
	var hit := space.intersect_ray(q)
	return String((hit.collider as Node).name) if not hit.is_empty() else ""


# ---------- Sokak ayrıntıları: posta kutusu, büfe, koni grupları, konteyner, otomat, bisiklet ----------

func _sokak_ayrintilari(ada: Dictionary, sehir: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var koni_grup := 0
	for run in ada.sidewalks:
		var rid := String(run.road)
		if rid == "ada" or rid == "plaza":
			continue
		var pts: Array = run.pts
		var line := []
		for p: Array in pts:
			var a := ap(p[0], p[1])
			var b := ap(p[2], p[3])
			var out := b - a
			out.y = 0
			if out.length() < 0.5:
				continue
			line.append([a, b, out.normalized()])
		if line.size() < 3:
			continue
		var outer := []
		var inner := []
		for e in line:
			outer.append([(e[1] as Vector3) - (e[2] as Vector3) * 0.6, e[2]])
			inner.append([(e[0] as Vector3) + (e[2] as Vector3) * 0.45, e[2]])
		var L := _uzunluk(outer)
		var s := 25.0 + rng.randf() * 40.0
		while s < L - 15.0:
			var np: Array = _nokta(outer, s)
			var pos: Vector3 = np[0]
			var out: Vector3 = np[1]
			var r := rng.randf()
			var ok := false
			if r < 0.3:
				ok = _koy("posta_kutusu", pos.x, pos.z, _yaw(-out), true, 0.05)
			elif r < 0.45 and rid.begins_with("av"):
				var bp: Vector3 = pos - out * 0.4
				ok = _koy("bufe", bp.x, bp.z, _yaw(-out), true, 0.2)
			elif r < 0.65:
				ok = _koy("icecek_otomati", pos.x, pos.z, _yaw(-out), true, 0.05)
			elif r < 0.85:
				var bk: Vector3 = pos - out * 0.1
				ok = _koy("bisiklet", bk.x, bk.z, _yaw(-out), true, 0.05)
			elif koni_grup < 14:
				# Bordür kenarında üç koni (kaldırım çalışması)
				var ip: Array = _nokta(inner, s)
				var base: Vector3 = ip[0]
				var along: Vector3 = (ip[1] as Vector3).cross(Vector3.UP)
				var n := 0
				for j in 3:
					var cp: Vector3 = base + along * (j - 1) * 1.1
					if _koy("trafik_konisi", cp.x, cp.z, rng.randf() * TAU, true, 0.02):
						n += 1
				ok = n > 0
				if ok:
					koni_grup += 1
			s += (90.0 if ok else 12.0) + rng.randf() * 60.0
	# Ara sokaklarda konteynerler: Sehir "yol" öğelerinin kenarında
	for it in sehir.items:
		if String(it.t) != "yol":
			continue
		var pts: Array = it.pts
		var w := float(it.get("w", 2.6))
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			var L := a.distance_to(b)
			var d := (b - a) / maxf(L, 0.01)
			var nrm := Vector2(-d.y, d.x)
			var k := 6.0
			while k < L - 4.0:
				var m := a + d * k + nrm * (w * 0.5 + 1.1)
				_koy("cop_konteyneri", m.x, m.y, atan2(-nrm.x, -nrm.y), false, 0.1)
				k += 22.0
