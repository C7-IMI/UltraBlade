shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Boost strips: scrolling chevrons pointing down the strip (+V).

uniform float intensity = 1.8;

varying vec3 v_team;
varying vec2 v_uv;

void vertex() {
	v_team = COLOR.rgb;
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv;
	vec3 team = v_team;

	float phase = fract(uv.y * 2.0 - TIME * 1.25 + abs(uv.x - 0.5) * 0.55);
	float chevron = smoothstep(0.30, 0.0, abs(phase - 0.22));
	float rails = 1.0 - smoothstep(0.0, 0.045, uv.x);
	rails = max(rails, smoothstep(0.955, 1.0, uv.x));
	float center = 1.0 - smoothstep(0.0, 0.012, abs(uv.x - 0.5));
	float fade = smoothstep(0.0, 0.10, uv.y) * (1.0 - smoothstep(0.90, 1.0, uv.y));
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0 + uv.y * 8.0);

	vec3 col = team * intensity * pulse * fade;
	col *= chevron * 1.35 + rails * 1.1 + center * 0.35;
	ALBEDO = col;
}
