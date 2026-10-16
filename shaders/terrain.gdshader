shader_type spatial;
render_mode specular_disabled;

// Ada arazisi: renk köşe renklerinden gelir (kum, çim, kaya, şev toprağı; ada_builder.gd).
// Görünüm ayarlarını (toon ışık, vertex snap) diğer malzemelerle paylaşır.

#include "res://shaders/common.gdshaderinc"

uniform float noise_strength = 0.0;

void vertex() {
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
