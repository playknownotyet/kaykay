shader_type spatial;
render_mode specular_disabled;

// İnce direkler (trafik ışığı, tabela, pano ayağı): düşük çözünürlüklü görüntüde uzakta
// pikselden ince kalıp kayboluyorlardı (levha havada asılı görünüyordu). Köşe, direğin
// ekseninden UV kadar yanda; ekranda en az min_pixels genişlik olacak kadar dışa itilir.

#include "res://shaders/common.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.32, 0.33, 0.35);
uniform float min_pixels = 1.3;

void vertex() {
	vec2 off = UV;                     // eksenden yatay uzaklık (x, z), metre
	float half_w = length(off);
	if (half_w > 0.0001) {
		vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float depth = max(-view.z, 0.1);
		// Bir pikselin bu derinlikteki dünya boyu
		float px = depth * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		float want = max(half_w, px * min_pixels * 0.5);
		VERTEX.xz += off / half_w * (want - half_w);
	}
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.8;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
