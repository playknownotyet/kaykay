extends ColorRect
## Ekran efektini (shaders/post.gdshader) sürer.
## Hız kısmı kameranın hız çarpanına göre her kare güncellenir;
## stil kısmını LookManager set_style() ile ayarlar.

const SHADER := preload("res://shaders/post.gdshader")

@export var camera: Node
@export var enabled := true
## Tam hızda bükülme. + değer: dıştan içe (kenarlar gerilir), - değer: balıkgözü.
@export var warp := 0.6
## Tam hızda kenar bulanıklığı uzunluğu.
@export var blur := 0.09
@export var aberration := 0.008
@export var vignette := 0.2
## Efektin başladığı hız oranı (0..1). Altında efekt yok.
@export var start := 0.17

var mat := ShaderMaterial.new()
var _style_active := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat.shader = SHADER
	material = mat


## Stil parametrelerini uygular (anahtarlar shader uniform adlarıdır).
func set_style(style: Dictionary) -> void:
	_style_active = false
	for key in style:
		var value = style[key]
		if key == "gradient":
			mat.set_shader_parameter("gradient_map", _gradient_texture(value))
			continue
		mat.set_shader_parameter(key, value)
		if value is float and key != "pixel_size" and value > 0.0:
			_style_active = true
		elif key == "pixel_size" and value > 1.0:
			_style_active = true


func _process(_delta: float) -> void:
	var s: float = camera.speed01 if camera else 0.0
	var amount := smoothstep(start, 1.0, s) if enabled else 0.0
	visible = amount > 0.002 or _style_active
	mat.set_shader_parameter("amount", amount)
	mat.set_shader_parameter("warp", warp)
	mat.set_shader_parameter("blur", blur)
	mat.set_shader_parameter("aberration", aberration)
	mat.set_shader_parameter("vignette", vignette)


static func _gradient_texture(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / float(max(colors.size() - 1, 1)))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	return tex
