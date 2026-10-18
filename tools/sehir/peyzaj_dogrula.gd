extends Node
## Üretilen peyzajı ayıklar: sokak eşyası, bina, bank, direk, tabela, kaldırım vb. ile çakışan ya da
## arazi dışında (kaldırım, yol, iskele, platform) duran öğeleri siler; assets/ada/peyzaj.json'u yazar.
##   Godot --headless --path . res://tools/sehir/peyzaj_dogrula.tscn

const R := {"Ağaç": 0.7, "Çalı": 0.55, "Ot / kaya": 0.25}

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 150:
		await get_tree().physics_frame
	var pz: Peyzaj = Peyzaj.instance
	# Peyzajın kendi gövdeleri sayılmasın
	for c in pz.get_children():
		if c.name.begins_with("Peyzaj_"):
			c.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := pz.get_world_3d().direct_space_state
	var keep := []
	var dropped := {}
	for it in pz.items:
		var tur: String = it[0]
		var spec: Dictionary = Peyzaj.TURLER[tur]
		var x: float = it[1]
		var z: float = it[2]
		var why := ""
		# Zemin: en üstteki yüzey arazi olmalı (kaldırım, yol, iskele, platform değil)
		var excl: Array[RID] = []
		var hit := {}
		for k in 6:
			var rq := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -60, z), 0xFFFFFFFF, excl)
			hit = space.intersect_ray(rq)
			if hit.is_empty() or String((hit.collider as Node).name) != "Govdeler":
				break
			excl.append(hit.rid)
		if hit.is_empty():
			why = "zemin yok"
		elif String((hit.collider as Node).name) != "AraziCarpisma":
			why = "zemin " + String((hit.collider as Node).name).left(12)
		else:
			var y: float = hit.position.y
			var r: float = float(R[String(spec.grup)]) * float(it[4])
			if tur.begins_with("kaya"):
				r = maxf(float(spec.get("r", 0.4)), 0.4) * float(it[4])
			var sh := CylinderShape3D.new()
			sh.radius = r
			sh.height = 2.6 if String(spec.grup) == "Ağaç" else 1.0
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = sh
			q.transform = Transform3D(Basis(), Vector3(x, y + 0.25 + sh.height * 0.5, z))
			q.collision_mask = 0xFFFFFFFF
			for h in space.intersect_shape(q, 8):
				var nm := String((h.collider as Node).name)
				if nm != "AraziCarpisma" and nm != "Govdeler":
					why = nm.left(14)
					break
		if why == "":
			keep.append(it)
		else:
			dropped[why] = int(dropped.get(why, 0)) + 1
	print("PEYZAJ önce %d, sonra %d" % [pz.items.size(), keep.size()])
	for k in dropped:
		print("  ", k, ": ", dropped[k])
	pz.items = keep
	pz.save()
	get_tree().quit()
