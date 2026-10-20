class_name RampaYetenek
extends Node3D
## Rampa yeteneği: butona (klavyede R) basınca oyuncunun kaykayda baktığı yönde ~20 m önde yerden
## toprak / kaya rampası çıkar (Rampa). Rampa yükselirken oyuncunun rotasını izler, sonra sabitlenir.
## Yol üstünde engel (duvar, bina, araba, su, ani yükselti) varsa engelin önüne açılır; çok yakınsa
## açılmaz (denied). Boyut hıza göre: yavaşta küçük kicker, hızlıda büyük rampa.
## Dolum (charge): ileride numaralarla dolacak; şimdilik test için hep dolu ve tükenmez.

signal denied
signal used

const MESAFE := 20.0          # giriş kenarına uzaklık (m)
const EN_YAKIN := 5.0         # bundan yakına açılmaz
const ADIM := 1.0             # yol taramasında örnek aralığı (m)
const YUKSELTI_ESIK := 0.45   # bir adımda bundan fazla yükselme / alçalma = engel

var player: SkateController
var camera: Node
var charge := 1.0             # 0..1; 1 = kullanılabilir
var testte_sinirsiz := true   # şimdilik: her basışta dolu kalır

var _rampa: Rampa = null
var _d0 := 0.0                # basıldığında giriş mesafesi
var _yol := 0.0               # basıştan beri oyuncunun aldığı yol (yükselirken)
var _son_poz := Vector3.ZERO


## Buton şu an basılabilir mi (görünüm için)
func can_use() -> bool:
	if player == null or player.on_foot or player.input_locked or player.fall_time > 0.0:
		return false
	if player.board_anim != SkateController.BoardAnim.NONE:
		return false
	if not (player.grounded or player.grinding):
		return false
	return charge >= 1.0


func _physics_process(delta: float) -> void:
	if SkateInput.consume_rampa():
		_dene()
	# Yükselen rampa oyuncunun rotasını izler: basıştan beri alınan yol düşülür, kalan mesafe
	# oyuncunun şimdiki yönüne konur (dönerse rampa da önüne döner)
	if is_instance_valid(_rampa) and _rampa.durum == Rampa.Durum.YUKSELIYOR and player:
		var p := player.global_position
		_yol += Vector2(p.x - _son_poz.x, p.z - _son_poz.z).length()
		_son_poz = p
		var d := _d0 - _yol
		var yer = _yer_bul(_yon(), d, _rampa.L, false)
		if yer != null:
			_rampa.hedef = yer[0]


func _dene() -> void:
	if not can_use():
		denied.emit()
		return
	var h := _boyut(absf(player.speed))
	var yer = _yer_bul(_yon(), MESAFE, h * 3.1, true)
	if yer == null:
		denied.emit()
		Haptics.pulse(12, 0.2)
		return
	if is_instance_valid(_rampa):
		_rampa.bat()
	var r := Rampa.new()
	r.player = player
	r.kur(h, yer[1], yer[0])
	add_child(r)
	_rampa = r
	_d0 = yer[2]
	_yol = 0.0
	_son_poz = player.global_position
	if not testte_sinirsiz:
		charge = 0.0
	if camera and camera.has_method("add_shake"):
		camera.add_shake(0.05)
	Haptics.pulse(30, 0.6)
	used.emit()


## Hıza göre rampa yüksekliği: ~15 km/sa'de 0,9 m, ~50 km/sa ve üstünde 2,4 m
static func _boyut(v: float) -> float:
	return lerpf(0.9, 2.4, clampf((v - 4.0) / 10.0, 0.0, 1.0))


## Kaykayın yatay yönü (yüzün baktığı yön)
func _yon() -> Vector3:
	var f := player.heading
	f.y = 0.0
	if f.length_squared() < 1e-4:
		f = -player.global_transform.basis.z
		f.y = 0.0
	return f.normalized()


## Rampanın yeri: [taban dünya dönüşümü, zemin rengi, giriş mesafesi] ya da null.
## Oyuncudan ileri ADIM aralıkla yol taranır; ilk engelin önüne sığacak en uzak yer seçilir.
func _yer_bul(fwd: Vector3, istenen: float, uzunluk: float, katı: bool):
	var space := get_world_3d().direct_space_state
	var p0 := player.global_position
	var mask := player.collision_mask
	var excl: Array[RID] = [player.get_rid()]
	for c in get_children():
		if c is CollisionObject3D:
			excl.append((c as CollisionObject3D).get_rid())
	var gerek := istenen + uzunluk + 1.0
	var onceki := p0.y
	var onceki_p := p0
	var engel := INF
	var n := int(ceilf(gerek / ADIM))
	for i in range(1, n + 1):
		var x := p0 + fwd * (i * ADIM)
		# Önceki noktadan buraya, dizden yüksek yatay ışın: duvar / araba / bina
		var a := Vector3(onceki_p.x, onceki + 0.7, onceki_p.z)
		var b := Vector3(x.x, onceki + 0.7, x.z)
		var q := PhysicsRayQueryParameters3D.create(a, b, mask, excl)
		var duvar := space.intersect_ray(q)
		if not duvar.is_empty() and (duvar.normal as Vector3).y < 0.6:
			engel = (i - 1) * ADIM
			break
		# Zemin yüksekliği
		var g := _zemin(space, x, onceki, mask, excl)
		if g.is_empty() or (g.position as Vector3).y < 0.03 or absf((g.position as Vector3).y - onceki) > YUKSELTI_ESIK:
			engel = (i - 1) * ADIM
			break
		onceki = (g.position as Vector3).y
		onceki_p = x
	var d := istenen
	if engel < INF:
		d = minf(istenen, engel - uzunluk - 1.0)
	if d < (EN_YAKIN if katı else 2.0):
		return null
	var giris := p0 + fwd * d
	var g0 := _zemin(space, giris, p0.y, mask, excl)
	if g0.is_empty():
		return null
	var dudak := p0 + fwd * (d + uzunluk)
	var g1 := _zemin(space, dudak, (g0.position as Vector3).y, mask, excl)
	var y0: float = (g0.position as Vector3).y
	var y1: float = (g1.position as Vector3).y if not g1.is_empty() else y0
	# Zemin eğimine göre rampa öne / arkaya yatar (en çok ±20°)
	var egim := clampf(atan2(y1 - y0, uzunluk), deg_to_rad(-20.0), deg_to_rad(20.0))
	var z := fwd.rotated(fwd.cross(Vector3.UP).normalized(), egim)
	var x_ax := Vector3.UP.cross(z).normalized()
	var basis := Basis(x_ax, z.cross(x_ax).normalized(), z)
	var origin := Vector3(giris.x, y0 - 0.03, giris.z)
	return [Transform3D(basis, origin), _renk(g0), d]


func _zemin(space: PhysicsDirectSpaceState3D, x: Vector3, ref_y: float, mask: int, excl: Array[RID]) -> Dictionary:
	var top := Vector3(x.x, ref_y + 2.5, x.z)
	var q := PhysicsRayQueryParameters3D.create(top, Vector3(x.x, ref_y - 6.0, x.z), mask, excl)
	return space.intersect_ray(q)


## Rampa kabuğunun rengi: açıldığı zeminin türünden
func _renk(hit: Dictionary) -> Color:
	var body := hit.get("collider") as Node
	var s := String(body.get_meta("surface", "asfalt")) if body else "asfalt"
	var pos: Vector3 = hit.position
	if s == "cim" and Sehir.instance and Sehir.instance.paved_at(pos.x, pos.z):
		s = "arnavut"
	match s:
		"cim":
			# Kıyıya yakın alçak arazi kumsal
			return Color(0.78, 0.7, 0.5) if pos.y < 1.2 else Color(0.32, 0.46, 0.2)
		"arnavut":
			return Color(0.45, 0.42, 0.38)
		"beton":
			return Color(0.6, 0.59, 0.55)
		"tahta":
			return Color(0.5, 0.36, 0.22)
		"metal":
			return Color(0.4, 0.42, 0.45)
		"kaya":
			return Color(0.47, 0.45, 0.43)
	return Color(0.21, 0.21, 0.23)
