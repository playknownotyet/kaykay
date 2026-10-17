shader_type spatial;
render_mode specular_disabled;

// Köşe rengiyle boyanan toon malzeme: şehirdeki küçük süsler (şemsiye, masa, ampul, tabela çerçevesi)
// tek mesh'te farklı renklerde çizilsin (scripts/sehir/sehir.gd).

#include "res://shaders/common.gdshaderinc"


void vertex() {
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * (1.0 - COLOR.a) * 1.4;    // alfa < 1: kendiliğinden parlayan (ampul, neon)
	ROUGHNESS = 0.8;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
