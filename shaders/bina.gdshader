shader_type spatial;
render_mode specular_disabled;

// Süs binaları (scripts/sehir/sehir.gd): cephe atlası assets/sehir/cepheler.png
// (tools/sehir/cephe_atlas.py). UV: x = bölme (3 m), y = kat (3 m, zeminden); her tam sayı bir hücre.
// COLOR.r = stil / 255, COLOR.g = kapı bölmesi + 1 (0: kapı yok) / 255,
// COLOR.b = hücre satırı / 255 (0: cephe -> kata göre seçilir; 3 silme, 4 düz çatı, 5 düz duvar, 6 kiremit),
// COLOR.a = 1 dükkânlı zemin kat (vitrin), 0 konut (zeminde de pencere).
// UV2.x = binanın tohumu: üst katlarda A / B pencere çeşidi binaya göre değişir (tekrar etmesin).

#include "res://shaders/common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform vec2 cells = vec2(24.0, 8.0);      // atlasta sütun (stil) ve satır sayısı

varying vec2 seed;

float h1(float a) {
	return fract(sin(a * 12.9898 + 78.233) * 43758.5453);
}

void vertex() {
	seed = UV2;
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	float style = round(COLOR.r * 255.0);
	float door = round(COLOR.g * 255.0);
	float mode = round(COLOR.b * 255.0);
	float row = mode;
	if (mode < 0.5) {
		float fl = floor(UV.y + 0.0001);
		float bay = floor(UV.x + 0.0001);
		float s = seed.x;
		// Üst kat çeşidi: bazı katlar baştan sona B, bazı binalarda tek / orta sütunlar B
		bool floor_b = h1(fl * 7.13 + s) < 0.3;
		bool odd_b = h1(s * 3.7) < 0.35 && mod(bay, 2.0) > 0.5;
		bool mid_b = door > 0.5 && h1(s * 5.3) < 0.45 && abs(bay - (door - 1.0)) < 0.5;
		float upper_row = (floor_b || odd_b || mid_b) ? 7.0 : 0.0;
		if (fl < 0.5) {
			if (door > 0.5 && abs(bay - (door - 1.0)) < 0.5) {
				row = 2.0;
			} else {
				row = COLOR.a > 0.5 ? 1.0 : 0.0;
			}
		} else {
			row = upper_row;
		}
	}
	vec2 f = clamp(fract(UV), vec2(0.5 / 32.0), vec2(1.0 - 0.5 / 32.0));
	if (mode < 0.5 && UV.y < 0.0) {
		f.y = 0.5 / 32.0;      // zeminin altına inen kısım: kaide pikseliyle uzar (pencere tekrarlanmasın)
	}
	vec2 auv = vec2((style + f.x) / cells.x, (row + 1.0 - f.y) / cells.y);
	ALBEDO = texture(atlas, auv).rgb;
	ROUGHNESS = 0.9;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
