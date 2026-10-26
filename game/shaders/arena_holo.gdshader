shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Holographic banners: procedural glyph columns, scanlines, frame + sweep.
// Vertex COLOR is the team tint.

uniform float intensity = 1.5;
uniform vec3 col_bone : source_color = vec3(0.918, 0.965, 1.0);

varying vec3 v_team;
varying vec2 v_uv;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_team = COLOR.rgb;
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv;
	vec3 team = v_team;
	float t = TIME;

	float bx = smoothstep(0.0, 0.010, uv.x) * (1.0 - smoothstep(0.990, 1.0, uv.x));
	float by = smoothstep(0.0, 0.030, uv.y) * (1.0 - smoothstep(0.970, 1.0, uv.y));
	float frame = max(1.0 - bx, 1.0 - by);

	float inner = 1.0 - smoothstep(0.0, 0.006, abs(uv.x - 0.045));
	inner = max(inner, 1.0 - smoothstep(0.0, 0.006, abs(uv.x - 0.955)));
	inner = max(inner, 1.0 - smoothstep(0.0, 0.012, abs(uv.y - 0.12)));

	vec2 cells = vec2(16.0, 3.0);
	vec2 cell = floor(uv * cells);
	float step_t = floor(t * 2.0);
	float r = hash21(cell + step_t * 0.173);
	float glyph = step(0.55, r) * (0.35 + 0.65 * hash21(cell + 11.0));
	float cellmask = step(0.10, fract(uv.x * cells.x)) * step(0.22, fract(uv.y * cells.y));

	float bars = step(0.5, fract(uv.y * 3.0 - t * 0.25)) * 0.14;
	float glitch_band = step(0.87, hash21(vec2(floor(uv.y * 44.0), floor(t * 9.0))));
	float scan = 0.80 + 0.20 * sin(uv.y * 170.0 - t * 8.0);
	float sweep_x = fract(uv.x * 0.5 - t * 0.18) * 2.0;
	float sweep = exp(-sweep_x * sweep_x * 5.0);
	float edge = smoothstep(0.0, 0.035, uv.x) * (1.0 - smoothstep(0.965, 1.0, uv.x));
	edge *= smoothstep(0.0, 0.09, uv.y) * (1.0 - smoothstep(0.91, 1.0, uv.y));

	vec3 col = team * intensity * scan * edge;
	col *= (glyph * cellmask * 0.85 + bars + glitch_band * 0.55 + frame * 2.3 + inner * 1.3 + sweep * 0.4);
	ALBEDO = col;
}
