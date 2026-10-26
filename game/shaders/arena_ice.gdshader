shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// ULTRABLADE — "THE VAULT" obsidian ice. One draw call carries all markings,
// team light pools, wet sheen and the animated league sigil.

uniform vec3 col_void : source_color = vec3(0.012, 0.016, 0.031);
uniform vec3 col_ice : source_color = vec3(0.031, 0.071, 0.125);
uniform vec3 col_cyan : source_color = vec3(0.129, 0.902, 1.0);
uniform vec3 col_blue : source_color = vec3(0.043, 0.404, 1.0);
uniform vec3 col_magenta : source_color = vec3(1.0, 0.176, 0.435);
uniform vec3 col_amber : source_color = vec3(1.0, 0.690, 0.125);
uniform vec3 col_bone : source_color = vec3(0.918, 0.965, 1.0);
uniform float emit_scale = 1.0;
uniform float time_scale = 1.0;

varying vec3 v_world;
varying vec3 v_world_normal;

const float HW = 16.3;
const float HL = 31.3;
const float CR = 2.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + 17.0;
		a *= 0.5;
	}
	return v;
}

float aa_line(float dist, float width) {
	float w = fwidth(dist) * 1.5 + 0.0008;
	return 1.0 - smoothstep(width, width + w, abs(dist));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float t = TIME * time_scale;
	vec2 p = v_world.xz;

	// --- rounded-rectangle distance to the boards ---------------------------------
	vec2 rq = abs(p) - vec2(HW - CR, HL - CR);
	float sdf = length(max(rq, 0.0)) + min(max(rq.x, rq.y), 0.0) - CR;
	float contact = smoothstep(-3.6, -0.12, sdf);

	// --- black ice base ------------------------------------------------------------
	float n1 = fbm2(p * 0.40);
	float n2 = fbm2(p * vec2(0.045, 0.011) + 3.0);
	float scratch = smoothstep(0.55, 0.92, fbm2(vec2(p.x * 9.0, p.y * 0.55)));
	vec3 base = mix(col_void, col_ice, 0.50 + 0.55 * n1);
	base = mix(base, col_ice * 2.3, 0.20 * n2);
	base += vec3(0.012, 0.02, 0.032) * scratch;
	base *= 1.0 - 0.58 * contact;

	// --- team halves, light pools -------------------------------------------------
	float zone = smoothstep(-4.0, 4.0, p.y);
	vec3 team = mix(col_cyan, col_magenta, zone);
	vec2 gb = p - vec2(0.0, -27.0);
	vec2 gr = p - vec2(0.0, 27.0);
	float pool_b = exp(-dot(gb, gb) / 95.0);
	float pool_r = exp(-dot(gr, gr) / 95.0);
	float pool_c = exp(-dot(p, p) / 90.0);
	vec3 pool = col_blue * pool_b * 0.30 + col_cyan * pool_b * 0.08;
	pool += col_magenta * pool_r * 0.34;
	pool += mix(col_cyan, col_magenta, zone) * pool_c * 0.06;

	// --- broadcast markings --------------------------------------------------------
	float inside = 1.0 - smoothstep(15.4, 16.2, abs(p.x));
	float center_line = aa_line(p.y, 0.085) * inside;
	float blue_lines = (aa_line(p.y - 9.0, 0.095) + aa_line(p.y + 9.0, 0.095)) * inside;
	float goal_lines = (aa_line(p.y - 28.6, 0.075) + aa_line(p.y + 28.6, 0.075)) * inside;
	float center_circle = aa_line(length(p) - 5.6, 0.05);
	vec2 fq = vec2(abs(p.x) - 9.0, abs(p.y) - 9.0);
	float faceoff_circles = aa_line(length(fq) - 3.0, 0.045) * (1.0 - smoothstep(14.0, 15.6, abs(p.x)));
	float faceoff_dots = 1.0 - smoothstep(0.10, 0.16, length(fq));
	float crease_b = step(-28.6, p.y) * (1.0 - smoothstep(3.0, 3.3, length(vec2(p.x, p.y + 28.6))));
	float crease_r = step(p.y, 28.6) * (1.0 - smoothstep(3.0, 3.3, length(vec2(p.x, p.y - 28.6))));

	// --- league sigil --------------------------------------------------------------
	float r = length(p);
	float ang = atan(p.x, p.y);
	float sigil_zone = smoothstep(-3.0, 3.0, p.y);
	vec3 sig_col = mix(col_cyan, col_magenta, sigil_zone);
	float sig = 0.0;

	// outer segmented ring, slow clockwise drift
	float seg1 = step(0.42, fract(ang / TAU * 12.0 + t * 0.04));
	sig = max(sig, aa_line(r - 5.05, 0.055) * seg1);
	// counter-rotating inner ring
	float seg2 = step(0.58, fract(ang / TAU * 16.0 - t * 0.065));
	sig = max(sig, aa_line(r - 4.55, 0.028) * seg2 * 0.75);
	// six-point star from three long bars
	for (int i = 0; i < 3; i++) {
		float a = float(i) * PI / 3.0;
		vec2 dir = vec2(sin(a), cos(a));
		vec2 perp = vec2(cos(a), -sin(a));
		float dp = abs(dot(p, perp));
		float along = abs(dot(p, dir));
		float bar = aa_line(dp, 0.030) * step(along, 4.35) * step(1.15, along);
		sig = max(sig, bar * 0.85);
	}
	// three sweeping blades
	for (int i = 0; i < 3; i++) {
		float a0 = float(i) * TAU / 3.0 + t * 0.20;
		float da = mod(ang - a0 + PI, TAU) - PI;
		float blade = smoothstep(0.46, 0.12, abs(da)) * smoothstep(1.15, 1.85, r) * (1.0 - smoothstep(3.45, 3.9, r));
		sig = max(sig, blade * 0.8);
	}
	// centre ring
	sig = max(sig, aa_line(r - 1.18, 0.035) * 0.9);

	// --- killball charger pad (amber hex) -----------------------------------------
	float hex_ang = mod(ang + PI / 6.0, PI / 3.0) - PI / 6.0;
	float hex_radius = cos(PI / 6.0) / max(cos(hex_ang), 0.001);
	float hex_ring = aa_line(r - hex_radius * 1.72, 0.045);
	float hex_dashes = step(0.30, fract(ang / TAU * 6.0 + t * 0.45));
	float hex_spokes = 0.0;
	for (int i = 0; i < 6; i++) {
		float a0 = float(i) * TAU / 6.0 + t * 0.45;
		float da = mod(ang - a0 + PI, TAU) - PI;
		hex_spokes = max(hex_spokes, smoothstep(0.05, 0.0, abs(da)) * smoothstep(1.72, 1.9, r) * (1.0 - smoothstep(2.1, 2.35, r)));
	}
	float amber_pulse = 0.62 + 0.38 * sin(t * 2.4);
	float charger_glow = (hex_ring * hex_dashes + hex_spokes * 0.7) * amber_pulse;

	// --- wet sheen + board reflection ---------------------------------------------
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world);
	float grazing = pow(1.0 - clamp(view_dir.y, 0.0, 1.0), 4.0);
	float wet = 0.45 + 0.55 * fbm2(vec2(p.x * 0.6, p.y * 0.05));
	vec3 board_glow = mix(col_cyan, col_magenta, zone) * grazing * (0.05 + 0.20 * wet);
	board_glow *= (1.0 - smoothstep(0.0, 12.0, -sdf)) * (1.0 - 0.4 * contact);

	// --- composite -----------------------------------------------------------------
	vec3 em = vec3(0.0);
	em += pool;
	em += team * 0.020;
	em += col_bone * center_line * 0.55;
	em += col_cyan * blue_lines * 1.05;
	em += mix(col_magenta, col_bone, 0.25) * goal_lines * 0.9;
	em += col_bone * center_circle * 0.45;
	em += col_bone * faceoff_circles * 0.42;
	em += col_bone * faceoff_dots * 0.65;
	em += col_cyan * crease_b * 0.14 + col_magenta * crease_r * 0.14;
	em += sig_col * sig * 1.75;
	em += col_amber * charger_glow * 1.9;
	em += board_glow;
	em += mix(col_cyan, col_magenta, zone) * smoothstep(-0.55, -0.06, sdf) * 0.30;

	ALBEDO = base;
	METALLIC = 0.45;
	ROUGHNESS = clamp(mix(0.55, 0.18, wet) + contact * 0.10, 0.10, 0.75);
	EMISSION = em * emit_scale;

	// subtle wet-ice normal ripples
	vec3 wn = normalize(v_world_normal + vec3((n1 - 0.5) * 0.07, 0.0, (n2 - 0.5) * 0.07));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
