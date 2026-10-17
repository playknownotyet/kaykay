shader_type spatial;
render_mode specular_disabled;

// Ada arazisi: renk köşe renklerinden gelir (kum, çim, kaya, şev toprağı; ada_builder.gd).
// Görünüm ayarlarını (toon ışık, vertex snap) diğer malzemelerle paylaşır.

#include "res://shaders/common.gdshaderinc"

uniform float noise_strength = 0.0;

// Şehir döşemesi (scripts/sehir/sehir.gd): arazinin boyanan yerleri Arnavut kaldırımı olur.
// Maske 1 m çözünürlükte, doğrusal süzülür; eşik yumuşak: kenarlar yuvarlak ve düzgün.
uniform sampler2D pave_mask : filter_linear, repeat_disable, hint_default_black;
uniform vec4 pave_rect = vec4(0.0, 0.0, 0.0, 0.0);     // x0, z0, en, boy (en 0: kapalı)
uniform vec3 stone_a : source_color = vec3(0.66, 0.63, 0.6);
uniform vec3 stone_b : source_color = vec3(0.52, 0.5, 0.5);
uniform vec3 grout : source_color = vec3(0.32, 0.3, 0.31);
uniform vec2 stone_size = vec2(0.16, 0.12);
uniform float grout_width = 0.012;

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// shaders/cobble.gdshader ile aynı taş deseni (ara sokaklar ve yükseltilerle aynı görünsün)
vec3 cobble(vec2 xz) {
	vec2 p = xz / stone_size;
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5 + hash2(vec2(row, 3.0)) * 0.3;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = hash2(cell);
	vec2 d = min(f, 1.0 - f) * stone_size;
	float e = min(d.x, d.y);
	float aa = fwidth(e);
	float stone = smoothstep(grout_width * 0.5 - aa, grout_width * 1.6 + aa, e);
	vec3 c = mix(stone_a, stone_b, h);
	float dome = 1.0 - length(f - 0.5) * 0.5;
	c *= 0.82 + 0.25 * dome;
	vec3 near_col = mix(grout, c, stone);
	vec3 avg = mix(grout, (stone_a + stone_b) * 0.47, 0.82);
	float far_k = clamp(aa / grout_width - 0.4, 0.0, 1.0);
	return mix(near_col, avg, far_k);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	vec3 col = COLOR.rgb;
	if (pave_rect.z > 0.0) {
		float m = texture(pave_mask, (world_pos.xz - pave_rect.xy) / pave_rect.zw).r;
		float k = smoothstep(0.42, 0.58, m);
		if (k > 0.0) {
			// Kenarda ince koyu bordür taşı çizgisi
			float rim = smoothstep(0.42, 0.5, m) * (1.0 - smoothstep(0.5, 0.62, m));
			col = mix(col, cobble(world_pos.xz) * (1.0 - 0.3 * rim), k);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
