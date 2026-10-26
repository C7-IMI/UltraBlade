shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Hazard laser curtain. Uniform "active" is driven from arena_builder.gd.

uniform float active = 1.0;
uniform vec3 beam_color : source_color = vec3(1.0, 0.36, 0.08);
uniform vec3 idle_color : source_color = vec3(0.55, 0.10, 0.03);

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv;
	float dashes = step(0.16, fract(uv.x * 78.0 - TIME * 1.4));
	float flicker = 0.70 + 0.30 * sin(TIME * 46.0 + uv.x * 190.0);
	float ends = smoothstep(0.0, 0.035, uv.x) * (1.0 - smoothstep(0.965, 1.0, uv.x));
	float glow = exp(-pow((uv.y - 0.5) * 2.3, 2.0));
	float core = 1.0 - smoothstep(0.0, 0.35, abs(uv.y - 0.5));

	vec3 col = mix(idle_color, beam_color, active);
	ALBEDO = col * (1.4 + 2.0 * active) * flicker;
	ALPHA = clamp(active * dashes * (0.35 + 0.65 * glow) * ends * flicker + (1.0 - active) * 0.045, 0.0, 1.0);
}
