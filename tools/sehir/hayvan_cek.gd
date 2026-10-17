extends Node
## İç mekân dokuları için oyundaki hayvanları önden "fotoğraflar" (piksel figür kaynağı).
## Çıktı: art/sehir_odalar/hayvan_<tür>_<poz>_<n>.png (saydam arka plan). Sonra
## tools/sehir/oda_atlas.py bunları odalara yerleştirir.
##   Godot --path . res://tools/sehir/hayvan_cek.tscn

const OUT := "res://art/sehir_odalar/"
const POSES := {"masa": ["drive", 0.6], "otur": ["otur", 0.5], "ayakta": ["idle", 0.4]}
const PX := 128


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := SubViewport.new()
	vp.size = Vector2i(PX, PX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 160, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.2
	cam.position = Vector3(0, 0.95, -4.0)
	cam.rotation_degrees = Vector3(0, 180, 0)
	vp.add_child(cam)
	cam.make_current()
	var mats := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 0
	for sp in NpcCatalog.SPECIES:
		for v in 2:
			var recipe := NpcCatalog.make_recipe(rng, sp)
			recipe.parts = recipe.parts.filter(func(p): return not String(p).begins_with("tur_kuyruk"))
			for pose in POSES:
				var model := Npc.build_model(recipe, mats)
				vp.add_child(model)
				var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
				var a: String = POSES[pose][0]
				if ap == null or not ap.has_animation(a):
					model.queue_free()
					continue
				ap.play(a)
				ap.seek(POSES[pose][1], true)
				ap.pause()
				for f in 3:
					await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image()
				img.save_png(OUT + "hayvan_%s_%s_%d.png" % [sp, pose, v])
				n += 1
				model.queue_free()
				await get_tree().process_frame
	print("HAYVAN ", n, " figür")
	get_tree().quit()
