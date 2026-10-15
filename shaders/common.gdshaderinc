// Tüm 3D malzemelerin paylaştığı görünüm ayarları (LookManager değiştirir).
//   toon_bands  : 0 = yumuşak ışık, 2-4 = kademeli (cel/toon) ışık
//   vertex_snap : 0 = kapalı; > 0 ise köşeler bu kadar piksellik ızgaraya
//                 oturur (PS1/Dreamcast tarzı titreyen poligonlar)

uniform float toon_bands = 0.0;
uniform float toon_softness = 0.04;
uniform float vertex_snap = 0.0;

vec4 snap_clip(vec4 clip, vec2 viewport_size) {
	if (vertex_snap > 0.0 && clip.w > 0.0) {
		vec2 grid = viewport_size * 0.5 / vertex_snap;
		vec2 ndc = clip.xy / clip.w;
		ndc = round(ndc * grid) / grid;
		clip.xy = ndc * clip.w;
	}
	return clip;
}

float toon_diffuse(vec3 normal, vec3 light_dir, float attenuation) {
	float ndl = clamp(dot(normal, light_dir), 0.0, 1.0) * attenuation;
	if (toon_bands > 0.5) {
		float b = ndl * toon_bands;
		float soft = toon_softness * toon_bands;
		ndl = min((floor(b) + smoothstep(0.5 - soft, 0.5 + soft, fract(b))) / toon_bands, 1.0);
	}
	return ndl;
}
