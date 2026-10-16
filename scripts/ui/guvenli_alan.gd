class_name GuvenliAlan
## Güvenli alan: iPhone X ve sonrasında yatay tutuşta çentik / Dynamic Island (solda ya da sağda)
## ve ana ekran çubuğunun (altta) kapladığı şeritler. Arayüz denetimleri bu şeritlerin içine
## yerleşir (fit): buton, panel ve yazılar karanlık bölgeye denk gelmez.
##
## Masaüstünde güvenli alan yok sayılır (görev çubuğu vb. değil); denemek için test_insets.

## Deneme: (sol, üst, sağ, alt) görüntü birimi; x < 0 ise kapalı (gerçek değer kullanılır)
static var test_insets := Vector4(-1, 0, 0, 0)


## Görüntü (viewport) biriminde kenar boşlukları: (sol, üst, sağ, alt)
static func insets(vp: Viewport) -> Vector4:
	if test_insets.x >= 0.0:
		return test_insets
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return Vector4.ZERO
	var k := vp.get_visible_rect().size / win
	return Vector4(maxf(safe.position.x, 0.0) * k.x, maxf(safe.position.y, 0.0) * k.y,
		maxf(win.x - safe.end.x, 0.0) * k.x, maxf(win.y - safe.end.y, 0.0) * k.y)


## Denetimi güvenli alana oturt (tam ekran çapası, kenar boşlukları kadar içeride).
## Her kare çağrılabilir: değişmediyse bir şey yapmaz (telefon ters çevrilince çentik yer değiştirir).
static func fit(c: Control) -> void:
	var v := insets(c.get_viewport())
	if c.anchor_left != 0.0 or c.anchor_top != 0.0 or c.anchor_right != 1.0 or c.anchor_bottom != 1.0:
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
	if c.offset_left != v.x or c.offset_top != v.y or c.offset_right != -v.z or c.offset_bottom != -v.w:
		c.offset_left = v.x
		c.offset_top = v.y
		c.offset_right = -v.z
		c.offset_bottom = -v.w
