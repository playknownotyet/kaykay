shader_type canvas_item;

// Tek geçişli ekran efekti: 3D sahnenin üstüne, arayüzün altına çizilir.
//
// 1) Hız efekti (speed_fx.gd sürer):
//    - Bükülme: warp > 0 kenarları dışarı doğru gerer, çizgiler merkeze doğru
//      kavis yapar (dıştan içe). warp < 0 ters yön (balıkgözü).
//    - Radyal bulanıklık, renk ayrışması, kenar kararması.
// 2) Görünüm / stil (look_manager.gd sürer):
//    - Piksel boyutu, renk kademesi + dither (retro), gölge/ışık renklendirme,
//      gradyan haritası (kendine has palet), kumlanma, kâğıt dokusu, kontur.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

// --- Hız ---
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float warp = 0.5;
uniform float blur = 0.07;
uniform float aberration = 0.006;
uniform float vignette = 0.12;
uniform float clear_radius = 0.3;

// --- Stil ---
uniform float pixel_size = 1.0;
uniform float posterize = 0.0;
uniform float dither = 0.0;
uniform vec3 shadow_tint : source_color = vec3(0.5);
uniform vec3 highlight_tint : source_color = vec3(0.5);
uniform float split_amount = 0.0;
uniform sampler2D gradient_map : filter_linear, repeat_disable;
uniform float gradient_amount = 0.0;
// Gradyanın kullanacağı parlaklık aralığı (sahne çok parlaksa paleti yayar)
uniform vec2 gradient_range = vec2(0.0, 1.0);
uniform float grain = 0.0;
uniform float paper = 0.0;
uniform float outline = 0.0;
uniform vec3 outline_color : source_color = vec3(0.12, 0.1, 0.18);
uniform float static_vignette = 0.0;

const int SAMPLES = 6;
const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 tap(vec2 c) {
	return texture(screen_tex, c + 0.5).rgb;
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * max(pixel_size, 1.0);
	vec2 uv = SCREEN_UV;
	if (pixel_size > 1.0) {
		uv = (floor(uv / px) + 0.5) * px;
	}

	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 c = uv - 0.5;
	vec2 ca = vec2(c.x * aspect, c.y);
	float rmax2 = 0.25 * (aspect * aspect + 1.0);
	float rn2 = dot(ca, ca) / rmax2;      // 0 merkez, 1 köşe
	float r = sqrt(rn2);

	// Bükülme: merkez ölçeği sabit; warp > 0 kenarları büyütür (dıştan içe)
	float k = warp * amount * 0.6;
	vec2 wc = c * (1.0 - k * rn2);
	if (k < 0.0) {
		wc /= (1.0 - k);   // balıkgözünde köşeler köşede kalsın
	}

	float edge = smoothstep(clear_radius, 1.0, r);
	vec3 col;
	if (amount > 0.002) {
		float len = blur * amount * edge;
		col = vec3(0.0);
		for (int i = 0; i < SAMPLES; i++) {
			float t = float(i) / float(SAMPLES - 1);
			col += tap(wc * (1.0 - len * t));
		}
		col /= float(SAMPLES);
		float ab = aberration * amount * edge;
		col.r = mix(col.r, tap(wc * (1.0 + ab)).r, 0.7);
		col.b = mix(col.b, tap(wc * (1.0 - ab)).b, 0.7);
	} else {
		col = tap(wc);
	}

	// Kontur: parlaklık farkından kenar bulma
	if (outline > 0.0) {
		vec2 o = px;
		float lx = luma(tap(wc + vec2(o.x, 0.0))) - luma(tap(wc - vec2(o.x, 0.0)));
		float ly = luma(tap(wc + vec2(0.0, o.y))) - luma(tap(wc - vec2(0.0, o.y)));
		float e = smoothstep(0.08, 0.2, abs(lx) + abs(ly));
		col = mix(col, outline_color, e * outline);
	}

	float l = luma(col);

	// Gölgelere ve ışıklara ayrı renk (split toning). 0.5 = nötr.
	if (split_amount > 0.0) {
		vec3 tint = mix(shadow_tint, highlight_tint, smoothstep(0.1, 0.9, l)) * 2.0;
		col = mix(col, col * tint, split_amount);
	}

	// Gradyan haritası: parlaklığı özel bir palete eşler
	if (gradient_amount > 0.0) {
		float gl = (l - gradient_range.x) / max(gradient_range.y - gradient_range.x, 0.01);
		vec3 g = texture(gradient_map, vec2(clamp(gl, 0.01, 0.99), 0.5)).rgb;
		col = mix(col, g, gradient_amount);
	}

	// Renk kademesi + sıralı dither (retro his)
	if (posterize > 0.0) {
		vec2 cell = floor(FRAGCOORD.xy / max(pixel_size, 1.0));
		int bi = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
		float d = (BAYER[bi] / 16.0 - 0.5) * dither;
		col = floor(col * posterize + d + 0.5) / posterize;
	}

	// Kâğıt dokusu: düşük frekanslı lekeler + lifler
	if (paper > 0.0) {
		vec2 p = SCREEN_UV * vec2(aspect, 1.0);
		float blot = value_noise(p * 6.0) * 0.6 + value_noise(p * 40.0) * 0.4;
		float fiber = value_noise(p * vec2(400.0, 60.0));
		col *= 1.0 - paper * (0.12 * blot + 0.06 * fiber);
		col = mix(col, col * vec3(1.03, 1.0, 0.94), paper);
	}

	if (grain > 0.0) {
		col += (hash(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5) * grain;
	}

	float vig = vignette * amount + static_vignette;
	col *= 1.0 - vig * smoothstep(0.45, 1.1, r);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
