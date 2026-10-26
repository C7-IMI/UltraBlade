shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Hard-light goal membrane: hex-ish lattice, rising energy lines, hot frame.

uniform float intensity = 2.1;

varying vec3 v_team;
varying vec2 v_uv;

void vertex() {
	v_team = COLOR.rgb;
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv;
	vec3 team = v_team;
	float t = TIME;

	vec2 g = uv * vec2(9.0, 3.4);
	g.x += floor(g.y) * 0.5;
	float gx = abs(fract(g.x) - 0.5);
	float gy = abs(fract(g.y) - 0.5);
	float lattice = 1.0 - smoothstep(0.03, 0.10, min(gx, gy));

	float lines = exp(-pow(fract(uv.y * 5.0 - t * 0.55) * 2.0 - 1.0, 2.0) * 7.0);
	float rays = pow(0.5 + 0.5 * sin(uv.x * 40.0 + t * 2.0), 12.0) * 0.5;

	float border = max(1.0 - smoothstep(0.0, 0.018, uv.x), 1.0 - smoothstep(0.0, 0.018, 1.0 - uv.x));
	border = max(border, max(1.0 - smoothstep(0.0, 0.02, uv.y), 1.0 - smoothstep(0.0, 0.02, 1.0 - uv.y)));

	float pulse = 0.6 + 0.4 * sin(t * 2.2 - length(uv - 0.5) * 5.0);
	float fade = smoothstep(0.0, 0.06, uv.x) * (1.0 - smoothstep(0.94, 1.0, uv.x));

	vec3 col = team * intensity * fade * pulse;
	col *= lattice * 0.55 + lines * 0.85 + rays + border * 2.2;
	ALBEDO = col;
}
