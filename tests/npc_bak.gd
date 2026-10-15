extends Node
## NPC'lere oyun içinde bakış (pencereli çalıştır):
##   Godot --path . res://tests/npc_bak.tscn
## Her türden bir NPC'yi oyuncunun önüne dizer, bekleme ve yürüme hallerinde
## iki ekran görüntüsü alır: tests/screens/npc_oyunda_*.png

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().physics_frame
	var crowd: NpcCrowd = main.world.get_node("Crowd")
	var p: SkateController = main.player
	var fwd := p.heading
	var right := fwd.cross(Vector3.UP).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var species: Array = NpcCatalog.SPECIES.keys()
	var row: Array[Npc] = []
	for i in species.size():
		var n := Npc.new()
		crowd.add_child(n)
		n.setup(NpcCatalog.make_recipe(rng, species[i]), {})
		n.global_position = p.global_position + fwd * 5.2 + right * (i - (species.size() - 1) * 0.5) * 0.78
		n.global_position.y = p.global_position.y - 0.05
		n.rotation.y = atan2(fwd.x, fwd.z)          # oyuncuya dönük
		n.idle_for(100.0)
		row.append(n)
	if main.look:
		main.look.add_root(crowd)
	for i in 50:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/screens/npc_oyunda_bekle.png")
	# Yürüme: yana doğru yürüsünler (yan profil)
	for n in row:
		n.set_path(PackedVector3Array([n.global_position + right * 30.0]))
	for i in 40:
		for n in row:
			n.tick(1.0 / 60.0, right * n.speed)
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/screens/npc_oyunda_yuru.png")
	get_tree().quit()
