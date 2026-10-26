shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Overhead jumbotron broadcast feed: league sigil, team score bars, glitch
// panels and scanlines. Four screens share one draw call.

uniform float intensity = 1.8;
uniform vec3 col_cyan : source_color = vec3(0.129, 0.902, 1.0);
uniform vec3 col_magenta : source_color = vec3(1.0, 0.176, 0.435);
uniform vec3 col_bone : source_color = vec3(0.918, 0.965, 1.0);

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = v_uv;
	float t = TIME;

	float border = max(1.0 - smoothstep(0.0, 0.012, uv.x), 1.0 - smoothstep(0.0, 0.012, 1.0 - uv.x));
	border = max(border, max(1.0 - smoothstep(0.0, 0.02, uv.y), 1.0 - smoothstep(0.0, 0.02, 1.0 - uv.y)));

	// horizontal broadcast ticker
	float ticker_y = 0.115;
	float ticker_row = 1.0 - smoothstep(0.0, 0.035, abs(uv.y - ticker_y));
	vec2 tick_cell = vec2(floor(uv.x * 46.0 - t * 6.0), 0.0);
	float ticker = step(0.55, hash21(tick_cell)) * ticker_row;

	// score bars left / right
	float lb = step(0.035, uv.x) * step(uv.x, 0.135) * step(0.24, uv.y) * step(uv.y, 0.24 + 0.42 * (0.55 + 0.45 * sin(t * 1.1)));
	float rb = step(0.865, uv.x) * step(uv.x, 0.965) * step(0.24, uv.y) * step(uv.y, 0.24 + 0.42 * (0.55 + 0.45 * sin(t * 1.1 + 1.7)));

	// centre league sigil
	vec2 c = (uv - vec2(0.5, 0.56)) * vec2(2.3, 1.0);
	float r = length(c);
	float ang = atan(c.x, c.y);
	float ring = 1.0 - smoothstep(0.0, 0.06, abs(r - 0.30)) * 0.0;
	ring = 1.0 - smoothstep(0.055, 0.085, abs(r - 0.30));
	float ring2 = 1.0 - smoothstep(0.0, 0.018, abs(r - 0.21));
	float blades = 0.0;
	for (int i = 0; i < 3; i++) {
		float a0 = float(i) * TAU / 3.0 + t * 0.5;
		float da = mod(ang - a0 + PI, TAU) - PI;
		blades = max(blades, smoothstep(0.40, 0.10, abs(da)) * smoothstep(0.055, 0.11, r) * (1.0 - smoothstep(0.20, 0.28, r)));
	}
	float core = 1.0 - smoothstep(0.03, 0.07, r);

	// glitch blocks along the top / bottom
	vec2 gcell = vec2(floor(uv.x * 26.0), floor(uv.y * 9.0));
	float glitch = step(0.94, hash21(gcell + floor(t * 7.0) * 0.31)) * step(0.72, uv.y) * 0.8;
	glitch += step(0.95, hash21(gcell + 5.0 + floor(t * 5.0) * 0.17)) * step(uv.y, 0.20) * 0.8;

	float scan = 0.82 + 0.18 * sin(uv.y * 210.0 - t * 10.0);
	float sweep_x = fract(uv.x * 0.5 - t * 0.10) * 2.0;
	float sweep = exp(-sweep_x * sweep_x * 8.0) * 0.55 + 0.40;
	float vign = smoothstep(0.0, 0.06, uv.x) * (1.0 - smoothstep(0.94, 1.0, uv.x));

	vec3 col = vec3(0.0);
	col += col_cyan * (ring * 0.85 + blades * 0.75 + core);
	col += col_magenta * ring2 * 0.8;
	col += col_cyan * lb * 1.5 + col_magenta * rb * 1.5;
	col += col_bone * (border * 2.4 + ticker * 0.9 + glitch * 0.7);
	col += vec3(0.22, 0.30, 0.40) * (0.55 + 0.45 * sin(uv.y * 3.0));
	col *= scan * sweep * vign * intensity;
	ALBEDO = col;
}
