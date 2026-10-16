shader_type spatial;
render_mode specular_disabled;

// Dokulu nesne malzemesi (Poly Haven sokak eşyaları): küçük renk dokusu + oyunun toon ışığı ve
// poligon titremesi. Doku yakından da piksel piksel görünür (retro).

#include "res://shaders/common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (t.a < 0.4) {
		discard;
	}
	ALBEDO = t.rgb * tint;
	ROUGHNESS = 0.85;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
