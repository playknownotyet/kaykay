class_name MuzikAksesuar
extends Node3D
## Karakterin müzik çaları, kulaklıkları ve kulaklık kablosu.
## Cihaz ve kulaklıklar karakter modelinin parçası (kemiklere bağlı meshler: tools/blender/karakter_rig.py
## add_music_bones); burada animasyonun karesine göre hangisinin görüneceği seçilir:
##   Calar_L / Calar_R (sol / sağ elde), Tomurcuk_El_L/R (parmak ucunda), Tomurcuk_Kulak_L/R (kulakta).
## Kablo her kare çizilir (ince çizgi): cihazın girişinden (cihaz cepteyse sol ön cepten) göğsün önündeki
## ayrılma noktasına, oradan iki kulaklığa; hafif sarkar.

const VC_SHADER := preload("res://shaders/toon_vc.gdshader")
# Olay kareleri (30 fps): karakter_rig.py MZ_* ile aynı
const CEPTEN := 22
const SAG_AL := 36
const SAG_TAK := 46
const EL_DEGIS := 56
const SOL_AL := 60
const SOL_TAK := 68
const IKI_EL := 76
const KOY_CEBE := 12
const KISA_CEPTEN := 22
# Güç kapatma (muzik_kulaklik_cikar): karakter_rig.py KC_* ile aynı
const KC_SAG_CEK := 10
const KC_SAG_BIT := 19
const KC_EL_DEGIS := 20
const KC_SOL_CEK := 29
const KC_SOL_BIT := 38
const KC_IKI_EL := 39
const KC_CEBE := 50

var controller: SkateController
var model: Node3D

var _skel: Skeleton3D
var _m := {}                    # ad -> MeshInstance3D
var _b := {}                    # kemik adı -> indis
var _cable: MeshInstance3D
var _im: ImmediateMesh


func _ready() -> void:
	_skel = model.find_child("Skeleton3D", true, false)
	var mat := ShaderMaterial.new()
	mat.shader = VC_SHADER
	var screen := StandardMaterial3D.new()
	screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.albedo_color = Color(0.72, 0.86, 1.0)
	for n in ["Calar_L", "Calar_R", "Tomurcuk_El_L", "Tomurcuk_El_R", "Tomurcuk_Kulak_L", "Tomurcuk_Kulak_R"]:
		var mi := model.find_child(n, true, false) as MeshInstance3D
		if mi == null:
			continue
		_m[n] = mi
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			# Ekran yüzeyi kendi malzemesiyle ("ekran"), gerisi köşe rengi
			var is_screen := src != null and String(src.resource_name).begins_with("ekran")
			mi.set_surface_override_material(i, screen if is_screen else mat)
	if _skel:
		for bn in ["jack.L", "jack.R", "kulak.L", "kulak.R", "kulaklik_el.L", "kulaklik_el.R", "cep.L", "ayirac"]:
			_b[bn] = _skel.find_bone(bn)
	_im = ImmediateMesh.new()
	_cable = MeshInstance3D.new()
	_cable.mesh = _im
	_cable.top_level = true
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.95, 0.95, 0.93)
	_cable.material_override = lm
	add_child(_cable)


func _bone(n: String) -> Vector3:
	var i: int = _b.get(n, -1)
	if i < 0:
		return Vector3.INF
	return _skel.global_transform * _skel.get_bone_global_pose(i).origin


func _show(n: String, on: bool) -> void:
	if _m.has(n):
		(_m[n] as MeshInstance3D).visible = on


func _process(_delta: float) -> void:
	if controller == null or _skel == null:
		return
	var c := controller
	var act := c.action_name if c.action_time > 0.0 else ""
	var f := 9999.0
	if act == "muzik_cikar":
		f = (SkateController.MUZIK_CIKAR_TIME - c.action_time) * 30.0
	elif act == "muzik_koy":
		f = (SkateController.MUZIK_KOY_TIME - c.action_time) * 30.0
	elif act == "muzik_cikar_kisa":
		f = (SkateController.MUZIK_KISA_TIME - c.action_time) * 30.0
	elif act == "muzik_kulaklik_cikar":
		f = (SkateController.MUZIK_KC_TIME - c.action_time) * 30.0
	var dev_l := false
	var dev_r := false
	var el_l := false
	var el_r := false
	var ear_l := c.earbuds_in
	var ear_r := c.earbuds_in
	match act:
		"muzik_cikar":
			dev_l = (f >= CEPTEN and f < EL_DEGIS) or f >= IKI_EL
			dev_r = f >= EL_DEGIS and f < IKI_EL
			el_r = f >= SAG_AL and f < SAG_TAK
			el_l = f >= SOL_AL and f < SOL_TAK
			ear_r = f >= SAG_TAK
			ear_l = f >= SOL_TAK
		"muzik_koy":
			dev_l = f < KOY_CEBE
		"muzik_cikar_kisa":
			dev_l = f >= KISA_CEPTEN
		"muzik_kulaklik_cikar":
			# Sağ kulaklık çekilir, el cihaza gelince sarılır; sonra sol; sonra cihaz cebe
			dev_l = f < KC_EL_DEGIS or (f >= KC_IKI_EL and f < KC_CEBE)
			dev_r = f >= KC_EL_DEGIS and f < KC_IKI_EL
			ear_r = f < KC_SAG_CEK
			el_r = f >= KC_SAG_CEK and f < KC_SAG_BIT
			ear_l = f < KC_SOL_CEK
			el_l = f >= KC_SOL_CEK and f < KC_SOL_BIT
		_:
			dev_l = c.music_open and c.on_foot
	_show("Calar_L", dev_l)
	_show("Calar_R", dev_r)
	_show("Tomurcuk_El_L", el_l)
	_show("Tomurcuk_El_R", el_r)
	_show("Tomurcuk_Kulak_L", ear_l)
	_show("Tomurcuk_Kulak_R", ear_r)
	_draw_cable(dev_l, dev_r, [ear_l, el_l], [ear_r, el_r])


## Kablo: kaynak (cihaz girişi ya da cep) -> ayrılma noktası -> görünen kulaklıklar
func _draw_cable(dev_l: bool, dev_r: bool, left: Array, right: Array) -> void:
	_im.clear_surfaces()
	var buds: Array[Vector3] = []
	for pair in [[left, "L"], [right, "R"]]:
		var st: Array = pair[0]
		if st[0]:
			buds.append(_bone("kulak." + pair[1]))
		elif st[1]:
			buds.append(_bone("kulaklik_el." + pair[1]))
	if buds.is_empty() or not visible or not controller.is_visible_in_tree():
		return
	var src := _bone("jack.L") if dev_l else (_bone("jack.R") if dev_r else _bone("cep.L"))
	if src == Vector3.INF:
		return
	var avg := Vector3.ZERO
	for p in buds:
		avg += p
	avg /= buds.size()
	# Ayrılma noktası: cihaz göğüsteyken kaynakla kulaklar arasında, cepteyken göğsün önünde
	var split := _bone("ayirac")
	if dev_l or dev_r or split == Vector3.INF:
		split = src.lerp(avg, 0.45) + Vector3.DOWN * 0.04
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	_curve(src, split, 0.05)
	for p in buds:
		_curve(split, p, 0.025)
	_im.surface_end()


func _curve(a: Vector3, b: Vector3, sag: float) -> void:
	var mid := (a + b) * 0.5 + Vector3.DOWN * sag * a.distance_to(b) * 4.0
	var prev := a
	var n := 8
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		_im.surface_add_vertex(prev)
		_im.surface_add_vertex(p)
		prev = p
