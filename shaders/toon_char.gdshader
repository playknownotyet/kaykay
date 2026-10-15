shader_type spatial;
render_mode specular_disabled;

// Düz renkli karakter / obje malzemesi. Görünüm ayarlarını (toon ışık,
// vertex snap) zemin malzemesiyle paylaşır.

#include "res://shaders/common.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);

void vertex() {
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.8;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
