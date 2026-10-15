shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Gri kutu (graybox) malzemesi: dünya koordinatında ızgara çizer.
// Görünüm (LookManager) şunları değiştirebilir:
//   line_strength : ızgara çizgilerinin görünürlüğü
//   toon_bands / vertex_snap: bkz. common.gdshaderinc
//   noise_strength: yüzeyde hafif renk dalgalanması (doku hissi)

uniform vec3 base_color : source_color = vec3(0.6, 0.65, 0.72);
uniform vec3 line_color : source_color = vec3(0.45, 0.5, 0.58);
uniform float cell_size = 2.0;
uniform float line_width = 0.035;
uniform float line_strength = 1.0;
uniform float noise_strength = 0.0;
uniform float noise_scale = 1.5;
// Zeminde delikler: üstünde başka bir yüzey (arnavut kaldırımı) olan alanlar hiç
// çizilmez; aksi halde iki yüzey üst üste titreşir. (xmin, zmin, xmax, zmax)
uniform vec4 holes[8];
uniform int hole_count = 0;

#include "res://shaders/common.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	POSITION = snap_clip(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), VIEWPORT_SIZE);
}

void fragment() {
	for (int i = 0; i < hole_count; i++) {
		vec4 h = holes[i];
		if (world_pos.x > h.x && world_pos.x < h.z && world_pos.z > h.y && world_pos.z < h.w) {
			discard;
		}
	}
	vec3 n = abs(world_normal);
	vec2 uv;
	if (n.y >= n.x && n.y >= n.z) {
		uv = world_pos.xz;
	} else if (n.x >= n.z) {
		uv = world_pos.zy;
	} else {
		uv = world_pos.xy;
	}
	// En yakın ızgara çizgisine uzaklık (metre)
	vec2 g = abs(fract(uv / cell_size - 0.5) - 0.5) * cell_size;
	float d = min(g.x, g.y);
	float aa = fwidth(d);
	float line = (1.0 - smoothstep(line_width - aa, line_width + aa, d)) * line_strength;
	vec3 col = mix(base_color, line_color, line);
	if (noise_strength > 0.0) {
		float nz = noise3(world_pos * noise_scale) * 0.65 + noise3(world_pos * noise_scale * 4.0) * 0.35;
		col *= 1.0 + (nz - 0.5) * noise_strength;
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION) * LIGHT_COLOR / PI;
}
