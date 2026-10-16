shader_type spatial;
render_mode specular_disabled, cull_back;

// Tabela levhaları ve reklam panoları: tek doku (assets/ada/tabelalar.png), saydam köşeler kesilir.

#include "res://shaders/common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;

void vertex() {
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	vec4 t = texture(atlas, UV);
	if (t.a < 0.5) {
		discard;
	}
	ALBEDO = t.rgb;
	ROUGHNESS = 0.85;
}

void light() {
	DIFFUSE_LIGHT += max(toon_diffuse(NORMAL, LIGHT, ATTENUATION), 0.45) * LIGHT_COLOR / PI;
}
