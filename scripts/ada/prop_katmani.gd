extends MultiMeshInstance3D
## Bir bölgedeki (128 m parça) aynı türden sokak eşyaları tek MultiMesh'te: tek çizim çağrısı.
## Hazır sahne başsız pişirildiği için MultiMesh verisi orada saklanmaz; açılışta kaydedilen
## konumlardan kurulur. Görünürlük mesafesi parçanın merkezinden (düğüm konumu) ölçülür.
## Malzeme: modelin renk dokusu oyunun toon shader'ıyla (shaders/toon_tex.gdshader).

const TEX_SHADER := preload("res://shaders/toon_tex.gdshader")

@export var model_path := ""
## Örneklerin dönüşümleri (bu düğüme göre)
@export var transforms: Array[Transform3D] = []

## Model başına (mesh, malzeme) önbelleği: bütün parçalar paylaşır
static var _cache := {}


func _ready() -> void:
	var entry := _load(model_path)
	if entry.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = entry.mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	multimesh = mm
	material_override = entry.material


static func _load(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var scene: PackedScene = load(path)
	if scene == null:
		return {}
	var root := scene.instantiate()
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: Mesh = mi.mesh
	# Modelin kendi düğüm dönüşümü (glTF) meshe işlenir: köke göre doğru dursun
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	if not xf.is_equal_approx(Transform3D.IDENTITY):
		var st := SurfaceTool.new()
		var am := ArrayMesh.new()
		for s in mesh.get_surface_count():
			st.clear()
			st.append_from(mesh, s, xf)
			st.commit(am)
		mesh = am
	var tex: Texture2D = null
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m == null:
			m = mi.get_active_material(s)
		if m is BaseMaterial3D and m.albedo_texture:
			tex = m.albedo_texture
			break
	var mat := ShaderMaterial.new()
	mat.shader = TEX_SHADER
	if tex:
		mat.set_shader_parameter("albedo_tex", tex)
	root.free()
	_cache[path] = {"mesh": mesh, "material": mat}
	return _cache[path]
