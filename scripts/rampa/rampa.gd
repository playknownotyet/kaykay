class_name Rampa
extends AnimatableBody3D
## Yerden çıkan toprak / kaya rampası (RampaYetenek açar).
## Yerel eksenler: +z ileri (giriş z = 0, dudak z = L), +y yukarı, +x sağ. Sürüş yüzeyi
## y = H·(z/L)²: girişte zeminle düz, dudakta ~33°. Üst kabuk açıldığı zeminin rengindedir
## (asfalt, çim, kum...), yanlarda kabuk / toprak / kaya katmanları ve yerinden fırlamış kayalar.
## Yükselir (YUKSELME_SURE, hafif aşıp oturur), oyuncu dudaktan uçunca biraz itki verir,
## sonra (ya da geçilince / zaman aşımında) toz kaldırarak geri yere batar ve silinir.

enum Durum { YUKSELIYOR, HAZIR, BATIYOR }

const YUKSELME_SURE := 0.6
const BATMA_SURE := 0.9
const DERIN := 1.3                  # zeminin altında kalan etek (eğimli zeminde boşluk kalmasın)
const ZAMAN_ASIMI := 10.0           # kullanılmazsa bu kadar sonra batar
const UCUS_SONRASI := 1.1           # dudaktan uçtuktan sonra batmaya başlama
## Fırlatma: dudaktan çıkınca yukarı (ITKI_Y + H·ITKI_Y_H) ve gidiş yönünde hız (ITKI_ILERI);
## zıplama dudakta tutarsa (erken basılıp beklenen ya da dudaktan hemen sonra) ek itki
const ITKI_Y := 1.7
const ITKI_Y_H := 0.8
const ITKI_ILERI := 3.0
const TAM_Y := 1.5
const TAM_ILERI := 1.5
const GEC_ZIPLAMA := 0.25           # dudaktan sonra bu kadar içinde basılan zıplama da "tam" sayılır
const NZ := 8                       # sürüş yüzeyi dilimleri (çarpışma ve görsel)

const TOON_VC := preload("res://shaders/toon_vc.gdshader")
const TOPRAK := Color(0.47, 0.3, 0.17)
const KAYA := Color(0.35, 0.32, 0.3)

var H := 1.5
var L := 4.6
var W := 3.4
var kabuk := Color(0.2, 0.2, 0.22)    # üst yüzey (açıldığı zeminin rengi)
var player: SkateController
var durum := Durum.YUKSELIYOR
var hedef := Transform3D()            # tabanın gitmek istediği yer (yükselirken yetenek günceller)

var _taban := Transform3D()
var _t := 0.0
var _hazir_t := 0.0
var _bekle := -1.0
var _ustunde := false
var _kalkti := false
var _tam := false
var _kalkis_t := 0.0
var _gorsel: MeshInstance3D
var _toz_cikis: CPUParticles3D
var _toz_patlama: CPUParticles3D
var _tas_patlama: CPUParticles3D
var _ses: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()

## Sahnedeki rampalar (trafik önlerinde durur)
static var aktif: Array[Rampa] = []


## Arabalar için engel mi (batarken yarıya inince yol açılır)
func engel_mi() -> bool:
	return durum != Durum.BATIYOR or _t < BATMA_SURE * 0.6


func _enter_tree() -> void:
	if not aktif.has(self):
		aktif.append(self)


func _exit_tree() -> void:
	aktif.erase(self)


## h: yükseklik (m); zemin: rengi alınacak yüzey; xf: tabanın (giriş kenarı ortası) dünya yeri
func kur(h: float, zemin_rengi: Color, xf: Transform3D) -> void:
	H = h
	L = H * 3.1
	W = 3.0 + H * 0.4
	kabuk = zemin_rengi
	hedef = xf
	_taban = xf
	_rng.randomize()
	collision_layer = Sehir.LAYER
	collision_mask = 0
	sync_to_physics = true
	set_meta("surface", "kaya")
	_build_mesh()
	_build_collision()
	_build_particles()
	_ses = AudioStreamPlayer3D.new()
	_ses.bus = "Ortam"
	_ses.unit_size = 14.0
	_ses.max_db = 4.0
	add_child(_ses)
	global_transform = _yer(0.0)


func _ready() -> void:
	_cal("rampa")
	_toz_cikis.emitting = true
	_tas_patlama.restart()


## Batmaya başla (yeni rampa açılınca eskisi de batar)
func bat() -> void:
	if durum == Durum.BATIYOR:
		return
	durum = Durum.BATIYOR
	_t = 0.0
	_toz_cikis.emitting = false
	_parcacik_yeri()
	_toz_patlama.amount = 26
	_toz_patlama.restart()
	_tas_patlama.amount = 10
	_tas_patlama.restart()
	_cal("rampa_bat")


func _physics_process(delta: float) -> void:
	_t += delta
	match durum:
		Durum.YUKSELIYOR:
			# Taban, yetenek her kare güncellediği hedefe yumuşakça kayar (oyuncunun yönünü izler)
			_taban = _taban.interpolate_with(hedef, 1.0 - exp(-14.0 * delta))
			var k := clampf(_t / YUKSELME_SURE, 0.0, 1.0)
			global_transform = _yer(_geri_tasarak(k))
			# Yükselirken toprak sarsılır (yalnız görsel)
			_gorsel.position = Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)) * 0.035 * (1.0 - k)
			_parcacik_yeri()
			if k >= 1.0:
				durum = Durum.HAZIR
				_gorsel.position = Vector3.ZERO
				_toz_cikis.emitting = false
				_toz_patlama.restart()
				_hazir_t = 0.0
				Haptics.pulse(25, 0.5)
			_kalkis_kontrol(delta)
		Durum.HAZIR:
			_hazir_t += delta
			_kalkis_kontrol(delta)
			_izle_oyuncu(delta)
		Durum.BATIYOR:
			var k := clampf(_t / BATMA_SURE, 0.0, 1.0)
			global_transform = _yer(1.0 - k * k)
			_gorsel.position = Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)) * 0.03
			if k >= 1.0:
				# Parçacıklar bitene kadar bekle, sonra sil
				visible = false
				collision_layer = 0
				if _t > BATMA_SURE + 1.8:
					queue_free()


## Dudağa (rampanın ucuna) rampa boyunca kalan yol (m); zıplama asisti kullanır
func dudaga_kalan(p: Vector3) -> float:
	return L - (_taban.affine_inverse() * p).z


## Dudaktan fırlama: belirgin itki (yukarı ve ileri); zıplama zamanlaması tuttuysa daha çok
func _kalkis_kontrol(delta: float) -> void:
	if player == null:
		return
	var lp := _taban.affine_inverse() * player.global_position
	var on := player.grounded and player.floor_body == self
	var ollie_ile := player._since_ollie < 0.3
	if _ustunde and not player.grounded and not _kalkti and not player.wallriding 			and (lp.z > L * 0.7 or (ollie_ile and lp.z > 0.0)):
		_kalkti = true
		_tam = ollie_ile
		_kalkis_t = 0.0
		player.ramp_launch(ITKI_Y + H * ITKI_Y_H + (TAM_Y if _tam else 0.0), ITKI_ILERI + (TAM_ILERI if _tam else 0.0))
		player.ramp_launched.emit(_tam)
		_bekle = UCUS_SONRASI
		_toz_patlama.restart()
		Haptics.pulse(30 if _tam else 20, 0.7 if _tam else 0.45)
	elif _kalkti and not _tam:
		# Dudaktan hemen sonra basılan zıplama (geç kalan): yine tam sayılır
		_kalkis_t += delta
		if _kalkis_t <= GEC_ZIPLAMA and player._since_ollie <= _kalkis_t:
			_tam = true
			player.ramp_launch(TAM_Y, TAM_ILERI)
			player.ramp_launched.emit(true)
			Haptics.pulse(30, 0.7)
	_ustunde = on


## Oyuncu dudaktan uçunca / geçip gidince batmaya başla
func _izle_oyuncu(delta: float) -> void:
	if player == null:
		return
	var lp := _taban.affine_inverse() * player.global_position
	var on := player.grounded and player.floor_body == self
	if _bekle >= 0.0:
		_bekle -= delta
		if _bekle < 0.0 and not on:
			bat()
		return
	var uzak := player.global_position.distance_to(_taban.origin) > 60.0
	var gecti := lp.z > L + 5.0 or (_kalkti and not on)
	if not on and (uzak or gecti or _hazir_t > ZAMAN_ASIMI or player.on_foot):
		bat()


## k: 0 = tamamen gömülü, 1 = yerinde
func _yer(k: float) -> Transform3D:
	var gom := (H + 0.35) * (1.0 - k)
	return Transform3D(_taban.basis, _taban.origin - _taban.basis.y * gom)


## Yükselme eğrisi: hızlı çıkar, sonda hafifçe aşıp oturur
static func _geri_tasarak(k: float) -> float:
	var s := 1.0 - pow(1.0 - k, 2.2)
	return s + 0.09 * sin(PI * k) * k * k


func _cal(ad: String) -> void:
	var s := SesAyar.load_sound(ad, false)
	if s:
		_ses.stream = s
		_ses.play()


# ---------- Parçacıklar (dünya koordinatında; tabanla birlikte zeminde dururlar) ----------

func _parcacik_yeri() -> void:
	var c := _taban * Vector3(0.0, 0.1, L * 0.5)
	for p in [_toz_cikis, _toz_patlama, _tas_patlama]:
		(p as CPUParticles3D).global_transform = Transform3D(_taban.basis, c)


func _build_particles() -> void:
	var ext := Vector3(W * 0.55, 0.15, L * 0.55)
	# Yükselirken sürekli toz
	_toz_cikis = _toz(56, 1.5, ext, Vector2(1.2, 3.5))
	_toz_cikis.one_shot = false
	_toz_cikis.explosiveness = 0.0
	# Oturunca / batarken toz bulutu
	_toz_patlama = _toz(44, 1.8, ext, Vector2(1.5, 5.0))
	# Fırlayan toprak / taş parçaları
	_tas_patlama = CPUParticles3D.new()
	_tas_patlama.mesh = _tas_mesh()
	_tas_patlama.amount = 26
	_tas_patlama.lifetime = 1.6
	_tas_patlama.one_shot = true
	_tas_patlama.explosiveness = 0.9
	_tas_patlama.emitting = false
	_tas_patlama.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_tas_patlama.emission_box_extents = ext
	_tas_patlama.direction = Vector3.UP
	_tas_patlama.spread = 40.0
	_tas_patlama.initial_velocity_min = 3.5
	_tas_patlama.initial_velocity_max = 8.0 + H
	_tas_patlama.gravity = Vector3(0, -14.5, 0)
	_tas_patlama.angular_velocity_min = -400.0
	_tas_patlama.angular_velocity_max = 400.0
	_tas_patlama.particle_flag_rotate_y = true
	_tas_patlama.angle_min = 0.0
	_tas_patlama.angle_max = 360.0
	_tas_patlama.scale_amount_min = 0.5
	_tas_patlama.scale_amount_max = 1.5
	for p in [_toz_cikis, _toz_patlama, _tas_patlama]:
		(p as CPUParticles3D).top_level = true
		add_child(p)
	_parcacik_yeri()


func _toz(n: int, life: float, ext: Vector3, hiz: Vector2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _toz_malzeme()
	p.mesh = q
	p.amount = n
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = ext
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = hiz.x
	p.initial_velocity_max = hiz.y
	p.gravity = Vector3(0, -0.6, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 2.2))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(kabuk.lerp(TOPRAK, 0.7).lightened(0.15), 0.95),
		Color(TOPRAK.lightened(0.25), 0.7), Color(TOPRAK.lightened(0.4), 0.0)])
	p.color_ramp = g
	return p


static var _toz_mat: StandardMaterial3D
static var _tas_m: ArrayMesh


static func _toz_malzeme() -> StandardMaterial3D:
	if _toz_mat:
		return _toz_mat
	# Yumuşak kenarlı yuvarlak toz lekesi
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_toz_mat = m
	return m


## Küçük köşeli taş (fırlayan parçalar)
static func _tas_mesh() -> ArrayMesh:
	if _tas_m:
		return _tas_m
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_kaya_ekle(st, Vector3.ZERO, Vector3(0.13, 0.1, 0.12), Color(0.36, 0.27, 0.19), rng, 0.3)
	_tas_m = st.commit()
	var m := ShaderMaterial.new()
	m.shader = TOON_VC
	_tas_m.surface_set_material(0, m)
	return _tas_m


# ---------- Mesh ----------

func _ys(z: float) -> float:
	var u := z / L
	return H * u * u


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := W * 0.5
	var ic := Vector3(0.0, -DERIN * 0.5, L * 0.5)     # kütlenin içi (yüzlerin dışa bakması için)
	# Üst yüzey: düz kaya rengi, tek parça (çizgisiz)
	var ust := Color(0.4, 0.37, 0.34)
	for i in NZ:
		var z0 := L * i / NZ
		var z1 := L * (i + 1) / NZ
		var alt := Vector3(0.0, -5.0, (z0 + z1) * 0.5)
		var a := Vector3(-hw, _ys(z0), z0)
		var b := Vector3(hw, _ys(z0), z0)
		var cc := Vector3(hw, _ys(z1), z1)
		var d := Vector3(-hw, _ys(z1), z1)
		_tri(st, a, b, cc, ust, alt)
		_tri(st, a, cc, d, ust, alt)
	# Yanlar: kabuk / toprak / kaya katmanları, dışa doğru pürüzlü
	var katman: Array[float] = [0.0, 0.16, 0.55, 1.0]               # üst kenardan aşağı oran (son: -DERIN)
	var yan_grid := {}
	for s in [-1.0, 1.0]:
		var grid := []
		for i in NZ + 1:
			var z := L * i / NZ
			var top := _ys(z)
			var row := []
			for k in katman.size():
				var y := top - 0.16 if k == 1 else lerpf(top, -DERIN, katman[k])
				var dis := 0.0 if k == 0 else _rng.randf_range(0.05, 0.28) * (1.0 if k < 3 else 0.6)
				var dz := 0.0 if (k == 0 or i == 0 or i == NZ) else _rng.randf_range(-0.12, 0.12)
				row.append(Vector3(s * (hw + dis), y, z + dz))
			grid.append(row)
		yan_grid[s] = grid
		for i in NZ:
			for k in katman.size() - 1:
				var c: Color = _ton(kabuk, 0.06) if k == 0 else (_ton(TOPRAK, 0.1) if k == 1 else _ton(KAYA, 0.1))
				var a: Vector3 = grid[i][k]
				var b: Vector3 = grid[i + 1][k]
				var cc: Vector3 = grid[i + 1][k + 1]
				var d: Vector3 = grid[i][k + 1]
				var ref := Vector3(0.0, (a.y + d.y) * 0.5, (a.z + b.z) * 0.5)
				_tri(st, a, b, cc, c, ref)
				_tri(st, a, cc, d, c, ref)
	# Arka: dudaktan aşağı, dışa taşan kaya yığını
	var bz := H * 0.5
	var bx := 5
	var brows: Array[float] = katman
	var bgrid := []
	for j in bx + 1:
		var x := -hw + W * j / bx
		var row := []
		for k in brows.size():
			var y := H - 0.16 if k == 1 else lerpf(H, -DERIN, brows[k])
			var z := L + bz * brows[k] + (0.0 if k == 0 else _rng.randf_range(0.0, 0.3))
			var xx := x + (0.0 if (k == 0 or j == 0 or j == bx) else _rng.randf_range(-0.15, 0.15))
			row.append(Vector3(xx, y, z))
		bgrid.append(row)
	for j in bx:
		for k in brows.size() - 1:
			var c: Color = _ton(kabuk, 0.06) if k == 0 else (_ton(TOPRAK, 0.1) if k == 1 else _ton(KAYA, 0.1))
			var a: Vector3 = bgrid[j][k]
			var b: Vector3 = bgrid[j + 1][k]
			var cc: Vector3 = bgrid[j + 1][k + 1]
			var d: Vector3 = bgrid[j][k + 1]
			_tri(st, a, b, cc, c, ic)
			_tri(st, a, cc, d, c, ic)
	# Arka köşelerdeki üçgen boşluklar: yan ızgaranın son sütunu ile arka ızgaranın kenarı arası
	for s in [-1.0, 1.0]:
		var bj := 0 if s < 0.0 else bx
		var sg: Array = yan_grid[s][NZ]
		for k in brows.size() - 1:
			var c: Color = _ton(kabuk, 0.06) if k == 0 else (_ton(TOPRAK, 0.1) if k == 1 else _ton(KAYA, 0.1))
			_tri(st, sg[k], bgrid[bj][k], bgrid[bj][k + 1], c, ic)
			_tri(st, sg[k], bgrid[bj][k + 1], sg[k + 1], c, ic)
	# Giriş yüzü (zeminin altında; aradan bakılırsa boşluk görünmesin)
	_tri(st, Vector3(-hw, 0, 0), Vector3(hw, 0, 0), Vector3(hw, -DERIN, 0), _ton(TOPRAK, 0.05), ic)
	_tri(st, Vector3(-hw, 0, 0), Vector3(hw, -DERIN, 0), Vector3(-hw, -DERIN, 0), _ton(TOPRAK, 0.05), ic)
	# Yanlarda ve arkada yerinden fırlamış kayalar, kenarlarda kalkmış zemin kabuğu parçaları
	var n_kaya := 6 + int(H * 3.0)
	for i in n_kaya:
		var yan := 1.0 if i % 2 == 0 else -1.0
		var p: Vector3
		if i % 4 == 3:
			p = Vector3(_rng.randf_range(-hw, hw), _rng.randf_range(-0.2, 0.25), L + bz * _rng.randf_range(0.6, 1.1))
		else:
			var z := _rng.randf_range(L * 0.15, L * 1.05)
			p = Vector3(yan * (hw + _rng.randf_range(0.15, 0.6)), _rng.randf_range(-0.25, minf(_ys(z) * 0.6, 0.6)), z)
		var r := _rng.randf_range(0.18, 0.32 + H * 0.1)
		_kaya_ekle(st, p, Vector3(r, r * _rng.randf_range(0.6, 1.0), r * _rng.randf_range(0.7, 1.1)), _ton(KAYA if i % 3 else TOPRAK, 0.12), _rng, 0.25)
	for i in 6:
		var yan := 1.0 if i % 2 == 0 else -1.0
		var z := _rng.randf_range(-0.6, L * 0.9)
		var c := Vector3(yan * (hw + _rng.randf_range(0.5, 1.1)), 0.02, z)
		_levha(st, c, Vector2(_rng.randf_range(0.5, 0.9), _rng.randf_range(0.4, 0.8)), yan, _rng.randf_range(0.25, 0.6))
	var mesh := st.commit()
	var m := ShaderMaterial.new()
	m.shader = TOON_VC
	mesh.surface_set_material(0, m)
	_gorsel = MeshInstance3D.new()
	_gorsel.mesh = mesh
	add_child(_gorsel)


## Kalkmış zemin kabuğu levhası: ince kutu, rampadan dışa doğru eğik
func _levha(st: SurfaceTool, c: Vector3, s: Vector2, yan: float, egim: float) -> void:
	var b := Basis(Vector3(0, 0, 1), -yan * egim) * Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4))
	var hx := s.x * 0.5
	var hz := s.y * 0.5
	var th := 0.07
	var pts := []
	for y in [0.0, th]:
		for v in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
			pts.append(c + b * Vector3(v.x, y, v.y))
	var ust := _ton(kabuk, 0.08)
	var kenar := _ton(TOPRAK, 0.08)
	_tri(st, pts[4], pts[5], pts[6], ust, c)
	_tri(st, pts[4], pts[6], pts[7], ust, c)
	for i in 4:
		var q := (i + 1) % 4
		_tri(st, pts[i], pts[q], pts[q + 4], kenar, c + b * Vector3(0, th * 0.5, 0))
		_tri(st, pts[i], pts[q + 4], pts[i + 4], kenar, c + b * Vector3(0, th * 0.5, 0))


## Pürüzlü kaya: ikosahedronun köşeleri rastgele çekilip itilir
static func _kaya_ekle(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, rng: RandomNumberGenerator, purus: float) -> void:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var p := []
	for q: Vector3 in v:
		var u := q.normalized() * rng.randf_range(1.0 - purus, 1.0 + purus * 0.4)
		p.append(c + Vector3(u.x * r.x, u.y * r.y, u.z * r.z))
	for tri in f:
		var cc := col * rng.randf_range(0.88, 1.1)
		cc.a = 1.0
		_tri(st, p[tri[0]], p[tri[1]], p[tri[2]], cc, c)


## Üçgen: normali "ic" noktasından dışa bakar, sarma Godot'nun ön yüz kuralına göre
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, ic: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - ic) < 0.0:
		n = -n
	var order := [a, b, c] if (b - a).cross(c - a).dot(n) < 0.0 else [a, c, b]
	for p: Vector3 in order:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(p)


func _ton(c: Color, oran: float) -> Color:
	var k := _rng.randf_range(1.0 - oran, 1.0 + oran)
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), 1.0)


# ---------- Çarpışma ----------

func _build_collision() -> void:
	var hw := W * 0.5
	# Sürüş yüzeyi: her dilim kendi dışbükey parçası (zeminin altına kadar)
	for i in NZ:
		var z0 := L * i / NZ
		var z1 := L * (i + 1) / NZ
		var pts := PackedVector3Array()
		for x in [-hw, hw]:
			pts.append(Vector3(x, _ys(z0), z0))
			pts.append(Vector3(x, _ys(z1), z1))
			pts.append(Vector3(x, -DERIN, z0))
			pts.append(Vector3(x, -DERIN, z1))
		_shape(pts)
	# Arka: dudaktan aşağı inen dik şev
	var bz := H * 0.5
	var pts := PackedVector3Array()
	for x in [-hw, hw]:
		pts.append(Vector3(x, H, L))
		pts.append(Vector3(x, -DERIN, L))
		pts.append(Vector3(x, -DERIN, L + bz))
	_shape(pts)


func _shape(pts: PackedVector3Array) -> void:
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = sh
	add_child(cs)
