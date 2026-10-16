shader_type spatial;
render_mode specular_disabled;

// Trafik ışığı başları (MultiMesh): hangi lambanın yandığı örnek başına özel veriden gelir
// (INSTANCE_CUSTOM.r: 1 kırmızı, 2 sarı, 3 yeşil, 4 yanıp sönen yeşil; yaya başında 1 ve 3/4).
// Lamba kimliği köşe renginde (COLOR.r * 4: 0 gövde, 1 kırmızı, 2 sarı, 3 yeşil).

#include "res://shaders/common.gdshaderinc"

uniform vec3 body_color : source_color = vec3(0.13, 0.13, 0.14);

varying flat float lamp_id;
varying flat float state;

void vertex() {
	lamp_id = floor(COLOR.r * 4.0 + 0.5);
	state = floor(INSTANCE_CUSTOM.r + 0.5);
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	ROUGHNESS = 0.8;
	if (lamp_id < 0.5) {
		ALBEDO = body_color;
	} else {
		vec3 c = lamp_id < 1.5 ? vec3(1.0, 0.12, 0.08) : (lamp_id < 2.5 ? vec3(1.0, 0.72, 0.1) : vec3(0.2, 1.0, 0.45));
		bool on = abs(lamp_id - state) < 0.5;
		if (state > 3.5 && lamp_id > 2.5) {
			on = fract(TIME * 1.6) < 0.55;
		}
		ALBEDO = on ? c : c * 0.12;
		EMISSION = on ? c * 1.6 : vec3(0.0);
	}
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
