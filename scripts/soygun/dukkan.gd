class_name Dukkan
extends Node3D
## Zürafa Bakkal: çocuk soygunu / gizlilik akışı.
##
## Bina, mobilyalar ve ürünler assets/dukkan/dukkan.glb'den (tools/blender/dukkan_build.py).
## Raflar bölümlere (yüzlere) ayrılır; her bölümde birkaç tür ürün dizilidir (MultiMesh, tür başına
## tek çizim). Rafın önüne gelince raf ince beyaz çizgiyle belirir; etkileşim butonuyla kamera rafa
## tam karşıdan bakar, istenen ürüne dokunulur (öne çıkar). "Onay" ürünü sol ele alır ve kamera
## üçüncü şahsa döner; yanlış seçimde "geri bırak" ürünü rafa koyar, "kapat" bir şey almadan çıkar.
## Elde gezdirilir; istenen yerde çantaya atılır ya da aynı rafa geri bırakılır.
##
## Liste: her ziyarette aranan birkaç ürün (sol üstte). Çantada olanlar işaretlenir.
##
## Akış:
##   - İçeride "göz" butonu: kamera kuş bakışına uçar, çatı kalkar; güvenlik kameralarının ve
##     kasadaki zürafanın görüş alanları zemine canlı çizilir (raflar görüşü keser; kameralar
##     tarar, zürafa etrafına bakınır). Kör noktaları ezberlemek için geri sayım ("hazır" ile
##     geçilir), sonra kamera üçüncü şahsa geri uçar.
##   - Yakalanma yalnız çantaya atarken bir kamera ya da zürafa görüyorsa: ekran kararır,
##     "YAKALANDIN!", kamera sokaktan kapıya bakar; zürafa çocuğu tişörtünden tutup hafifçe
##     kaldırır ve dükkândan dışarı atar; çocuk kalkar, oyun sürer. Dükkândan aldıkları geri alınır.
##
## Yerel düzen: köken kapı ortası (zemin), -Z dükkanın içi, +X sağ (içeri bakınca).
##
## İki biçim (scripts/soygun/ic_mekan.gd geçişi yönetir):
##   - Dış (ic = false, şehirde): yalnız kabuk, tabela, vitrinden görünen sabit raflar, otomatik
##     kapı ve önünde silik giriş konisi. Betik / ışın / ışık / sahibi yok: yanından geçmek bedava.
##   - İç (ic = true, dünyanın uzağında, girince kurulur): raflar, ürünler, zürafa, kameralar,
##     liste. Kapının içindeki koniden çıkılır (elde ürün varken çıkılmaz).

enum Faz { NORMAL, KESIF_GIRIS, KESIF, KESIF_CIKIS, YAKALANDI, RAF_GIRIS, RAF, RAF_CIKIS }

const W := 10.0
const D := 8.0
const H := 3.6
const GLB := preload("res://assets/dukkan/dukkan.glb")
const CHAR_SHADER := preload("res://shaders/toon_char.gdshader")
const PROP_SCRIPT := preload("res://scripts/ada/prop_katmani.gd")
const DOKU_SHADER := preload("res://shaders/doku.gdshader")
const DOKU_ATLAS := preload("res://assets/sehir/dokular.png")
## Ürün etiketleri (tools/blender/urun_etiket.py)
const URUN_SHADER := preload("res://shaders/urun.gdshader")
const ETIKET := preload("res://assets/dukkan/urun_etiket.png")
## Piksel dokulu yüzeyler (şehrin cepheleriyle aynı tarz): malzeme adı -> [karo, karo boyu (m), renk]
const DOKULU := {
	"duvar": [0, 1.5, Color.WHITE], "tas": [1, 1.0, Color.WHITE], "tas_koyu": [1, 1.0, Color(0.82, 0.82, 0.82)],
	"korniz": [2, 0.5, Color.WHITE], "cati": [3, 2.0, Color.WHITE], "duvar_ic": [4, 1.5, Color.WHITE],
	"lambri": [5, 1.0, Color.WHITE], "tabela": [6, 0.6, Color.WHITE], "ahsap": [7, 0.8, Color.WHITE],
	"ahsap_koyu": [7, 0.8, Color(0.62, 0.55, 0.5)],
}
## Raf kamerasına geçiş süresi (sn)
const RAF_GECIS := 0.55
const KESIF_SURE := 10.0
const GECIS := 1.0
## karakter_rig.py "eline_al": 20 kare, eşya 10. karede elde
const AL_SURE := 20.0 / 30.0
const AL_GRAB := 10.0 / 30.0
## npc_ortak.py "disari_at": 60 kare; 12. karede tutar, 34. karede bırakır
const AT_TUT := 12.0 / 30.0
const AT_BIRAK := 34.0 / 30.0
const RAY_N := 48
const CONE_H := 1.2               # görüş ışınlarının yüksekliği: raflar keser, tezgâh kesmez
## Rafın önünden bu kadar uzaktan (m) ürün alınabilir
const REACH := 1.2
const LIST_SIZE := 3
## İç mekân (raflar, ürünler, zürafa) bu mesafeden uzakta çizilmez; dükkân bu kadar uzaktayken
## görüş alanlarını güncellemez (telefonda kare başına yüzlerce ışın)
const INSIDE_VIS := 60.0
const SLEEP_DIST := 45.0

## Raf seviyeleri (ürün tabanı; dukkan_build.py ile aynı)
const GONDOLA_Z := [0.14, 0.5, 0.86, 1.22]
const WALL_Z := [0.14, 0.52, 0.9, 1.28, 1.66]
const FRIDGE_Z := [0.2, 0.62, 1.04, 1.42]

## Mobilyalar: [şablon, konum (x, z), yön (derece: ön yüz +Z'den bu kadar döner), bölümler]
## Bölümler: her yüz için alttan üste seviye başına ürün türleri.
## Raf (ada) iki yüzlü: [ön (+Z yerel), arka]; DuvarRaf / Buzdolabi tek yüz.
const LAYOUT := [
	["Raf", Vector2(-2.2, -4.3), 90.0, [
		[["gevrek"], ["gevrek"], ["cikolata"], ["cikolata", "cips"]],
		[["konserve"], ["konserve", "bal"], ["bal", "kurabiye"], ["kurabiye"]]]],
	["Raf", Vector2(0.6, -4.3), 90.0, [
		[["sampuan"], ["sampuan", "macun"], ["macun"], ["macun", "sampuan"]],
		[["cips"], ["cips"], ["cikolata", "kurabiye"], ["kurabiye"]]]],
	["DuvarRaf", Vector2(-4.755, -2.6), 90.0, [[["ekmek"], ["ekmek"], ["ekmek"], ["kurabiye"], ["cikolata"]]]],
	["DuvarRaf", Vector2(-4.755, -5.45), 90.0, [[["konserve"], ["konserve"], ["bal"], ["bal"], ["gevrek"]]]],
	["DuvarRaf", Vector2(-3.0, -7.755), 0.0, [[["yumurta"], ["yumurta"], ["konserve"], ["macun"], ["sampuan"]]]],
	["DuvarRaf", Vector2(-0.15, -7.755), 0.0, [[["cips"], ["cips"], ["gevrek"], ["cikolata"], ["kurabiye"]]]],
	["Buzdolabi", Vector2(3.35, -7.6), 0.0, [[["su"], ["su"], ["kola"], ["kola"]]]],
	["Buzdolabi", Vector2(4.4, -7.6), 0.0, [[["sut"], ["sut"], ["kola"], ["su"]]]],
	["MeyveKasasi", Vector2(-2.9, -0.7), 180.0, [[["elma"]]]],
	["Tezgah", Vector2(2.9, -2.2), -90.0, [[["cikolata"]]]],
	["Sepetler", Vector2(-1.45, -0.55), 15.0, []],
]
## Dışarıdaki süsler: [şablon, konum (x, z), yön]; "prop:" ile başlayanlar Poly Haven sokak eşyası
const OUTSIDE := [
	["MeyveTezgahi", Vector2(-3.0, 0.75), 0.0],
	["TabelaA", Vector2(1.85, 0.75), -20.0],
	["GazeteStandi", Vector2(3.7, 0.55), 0.0],
	["prop:planter_box_01", Vector2(-4.85, 0.45), 0.0],
	["prop:planter_box_01", Vector2(5.0, 0.45), 0.0],
	["prop:metal_trash_can", Vector2(5.75, -0.4), 0.0],
	["prop:plastic_crate_02", Vector2(5.65, -1.4), 90.0],
	["prop:plastic_crate_02", Vector2(5.65, -2.0), 80.0],
]
const PROP_COLLIDE := {
	"planter_box_01": Vector3(0.93, 0.43, 0.43), "metal_trash_can": Vector3(0.6, 0.9, 0.6),
	"plastic_crate_02": Vector3(0.51, 0.25, 0.4),
}

var player: SkateController
var follow_cam: Camera3D
## true: iç mekân (girilince kurulur); false: şehirdeki dış yüz
var ic := false
## Ekran arayüzünün ekleneceği düğüm (ana görüntüde; dünya ayrı bir SubViewport'ta çizilir ve
## oraya dokunuş gitmez). Verilmezse dükkânın kendisi.
var ui_parent: Node
## Tabela yazısı (şehir editöründe dükkân adı)
var ad := "ZÜRAFA BAKKAL"
var _layer: CanvasLayer

var faz := Faz.NORMAL
var _t := 0.0
var _cam: Camera3D
var _from := Transform3D.IDENTITY
var _from_fov := 60.0
var _roof: Node3D
var _watchers: Array = []
var _owner: Node3D
var _owner_head := -1
var _owner_skel: Skeleton3D
var _owner_yaw := PI * 0.5
var _owner_target := PI * 0.5
var _owner_hold := 2.0
var _owner_anim: AnimationPlayer
var _owner_mode := 0           # 0 tezgâhta, 1 sinematik, 2 tezgâha dönüyor
var _owner_path: Array[Vector3] = []
var _ct := 0.0                 # yakalanma sinematiği zamanı
var _released := false
var _back_t := -1.0
var _fade := 0.0
var _cine_from := Transform3D.IDENTITY
var _banner := ""
var _banner_t := 0.0
var _owns_buttons := false
var _ui: Control
var _rng := RandomNumberGenerator.new()

# Ürünler ve raflar
var _glb: Node3D
var _meshes := {}               # şablon adı -> dönüştürülmüş mesh
var _mats := {}
var _slots: Array = []          # {type, xf, bay, mm, idx, gone}
var _bays: Array = []           # {c, n, t, half, slots}
var _mm := {}                   # tür -> MultiMesh
var _mm_count := {}
var _near_bay := -1
var _take_t := -1.0
var _take_slot := -1
var _put_t := -1.0
var _held_slot := -1            # elde tutulan (bu dükkândan) ürünün yeri
var _held_node: Node3D
var _stolen: Array[int] = []    # çantaya atılmış ürünlerin yerleri (raf boş)
var _stowing_slot := -1
var _stow_seen := false
var _wanted: Array[String] = []
var _list_done := false

# Raf kamerası ve dış çizgi
var _furn: Array[MeshInstance3D] = []  # LAYOUT sırasıyla mobilya düğümleri
var _cur_inst: MeshInstance3D          # stoklanırken bölümün mobilyası
var _outline_mat: StandardMaterial3D
var _outline_mask: StandardMaterial3D
var _lit: Node3D                       # şu an çizgisi yanan mobilyanın dış çizgisi
var _raf_bay := -1
var _raf_from := Transform3D.IDENTITY
var _raf_fov := 60.0
var _sel := -1                         # seçilen (öne çıkan) ürün
var _sel_node: Node3D
var _sel_t := 0.0
var _raf_take := -1                    # onaylanan ürün: kamera dönünce ele alınır
var _raf_btn := {}                     # buton adı -> ekran dikdörtgeni

# Kapı ve giriş / çıkış konisi
var _doors: Array[Node3D] = []
var _door_open := 0.0
var _marker: MeshInstance3D
var _armed := false                    # koni ancak oyuncu bir kez uzaklaşınca tetiklenir
static var _marker_shader: Shader


func _ready() -> void:
	_rng.randomize()
	_outline_mask = StandardMaterial3D.new()
	_outline_mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mask.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_mask.albedo_color = Color(0, 0, 0, 0)
	_outline_mask.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_outline_mask.no_depth_test = true      # maske hep tam: kutu yüzleri rafla çakışıp benek bırakmasın
	_outline_mask.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	_outline_mask.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	_outline_mask.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	_outline_mask.stencil_reference = 1
	_outline_mask.render_priority = 20
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_mat.albedo_color = Color(1, 1, 1, 0.8)
	_outline_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_outline_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	_outline_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
	_outline_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
	_outline_mat.stencil_reference = 1
	_outline_mat.render_priority = 21
	_glb = GLB.instantiate()
	_build_shell()
	_build_furniture()
	_build_products()
	_build_doors()
	if not ic:
		# Dış yüz: kapı kapalı (içeri ancak koniyle, yükleme ekranıyla girilir)
		_build_outside()
		_marker = _build_marker(Vector3(0, 0, 1.15))
		_collide(Vector3(2.0, 2.3, 0.25), Transform3D(Basis(), Vector3(0, 1.15, 0.1)))
		_armed = true
		return
	_marker = _build_marker(Vector3(0, 0, -0.5))
	# İçeriden kapı boşluğu kapalı: iç mekân boşlukta durur, kapıdan dışarı yürünürse düşülürdü.
	# Çıkış yalnız koniyle (yükleme ekranı); kapı görsel olarak açılır ama geçilmez.
	_collide(Vector3(2.0, 2.3, 0.25), Transform3D(Basis(), Vector3(0, 1.15, 0.2)))
	_armed = true
	_build_owner()
	_build_cameras()
	_new_list()
	_cam = Camera3D.new()
	_cam.name = "KesifKamerasi"
	# Dükkân içi ve tepeden bakış: uzak şehir çizilmez (varsayılan 4 km tüm adayı çiziyordu)
	_cam.far = 140.0
	add_child(_cam)
	_cam.top_level = true
	_layer = CanvasLayer.new()
	_layer.layer = 3
	(ui_parent if ui_parent else self).add_child(_layer)
	_ui = preload("res://scripts/soygun/dukkan_ui.gd").new()
	_ui.shop = self
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_ui)
	if player:
		player.context_action.connect(_on_context)
		player.stow_started.connect(_on_stow_started)
		player.item_stowed.connect(_on_item_stowed)


func _exit_tree() -> void:
	if _glb and is_instance_valid(_glb):
		_glb.free()
	if _layer and is_instance_valid(_layer) and _layer.get_parent() != self:
		_layer.queue_free()


# ---------- Modeller ve malzemeler ----------

## glb'deki malzemeyi oyunun görünümüne çevir: düz renk toon; cam saydam; ışık / ekran parlak
func _material_for(src: Material) -> Material:
	var key := String(src.resource_name) if src else ""
	if _mats.has(key):
		return _mats[key]
	var c := Color.WHITE
	if src is BaseMaterial3D:
		c = (src as BaseMaterial3D).albedo_color
	var m: Material
	if key == "cam":
		var sm := StandardMaterial3D.new()
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = Color(c.r, c.g, c.b, 0.28) if not ic else Color(0.86, 0.93, 0.98, 0.9)
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		m = sm
	elif key == "etiket":
		var um := ShaderMaterial.new()
		um.shader = URUN_SHADER
		um.set_shader_parameter("atlas", ETIKET)
		m = um
	elif DOKULU.has(key):
		var spec: Array = DOKULU[key]
		var dm := ShaderMaterial.new()
		dm.shader = DOKU_SHADER
		dm.set_shader_parameter("atlas", DOKU_ATLAS)
		dm.set_shader_parameter("tile", float(spec[0]))
		dm.set_shader_parameter("meters", float(spec[1]))
		dm.set_shader_parameter("tint", spec[2])
		m = dm
	elif key in ["isik", "led", "ekran", "lamba"]:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = c
		m = sm
	else:
		var sh := ShaderMaterial.new()
		sh.shader = CHAR_SHADER
		sh.set_shader_parameter("albedo", c)
		m = sh
	_mats[key] = m
	return m


## Şablonun meshi (malzemeleri dönüştürülmüş, önbellekli)
func _mesh(name: String) -> ArrayMesh:
	if _meshes.has(name):
		return _meshes[name]
	var src := _glb.find_child(name, true, false) as MeshInstance3D
	if src == null:
		push_warning("Dukkan: şablon yok: " + name)
		_meshes[name] = null
		return null
	var am := (src.mesh as ArrayMesh).duplicate() as ArrayMesh
	for i in am.get_surface_count():
		am.surface_set_material(i, _material_for(src.mesh.surface_get_material(i)))
	_meshes[name] = am
	return am


func _instance(name: String, xf: Transform3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _mesh(name)
	mi.transform = xf
	(parent if parent else self).add_child(mi)
	return mi


## Görünmez çarpışma kutusu (yerel dönüşümle)
func _collide(size: Vector3, xf: Transform3D, surface := "beton") -> void:
	var body := StaticBody3D.new()
	body.set_meta("surface", surface)
	# Şehir katmanı (Sehir.LAYER): adanın iskeleti değil; editörün çakışma denetimi bunu görmez
	body.collision_layer = Sehir.LAYER
	body.collision_mask = 0
	body.transform = xf
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)


## Mobilyanın kendi sınır kutusuyla çarpışma
func _collide_aabb(name: String, xf: Transform3D, shrink := 0.0) -> void:
	var m := _mesh(name)
	if m == null:
		return
	var bb := m.get_aabb()
	_collide(bb.size - Vector3(shrink, 0, shrink), xf * Transform3D(Basis(), bb.get_center()))


static func _xf(p: Vector2, yaw_deg: float, y := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(p.x, y, p.y))


# ---------- Yapı ----------

func _build_shell() -> void:
	_instance("Bina", Transform3D.IDENTITY)
	_roof = Node3D.new()
	_roof.name = "Cati"
	add_child(_roof)
	_instance("Cati", Transform3D.IDENTITY, _roof)
	# Çarpışmalar: zemin, duvarlar (vitrin camları da duvar), kapı üstü, çatı
	var T := 0.2
	_collide(Vector3(W + 0.4, 0.12, D + 1.1), Transform3D(Basis(), Vector3(0, -0.06, -D * 0.5 + 0.55)))
	_collide(Vector3(W + 0.4, H, T), Transform3D(Basis(), Vector3(0, H * 0.5, -D - T * 0.5)))
	_collide(Vector3(T, H, D + T), Transform3D(Basis(), Vector3(-W * 0.5 - T * 0.5, H * 0.5, -D * 0.5 + T * 0.5)))
	_collide(Vector3(T, H, D + T), Transform3D(Basis(), Vector3(W * 0.5 + T * 0.5, H * 0.5, -D * 0.5 + T * 0.5)))
	var seg := (W + 2 * T - 2.0) * 0.5
	for s in [-1.0, 1.0]:
		_collide(Vector3(seg, H, T), Transform3D(Basis(), Vector3(s * (1.0 + seg * 0.5), H * 0.5, T * 0.5)))
	_collide(Vector3(2.0, H - 2.3, T), Transform3D(Basis(), Vector3(0, 2.3 + (H - 2.3) * 0.5, T * 0.5)))
	_collide(Vector3(W + 0.4, 0.15, D + T * 2), Transform3D(Basis(), Vector3(0, H + 0.075, -D * 0.5)))
	# Tabela yazısı
	var sign := Label3D.new()
	sign.text = ad
	sign.font_size = 72
	sign.outline_size = 12
	sign.modulate = Color(1.0, 0.86, 0.3)
	sign.outline_modulate = Color(0.12, 0.2, 0.16)
	sign.pixel_size = 0.0065
	sign.position = Vector3(0, 3.25, T + 0.13)
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(sign)
	# İç ışıklar (çatı güneşi keser): yalnız iç mekânda
	for z in ([-2.2, -5.6] if ic else []):
		var l := OmniLight3D.new()
		l.position = Vector3(0, H - 0.5, z)
		l.omni_range = 7.5
		l.light_energy = 1.0
		l.light_color = Color(1.0, 0.97, 0.9)
		add_child(l)


func _build_furniture() -> void:
	for f in LAYOUT:
		var name: String = f[0]
		var xf := _xf(f[1], f[2])
		var inst := _instance(name, xf)
		inst.visibility_range_end = INSIDE_VIS if ic else 35.0
		_furn.append(inst)
		if not ic:
			if name == "Buzdolabi":
				_instance("DolapRaflari", xf).visibility_range_end = 35.0
			continue
		if name != "Sepetler":
			var hull := _outline_node(inst.mesh.get_aabb(), 0.03)
			hull.visible = false
			inst.add_child(hull)
		if name == "Buzdolabi":
			_instance("DolapRaflari", xf * Transform3D(Basis(), Vector3(0, 0, 0.0)))
		if name == "Tezgah":
			# Yazar kasa tezgâhın kasiyer tarafında
			_instance("YazarKasa", xf * Transform3D(Basis(), Vector3(0.45, 1.0, -0.05)))
		if name == "Tezgah":
			# Yalnız tezgâhın gövdesi (üstündeki şeker standı ve kasa zürafanın görüşünü kesmesin)
			_collide(Vector3(2.5, 1.0, 0.8), xf * Transform3D(Basis(), Vector3(0, 0.5, 0)), "tahta")
		elif name != "Sepetler":
			_collide_aabb(name, xf, 0.02)


func _build_outside() -> void:
	for o in OUTSIDE:
		var name: String = o[0]
		var xf := _xf(o[1], o[2])
		if name.begins_with("prop:"):
			var key := name.substr(5)
			var entry: Dictionary = PROP_SCRIPT._load("res://assets/props/%s.glb" % key)
			if entry.is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = entry.mesh
			mi.material_override = entry.material
			mi.transform = xf
			add_child(mi)
			var sz: Vector3 = PROP_COLLIDE.get(key, Vector3(0.4, 0.5, 0.4))
			_collide(sz, xf * Transform3D(Basis(), Vector3(0, sz.y * 0.5, 0)), "metal")
		else:
			_instance(name, xf)
			_collide_aabb(name, xf, 0.04)


# ---------- Ürünler ve raf bölümleri ----------

func _build_products() -> void:
	for li in LAYOUT.size():
		var f: Array = LAYOUT[li]
		_cur_inst = _furn[li]
		var name: String = f[0]
		var xf := _xf(f[1], f[2])
		var faces: Array = f[3]
		match name:
			"Raf":
				for side in faces.size():
					var sg := 1.0 if side == 0 else -1.0
					_stock_face(xf, faces[side], GONDOLA_Z, 2.7, 0.25 * sg, sg, 0.45 * sg)
			"DuvarRaf":
				_stock_face(xf, faces[0], WALL_Z, 2.7, 0.02, 1.0, 0.225)
			"Buzdolabi":
				_stock_face(xf, faces[0], FRIDGE_Z, 0.82, 0.0, 1.0, 0.375)
			"MeyveKasasi":
				_stock_crates(xf)
			"Tezgah":
				_stock_counter(xf)
	# Tür başına bir MultiMesh
	var per_type := {}
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		if not per_type.has(s.type):
			per_type[s.type] = []
		per_type[s.type].append(i)
	for type in per_type:
		var list: Array = per_type[type]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh("urun_" + type)
		mm.instance_count = list.size()
		for k in list.size():
			var s: Dictionary = _slots[list[k]]
			s.mm = mm
			s.idx = k
			mm.set_instance_transform(k, s.xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Urun_" + type
		mmi.multimesh = mm
		mmi.visibility_range_end = INSIDE_VIS
		add_child(mmi)
		_mm[type] = mm


## Bir raf yüzü: seviye başına türler; L: kullanılabilir uzunluk, depth: ürün sırasının yerel z'si,
## facing: yüzün baktığı yön (+1 yerel +Z), front: yüzün önü (yerel z)
func _stock_face(xf: Transform3D, levels: Array, heights: Array, L: float, depth: float, facing: float, front: float) -> void:
	var bay := _add_bay(xf * Vector3(0, 0, front + 0.05 * facing), xf.basis * Vector3(0, 0, facing), xf.basis * Vector3(1, 0, 0), L * 0.5)
	var yaw := 0.0 if facing > 0.0 else PI
	for lv in mini(levels.size(), heights.size()):
		var types: Array = levels[lv]
		var block := L / types.size()
		for ti in types.size():
			var type: String = types[ti]
			var m := _mesh("urun_" + type)
			if m == null:
				continue
			var bb := m.get_aabb()
			var w := bb.size.x + 0.025
			var n := int(floor(block / w))
			var x0 := -L * 0.5 + ti * block + (block - n * w) * 0.5 + w * 0.5
			for k in n:
				var basis := Basis(Vector3.UP, yaw + _rng.randf_range(-0.06, 0.06))
				var lift := 0.0
				if type == "cikolata":
					# Rafta dik durur: geniş yüzü (ambalaj) öne bakar
					basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
					lift = bb.size.z * 0.5
				var local := Transform3D(basis, Vector3(x0 + k * w, heights[lv] + lift, depth))
				_add_slot(type, xf * local, bay)


## Meyve kasaları: üç kasada elma yığını (alt sıra ve araya oturan üst sıra)
func _stock_crates(xf: Transform3D) -> void:
	var bay := _add_bay(xf * Vector3(0, 0, 0.35), xf.basis * Vector3(0, 0, 1), xf.basis * Vector3(1, 0, 0), 0.6)
	for cx in [-0.4, 0.0, 0.4]:
		for layer in 2:
			var nx := 4 - layer
			var nz := 5 - layer
			for i in nx:
				for j in nz:
					var p := Vector3(cx - 0.135 + i * 0.09 + layer * 0.045, 0.48 + layer * 0.07, -0.18 + j * 0.09 + layer * 0.045)
					_add_slot("elma", xf * Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p), bay)


## Tezgâhtaki şeker standı: zürafanın burnunun dibinde çikolatalar
func _stock_counter(xf: Transform3D) -> void:
	# dukkan_build.py: basamaklar x -0,75, y -0,12 + k*0,08, üstleri 1,08 + 0,12k (Blender; Godot z = -y)
	var bay := _add_bay(xf * Vector3(-0.75, 0, 0.5), xf.basis * Vector3(0, 0, 1), xf.basis * Vector3(1, 0, 0), 0.4)
	for k in 3:
		for i in 3:
			var p := Vector3(-0.95 + i * 0.2, 1.08 + 0.12 * k, 0.12 - k * 0.08)
			_add_slot("cikolata", xf * Transform3D(Basis(), p), bay)


func _add_bay(c: Vector3, n: Vector3, t: Vector3, half: float) -> int:
	_bays.append({"c": Vector3(c.x, 0.0, c.z), "n": Vector3(n.x, 0.0, n.z).normalized(), "t": Vector3(t.x, 0.0, t.z).normalized(), "half": half, "slots": [],
		"inst": _cur_inst, "lo": INF, "hi": -INF})
	return _bays.size() - 1


func _add_slot(type: String, xf: Transform3D, bay: int) -> void:
	_slots.append({"type": type, "xf": xf, "bay": bay, "mm": null, "idx": -1, "gone": false})
	var b: Dictionary = _bays[bay]
	b.slots.append(_slots.size() - 1)
	var m := _mesh("urun_" + type)
	var h := m.get_aabb().size.y if m else 0.1
	b.lo = minf(b.lo, xf.origin.y)
	b.hi = maxf(b.hi, xf.origin.y + h)


func _set_slot_visible(i: int, on: bool) -> void:
	var s: Dictionary = _slots[i]
	s.gone = not on
	var mm: MultiMesh = s.mm
	if mm:
		mm.set_instance_transform(s.idx, s.xf if on else Transform3D(Basis().scaled(Vector3.ZERO), s.xf.origin))


## Oyuncunun önünde durduğu raf bölümü (yoksa -1)
func _bay_at(lp: Vector3) -> int:
	var best := -1
	var best_d := REACH
	for b in _bays.size():
		var bay: Dictionary = _bays[b]
		var rel: Vector3 = Vector3(lp.x, 0, lp.z) - bay.c
		var out: float = rel.dot(bay.n)
		var along: float = absf(rel.dot(bay.t))
		if out > -0.2 and out < best_d and along < bay.half + 0.25:
			best_d = out
			best = b
	return best


## Dış çizgi: sınır kutusu biçiminde ince beyaz çerçeve. Görünmez maske kutusu şablon tamponuna
## (stencil) yazar; biraz büyük beyaz kutu yalnız maskenin dışında çizilir: rafın boşluklarından
## içerisi beyazlaşmaz, yalnız kenarı belirir.
func _outline_node(bb: AABB, grow: float) -> Node3D:
	var root := Node3D.new()
	root.name = "DisCizgi"
	for k in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bb.size + Vector3.ONE * (grow * 2.0 if k == 1 else 0.0)
		mi.mesh = bm
		mi.position = bb.get_center()
		mi.material_override = _outline_mask if k == 0 else _outline_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## Etkileşilebilir mobilyanın dış çizgisini yak (yalnız biri)
func _light_outline(inst: MeshInstance3D) -> void:
	var hull: Node3D = inst.get_node_or_null("DisCizgi") if inst else null
	if hull == _lit:
		return
	if _lit and is_instance_valid(_lit):
		_lit.visible = false
	_lit = hull
	if _lit:
		_lit.visible = true


## Bölüm kamerası: rafa tam karşıdan, bütün ürünler kadraja girecek açıyla
func _raf_view(b: int) -> Array:
	var bay: Dictionary = _bays[b]
	var n: Vector3 = bay.n
	var c: Vector3 = bay.c
	var lo: float = bay.lo
	var hi: float = bay.hi
	var half: float = bay.half
	var mid := (lo + hi) * 0.5
	var pos: Vector3
	var target: Vector3
	var dist: float
	if hi < 0.85:
		# Alçak kasalar: önden ve yukarıdan
		dist = 1.0
		pos = c + n * 0.8 + Vector3.UP * 1.6
		target = c - n * 0.3 + Vector3.UP * 0.5
	else:
		# Biraz yukarıdan, hafif aşağı bakarak: alt raflar ve yatık ürünler de okunsun
		dist = 1.35 if half > 0.8 else 1.05
		pos = c + n * dist + Vector3.UP * (mid + (hi - lo) * 0.35)
		target = c - n * 0.25 + Vector3.UP * (mid - 0.05)
	var d_eff := dist + 0.25
	var vp := _cam.get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var vf := 2.0 * atan((hi - lo + 0.6) * 0.5 / d_eff)
	var hf := 2.0 * atan(half * 1.22 / d_eff)
	var vf2 := 2.0 * atan(tan(hf * 0.5) / aspect)
	var fov := clampf(rad_to_deg(maxf(vf, vf2)), 30.0, 88.0)
	var gp := to_global(pos)
	var gt := to_global(target)
	return [Transform3D(Basis.looking_at(gt - gp, Vector3.UP), gp), fov]


func _start_raf(b: int) -> void:
	faz = Faz.RAF_GIRIS
	_t = 0.0
	_raf_bay = b
	_sel = -1
	_raf_take = -1
	_set_buttons([])
	_light_outline(null)
	player.input_locked = true
	_raf_from = follow_cam.global_transform
	_raf_fov = follow_cam.fov
	_cam.global_transform = _raf_from
	_cam.fov = _raf_fov
	_cam.make_current()
	_player_visual(false)
	_ui.mouse_filter = Control.MOUSE_FILTER_STOP


func _exit_raf(take: bool) -> void:
	if faz != Faz.RAF:
		return
	if take and _sel >= 0:
		_raf_take = _sel
	_put_back_sel()
	faz = Faz.RAF_CIKIS
	_t = 0.0
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _player_visual(on: bool) -> void:
	var v := player.get_node_or_null("Visual") as Node3D
	if v:
		v.visible = on


## Ürünü seç: raftan hafifçe öne çıkar, büyür, beyaz çizgiyle belirir
func _select(i: int) -> void:
	_put_back_sel()
	_sel = i
	_sel_t = 0.0
	_set_slot_visible(i, false)
	var s: Dictionary = _slots[i]
	_sel_node = Node3D.new()
	_sel_node.name = "Secilen"
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("urun_" + s.type)
	_sel_node.add_child(mi)
	_sel_node.add_child(_outline_node(mi.mesh.get_aabb(), 0.012))
	add_child(_sel_node)
	_place_sel()


func _place_sel() -> void:
	if _sel < 0 or _sel_node == null:
		return
	var s: Dictionary = _slots[_sel]
	var n: Vector3 = _bays[s.bay].n
	var k := smoothstep(0.0, 1.0, minf(_sel_t / 0.18, 1.0))
	var bob := sin(_sel_t * 4.0) * 0.008
	var xf: Transform3D = s.xf
	_sel_node.transform = Transform3D(xf.basis.scaled(Vector3.ONE * (1.0 + 0.25 * k)), xf.origin + n * 0.14 * k + Vector3.UP * (0.03 * k + bob))


## Seçili ürünü rafa geri koy (yanlış seçim)
func _put_back_sel() -> void:
	if _sel >= 0:
		_set_slot_visible(_sel, true)
	_sel = -1
	if _sel_node and is_instance_valid(_sel_node):
		_sel_node.queue_free()
	_sel_node = null


## Ekrandaki dokunuşun altındaki ürün (raf kamerasında; yoksa -1)
func _pick(screen_pos: Vector2) -> int:
	var ui_size := _ui.get_viewport_rect().size
	var vp := _cam.get_viewport().get_visible_rect().size
	var sc := ui_size / vp
	var best := -1
	var bd := ui_size.y * 0.07
	for i in _bays[_raf_bay].slots:
		var s: Dictionary = _slots[i]
		if s.gone:
			continue
		var m := _mesh("urun_" + s.type)
		var h := m.get_aabb().size.y if m else 0.1
		var gp := to_global(s.xf.origin + Vector3.UP * h * 0.5)
		if _cam.is_position_behind(gp):
			continue
		var sp := _cam.unproject_position(gp) * sc - _ui.position
		var d := sp.distance_to(screen_pos)
		if d < bd:
			bd = d
			best = i
	return best


func _on_ui_input(event: InputEvent) -> void:
	if faz != Faz.RAF:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos: Vector2 = event.position
	_ui.accept_event()
	for k in _raf_btn:
		if (_raf_btn[k] as Rect2).grow(6.0).has_point(pos):
			_raf_button(k)
			return
	var i := _pick(pos)
	if i >= 0:
		_select(i)


func _raf_button(k: String) -> void:
	match k:
		"onay":
			if _sel >= 0:
				_exit_raf(true)
		"geri":
			_put_back_sel()
		"kapat":
			_exit_raf(false)


## Klavye (bilgisayarda deneme): Enter / boşluk onay, Backspace geri bırak, Esc / F kapat
func _on_key(event: InputEvent) -> void:
	if faz != Faz.RAF or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_raf_button("onay")
		KEY_BACKSPACE:
			_raf_button("geri")
		KEY_ESCAPE, KEY_F:
			_raf_button("kapat")
		_:
			return
	_ui.get_viewport().set_input_as_handled()


## Elde taşınan ürünün görseli: kök elin altında, ürünün ortası avuçta
func _make_held(type: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Elde_" + type
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("urun_" + type)
	var h := mi.mesh.get_aabb().size.y if mi.mesh else 0.1
	mi.position = Vector3(0, 0.12 - h * 0.5, -0.04)
	root.add_child(mi)
	add_child(root)
	root.top_level = true
	return root


# ---------- Liste ----------

func _new_list() -> void:
	var types := []
	for s in _slots:
		if not types.has(s.type):
			types.append(s.type)
	types.shuffle()
	_wanted.clear()
	for k in mini(LIST_SIZE, types.size()):
		_wanted.append(types[k])
	_list_done = false


func _have(type: String) -> bool:
	return player != null and player.inventory.has(type)


# ---------- Yapı: zürafa ve kameralar ----------

## Kasiyer: dükkânın adındaki hayvan (PENGUEN MARKET -> penguen); yoksa zürafa
const KASIYER := {"ZURAFA": "zurafa", "FIL": "fil", "PENGUEN": "penguen", "GUVERCIN": "guvercin", "KEDI": "kedi",
	"KOPEK": "kopek", "TAVSAN": "tavsan", "SICAN": "sican", "FARE": "sican", "KURBAGA": "kurbaga", "SINEK": "sinek",
	"PAPAGAN": "papagan", "TILKI": "tilki", "ASLAN": "aslan"}


static func cashier_species(shop_name: String) -> String:
	var n := shop_name.to_upper()
	for a in [["İ", "I"], ["Ş", "S"], ["Ğ", "G"], ["Ü", "U"], ["Ö", "O"], ["Ç", "C"], ["ı", "I"]]:
		n = n.replace(a[0], a[1])
	for word in n.split(" ", false):
		for k in KASIYER:
			if word.begins_with(k):
				return KASIYER[k]
	return "zurafa"


func _build_owner() -> void:
	var recipe := NpcCatalog.make_recipe(_rng, cashier_species(ad))
	_owner = Node3D.new()
	_owner.name = "Zurafa"
	_owner.position = Vector3(3.95, 0, -2.2)
	add_child(_owner)
	var model := Npc.build_model(recipe, {})
	_owner.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = INSIDE_VIS
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	_owner_anim = anim
	if anim:
		for n in ["idle_look", "walk", "idle"]:
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		anim.play("idle_look")
	_owner_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	_owner_head = _owner_skel.find_bone("head")
	_owner.rotation.y = _owner_yaw
	_watchers.append({"kind": "zurafa", "fov": deg_to_rad(80.0), "range": 6.5, "color": Color(1.0, 0.85, 0.2, 0.3)})


func _build_cameras() -> void:
	# Tavan köşelerinde kameralar: [konum, baktığı nokta (x, z), tarama genliği, evre]
	var specs := [[Vector3(-4.78, H - 0.02, -0.4), Vector2(2.5, -5.5), 0.45, 0.0],
		[Vector3(-4.78, H - 0.02, -7.6), Vector2(2.0, -2.0), 0.4, 2.2]]
	for sp in specs:
		var p: Vector3 = sp[0]
		var aim: Vector2 = sp[1]
		var mount := _instance("Kamera", Transform3D(Basis(), p))
		var head := _instance("KameraKafa", Transform3D(Basis(), Vector3(0, -0.17, 0)), mount)
		var led := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.03, 0.03, 0.02)
		led.mesh = lm
		var lmat := StandardMaterial3D.new()
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lmat.albedo_color = Color(1, 0.1, 0.1)
		led.material_override = lmat
		led.position = Vector3(0.045, 0.06, 0.2)
		head.add_child(led)
		var dir := Vector2(aim.x - p.x, aim.y - p.z)
		var base_yaw := atan2(-dir.x, -dir.y)
		_watchers.append({"kind": "kamera", "node": head, "pos": p, "base": base_yaw, "sweep": sp[2], "phase": sp[3],
			"fov": deg_to_rad(50.0), "range": 9.5, "color": Color(1.0, 0.25, 0.2, 0.28), "led": led})
	# Görüş alanı meshleri: her biri ayrı yükseklikte ve çizim sırasında (üst üste binen
	# saydam alanlar kare kare yer değiştirip titremesin)
	for i in _watchers.size():
		var w: Dictionary = _watchers[i]
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.position.y = 0.03 + 0.015 * i
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = w.color
		m.render_priority = i + 1
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.no_depth_test = true
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.albedo_color = Color(w.color.r, w.color.g, w.color.b, 0.9)
		lm.render_priority = i + 10
		lm.no_depth_test = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		w["mesh"] = mi
		w["mat"] = m
		w["line_mat"] = lm
		w["dists"] = PackedFloat32Array()


# ---------- Her kare ----------

func _physics_process(delta: float) -> void:
	if not player:
		return
	if not ic:
		_outside_step(delta)
		return
	if _owner_mode == 0:
		_update_owner(delta)
	elif _owner_mode == 2:
		_owner_walk_back(delta)
	_update_watchers()
	var lp := to_local(player.global_position)
	if lp.y < -4.0 and faz == Faz.NORMAL:
		# Güvenlik ağı: bir şekilde zeminin altına düşüldüyse kapının içine geri koy
		player.global_position = to_global(Vector3(0, 0.05, -1.3))
		player.velocity = Vector3.ZERO
		player.speed = 0.0
		player.reset_physics_interpolation()
		return
	var inside := absf(lp.x) < W * 0.5 - 0.2 and lp.z < -0.3 and lp.z > -D + 0.2 and absf(lp.y) < 2.0

	match faz:
		Faz.NORMAL:
			_door_step(delta, 1.0 if lp.z > -2.6 else 0.0)
			if _exit_step(lp):
				return
			var list := []
			var free := player.on_foot and player.fall_time <= 0.0 and player.action_time <= 0.0 and not player.bag_open \
				and not player.sitting and _take_t < 0.0 and _put_t < 0.0
			_near_bay = _bay_at(lp) if inside and free else -1
			# Etkileşilebilir raf: ince beyaz çizgi ve etkileşim butonu (ilk buton: F tuşu)
			_light_outline(_bays[_near_bay].inst if _near_bay >= 0 and player.held_item == "" else null)
			if inside and free and player.held_item == "":
				if _near_bay >= 0:
					list.append({"id": "raf", "icon": "al"})
				list.append({"id": "goz", "icon": "goz"})
			elif inside and free and _held_slot >= 0 and _near_bay == _slots[_held_slot].bay:
				list.append({"id": "birak", "icon": "birak"})
			_set_buttons(list)
			_step_take(delta)
			# Liste tamam mı?
			if not _list_done and not _wanted.is_empty():
				var all := true
				for type in _wanted:
					if not _have(type):
						all = false
				if all:
					_list_done = true
					_banner = "LİSTE TAMAM!"
					_banner_t = 2.5
		Faz.RAF_GIRIS:
			_t += delta
			var view := _raf_view(_raf_bay)
			var k := smoothstep(0.0, 1.0, _t / RAF_GECIS)
			_cam.global_transform = _raf_from.interpolate_with(view[0], k)
			_cam.fov = lerpf(_raf_fov, view[1], k)
			if _t >= RAF_GECIS:
				faz = Faz.RAF
		Faz.RAF:
			if _sel >= 0:
				_sel_t += delta
				_place_sel()
		Faz.RAF_CIKIS:
			_t += delta
			var view := _raf_view(_raf_bay)
			var k := smoothstep(0.0, 1.0, _t / RAF_GECIS)
			_cam.global_transform = (view[0] as Transform3D).interpolate_with(follow_cam.global_transform, k)
			_cam.fov = lerpf(view[1], follow_cam.fov, k)
			if _t >= RAF_GECIS:
				follow_cam.make_current()
				_player_visual(true)
				player.input_locked = false
				faz = Faz.NORMAL
				# Onaylanan ürün: el uzanır, 10. karede ele geçer
				if _raf_take >= 0 and not _slots[_raf_take].gone and player.held_item == "":
					_face(to_global(_slots[_raf_take].xf.origin))
					player.play_action("eline_al", AL_SURE)
					_take_t = 0.0
					_take_slot = _raf_take
				_raf_take = -1
		Faz.KESIF_GIRIS:
			_t += delta
			var k := smoothstep(0.0, 1.0, _t / GECIS)
			_cam.global_transform = _from.interpolate_with(_top_transform(), k)
			_cam.fov = lerpf(_from_fov, 52.0, k)
			if _t >= GECIS:
				faz = Faz.KESIF
				_t = 0.0
		Faz.KESIF:
			_t += delta
			_set_buttons([{"id": "hazir", "icon": "tamam"}])
			if _t >= KESIF_SURE:
				_start_exit()
		Faz.KESIF_CIKIS:
			_t += delta
			var k := smoothstep(0.0, 1.0, _t / GECIS)
			_cam.global_transform = _top_transform().interpolate_with(follow_cam.global_transform, k)
			_cam.fov = lerpf(52.0, follow_cam.fov, k)
			_roof.visible = k > 0.55
			for w in _watchers:
				w.mat.albedo_color = Color(w.color.r, w.color.g, w.color.b, w.color.a * (1.0 - k))
			if _t >= GECIS:
				follow_cam.make_current()
				for w in _watchers:
					w.mesh.visible = false
					w.mat.albedo_color = w.color
				player.input_locked = false
				faz = Faz.NORMAL
		Faz.YAKALANDI:
			_caught_step(delta)
	_banner_t = maxf(_banner_t - delta, 0.0)
	GuvenliAlan.fit(_ui)
	_ui.visible = true
	_ui.queue_redraw()


## Alma / geri koyma: el uzanır, 10. karede ürün ele geçer (ya da rafa döner)
func _step_take(delta: float) -> void:
	if _take_t >= 0.0:
		_take_t += delta
		if _take_t >= AL_GRAB:
			_take_t = -1.0
			var i := _take_slot
			_take_slot = -1
			if i >= 0 and not _slots[i].gone and player.held_item == "":
				_set_slot_visible(i, false)
				_held_slot = i
				_held_node = _make_held(_slots[i].type)
				player.hold_item(_slots[i].type, _held_node)
	if _put_t >= 0.0:
		_put_t += delta
		if _put_t >= AL_GRAB:
			_put_t = -1.0
			if _held_slot >= 0:
				_set_slot_visible(_held_slot, true)
				_held_slot = -1
				_free_held()
				player.release_held()


func _free_held() -> void:
	if _held_node and is_instance_valid(_held_node):
		_held_node.queue_free()
	_held_node = null


func _set_buttons(list: Array) -> void:
	if list.is_empty():
		if _owns_buttons:
			player.context_buttons = []
			_owns_buttons = false
	else:
		player.context_buttons = list
		_owns_buttons = true


func _face(p: Vector3) -> void:
	var to := p - player.global_position
	to.y = 0.0
	if to.length() > 0.01:
		player.heading = to.normalized()


func _on_context(id: String) -> void:
	match id:
		"raf":
			if faz != Faz.NORMAL or _take_t >= 0.0 or player.held_item != "" or _near_bay < 0:
				return
			_start_raf(_near_bay)
		"goz":
			if faz != Faz.NORMAL:
				return
			faz = Faz.KESIF_GIRIS
			_t = 0.0
			_set_buttons([])
			player.input_locked = true
			_light_outline(null)
			_from = follow_cam.global_transform
			_from_fov = follow_cam.fov
			_cam.global_transform = _from
			_cam.fov = _from_fov
			_cam.make_current()
			_roof.visible = false
			for w in _watchers:
				w.mesh.visible = true
				w.mat.albedo_color = w.color
		"hazir":
			if faz == Faz.KESIF:
				_start_exit()
		"birak":
			if faz != Faz.NORMAL or _held_slot < 0 or _put_t >= 0.0:
				return
			_face(to_global(_slots[_held_slot].xf.origin))
			player.play_action("eline_al", AL_SURE)
			_put_t = 0.0
			_set_buttons([])


# ---------- Kapı ve giriş / çıkış ----------

## İki kanatlı otomatik cam kapı (kapı boşluğunda; yaklaşınca iki yana kayar)
func _build_doors() -> void:
	var frame_mat := ShaderMaterial.new()
	frame_mat.shader = CHAR_SHADER
	frame_mat.set_shader_parameter("albedo", Color(0.28, 0.3, 0.33))
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(0.72, 0.86, 0.95, 0.35) if not ic else Color(0.86, 0.93, 0.98, 0.9)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	for sx: float in [-1.0, 1.0]:
		var panel := Node3D.new()
		panel.position = Vector3(sx * 0.5, 0, 0.06)
		add_child(panel)
		var g := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.92, 2.14, 0.02)
		g.mesh = gm
		g.material_override = glass
		g.position = Vector3(0, 1.12, 0)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		panel.add_child(g)
		var f := MeshInstance3D.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for bar in [[Vector3(0, 2.22, 0), Vector3(1.0, 0.08, 0.05)], [Vector3(0, 0.04, 0), Vector3(1.0, 0.08, 0.05)],
				[Vector3(-0.48, 1.13, 0), Vector3(0.05, 2.18, 0.05)], [Vector3(0.48, 1.13, 0), Vector3(0.05, 2.18, 0.05)],
				[Vector3(-sx * 0.38, 1.05, 0.03), Vector3(0.03, 0.4, 0.03)]]:
			Sehir._box(st, Transform3D.IDENTITY, bar[0], bar[1], Color.WHITE)
		f.mesh = st.commit()
		f.material_override = frame_mat
		panel.add_child(f)
		_doors.append(panel)


func _door_step(delta: float, target: float) -> void:
	_door_open = move_toward(_door_open, target, delta * 2.6)
	var k := _door_open * _door_open * (3.0 - 2.0 * _door_open)
	for i in _doors.size():
		var sx := -1.0 if i == 0 else 1.0
		_doors[i].position.x = sx * (0.5 + 0.93 * k)


## Giriş / çıkış konisi: yerden yükselen, yukarı doğru silinen saydam ışık (çok belirgin değil)
func _build_marker(pos: Vector3) -> MeshInstance3D:
	if _marker_shader == null:
		_marker_shader = Shader.new()
		_marker_shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.86, 0.35, 0.22);
varying float h;
void vertex() { h = VERTEX.y / 0.9 + 0.5; }
void fragment() {
	float pulse = 0.8 + 0.2 * sin(TIME * 2.6);
	ALBEDO = col.rgb;
	ALPHA = col.a * pulse * pow(clamp(1.0 - h, 0.0, 1.0), 1.4);
}
"""
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.36
	cm.bottom_radius = 0.5
	cm.height = 0.9
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = _marker_shader
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.45, 0)
	mi.visibility_range_end = 40.0
	add_child(mi)
	return mi


## Dış yüz: yaklaşınca kapı açılır; koniye gelince iç mekâna geçilir
func _outside_step(delta: float) -> void:
	var lp := to_local(player.global_position)
	var near := lp.z > -0.5 and lp.z < 4.5 and absf(lp.x) < 3.5 and absf(lp.y) < 2.0
	if near or _door_open > 0.0:
		_door_step(delta, 1.0 if near else 0.0)
	var on := absf(lp.x) < 0.7 and lp.z > 0.55 and lp.z < 1.6 and absf(lp.y) < 1.2
	if not on:
		if lp.z > 2.4 or absf(lp.x) > 1.6 or absf(lp.y) > 1.5:
			_armed = true
		return
	if _armed and absf(player.speed) < 4.5 and IcMekan.instance and not IcMekan.instance.busy:
		_armed = false
		IcMekan.instance.enter(self)


## İç mekân: kapının içindeki koniye gelince dışarı çıkılır (elde ürün varken çıkılmaz)
func _exit_step(lp: Vector3) -> bool:
	var on := absf(lp.x) < 0.8 and lp.z > -0.95 and lp.z < 0.4
	if not on:
		_armed = true
		return false
	if not _armed or IcMekan.instance == null or IcMekan.instance.busy:
		return false
	if player.held_item != "" or _held_slot >= 0:
		_banner = "ÖNCE ELİNDEKİNİ BIRAK YA DA ÇANTANA KOY"
		_banner_t = 2.2
		player.global_position = to_global(Vector3(lp.x, lp.y, -1.25))
		player.velocity = Vector3.ZERO
		player.speed = 0.0
		_armed = false
		return false
	_armed = false
	_set_buttons([])
	_light_outline(null)
	IcMekan.instance.exit(false)
	return true


## İç mekân silinmeden önce: butonlar, eldeki ürün, kamera
func leave() -> void:
	_set_buttons([])
	_light_outline(null)
	_free_held()
	if _cam and _cam.current and follow_cam:
		follow_cam.make_current()
	if player:
		player.held_in_air = false


func _start_exit() -> void:
	faz = Faz.KESIF_CIKIS
	_t = 0.0
	_set_buttons([])


## Çantaya atmaya başladı: bu dükkânın ürünüyse ve o an görülüyorsa yakalanacak
func _on_stow_started(_item: String) -> void:
	_stowing_slot = _held_slot
	_stow_seen = _held_slot >= 0 and _player_seen()


func _on_item_stowed(_item: String) -> void:
	if _stowing_slot >= 0:
		_stolen.append(_stowing_slot)
		_stowing_slot = -1
		_held_slot = -1
		_free_held()
	if _stow_seen:
		_stow_seen = false
		_start_caught()


# ---------- Yakalanma sinematiği ----------

func _start_caught() -> void:
	faz = Faz.YAKALANDI
	_ct = 0.0
	_back_t = -1.0
	_released = false
	_set_buttons([])
	player.input_locked = true
	_cine_from = follow_cam.global_transform


func _caught_step(delta: float) -> void:
	_ct += delta
	var out := (to_global(Vector3(0, 0, 1)) - to_global(Vector3.ZERO)).normalized()
	# 0-0,45 kararma, 0,45-1,7 karanlık + yazı, 1,7-2,1 aydınlanma
	if _ct < 0.45:
		_fade = _ct / 0.45
	elif _ct < 1.7:
		_fade = 1.0
	elif _ct < 2.1:
		_fade = 1.0 - (_ct - 1.7) / 0.4
	else:
		_fade = 0.0
	var scr := IcMekan.instance.screen if IcMekan.instance else null
	if scr and not _released:
		scr.caught = _fade > 0.0
		scr.loading = false
		scr.alpha = _fade
		scr.visible = _fade > 0.0
	if _ct >= 0.45 and _ct - delta < 0.45:
		_setup_caught_scene()
	var ot := _ct - 1.75                       # sahibinin animasyon zamanı
	if ot >= 0.0 and ot - delta < 0.0 and _owner_anim:
		_owner_anim.play("disari_at", 0.1)
	if ot >= AT_TUT and not _released:
		# Tişörtünden tutulmuş: kök, iki elin ortasının 0,86 m altında, sahibine dönük
		player.held_in_air = true
		var hands := _owner_hands()
		player.global_position = player.global_position.lerp(hands - Vector3.UP * 0.86 + out * 0.12, 1.0 - exp(-30.0 * delta))
	if ot >= AT_BIRAK and not _released:
		_released = true
		player.held_in_air = false
		if IcMekan.instance:
			IcMekan.instance.exit(true)        # kapıdan dışarı atıldı: sokağa düşer
		else:
			player.knockdown(out * 4.2)
	# Sahibi işini bitirince tezgâha döner; çocuk kalkınca kamera oyuna geri döner
	if _released and ot > 2.1 and _owner_mode == 1:
		_owner_mode = 2
		_owner_path = [Vector3(1.5, 0, -0.6), Vector3(3.95, 0, -0.6), Vector3(3.95, 0, -2.2)]
		if _owner_anim:
			_owner_anim.play("walk", 0.3)
	if _released and player.fall_time <= 0.0 and ot > AT_BIRAK + 0.5:
		if _back_t < 0.0:
			_back_t = 0.0
			_cine_from = _cam.global_transform
		_back_t += delta
		var k := smoothstep(0.0, 1.0, _back_t / GECIS)
		_cam.global_transform = _cine_from.interpolate_with(follow_cam.global_transform, k)
		_cam.fov = lerpf(48.0, follow_cam.fov, k)
		if _back_t >= GECIS:
			follow_cam.make_current()
			player.input_locked = false
			faz = Faz.NORMAL


func _setup_caught_scene() -> void:
	# Dükkândan alınanlar (elde ve çantada) geri alınır, rafları dolar
	var types := []
	for i in _stolen:
		if not types.has(_slots[i].type):
			types.append(_slots[i].type)
	if _held_slot >= 0 and not types.has(_slots[_held_slot].type):
		types.append(_slots[_held_slot].type)
	player.take_back(types)
	for i in _stolen:
		_set_slot_visible(i, true)
	_stolen.clear()
	if _held_slot >= 0:
		_set_slot_visible(_held_slot, true)
		_held_slot = -1
	_free_held()
	_take_t = -1.0
	_put_t = -1.0
	player.bag_open = false
	player.action_time = 0.0
	player.action_name = ""
	# Sahibi kapının içinde dışarı bakar; çocuk önünde, sırtı kapıya
	_owner_mode = 1
	_owner_yaw = PI
	_owner.rotation.y = PI
	_owner.position = Vector3(0, 0, -1.05)
	if _owner_anim:
		_owner_anim.play("idle", 0.0)
	player.global_position = to_global(Vector3(0, 0.02, -0.5))
	player.heading = (to_global(Vector3(0, 0, -1)) - to_global(Vector3.ZERO)).normalized()
	player.velocity = Vector3.ZERO
	player.speed = 0.0
	player.reset_physics_interpolation()
	# Kamera içeride, kapıya bakar (dış dünya iç mekândayken yok)
	var cam_pos := to_global(Vector3(-1.9, 1.75, -4.6))
	var look := to_global(Vector3(0, 1.15, -0.6))
	_cam.global_transform = Transform3D(Basis.looking_at(look - cam_pos, Vector3.UP), cam_pos)
	_cam.fov = 48.0
	_cam.make_current()
	_roof.visible = true
	for w in _watchers:
		w.mesh.visible = false


## Kuş bakışı: dükkanın ortasının üstünde, kapı ekranın altında
func _top_transform() -> Transform3D:
	var center := to_global(Vector3(0, 0, -D * 0.5))
	var into := (to_global(Vector3(0, 0, -1)) - to_global(Vector3.ZERO)).normalized()
	var pos := center + Vector3.UP * 12.5 - into * 0.8
	return Transform3D(Basis.looking_at(center - pos, into), pos)


func _owner_hands() -> Vector3:
	var l := _owner_skel.find_bone("hand.L")
	var r := _owner_skel.find_bone("hand.R")
	if l < 0 or r < 0:
		return _owner.global_position + Vector3.UP * 1.2
	var gl := _owner_skel.global_transform * _owner_skel.get_bone_global_pose(l).origin
	var gr := _owner_skel.global_transform * _owner_skel.get_bone_global_pose(r).origin
	return (gl + gr) * 0.5


## Sinematikten sonra tezgâhın arkasına yürür
func _owner_walk_back(delta: float) -> void:
	if _owner_path.is_empty():
		_owner_mode = 0
		_owner_yaw = PI * 0.5
		_owner_target = PI * 0.5
		if _owner_anim:
			_owner_anim.play("idle_look", 0.4)
		return
	var target: Vector3 = _owner_path[0]
	var to := target - _owner.position
	to.y = 0.0
	if to.length() < 0.15:
		_owner_path.pop_front()
		return
	var yaw := atan2(-to.x, -to.z)
	_owner_yaw = rotate_toward(_owner_yaw, yaw, deg_to_rad(240.0) * delta)
	_owner.rotation.y = _owner_yaw
	_owner.position += to.normalized() * minf(1.4 * delta, to.length())


# ---------- Görüş alanları ----------

## Zürafa: belli aralıklarla başka bir yöne döner (kapı, raflar, dolaplar); bakarken bekler
func _update_owner(delta: float) -> void:
	_owner_hold -= delta
	if _owner_hold <= 0.0:
		_owner_hold = _rng.randf_range(1.8, 3.6)
		_owner_target = PI * 0.5 + _rng.randf_range(-0.75, 1.0)
	_owner_yaw = rotate_toward(_owner_yaw, _owner_target, deg_to_rad(55.0) * delta)
	_owner.rotation.y = _owner_yaw


func _update_watchers() -> void:
	var space := get_world_3d().direct_space_state
	var t := Time.get_ticks_msec() * 0.001
	var excl: Array[RID] = []
	if player:
		excl.append(player.get_rid())
	for w in _watchers:
		var origin: Vector3
		var yaw: float
		if w.kind == "zurafa":
			# Başın sallanması koniyi titretmesin: gövdenin biraz önünden, sabit noktadan
			yaw = _owner_yaw
			origin = _owner.position + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.35
			origin.y = CONE_H
		else:
			var head: Node3D = w.node
			yaw = w.base + w.sweep * sin(t * 0.55 + w.phase)
			head.rotation = Vector3(0.45, yaw + PI, 0.0)    # kafa modeli +Z'ye bakar
			var p: Vector3 = w.pos
			origin = Vector3(p.x, CONE_H, p.z)
			w.led.visible = fmod(t, 1.0) < 0.5
		w["origin"] = origin
		w["yaw"] = yaw
		var prev: PackedFloat32Array = w.dists
		var dists := PackedFloat32Array()
		dists.resize(RAY_N)
		var fov: float = w.fov
		var rng: float = w.range
		for i in RAY_N:
			var a := yaw - fov * 0.5 + fov * i / (RAY_N - 1)
			var dir := Vector3(-sin(a), 0.0, -cos(a))
			var from := to_global(origin)
			var to := to_global(origin + dir * rng)
			var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, excl)
			var hit := space.intersect_ray(q)
			var d := from.distance_to(hit.position) if not hit.is_empty() else rng
			# Kenarlar kare kare zıplamasın: uzaması yumuşak, kısalması (engel) hemen
			dists[i] = d if prev.size() != RAY_N or d < prev[i] else lerpf(prev[i], d, 0.35)
		w["dists"] = dists
		var mi: MeshInstance3D = w.mesh
		if mi.visible:
			var im: ImmediateMesh = mi.mesh
			im.clear_surfaces()
			var c := Vector3(origin.x, 0.0, origin.z)
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, w.mat)
			for i in RAY_N - 1:
				var a0 := yaw - fov * 0.5 + fov * i / (RAY_N - 1)
				var a1 := yaw - fov * 0.5 + fov * (i + 1) / (RAY_N - 1)
				im.surface_add_vertex(c)
				im.surface_add_vertex(c + Vector3(-sin(a0), 0, -cos(a0)) * dists[i])
				im.surface_add_vertex(c + Vector3(-sin(a1), 0, -cos(a1)) * dists[i + 1])
			im.surface_end()
			# Kenar çizgisi: alanın sınırı net okunsun
			im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, w.line_mat)
			im.surface_add_vertex(c)
			for i in RAY_N:
				var a := yaw - fov * 0.5 + fov * i / (RAY_N - 1)
				im.surface_add_vertex(c + Vector3(-sin(a), 0, -cos(a)) * dists[i])
			im.surface_add_vertex(c)
			im.surface_end()


## Oyuncu bir görüş alanının içinde mi?
func _player_seen() -> bool:
	var lp := to_local(player.global_position)
	for w in _watchers:
		if not w.has("origin"):
			continue
		var o: Vector3 = w.origin
		var rel := Vector2(lp.x - o.x, lp.z - o.z)
		var dist := rel.length()
		if dist > w.range or dist < 0.3:
			continue
		var a := atan2(-rel.x, -rel.y)
		var da := wrapf(a - float(w.yaw), -PI, PI)
		var fov: float = w.fov
		if absf(da) > fov * 0.5:
			continue
		var fi := (da + fov * 0.5) / fov * (RAY_N - 1)
		var dists: PackedFloat32Array = w.dists
		var dd := lerpf(dists[int(floor(fi))], dists[mini(int(floor(fi)) + 1, RAY_N - 1)], fi - floor(fi))
		if dist < dd:
			return true
	return false


# ---------- Ekran yazıları (piksel) ----------

func _draw_ui() -> void:
	var size := _ui.size
	var px := maxf(floorf(size.y / 120.0), 2.0)
	var shadow := Color(0.05, 0.04, 0.08, 0.8)
	if faz == Faz.KESIF or faz == Faz.KESIF_GIRIS:
		var title := "KÖR NOKTALARI EZBERLE"
		var s := px
		PixelArt.draw_text(_ui, title, Vector2(size.x * 0.5 - PixelArt.text_width(title, s) * 0.5, px * 6.0), s, Color(1, 1, 1, 0.9), shadow)
		if faz == Faz.KESIF:
			var left := str(ceili(KESIF_SURE - _t))
			var bs := px * 2.0
			PixelArt.draw_text(_ui, left, Vector2(size.x * 0.5 - PixelArt.text_width(left, bs) * 0.5, px * 16.0), bs, Color(1.0, 0.85, 0.3), shadow)
		# Lejant
		var ls := maxf(floorf(px * 0.6), 1.0)
		var y := size.y - px * 14.0
		_ui.draw_rect(Rect2(px * 4.0, y, px * 3.0, px * 3.0), Color(1.0, 0.85, 0.2))
		PixelArt.draw_text(_ui, "KASİYER", Vector2(px * 8.5, y), ls, Color(1, 1, 1, 0.85), shadow)
		_ui.draw_rect(Rect2(px * 4.0, y + px * 5.0, px * 3.0, px * 3.0), Color(1.0, 0.3, 0.25))
		PixelArt.draw_text(_ui, "KAMERA", Vector2(px * 8.5, y + px * 5.0), ls, Color(1, 1, 1, 0.85), shadow)
	elif (faz == Faz.NORMAL or faz == Faz.RAF or faz == Faz.RAF_GIRIS) and not _wanted.is_empty():
		_draw_list(size, px, shadow)
	_raf_btn.clear()
	if faz == Faz.RAF:
		_draw_raf_ui(size, px, shadow)
	if _banner_t > 0.0 and _banner != "":
		var a := clampf(_banner_t / 0.5, 0.0, 1.0)
		var s := px
		while s > 1.0 and PixelArt.text_width(_banner, s) > size.x * 0.9:
			s -= 1.0
		PixelArt.draw_text(_ui, _banner, Vector2(size.x * 0.5 - PixelArt.text_width(_banner, s) * 0.5, size.y * 0.2), s,
			Color(1.0, 0.9, 0.4, 0.85 * a), Color(0.08, 0.04, 0.12, 0.6 * a))
	# Yakalanma kararması ve yazısı tam ekran yükleme ekranında (scripts/soygun/yukleme_ekrani.gd)


## Raf kamerası: başlık, seçilen ürünün adı, "geri bırak" / "onay" ve kapat butonları
func _draw_raf_ui(size: Vector2, px: float, shadow: Color) -> void:
	var title := "ALMAK İSTEDİĞİN ÜRÜNE DOKUN" if _sel < 0 else Urunler.name_of(_slots[_sel].type).to_upper()
	var tc := Color(1, 1, 1, 0.9) if _sel < 0 else Urunler.color(_slots[_sel].type)
	PixelArt.draw_text(_ui, title, Vector2(size.x * 0.5 - PixelArt.text_width(title, px) * 0.5, px * 6.0), px, tc, shadow)
	var bd := floorf(size.y * 0.15)
	var y := size.y - bd - px * 12.0
	var gap := px * 8.0
	var on := _sel >= 0
	_raf_btn["onay"] = Rect2(size.x - bd - px * 8.0, y, bd, bd)
	_raf_btn["geri"] = Rect2(size.x - bd * 2.0 - gap - px * 8.0, y, bd, bd)
	var dim := Color(1, 1, 1, 0.3)
	PixelArt.draw_round_button(_ui, _raf_btn["geri"], "birak", false, Color(1.0, 0.82, 0.25), Color(1, 1, 1, 0.95) if on else dim)
	PixelArt.draw_round_button(_ui, _raf_btn["onay"], "tamam", false, Color(1.0, 0.82, 0.25), Color(0.45, 1.0, 0.5) if on else dim)
	var ls := maxf(floorf(px * 0.6), 1.0)
	for k in ["geri", "onay"]:
		var r: Rect2 = _raf_btn[k]
		var t := "GERİ BIRAK" if k == "geri" else "ONAY"
		PixelArt.draw_text(_ui, t, Vector2(r.get_center().x - PixelArt.text_width(t, ls) * 0.5, r.end.y + px * 2.0), ls,
			Color(1, 1, 1, 0.85 if on else 0.35), shadow)
	var cs := floorf(size.y * 0.11)
	_raf_btn["kapat"] = Rect2(size.x - cs - px * 6.0, px * 6.0, cs, cs)
	PixelArt.draw_button(_ui, _raf_btn["kapat"], "kapat", false)


## Aranan ürünler listesi (sol üst, butonların altında): ikon, ad, çantadaysa tik
func _draw_list(size: Vector2, px: float, shadow: Color) -> void:
	var s := maxf(floorf(px * 0.75), 1.0)
	var row := px * 9.0
	var w := px * 50.0
	var pos := Vector2(px * 4.0, size.y * 0.2)
	var box := Rect2(pos, Vector2(w, px * 9.0 + row * _wanted.size()))
	PixelArt._stepped_rect(_ui, box, px, Color(1, 1, 1, 0.55))
	PixelArt._stepped_rect(_ui, box.grow(-px * 0.5), px, Color(0.08, 0.07, 0.12, 0.72))
	PixelArt.draw_text(_ui, "LİSTE", pos + Vector2(px * 3.0, px * 2.5), s, Color(1.0, 0.86, 0.3), shadow)
	for k in _wanted.size():
		var type := _wanted[k]
		var y := pos.y + px * 9.0 + row * k
		var have := _have(type)
		var c := Urunler.color(type)
		PixelArt.draw_icon(_ui, type, Vector2(pos.x + px * 7.0, y + row * 0.4), px * 7.0, c if not have else Color(c.r, c.g, c.b, 0.45))
		var name := Urunler.name_of(type)
		PixelArt.draw_text(_ui, name, Vector2(pos.x + px * 13.0, y + row * 0.4 - px * 2.5), s, Color(1, 1, 1, 0.9 if not have else 0.45), shadow)
		if have:
			PixelArt.draw_icon(_ui, "tamam", Vector2(pos.x + w - px * 6.0, y + row * 0.4), px * 6.0, Color(0.4, 1.0, 0.45))
