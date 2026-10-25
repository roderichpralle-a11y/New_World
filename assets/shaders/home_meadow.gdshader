shader_type canvas_item;
// The existing coast mask clips one continuous detailed meadow. World coordinates
// remove the old 16-pixel stripes and prevent the texture moving with the camera.
uniform sampler2D meadow : source_color, repeat_enable, filter_nearest;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
varying vec2 ground_position;
varying vec4 ground_tint;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	ground_tint = COLOR;
}

void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	// Blend offset samples across the wrap, keeping every tuft upright. Mirrored
	// repetition would turn grass and flowers upside down at alternating edges.
	vec2 uv = fract(ground_position / 160.0);
	vec2 edge = smoothstep(vec2(0.35), vec2(0.5), abs(uv - 0.5));
	vec3 a = texture(meadow, uv).rgb;
	vec3 b = texture(meadow, uv + vec2(0.5, 0.0)).rgb;
	vec3 c = texture(meadow, uv + vec2(0.0, 0.5)).rgb;
	vec3 d = texture(meadow, uv + vec2(0.5, 0.5)).rgb;
	vec3 rgb = mix(mix(a, b, edge.x), mix(c, d, edge.x), edge.y) * ground_tint.rgb;
	float l = dot(rgb, vec3(0.3, 0.59, 0.11));
	vec3 sn = mix(vec3(0.74, 0.8, 0.93), vec3(1.0), clamp(l * 1.7, 0.0, 1.0));
	COLOR = vec4(mix(rgb, sn, snow), alpha * ground_tint.a);
}
