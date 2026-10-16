extends MultiMeshInstance3D
## Adadaki tüm trafik ışığı başları tek bir MultiMesh: hangi lambanın yandığı örnek başına
## özel veride (shaders/trafik_lamba.gdshader). Durumlar saatten (TrafikSinyal), yalnız
## değişince yazılır; uzak kavşaklar da doğru renkte durur (ucuz).

## Örnek başına: kavşak, kol, tür (0 araç, 1 yaya), konum ve baktığı yön. ada_builder.gd doldurur.
## MultiMesh açılışta kurulur (hazır sahne başsız pişirilir; orada MultiMesh verisi saklanmaz).
@export var junction := PackedInt32Array()
@export var positions := PackedVector3Array()
@export var faces := PackedVector3Array()
@export var car_heads := true
@export var arm := PackedInt32Array()
@export var kind := PackedInt32Array()

var _last := PackedInt32Array()
var _timer := 0.0


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = AdaBuilder._lamp_head(car_heads)
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis.looking_at(-faces[i], Vector3.UP), positions[i]))
		mm.set_instance_custom_data(i, Color(1, 0, 0, 0))
	multimesh = mm
	_last.resize(junction.size())
	_last.fill(-1)
	if not TrafikSinyal.ensure():
		set_process(false)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	var t := TrafikSinyal.now()
	var mm := multimesh
	for i in junction.size():
		var s: int
		if kind[i] == 0:
			s = TrafikSinyal.car_state(junction[i], arm[i], t)
		else:
			s = TrafikSinyal.ped_state(junction[i], t, arm[i])
		if s != _last[i]:
			_last[i] = s
			mm.set_instance_custom_data(i, Color(float(s), 0, 0, 0))
