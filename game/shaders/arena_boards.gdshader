shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Low drome boards + goal gate fascia. UV.x runs along the perimeter, UV.y is
// 0 at the ice and 1 at the top rail. Vertex COLOR carries the team accent.

uniform vec3 col_steel : source_color = vec3(0.227, 0.290, 0.388);
uniform vec3 col_bone : source_color = vec3(0.918, 0.965, 1.0);
uniform float emissive_scale = 1.0;

varying vec3 v_team;

void vertex() {
	v_team = COLOR.rgb;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	vec3 team = v_team;

	float panel_seed = fract(sin(dot(vec2(floor(u * 120.0), floor(v * 18.0)), vec2(12.9898, 78.233))) * 43758.5453);
	float panel_var = 0.80 + 0.40 * panel_seed;

	// brushed black-glass panel
	vec3 base = col_steel * (0.16 + 0.30 * v) * panel_var;
	base += vec3(0.006, 0.009, 0.014) * (1.0 - v);

	// seams and design lines
	float seam_u = fract(u * 120.0);
	float seam = 1.0 - smoothstep(0.0, 0.055, min(seam_u, 1.0 - seam_u));
	float seam_v = fract(v * 18.0);
	seam = max(seam, (1.0 - smoothstep(0.0, 0.035, min(seam_v, 1.0 - seam_v))) * 0.45);
	float line_hi = 1.0 - smoothstep(0.0, 0.015, abs(v - 0.52));
	float line_lo = 1.0 - smoothstep(0.0, 0.015, abs(v - 0.30));

	// neon top rail + kick strip
	float top = smoothstep(0.885, 0.925, v) * (1.0 - smoothstep(0.955, 1.0, v));
	float bot = 1.0 - smoothstep(0.035, 0.075, v);

	// LED sponsor band with animated glyphs
	float band = step(0.335, v) * step(v, 0.475);
	vec2 cell = vec2(floor(u * 170.0), floor((v - 0.335) * 90.0));
	float cell_hash = fract(sin(dot(cell, vec2(41.3, 289.1)) + floor(TIME * 1.5) * 0.37) * 15731.743);
	float glyph = step(0.66, cell_hash) * (0.35 + 0.65 * fract(cell_hash * 7.13));
	float stripes = step(0.5, fract(u * 240.0 + (v - 0.335) * 34.0 + TIME * 0.10));
	float scanline = 0.75 + 0.25 * sin(v * 220.0 - TIME * 5.0);

	// glassy fresnel
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	vec3 em = vec3(0.0);
	em += team * top * 2.0;
	em += team * bot * 0.9;
	em += team * seam * 0.07;
	em += col_bone * line_hi * 0.22;
	em += mix(team, col_bone, 0.35) * line_lo * 0.16;
	em += team * band * glyph * 1.2;
	em += team * band * stripes * 0.22;
	em += team * scanline * 0.035;
	em += team * fres * 0.22;
	em += team * 0.018;

	ALBEDO = base;
	METALLIC = 0.55;
	ROUGHNESS = 0.30;
	EMISSION = em * emissive_scale;
}
