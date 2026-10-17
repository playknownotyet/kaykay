shader_type spatial;
render_mode specular_disabled;

// Kutu izdüşümlü piksel doku (dükkân duvarı, kaide, korniş, çatı...): assets/sehir/dokular.png'den
// bir karo (tools/sehir/doku_atlas.py), yüzeyin baktığı eksene göre yerel konumdan döşenir.
// Süs binalarının cepheleriyle aynı tarz ve piksel yoğunluğu.

#include "res://shaders/common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float tiles = 8.0;        // atlastaki karo sayısı
uniform float tile = 0.0;         // kullanılan karo
uniform float meters = 1.5;       // bir karonun kapladığı mesafe (m)
uniform vec3 tint : source_color = vec3(1.0);

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	vec3 n = abs(ln);
	vec2 uv;
	if (n.y >= n.x && n.y >= n.z) {
		uv = lp.xz;
	} else if (n.x >= n.z) {
		uv = vec2(lp.z, lp.y);
	} else {
		uv = vec2(lp.x, lp.y);
	}
	vec2 f = clamp(fract(uv / meters), vec2(0.5 / 32.0), vec2(1.0 - 0.5 / 32.0));
	ALBEDO = texture(atlas, vec2((tile + f.x) / tiles, 1.0 - f.y)).rgb * tint;
	ROUGHNESS = 0.9;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
