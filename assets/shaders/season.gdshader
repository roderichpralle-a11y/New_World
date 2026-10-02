shader_type canvas_item;
// Jahreszeiten: Herbstlaub färbt Grün orange-rot, Schnee hellt Flächen zu Weiß auf.
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float autumn : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec3 rgb = c.rgb;
	float l = dot(rgb, vec3(0.3, 0.59, 0.11));
	float green = clamp((rgb.g - max(rgb.r, rgb.b)) * 5.0, 0.0, 1.0);
	vec3 fall = vec3(min(1.0, l * 2.0 + 0.1), l * 1.05, l * 0.35);
	rgb = mix(rgb, fall, autumn * green);
	vec3 sn = mix(vec3(0.74, 0.8, 0.93), vec3(1.0), clamp(l * 1.7, 0.0, 1.0));
	rgb = mix(rgb, sn, snow);
	COLOR = vec4(rgb, c.a);
}
