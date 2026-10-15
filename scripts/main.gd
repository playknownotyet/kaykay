extends Node3D
## Test sahnesi: ışık, gökyüzü, oyuncu, kamera ve arayüzü kurar.
## Pist geometrisi sahnedeki "Level" düğümünde (level_builder.gd).

const SkateControllerScript := preload("res://scripts/skate_controller.gd")
const PlayerVisualScript := preload("res://scripts/player_visual.gd")
const FollowCameraScript := preload("res://scripts/follow_camera.gd")
const TouchControlsScript := preload("res://scripts/ui/touch_controls.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const SpeedFxScript := preload("res://scripts/speed_fx.gd")
const LookManagerScript := preload("res://scripts/look_manager.gd")

var player: SkateController
var camera: Camera3D
var fx: ColorRect
var look: Node
var env: Environment
var sun: DirectionalLight3D


func _ready() -> void:
	_build_environment()

	player = SkateControllerScript.new()
	player.name = "Player"
	add_child(player)
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.set_script(PlayerVisualScript)
	player.add_child(visual)

	camera = FollowCameraScript.new()
	camera.name = "Camera"
	camera.target = player
	add_child(camera)
	camera.make_current()

	# Hız efekti 3D'nin üstünde, arayüzün altında çizilir
	var post := CanvasLayer.new()
	post.layer = 1
	add_child(post)
	fx = SpeedFxScript.new()
	fx.camera = camera
	post.add_child(fx)

	look = LookManagerScript.new()
	look.name = "Look"
	var look_roots: Array[Node] = [$Level, player]
	look.setup(env, sun, fx, look_roots)
	add_child(look)
	look.apply()

	var ui := CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	var touch := TouchControlsScript.new()
	ui.add_child(touch)
	var hud := HudScript.new()
	ui.add_child(hud)
	hud.setup(player, camera, visual, fx, look, touch)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.58, 1.0)
	sky_mat.sky_horizon_color = Color(0.72, 0.87, 1.0)
	sky_mat.ground_horizon_color = Color(0.72, 0.87, 1.0)
	sky_mat.ground_bottom_color = Color(0.35, 0.55, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.87, 1.0)
	env.fog_density = 0.004
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)
