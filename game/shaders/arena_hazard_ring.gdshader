shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Rotating danger ring on the ice beneath turnstiles / hazards.

uniform vec3 ring_color : source_color = vec3(1.0, 0.69, 0.12);
uniform float intensity = 1.5;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	float a = v_uv.x;
	float rad = v_uv.y;

	float band = smoothstep(0.0, 0.10, rad) * (1.0 - smoothstep(0.72, 1.0, rad));
	float inner_line = 1.0 - smoothstep(0.0, 0.06, abs(rad - 0.52));
	float dashes = step(0.52, fract(a * 26.0 + TIME * 0.85));
	float arrows = step(0.62, fract(a * 13.0 - TIME * 0.55));
	float pulse = 0.6 + 0.4 * sin(TIME * 2.6 - a * TAU * 2.0);

	vec3 col = ring_color * intensity * band * pulse;
	col *= dashes * 0.8 + arrows * 0.55 + inner_line * 1.1;
	ALBEDO = col;
}
