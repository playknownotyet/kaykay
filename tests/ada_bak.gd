extends Node
## Ada görüntü kontrolü (pencereli çalıştır): Godot --path . res://tests/ada_bak.tscn
## Meydandan, serpantin tepesinden ve limandan birer kare: tests/screens/ada_*.png

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 90:
		await get_tree().physics_frame
	await _shot(main, "ada_meydan")
	var ada: Node = main.world.get_child(0)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ada/ada.json"))
	var serp: Dictionary = {}
	for r in d.roads:
		if r.id == "serp":
			serp = r
	var p0: Array = serp.pts[2]
	var p1: Array = serp.pts[8]
	await _place(main, AdaBuilder.p3(p0[0], p0[1], p0[2] + 0.2), AdaBuilder.p3(p1[0], p1[1], p1[2]) - AdaBuilder.p3(p0[0], p0[1], p0[2]))
	await _shot(main, "ada_tepe")
	# Kavşak köşeleri: meydandan uzaklığa göre sıralı kavşaklardan ikisi, çapraz açıdan
	var discs: Array = d.discs.duplicate()
	discs.sort_custom(func(a, b): return Vector2(a.x - d.plaza.x, a.y - d.plaza.y).length() < Vector2(b.x - d.plaza.x, b.y - d.plaza.y).length())
	for k in [discs.size() / 3, discs.size() / 2]:
		var jc: Dictionary = discs[k]
		var c := AdaBuilder.p3(jc.x, jc.y, jc.h)
		var from := c + Vector3(14, 0, 14)
		await _place(main, Vector3(from.x, c.y + 0.3, from.z), c - from)
		await _shot(main, "ada_kose_%d" % k)
	# Meydan göbeği: iki cadde arası yaya adası (göbek yolundan dışa bakış)
	var P := AdaBuilder.p3(d.plaza.x, d.plaza.y, d.plaza.h)
	for ang in [0.62, 1.95]:
		var dirp := Vector3(cos(ang), 0, -sin(ang))
		await _place(main, P + dirp * 29.0 + Vector3.UP * 0.3, dirp)
		await _shot(main, "ada_gobek_%d" % int(ang * 100))
	# Üç kavşaklı küçük üçgen ve dar açılı katılım
	await _place(main, AdaBuilder.p3(300, 222, 3.0), AdaBuilder.p3(330, 192, 0) - AdaBuilder.p3(300, 222, 0))
	await _shot(main, "ada_ucgen")
	# Çevre bariyeri, yakından
	var bar: Array = d.barrier[0]
	var q0: Array = bar[150]
	var q1: Array = bar[158]
	var bd := AdaBuilder.p3(q1[0], q1[1], q1[2]) - AdaBuilder.p3(q0[0], q0[1], q0[2])
	var side := bd.cross(Vector3.UP).normalized()
	var pos := AdaBuilder.p3(q0[0], q0[1], q0[2] + 0.3)
	if pos.dot(side) > 0.0:
		side = -side
	await _place(main, pos + side * 2.0, bd + side * 3.0)
	await _shot(main, "ada_bariyer")
	# Trafik: bir arabanın arkasından ve bir kavşağa yaklaşırken
	var tr: Node = main.world.get_node_or_null("Trafik")
	if tr:
		for i in 120:
			await get_tree().physics_frame
		var shots := 0
		for c in tr.car_list():
			if c.lane < 0 or shots >= 3:
				continue
			var back: Vector3 = c.global_position - c.fwd * (c.half.z + 6.0) + c.fwd.cross(Vector3.UP) * 2.2
			await _place(main, back + Vector3.UP * 0.2, c.global_position - back)
			print("ARABA ", c.model_key, " konum ", c.global_position, " oyuncu ", main.player.global_position, " hız ", c.speed, " görünür ", c.is_visible_in_tree(), " kamerada ", main.camera.is_position_in_frustum(c.global_position))
			await _shot(main, "trafik_%d" % shots)
			shots += 1
	var J: Array = TrafikSinyal.data.junctions
	for ji in [21, 5, 31]:
		var jp: Array = J[ji].p
		var c := Vector3(jp[0], jp[1], jp[2])
		var from := c + Vector3(22, 0, 9)
		await _place(main, Vector3(from.x, c.y + 0.3, from.z), c - from)
		await _shot(main, "isik_%d" % ji)
	get_tree().quit()


func _place(main: Node, pos: Vector3, dir: Vector3) -> void:
	var p: SkateController = main.player
	dir.y = 0.0
	p.global_transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), pos)
	p.heading = dir.normalized()
	p.speed = 0.0
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	main.camera.snap()
	for i in 40:
		await get_tree().physics_frame


func _shot(main: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/screens/%s.png" % name)
	print("KARE ", name, " oyuncu ", main.player.global_position, " yuzey ", main.player.floor_surface)
