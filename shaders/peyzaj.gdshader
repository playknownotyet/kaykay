shader_type spatial;
render_mode specular_disabled;

// Peyzaj (ağaç, çalı, ot, kaya): köşe renkli toon malzeme, rüzgârda hafif salınım (scripts/sehir/peyzaj.gd).
// Köşe rengi (tools/blender/peyzaj_build.py): RGB renk; A 0..0.5 gövde (rüzgâr payı a*2),
// 0.5..1 yaprak (rüzgâr payı (a-0.5)*2). MultiMesh örnek verisi (INSTANCE_CUSTOM): rgb yaprak renk
// çarpanı (her ağaç biraz farklı), a = 1 (örnek verisi var).

#include "res://shaders/common.gdshaderinc"

uniform float wind_strength = 0.07;
uniform float wind_speed = 1.2;

varying vec3 tint;

void vertex() {
	float a = COLOR.a;
	float leaf = step(0.5, a);
	float sway = leaf > 0.5 ? (a - 0.5) * 2.0 : a * 2.0;
	// Örnek kökü (dünya): her ağaç başka evrede sallanır
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = o.x * 0.13 + o.z * 0.17;
	float t = TIME * wind_speed + ph;
	vec3 off = vec3(sin(t) + 0.35 * sin(t * 2.3 + 1.7), 0.0, cos(t * 0.8) * 0.55) * wind_strength * sway;
	// Yaprak titremesi (küçük, hızlı)
	off += vec3(sin(TIME * 4.1 + VERTEX.y * 3.0 + ph * 5.0), 0.0, cos(TIME * 3.7 + VERTEX.x * 3.0)) * 0.012 * sway * leaf;
	VERTEX += off;
	tint = INSTANCE_CUSTOM.a > 0.5 ? mix(vec3(1.0), INSTANCE_CUSTOM.rgb, leaf) : vec3(1.0);
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.9;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
