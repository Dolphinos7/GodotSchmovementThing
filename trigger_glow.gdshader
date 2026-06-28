shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, unshaded;

uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.2, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.12;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.7;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Fresnel: close to 0 when looking straight at a face, close to 1 at
	// grazing/edge angles - this is what makes the rim brighter than the
	// flat faces, like a soap-bubble/force-field look.
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_position);
	float fresnel = pow(1.0 - abs(dot(world_normal, view_dir)), 2.0);

	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
	float alpha = base_alpha + fresnel * rim_alpha * (0.7 + 0.3 * pulse);

	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * (0.4 + fresnel);
	ALPHA = clamp(alpha * glow_color.a, 0.0, 1.0);
}
