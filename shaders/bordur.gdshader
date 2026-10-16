shader_type spatial;
render_mode specular_disabled;

// Bordür taşları: yaklaşık 1 m'lik beton parçalar, aralarında derz; üst kenar açık (pahlı),
// alt kısım yol kirinden biraz koyu; her taşın tonu biraz farklı. UV: x kenar boyunca,
// y üstten aşağı (metre). Kaldırımın dış (araziye inen) yüzünde de aynı.

#include "res://shaders/common.gdshaderinc"

uniform vec3 stone_a : source_color = vec3(0.74, 0.73, 0.7);
uniform vec3 stone_b : source_color = vec3(0.62, 0.61, 0.58);
uniform vec3 joint : source_color = vec3(0.42, 0.41, 0.4);
uniform float stone_len = 1.0;

varying vec2 uv_m;

float hash1(float p) {
	return fract(sin(p * 91.345) * 47453.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	uv_m = UV;
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	float u = uv_m.x / stone_len;
	float idx = floor(u);
	float h = hash1(idx);
	float fu = fract(u);
	float e = min(fu, 1.0 - fu) * stone_len;
	float aa = fwidth(e) + 1e-4;
	float stone = smoothstep(0.006 - aa, 0.018 + aa, e);
	vec3 c = mix(stone_a, stone_b, h);
	// Üst pah: ilk 2 cm açık; alt: yol kiri
	c *= mix(1.08, 1.0, smoothstep(0.0, 0.025, uv_m.y));
	c *= mix(1.0, 0.82, smoothstep(0.06, 0.14, uv_m.y));
	c *= 0.94 + 0.1 * vnoise(vec2(uv_m.x * 18.0, uv_m.y * 30.0));
	vec3 near_col = mix(joint, c, stone);
	float far_k = clamp(aa / 0.012 - 0.5, 0.0, 1.0);
	ALBEDO = mix(near_col, mix(stone_a, stone_b, 0.5) * 0.95, far_k);
	ROUGHNESS = 0.9;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
