shader_type spatial;
render_mode specular_disabled, cull_disabled;

// Köşe rengiyle boyalı, rüzgârla hafifçe sallanan model (balkon çamaşırları; scripts/sehir/cephe_esyalari.gd).
// İp yüksekliğinin (IP_Y) altındaki her şey aşağı indikçe daha çok sallanır; ip ve dikmeler sabit.

#include "res://shaders/common.gdshaderinc"

global uniform float gece;
const float IP_Y = 1.48;

void vertex() {
	float alt = clamp((IP_Y - VERTEX.y) / 0.9, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 2.3 + wp.x * 0.7 + wp.z * 0.5;
	VERTEX.z += sin(t) * 0.05 * alt + sin(t * 2.1 + 1.3) * 0.015 * alt;
	VERTEX.x += sin(t * 0.8 + 0.4) * 0.02 * alt;
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * (1.0 - COLOR.a) * mix(0.7, 3.0, gece);
	ROUGHNESS = 0.8;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
