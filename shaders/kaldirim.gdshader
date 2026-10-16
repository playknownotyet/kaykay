shader_type spatial;
render_mode specular_disabled;

// Kaldırım: gerçek sokak kaldırımı gibi beton plaklar (yaklaşık 50 x 40 cm), kaldırım boyunca
// dizili. Her plağın tonu biraz farklı; aralarında derz, kenarları hafif aşınmış; yüzeyde ince
// beton dokusu, yer yer leke ve nadiren çatlak. UV: x kaldırım boyunca, y bordürden dışa (metre).
// Kaldırım adalarında (köşe yelpazeleri) COLOR.a = 0: dünya koordinatı kullanılır.

#include "res://shaders/common.gdshaderinc"

uniform vec3 slab_a : source_color = vec3(0.63, 0.61, 0.58);
uniform vec3 slab_b : source_color = vec3(0.5, 0.49, 0.47);
uniform vec3 grout : source_color = vec3(0.32, 0.31, 0.3);
uniform vec2 slab_size = vec2(0.5, 0.4);
uniform float grout_width = 0.016;

varying vec3 world_pos;
varying vec2 uv_m;
varying float use_uv;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i), b = hash2(i + vec2(1.0, 0.0)), c = hash2(i + vec2(0.0, 1.0)), d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	uv_m = UV;
	use_uv = COLOR.a;
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	vec2 q = use_uv > 0.5 ? uv_m : world_pos.xz;
	vec2 p = q / slab_size;
	// Sıralar yarım plak kaydırmalı (gerçek döşeme gibi)
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = hash2(cell);
	float h2 = hash2(cell + 17.3);
	vec2 dm = min(f, 1.0 - f) * slab_size;
	float e = min(dm.x, dm.y);
	float aa = fwidth(e) + 1e-4;
	float slab = smoothstep(grout_width * 0.5 - aa, grout_width * 1.5 + aa, e);
	// Plak tonu ve hafif renk kayması; yer yer biraz daha yeni / eski plak
	vec3 c = mix(slab_a, slab_b, h);
	c *= 0.9 + 0.2 * h2;
	if (h2 > 0.93) {
		c *= vec3(0.93, 0.95, 1.0);
	}
	// Aşınmış kenarlar: derze yakın biraz koyu
	c *= mix(0.82, 1.0, smoothstep(0.0, 0.06, e));
	// Beton dokusu (ince) ve büyük lekeler (çok hafif)
	float grain = vnoise(q * 22.0) * 0.5 + vnoise(q * 57.0) * 0.5;
	c *= 0.88 + 0.2 * grain;
	float stain = smoothstep(0.62, 0.9, vnoise(world_pos.xz * 0.35 + 3.1));
	c *= 1.0 - 0.18 * stain;
	// Nadir çatlak: bazı plaklarda çapraz ince çizgi
	if (h > 0.9) {
		float crack = abs(f.y - (0.25 + 0.5 * h2) - (f.x - 0.5) * (h2 - 0.5) * 1.4 - 0.04 * sin(f.x * 23.0));
		c = mix(c, grout, (1.0 - smoothstep(0.0, 0.012 + fwidth(f.y), crack)) * 0.7);
	}
	vec3 near_col = mix(grout, c, slab);
	// Uzakta derz ve doku pikselden ince: ortalama tona geç (titreşmesin)
	vec3 avg = mix(grout, (slab_a + slab_b) * 0.5, 0.9) * (1.0 - 0.12 * stain);
	float far_k = clamp(aa / grout_width - 0.5, 0.0, 1.0);
	ALBEDO = mix(near_col, avg, far_k);
	ROUGHNESS = 0.92;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
