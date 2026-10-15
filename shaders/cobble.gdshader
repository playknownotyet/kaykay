shader_type spatial;
render_mode specular_disabled;

// Arnavut kaldırımı: dünya koordinatında şaşırtmalı sıralı taşlar, aralarında derz.
// Her taşın tonu biraz farklı; taşların üstü hafif kubbeli görünür.
// Görünüm ayarları (toon ışık, poligon titremesi) common.gdshaderinc'den gelir.

#include "res://shaders/common.gdshaderinc"

uniform vec3 stone_a : source_color = vec3(0.66, 0.63, 0.6);
uniform vec3 stone_b : source_color = vec3(0.52, 0.5, 0.5);
uniform vec3 grout : source_color = vec3(0.32, 0.3, 0.31);
uniform vec2 stone_size = vec2(0.16, 0.12);
uniform float grout_width = 0.012;

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	vec2 p = world_pos.xz / stone_size;
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5 + hash2(vec2(row, 3.0)) * 0.3;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = hash2(cell);
	// Taş kenarına uzaklık (metre)
	vec2 d = min(f, 1.0 - f) * stone_size;
	float e = min(d.x, d.y);
	float aa = fwidth(e);
	float stone = smoothstep(grout_width * 0.5 - aa, grout_width * 1.6 + aa, e);
	vec3 c = mix(stone_a, stone_b, h);
	// Kubbe: ortası açık, kenarı koyu
	float dome = 1.0 - length(f - 0.5) * 0.5;
	c *= 0.82 + 0.25 * dome;
	vec3 near_col = mix(grout, c, stone);
	// Uzakta derzler pikselden ince kalır ve koyu bantlar (moiré) oluşturur:
	// mesafe arttıkça ortalama taş rengine geç.
	vec3 avg = mix(grout, (stone_a + stone_b) * 0.47, 0.82);
	float far_k = clamp(aa / grout_width - 0.4, 0.0, 1.0);
	ALBEDO = mix(near_col, avg, far_k);
	ROUGHNESS = 0.9;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
