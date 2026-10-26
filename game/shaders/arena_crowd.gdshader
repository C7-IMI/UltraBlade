shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Holographic crowd pixels. One MultiMesh = one draw call; per-instance custom
// data (rgb tint, phase) drives shimmer, a travelling wave and a subtle bob.

uniform float intensity = 1.9;
uniform float bob_amount = 0.035;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float phase = v_custom.a;
	VERTEX.y += sin(TIME * 2.6 + phase * 24.0 + MODEL_MATRIX[3].z * 0.30) * bob_amount;
}

void fragment() {
	vec2 uv = UV;
	vec2 body_c = (uv - vec2(0.5, 0.40)) * vec2(1.0, 1.12);
	float body = 1.0 - smoothstep(0.17, 0.26, length(body_c * vec2(1.0, 0.82)));
	float head = 1.0 - smoothstep(0.042, 0.080, length((uv - vec2(0.5, 0.855)) * vec2(1.45, 1.0)));
	float mask = max(body * 0.92, head);
	if (mask < 0.02) {
		discard;
	}
	float phase = v_custom.a;
	float flick = 0.62 + 0.38 * sin(TIME * 5.5 + phase * 37.0 + MODEL_MATRIX[3].z * 0.55);
	float wave = 0.80 + 0.20 * sin(TIME * 2.4 - MODEL_MATRIX[3].z * 0.22 + phase * 2.0);
	float scan = 0.82 + 0.18 * sin(uv.y * 26.0 + phase * 9.0 - TIME * 3.0);
	vec3 col = v_custom.rgb * intensity * mask * flick * wave * scan;
	ALBEDO = col;
}
