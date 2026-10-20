extends Node3D
## Test sahnesi: ışık, gökyüzü, oyuncu, kamera ve arayüzü kurar.
## Pist geometrisi sahnedeki "Level" düğümünde (level_builder.gd).
##
## Retro görüntü: tüm 3D dünya + ekran efekti küçük bir "sanal ekranda"
## (SubViewport, örn. 457x206) çizilir ve pikseller yumuşatılmadan büyütülür.
## Böylece pikseller keskin kalır, zayıf telefonlarda da hızlı çalışır.
## Arayüz (butonlar, yazılar) tam çözünürlükte, ayrı katmanda çizilir.

const SkateControllerScript := preload("res://scripts/skate_controller.gd")
const PlayerVisualScript := preload("res://scripts/player_visual.gd")
const FollowCameraScript := preload("res://scripts/follow_camera.gd")
const TouchControlsScript := preload("res://scripts/ui/touch_controls.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const SpeedFxScript := preload("res://scripts/speed_fx.gd")
const LookManagerScript := preload("res://scripts/look_manager.gd")
## Oyunun adası (tools/ada/ada_bake.gd ile hazırlanır). Yoksa eski gri kutu test pisti açılır.
const ADA_SCENE := "res://scenes/ada.scn"

var player: SkateController
var camera: Camera3D
var fx: ColorRect
var look: Node
var env: Environment
var sun: DirectionalLight3D
## 3D dünyanın çizildiği düşük çözünürlüklü sanal ekran
var world: SubViewport
var _world_view: TextureRect
var _pixel_size := 1.0
## false: eski test pisti (otomatik testler bunu kullanır)
var use_island := true


func _ready() -> void:
	_setup_performance()
	_build_world_view()

	# Ada (ya da eski test pisti) sanal ekrana
	var level: Node3D = $Level
	remove_child(level)
	if use_island and ResourceLoader.exists(ADA_SCENE):
		level.free()
		level = load(ADA_SCENE).instantiate()
	world.add_child(level)

	_build_environment()

	player = SkateControllerScript.new()
	player.name = "Player"
	if level.has_meta("spawn"):
		player.transform = level.get_meta("spawn")   # "Başa dön" de buraya döner
	world.add_child(player)
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.set_script(PlayerVisualScript)
	player.add_child(visual)

	# Titreşim (telefon) ve yüzey hissi
	var haptics := Haptics.new()
	haptics.name = "Haptics"
	add_child(haptics)
	var feedback := SurfaceFeedback.new()
	feedback.name = "Feedback"
	player.add_child(feedback)

	camera = FollowCameraScript.new()
	camera.name = "Camera"
	camera.target = player
	camera.feedback = feedback
	world.add_child(camera)
	camera.make_current()

	# Hız efekti / retro filtre de düşük çözünürlükte çizilir (hem ucuz hem keskin)
	var post := CanvasLayer.new()
	world.add_child(post)
	fx = SpeedFxScript.new()
	fx.camera = camera
	post.add_child(fx)

	look = LookManagerScript.new()
	look.name = "Look"
	var look_roots: Array[Node] = [level, player]
	look.setup(env, sun, fx, look_roots)
	look.pixel_size_changed.connect(set_pixel_size)
	add_child(look)
	look.apply()

	# Banklar: oyuncu ve NPC'ler oturabilir
	var benches := Banklar.new()
	benches.name = "Banklar"
	benches.player = player
	benches.level = level
	world.add_child(benches)

	# Hayvan NPC kalabalığı (yürüme ağı açılışta haritadan çıkarılır)
	var crowd := NpcCrowd.new()
	crowd.benches = benches
	crowd.name = "Crowd"
	crowd.player = player
	crowd.camera = camera
	crowd.look = look
	crowd.walk_source = level
	world.add_child(crowd)

	# Araba trafiği (adanın şerit ağı; eski test pistinde araba yok)
	var traffic := Trafik.new()
	traffic.name = "Trafik"
	traffic.player = player
	traffic.camera = camera
	traffic.crowd = crowd
	traffic.look = look
	if not (use_island and level.has_meta("walk_cross")):
		traffic.count = 0
	world.add_child(traffic)

	# Kaykay ve çevre sesleri (Ortam yolu; kulaklık takılıyken bastırılır)
	var sounds := KaykaySes.new()
	sounds.name = "Sesler"
	sounds.player = player
	sounds.feedback = feedback
	sounds.traffic = traffic
	world.add_child(sounds)

	# Şehir: süs binaları, dükkânlar, ara sokaklar, merdivenler, yükseltiler, korkuluklar
	# (assets/ada/sehir.json; oyun içi editörle düzenlenir). Gövdeleri katman 2'de.
	player.collision_mask |= Sehir.LAYER
	var city := Sehir.new()
	city.name = "Sehir"
	city.player = player
	city.follow_cam = camera
	city.look = look
	city.ui_parent = self
	city.level = level
	if use_island and level.has_meta("dukkan"):
		city.initial_shop = level.get_meta("dukkan")
	world.add_child(city)

	# Peyzaj: ağaçlar, çalılar, ot öbekleri, kayalar (assets/ada/peyzaj.json)
	var peyzaj := Peyzaj.new()
	peyzaj.name = "Peyzaj"
	peyzaj.look = look
	world.add_child(peyzaj)

	# İç mekân geçişleri: içerideyken dış dünya gizli ve durur
	var interiors := IcMekan.new()
	interiors.name = "IcMekan"
	interiors.player = player
	interiors.follow_cam = camera
	interiors.ui_parent = self
	interiors.world = world
	interiors.outside = [level, crowd, traffic, city, benches, peyzaj]
	add_child(interiors)

	var ui := CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	var touch := TouchControlsScript.new()
	ui.add_child(touch)
	var hud := HudScript.new()
	ui.add_child(hud)
	hud.setup(player, camera, visual, fx, look, touch)

	# Rampa yeteneği: buton direksiyonun üstünde; rampa dünyada (dış mekânla birlikte gizlenir)
	var rampa := RampaYetenek.new()
	rampa.name = "Rampa"
	rampa.player = player
	rampa.camera = camera
	world.add_child(rampa)
	interiors.outside.append(rampa)
	touch.rampa = rampa
	rampa.denied.connect(touch.rampa_denied)

	# Navigasyon: harita ve hedef işareti (HUD'un altında, hedef işareti dünyanın üstünde)
	var nav := Navigasyon.new()
	nav.name = "Navigasyon"
	nav.player = player
	nav.camera = camera
	nav.world = world
	nav.touch_controls = touch
	ui.add_child(nav)
	ui.move_child(nav, 0)

	# Şehir editörü (bilgisayarda Tab)
	var editor := SehirEditor.new()
	editor.name = "SehirEditor"
	editor.sehir = city
	editor.world = world
	editor.player = player
	editor.follow_cam = camera
	editor.hide_while_open = [touch, hud, nav]
	add_child(editor)


## Bir sanal ekran pikselinin gerçek ekranda kaç piksel olacağı.
func set_pixel_size(value: float) -> void:
	_pixel_size = maxf(value, 1.0)
	_resize_world()


func _build_world_view() -> void:
	SesAyar.setup()
	world = SubViewport.new()
	# 3D sesler (korna) bu görüntünün kamerasından duyulur
	world.audio_listener_enable_3d = true
	world.name = "World"
	world.msaa_3d = Viewport.MSAA_DISABLED
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.physics_object_picking = false
	add_child(world)

	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_world_view = TextureRect.new()
	_world_view.texture = world.get_texture()
	_world_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_world_view.stretch_mode = TextureRect.STRETCH_SCALE
	_world_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_world_view)

	get_viewport().size_changed.connect(_resize_world)
	_resize_world()


func _resize_world() -> void:
	var screen := get_viewport().get_visible_rect().size
	world.size = Vector2i(ceili(screen.x / _pixel_size), ceili(screen.y / _pixel_size))


## Zayıf telefonlar için çizim ayarları. Retro görünümde kenar yumuşatma
## işe yaramaz, gölgeler de sert ve tek kademeli daha iyi durur.
func _setup_performance() -> void:
	# Telefonda kare hızı 60'ta sabit: ekranın gösteremeyeceği fazladan kareler (120-180 FPS)
	# işlemciyi ve ekran kartını boşuna ısıtır; birkaç dakikada telefon kendini yavaşlatır
	if OS.has_feature("mobile"):
		Engine.max_fps = 60
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(1024, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)


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
	world.add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 30.0
	world.add_child(sun)
