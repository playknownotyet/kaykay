shader_type spatial;
render_mode specular_disabled;

// Köşe rengiyle boyanan toon malzeme: şehirdeki küçük süsler (şemsiye, masa, ampul, tabela çerçevesi)
// tek mesh'te farklı renklerde çizilsin (scripts/sehir/sehir.gd).

#include "res://shaders/common.gdshaderinc"

// Gece (0 gündüz .. 1 gece; Sehir.set_night): parlayan yüzler (ampul, lamba camı, neon) gece güçlenir
global uniform float gece;


void vertex() {
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	// alfa < 1: kendiliğinden parlayan (ampul, neon); gündüz hafif, gece parlak
	EMISSION = COLOR.rgb * (1.0 - COLOR.a) * mix(0.7, 3.0, gece);
	ROUGHNESS = 0.8;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
