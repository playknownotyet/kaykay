shader_type spatial;
render_mode specular_disabled;

// Süs binaları (scripts/sehir/sehir.gd): cephe atlası assets/sehir/cepheler.png
// (tools/sehir/cephe_atlas.py). UV: x = bölme (3 m), y = kat (3 m, zeminden); her tam sayı bir hücre.
// COLOR.r = stil / 255, COLOR.b = atlas satırı / 255 (0 üst kat A, 1 vitrin, 2 kapı, 3 silme,
// 4 düz çatı, 5 düz duvar, 6 kiremit, 7 üst kat B), COLOR.a = 1 cephe hücresi.
// UV2.x = binanın tohumu (oda seçimi, ışığı yanan odalar).
//
// İç mekân: atlasta camın pikselleri yarı saydam işaretli. Orada, cephe hücresinin arkasında
// 3 m'lik bir oda varmış gibi bakış ışını odanın duvarlarına, zeminine, tavanına çarptırılır
// (interior mapping); oda yüzleri assets/sehir/odalar.png'den (tools/sehir/oda_atlas.py).

#include "res://shaders/common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D rooms : source_color, filter_nearest, repeat_disable;
uniform vec2 cells = vec2(24.0, 8.0);      // atlasta sütun (stil) ve satır sayısı
uniform vec2 room_cells = vec2(8.0, 6.0);
uniform float room_depth = 0.85;           // odanın derinliği (hücre boyu cinsinden)
uniform float gece : hint_range(0.0, 1.0) = 0.0;
// Oyuncuya yakın gerçek 3D odalar (scripts/sehir/canli_odalar.gd): bu cephe parçalarında cam
// delinir, arkadaki gerçek oda görünür. a = (merkez x, merkez z, normal x, normal z),
// b = (yarı genişlik, alt y, üst y, açık mı)
uniform vec4 cut_a[4];
uniform vec4 cut_b[4];

varying vec2 seed;
varying vec3 wpos;
varying vec3 wnorm;

float h1(float a) {
	return fract(sin(a * 12.9898 + 78.233) * 43758.5453);
}

void vertex() {
	seed = UV2;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

vec3 room_tex(float idx, vec2 uv) {
	vec2 c = vec2(mod(idx, room_cells.x), floor(idx / room_cells.x));
	vec2 f = clamp(uv, vec2(0.5 / 64.0), vec2(1.0 - 0.5 / 64.0));
	return texture(rooms, (c + f) / room_cells).rgb;
}

// Hücre içi konum p (0..1, y yukarı), bakış yönü d (x sağ, y yukarı, z dışarı)
vec3 interior(vec2 p, vec3 d, float back, float side, float flr, out float lamp) {
	vec3 o = vec3(p, 0.0);
	float tx = d.x > 0.0 ? (1.0 - o.x) / d.x : -o.x / min(d.x, -1e-4);
	float ty = d.y > 0.0 ? (1.0 - o.y) / d.y : -o.y / min(d.y, -1e-4);
	float tz = room_depth / max(-d.z, 1e-4);
	float t = min(tx, min(ty, tz));
	vec3 h = o + d * t;
	float depth = clamp(-h.z / room_depth, 0.0, 1.0);
	vec3 col;
	lamp = 0.0;
	if (t == tz) {
		col = room_tex(back, vec2(h.x, 1.0 - h.y));
	} else if (t == tx) {
		// Yan duvar: derin kısım arka duvara bitişik
		float u = d.x > 0.0 ? depth : 1.0 - depth;
		col = room_tex(24.0 + side, vec2(u, 1.0 - h.y)) * 0.88;
	} else if (d.y < 0.0) {
		col = room_tex(32.0 + flr, vec2(h.x, depth)) * 0.92;
	} else {
		col = room_tex(40.0, vec2(h.x, depth));
		lamp = 1.0;
	}
	// Derinlik karanlığı: odanın içi sokaktan loş görünür
	return col * mix(1.0, 0.72, depth);
}

void fragment() {
	float style = round(COLOR.r * 255.0);
	float row = round(COLOR.b * 255.0);
	bool facade = COLOR.a > 0.5;
	vec2 f = clamp(fract(UV), vec2(0.5 / 32.0), vec2(1.0 - 0.5 / 32.0));
	if (facade && UV.y < 0.0) {
		f.y = 0.5 / 32.0;      // zeminin altına inen kısım: kaide pikseliyle uzar (pencere tekrarlanmasın)
	}
	vec2 auv = vec2((style + f.x) / cells.x, (row + 1.0 - f.y) / cells.y);
	vec4 tex = texture(atlas, auv);
	vec3 col = tex.rgb;
	vec3 emit = vec3(0.0);
	if (facade && tex.a < 0.9 && UV.y >= 0.0) {
		for (int i = 0; i < 4; i++) {
			vec4 ca = cut_a[i];
			vec4 cb = cut_b[i];
			if (cb.w > 0.5) {
				vec2 rel = wpos.xz - ca.xy;
				if (abs(dot(rel, ca.zw)) < 0.3 && abs(dot(rel, vec2(ca.w, -ca.z))) < cb.x && wpos.y > cb.y && wpos.y < cb.z) {
					discard;
				}
			}
		}
		// Cam: arkasındaki oda
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 n = normalize(wnorm);
		vec3 right = normalize(cross(up, n));
		vec3 v = normalize(wpos - CAMERA_POSITION_WORLD);
		vec3 d = vec3(dot(v, right), dot(v, up), dot(v, n));
		vec2 cell = floor(UV + 0.0001);
		float r = h1(seed.x * 13.1 + cell.x * 7.7 + cell.y * 3.3);
		float back = row > 0.5 && row < 1.5 ? 18.0 + floor(r * 6.0) : floor(r * 18.0);
		float side = floor(h1(r * 51.7) * 8.0);
		float flr = floor(h1(r * 23.3) * 8.0);
		float lamp;
		vec3 room = interior(fract(UV), d, back, side, flr, lamp);
		// Cam: biraz gökyüzü yansıması ve camın kendi rengi
		float fres = pow(1.0 - clamp(-d.z, 0.0, 1.0), 3.0);
		// İçerinin kendi ışığı: güneşten bağımsız (gölgedeki cephede de oda okunur)
		float refl = 0.08 + fres * 0.3;
		emit = room * 0.4 * (1.0 - refl);
		col = mix(room * 0.45, tex.rgb, refl);
		// Gece: odaların bir kısmı yanar (sıcak ışık), tavan lambası parlar
		float lit = step(0.45, h1(r * 97.1 + 4.2)) * gece;
		emit += room * vec3(1.0, 0.86, 0.6) * lit * 0.7 + vec3(1.0, 0.9, 0.6) * lamp * lit * 0.6;
		col *= 1.0 - lit * 0.5;
	}
	ALBEDO = col;
	EMISSION = emit;
	ROUGHNESS = 0.9;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
