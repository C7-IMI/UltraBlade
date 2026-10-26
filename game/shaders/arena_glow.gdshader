shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Generic HDR vertex-colour glow used by every arena trim, rail, goal frame and
// roof strip so they all batch into a handful of draw calls.

uniform float intensity = 2.6;
uniform float pulse_speed = 0.0;
uniform float pulse_amount = 0.0;
uniform float flicker_speed = 0.0;
uniform float flicker_amount = 0.0;

varying vec3 v_col;

void vertex() {
	v_col = COLOR.rgb;
}

void fragment() {
	float pulse = 1.0 - pulse_amount * (0.5 + 0.5 * sin(TIME * pulse_speed));
	float flick = 1.0 - flicker_amount * (0.5 + 0.5 * sin(TIME * flicker_speed + v_col.r * 13.0));
	ALBEDO = v_col * intensity * pulse * flick;
}
