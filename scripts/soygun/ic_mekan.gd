class_name IcMekan
extends Node
## İç mekâna giriş / çıkış. Dışarıda yalnız dükkânın kabuğu, kapısı ve giriş konisi durur
## (Dukkan, ic = false); koniye girince kapı açılır, karakter içeri yürür, yükleme ekranı
## gelir. Bu arada dış dünya (ada, şehir, trafik, kalabalık) gizlenip durdurulur ve dükkânın
## içi (Dukkan, ic = true: raflar, ürünler, sahibi, kameralar) uzakta ayrı bir yerde kurulur.
## Çıkışta tersi: iç silinir, dış dünya geri gelir. Böylece dışarıda iç mekânlar, içeride dış
## dünya hiç işlemci / ekran kartı harcamaz; içine girilebilen yer sayısı performansı etkilemez.

static var instance: IcMekan

## İç mekânların kurulduğu yer: dünyanın çok üstünde (dış dünya gizliyken görünmez)
const ORIGIN := Vector3(0, 1000, 0)
const FADE_IN := 0.35
const FADE_OUT := 0.35
const MIN_LOAD := 0.55
const WALK := 1.7               # kapıdan geçerken yürüme hızı (m/sn)

var player: SkateController
var follow_cam: Node
var ui_parent: Node
var world: Node
## Dışarıda kalan, içerideyken gizlenip durdurulan düğümler
var outside: Array[Node] = []

var inside: Dukkan = null       # şu an içinde bulunulan iç mekân
var busy := false
var _ext: Dukkan = null         # girilen dükkânın dış yüzü (çıkışta oraya dönülür)
var _layer: CanvasLayer
var screen: YuklemeEkrani


func _ready() -> void:
	instance = self
	_layer = CanvasLayer.new()
	_layer.layer = 50
	(ui_parent if ui_parent else self).add_child(_layer)
	screen = YuklemeEkrani.new()
	_layer.add_child(screen)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Giriş: dükkânın dış yüzündeki koniye gelindi
func enter(ext: Dukkan) -> void:
	if busy or inside != null or not _free_to_move():
		return
	busy = true
	_ext = ext
	player.input_locked = true
	# Kaykaydaysa önce iner (kaykay elde)
	if not player.on_foot:
		player.input_locked = false
		player.toggle_board()
		while player.board_anim != SkateController.BoardAnim.NONE:
			await get_tree().physics_frame
		player.input_locked = true
	var into := -ext.global_basis.z.normalized()
	player.auto_walk = Vector3(into.x, 0.0, into.z) * WALK
	await screen.fade_to(1.0, FADE_IN, true)
	player.auto_walk = Vector3.ZERO
	var t0 := Time.get_ticks_msec()
	_set_outside(false)
	var shop := Dukkan.new()
	shop.ic = true
	shop.ad = ext.ad
	shop.player = player
	shop.follow_cam = follow_cam
	shop.ui_parent = ui_parent
	shop.name = "IcMekan_" + ext.name
	shop.transform = Transform3D(Basis.IDENTITY, ORIGIN)
	world.add_child(shop)
	inside = shop
	_place_player(shop.to_global(Vector3(0, 0.05, -1.3)), -shop.global_basis.z)
	await _hold(t0)
	player.input_locked = false
	await screen.fade_to(0.0, FADE_OUT)
	busy = false


## Çıkış: içerideki kapı konisine gelindi ya da yakalanıp dışarı atıldı (thrown)
func exit(thrown := false) -> void:
	if busy or inside == null:
		return
	busy = true
	player.input_locked = true
	screen.caught = false
	if not thrown:
		var out := inside.global_basis.z.normalized()
		player.auto_walk = Vector3(out.x, 0.0, out.z) * WALK
		await screen.fade_to(1.0, FADE_IN, true)
	else:
		await screen.fade_to(1.0, 0.25, true)
	player.auto_walk = Vector3.ZERO
	var t0 := Time.get_ticks_msec()
	var shop := inside
	inside = null
	shop.leave()
	shop.queue_free()
	_set_outside(true)
	var ext := _ext
	if ext and is_instance_valid(ext):
		var out := ext.global_basis.z.normalized()
		_place_player(ext.to_global(Vector3(0, 0.1, 1.9 if not thrown else 1.3)), out)
	await _hold(t0)
	player.input_locked = false
	if thrown and ext and is_instance_valid(ext):
		# Dışarı atılmış: kapının önüne düşer, kalkar
		player.knockdown(ext.global_basis.z.normalized() * 3.0)
	await screen.fade_to(0.0, FADE_OUT)
	busy = false


func is_inside() -> bool:
	return inside != null


func _free_to_move() -> bool:
	return player.fall_time <= 0.0 and not player.sitting and not player.held_in_air and player.skitch_car == null \
		and player.board_anim == SkateController.BoardAnim.NONE


func _hold(t0: int, min_s := MIN_LOAD) -> void:
	while (Time.get_ticks_msec() - t0) / 1000.0 < min_s:
		await get_tree().process_frame


func _place_player(pos: Vector3, facing: Vector3) -> void:
	player.global_position = pos
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	player.heading = f
	player.velocity = Vector3.ZERO
	player.speed = 0.0
	player.reset_physics_interpolation()
	if follow_cam and follow_cam.has_method("snap"):
		follow_cam.snap()


## Dış dünyayı aç / kapat (görünmez ve durur; çarpışmaları uzakta kalır)
func _set_outside(on: bool) -> void:
	for n in outside:
		if not is_instance_valid(n):
			continue
		if n is Node3D:
			(n as Node3D).visible = on
		n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
