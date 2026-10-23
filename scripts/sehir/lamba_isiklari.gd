class_name LambaIsiklari
extends Node3D
## Sokak lambalarının gece ışıkları (Esyalar kurar; gece değeri Sehir.set_night'tan gelir):
##  - Her lambanın altında yere düşen sıcak ışık havuzu: hepsi tek MultiMesh (tek çizim, ucuz)
##  - Oyuncuya en yakın birkaç lambada gerçek ışık (OmniLight): karakter ve kaykay lamba altında aydınlanır.
##    186 gerçek ışık telefonda çok pahalı; az sayıda ışık en yakın lambalara taşınır.

const HAVUZ_SHADER := preload("res://shaders/isik_havuzu.gdshader")
const GERCEK := 6               # aynı anda yanan gerçek ışık
const HAVUZ_R := 3.4            # yerdeki ışık havuzunun yarıçapı (m)

var player: Node3D
var heads: Array[Vector3] = []  # lamba başlarının (ampul) dünya konumları
var grounds: Array[Vector3] = []  # ampulün altındaki zemin noktaları
var _pool: MultiMeshInstance3D
var _lights: Array[OmniLight3D] = []
var _gece := 0.0
var _t := 0.0


func setup(p_heads: Array[Vector3], p_grounds: Array[Vector3]) -> void:
	heads = p_heads
	grounds = p_grounds
	var q := QuadMesh.new()
	q.size = Vector2(HAVUZ_R * 2.0, HAVUZ_R * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = HAVUZ_SHADER
	q.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = grounds.size()
	for i in grounds.size():
		mm.set_instance_transform(i, Transform3D(Basis(), grounds[i] + Vector3.UP * 0.1))
	_pool = MultiMeshInstance3D.new()
	_pool.name = "IsikHavuzlari"
	_pool.multimesh = mm
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)
	for i in GERCEK:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.52)
		l.omni_range = 7.5
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
	if Sehir.instance:
		Sehir.instance.night_changed.connect(_set_night)
		_set_night(Sehir.instance.gece)


func _set_night(v: float) -> void:
	_gece = v
	_pool.visible = v > 0.02
	for l in _lights:
		l.light_energy = 1.6 * v
		if v <= 0.02:
			l.visible = false
	_t = 0.0


func _process(delta: float) -> void:
	if _gece <= 0.02 or player == null or heads.is_empty():
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.3
	# En yakın lambalar (kaba sıralama; 200 lamba için her 0,3 sn yeterince ucuz)
	var p := player.global_position
	var best: Array = []
	for i in heads.size():
		var d := heads[i].distance_squared_to(p)
		if d > 60.0 * 60.0:
			continue
		best.append([d, i])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for k in _lights.size():
		var l := _lights[k]
		if k < best.size():
			l.global_position = heads[best[k][1]] - Vector3.UP * 0.25
			l.visible = true
		else:
			l.visible = false
