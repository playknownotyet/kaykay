extends Node
## Görünüm (look) ön ayarları: ışık, gökyüzü, sis, renk paleti, malzeme
## gölgelendirmesi ve ekran filtresi tek bir pakette değişir.
## Amaç oyunun kendine has dokusunu bulmak için hızlıca alternatifler denemek.
## Ön ayarlar aşağıdaki PRESETS listesinde; beğenilen bir yön seçilince
## onu birlikte ince ayarlayacağız.

signal changed(name: String)
signal pixel_size_changed(value: float)

const BASE := {
	"sky_top": Color(0.3, 0.58, 1.0),
	"sky_horizon": Color(0.72, 0.87, 1.0),
	"ground_bottom": Color(0.35, 0.55, 0.4),
	"ambient_energy": 1.0,
	## Saydam (a = 0) ise ortam ışığı gökyüzünden gelir; değilse bu renk kullanılır.
	"ambient_color": Color(0, 0, 0, 0),
	"sun_pitch": -52.0,
	"sun_yaw": -35.0,
	"sun_color": Color(1.0, 0.95, 0.85),
	"sun_energy": 1.15,
	"shadow_opacity": 1.0,
	"fog_color": Color(0.75, 0.87, 1.0),
	"fog_density": 0.004,
	"exposure": 1.0,
	"brightness": 1.0,
	"contrast": 1.0,
	"saturation": 1.2,
	"glow": false,
	"glow_intensity": 0.8,
	"glow_bloom": 0.0,
	# Malzemeler
	"line_strength": 1.0,
	"toon_bands": 0.0,
	"toon_softness": 0.04,
	"noise_strength": 0.0,
	"vertex_snap": 0.0,
	# Ekran filtresi (post.gdshader uniform adları)
	"post": {
		"pixel_size": 1.0,
		"posterize": 0.0,
		"dither": 0.0,
		"shadow_tint": Color(0.5, 0.5, 0.5),
		"highlight_tint": Color(0.5, 0.5, 0.5),
		"split_amount": 0.0,
		"gradient": [Color.BLACK, Color.WHITE],
		"gradient_amount": 0.0,
		"gradient_range": Vector2(0.0, 1.0),
		"grain": 0.0,
		"paper": 0.0,
		"outline": 0.0,
		"outline_color": Color(0.12, 0.1, 0.18),
		"static_vignette": 0.0,
	},
}

# Retro 32-bit temeli: düşük çözünürlük (piksel), 24 kademe renk + dither,
# piksel ızgarasına oturan titrek poligonlar (vertex snap) ve renkli uzak sis.
const RETRO_POST := {"pixel_size": 3.0, "posterize": 24.0, "dither": 0.6}

# Şeker paleti: koyu çivit -> mor -> mercan -> şeftali -> krem.
# Gölgeler hiçbir zaman siyaha düşmez, morumsu kalır: tatlı ama karakterli.
const CANDY := [Color(0.18, 0.12, 0.38), Color(0.45, 0.25, 0.65), Color(1.0, 0.45, 0.55),
	Color(1.0, 0.75, 0.55), Color(1.0, 0.96, 0.85)]

const PRESETS := [
	# Seçilen yön (2026-10-14): düz retro. Kontrast vb. oyuncu panelden ayarlıyor.
	{
		"name": "Retro Düz",
		"fog_color": Color(0.7, 0.8, 1.0), "fog_density": 0.014,
		"shadow_opacity": 0.55,
		# Oyuncunun panelden ayarladığı değerler (2026-10-14)
		"contrast": 0.95, "saturation": 1.53, "exposure": 1.01,
		"line_strength": 0.5, "vertex_snap": 2.5,
		"post": {"pixel_size": 3.5, "posterize": 25.0, "dither": 1.0},
		"retro": true,
	},
	{
		"name": "Retro Altın Saat",
		"sky_top": Color(0.28, 0.3, 0.68), "sky_horizon": Color(1.0, 0.62, 0.45),
		"ground_bottom": Color(0.45, 0.3, 0.35),
		"ambient_energy": 0.75, "ambient_color": Color(0.62, 0.45, 0.65),
		"sun_pitch": -14.0, "sun_yaw": -70.0, "sun_color": Color(1.0, 0.64, 0.36), "sun_energy": 1.75,
		"shadow_opacity": 0.8,
		"fog_color": Color(1.0, 0.7, 0.55), "fog_density": 0.012,
		"contrast": 1.08, "saturation": 1.3,
		"glow": true, "glow_intensity": 0.9, "glow_bloom": 0.12,
		"line_strength": 0.35, "noise_strength": 0.08, "vertex_snap": 3.0,
		"post": {
			"shadow_tint": Color(0.48, 0.4, 0.62), "highlight_tint": Color(0.64, 0.5, 0.38),
			"split_amount": 0.7, "static_vignette": 0.3,
		},
		"retro": true,
	},
	{
		"name": "Retro Şeker",
		"sky_top": Color(0.25, 0.55, 1.0), "sky_horizon": Color(0.75, 0.9, 1.0),
		"sun_pitch": -45.0, "sun_color": Color(1.0, 0.93, 0.85), "sun_energy": 1.4,
		"ambient_energy": 0.65, "ambient_color": Color(0.6, 0.55, 0.85),
		"fog_color": Color(0.78, 0.86, 1.0), "fog_density": 0.01,
		"contrast": 1.15, "saturation": 1.5,
		"line_strength": 0.35, "noise_strength": 0.06, "vertex_snap": 3.0,
		"post": {
			"gradient": CANDY, "gradient_amount": 0.55, "gradient_range": Vector2(0.0, 1.1),
			"shadow_tint": Color(0.45, 0.4, 0.62), "highlight_tint": Color(0.58, 0.52, 0.45),
			"split_amount": 0.5, "static_vignette": 0.15,
		},
		"retro": true,
	},
	{
		"name": "Retro Altın Şeker",
		"sky_top": Color(0.28, 0.3, 0.68), "sky_horizon": Color(1.0, 0.62, 0.45),
		"ground_bottom": Color(0.45, 0.3, 0.35),
		"ambient_energy": 0.75,
		"sun_pitch": -16.0, "sun_yaw": -70.0, "sun_color": Color(1.0, 0.66, 0.4), "sun_energy": 1.7,
		"shadow_opacity": 0.8,
		"fog_color": Color(1.0, 0.68, 0.6), "fog_density": 0.012,
		"contrast": 1.1, "saturation": 1.3,
		"glow": true, "glow_intensity": 0.8, "glow_bloom": 0.1,
		"line_strength": 0.35, "noise_strength": 0.08, "vertex_snap": 3.0,
		"post": {
			"gradient": CANDY, "gradient_amount": 0.3, "gradient_range": Vector2(0.1, 0.95),
			"shadow_tint": Color(0.42, 0.42, 0.66), "highlight_tint": Color(0.64, 0.5, 0.38),
			"split_amount": 0.5, "static_vignette": 0.28,
		},
		"retro": true,
	},
	{
		"name": "Retro Kartpostal",
		"sky_top": Color(0.45, 0.6, 0.8), "sky_horizon": Color(0.92, 0.86, 0.78),
		"sun_pitch": -35.0, "sun_yaw": -50.0, "sun_color": Color(1.0, 0.88, 0.72), "sun_energy": 1.2,
		"fog_color": Color(0.92, 0.86, 0.78), "fog_density": 0.012,
		"brightness": 1.03, "contrast": 0.9, "saturation": 0.85,
		"line_strength": 0.35, "noise_strength": 0.1, "vertex_snap": 3.0,
		"post": {
			"gradient": [Color(0.25, 0.22, 0.3), Color(0.45, 0.42, 0.45), Color(0.8, 0.66, 0.55),
				Color(0.98, 0.93, 0.82)],
			"gradient_amount": 0.3, "gradient_range": Vector2(0.05, 1.0),
			"shadow_tint": Color(0.4, 0.52, 0.56), "highlight_tint": Color(0.6, 0.52, 0.42),
			"split_amount": 0.6, "grain": 0.05, "static_vignette": 0.3,
			"dither": 0.5,
		},
		"retro": true,
	},
]

var env: Environment
var sun: DirectionalLight3D
var fx: Node
var roots: Array[Node] = []

## Seçili ön ayar; ayar panelinde saklanır.
var preset_index := 0:  # Retro Düz (oyuncunun seçimi)
	set(value):
		preset_index = posmod(value, PRESETS.size())
		if is_inside_tree():
			apply()


# --- Panelden canlı ayarlanan retro değerleri (ön ayarı değiştirince sıfırlanır) ---
## Bir retro pikselin ekranda kaç piksel olacağı. Dünya bu oranda küçük
## bir sanal ekranda çizilip keskin büyütülür (main.gd), ekran efekti de o
## çözünürlükte çalıştığı için shader'a 1 gönderilir.
var pixel_size := 1.0:
	set(v):
		pixel_size = v
		_post_param("pixel_size", 1.0)
		pixel_size_changed.emit(v)
		_apply_vertex_snap()
var posterize := 0.0:
	set(v):
		posterize = v
		_post_param("posterize", v)
var dither := 0.0:
	set(v):
		dither = v
		_post_param("dither", v)
## Ekran pikseli cinsinden; sanal ekran pikseline çevrilerek gönderilir.
var vertex_snap := 0.0:
	set(v):
		vertex_snap = v
		_apply_vertex_snap()


func setup(p_env: Environment, p_sun: DirectionalLight3D, p_fx: Node, p_roots: Array[Node]) -> void:
	env = p_env
	sun = p_sun
	fx = p_fx
	roots = p_roots


func preset_name() -> String:
	return PRESETS[preset_index].name


func next() -> void:
	preset_index += 1


func apply() -> void:
	var p := _merged(PRESETS[preset_index])

	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	sky_mat.sky_top_color = p.sky_top
	sky_mat.sky_horizon_color = p.sky_horizon
	sky_mat.ground_horizon_color = p.sky_horizon
	sky_mat.ground_bottom_color = p.ground_bottom
	env.ambient_light_energy = p.ambient_energy
	if p.ambient_color.a > 0.0:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = p.ambient_color
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_light_color = p.fog_color
	env.fog_density = p.fog_density
	env.tonemap_exposure = p.exposure
	env.adjustment_brightness = p.brightness
	env.adjustment_contrast = p.contrast
	env.adjustment_saturation = p.saturation
	env.glow_enabled = p.glow
	env.glow_intensity = p.glow_intensity
	env.glow_bloom = p.glow_bloom

	sun.rotation_degrees = Vector3(p.sun_pitch, p.sun_yaw, 0.0)
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
	sun.shadow_opacity = p.shadow_opacity

	for root in roots:
		_apply_materials(root, p)

	fx.set_style(p.post)
	pixel_size = p.post.pixel_size
	posterize = p.post.posterize
	dither = p.post.dither
	vertex_snap = p.vertex_snap
	changed.emit(p.name)


func _apply_vertex_snap() -> void:
	var v := vertex_snap / maxf(pixel_size, 1.0)
	for root in roots:
		_set_material_param(root, "vertex_snap", v)


func _post_param(key: String, value: float) -> void:
	if fx:
		fx.mat.set_shader_parameter(key, value)


func _set_material_param(node: Node, key: String, value: float) -> void:
	for m in _shader_materials(node):
		m.set_shader_parameter(key, value)
	for child in node.get_children():
		_set_material_param(child, key, value)


func _apply_materials(node: Node, p: Dictionary) -> void:
	for m in _shader_materials(node):
		for key in ["line_strength", "toon_bands", "toon_softness", "noise_strength"]:
			m.set_shader_parameter(key, p[key])
	for child in node.get_children():
		_apply_materials(child, p)


## Bir meshin oyun shader'ı kullanan malzemeleri (tek malzeme ya da yüzey başına).
func _shader_materials(node: Node) -> Array:
	var out := []
	if node is MeshInstance3D:
		if node.material_override is ShaderMaterial:
			out.append(node.material_override)
		for i in node.get_surface_override_material_count():
			var m: Material = node.get_surface_override_material(i)
			if m is ShaderMaterial:
				out.append(m)
	return out


func _merged(preset: Dictionary) -> Dictionary:
	var out := BASE.duplicate(true)
	if preset.get("retro", false):
		for pk in RETRO_POST:
			out.post[pk] = RETRO_POST[pk]
	for k in preset:
		if k == "retro":
			continue
		if k == "post":
			for pk in preset.post:
				out.post[pk] = preset.post[pk]
		else:
			out[k] = preset[k]
	return out
