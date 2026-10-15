extends SceneTree
func _init() -> void:
	var s: Node = load("res://assets/karakter/karakter.glb").instantiate()
	_print(s, 0)
	var ap: AnimationPlayer = s.find_child("AnimationPlayer", true, false)
	if ap:
		for n in ap.get_animation_list():
			var a := ap.get_animation(n)
			print("ANIM ", n, " len=", a.length, " tracks=", a.get_track_count())
	quit()
func _print(n: Node, d: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var m: Mesh = n.mesh
		extra = " surfaces=%d" % m.get_surface_count()
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat is StandardMaterial3D:
				extra += " [%s %s]" % [mat.resource_name, mat.albedo_color]
	if n is Skeleton3D:
		extra = " bones=%d" % n.get_bone_count()
	print("  ".repeat(d), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_print(c, d + 1)
