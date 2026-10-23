shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Sokak lambasının altında yere düşen ışık havuzu (scripts/sehir/lamba_isiklari.gd). Yalnız gece görünür:
// yumuşak kenarlı sıcak bir daire, toplanarak (additive) zemini aydınlatır.
global uniform float gece;
uniform vec3 renk : source_color = vec3(1.0, 0.82, 0.5);
uniform float guc = 1.1;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = 1.0 - smoothstep(0.0, 1.0, d);
	ALBEDO = renk * a * a * guc * gece;
}
