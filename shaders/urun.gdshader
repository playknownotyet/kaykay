shader_type spatial;
render_mode specular_disabled;

// Market ürünlerinin etiketli yüzleri: piksel-art etiket atlası (assets/dukkan/urun_etiket.png,
// tools/blender/urun_etiket.py), UV tools/blender/dukkan_build.py'den. Işık cephelerle aynı (toon).

#include "res://shaders/common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;

void vertex() {
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	ALBEDO = texture(atlas, UV).rgb;
	ROUGHNESS = 0.8;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
