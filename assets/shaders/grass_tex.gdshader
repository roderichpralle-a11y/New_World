shader_type canvas_item;
// Grasmuster der ganzen Insel (josh 2026-10-28) mit Jahreszeiten wie season.gdshader. gmask: je Feld 1 auf
// vollem Gras, sonst 0 (World._update_grass_mask), linear gefiltert: zum Sand hin blendet das Muster weich
// aus, so entstehen an den Übergängen keine eckigen Kanten.
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float autumn : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D gmask : filter_linear, repeat_disable;
uniform vec2 gmask_size = vec2(1.0);
uniform float tile = 16.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = COLOR;
	vec3 rgb = c.rgb;
	float l = dot(rgb, vec3(0.3, 0.59, 0.11));
	float green = clamp((rgb.g - max(rgb.r, rgb.b)) * 5.0, 0.0, 1.0);
	vec3 fall = vec3(min(1.0, l * 2.0 + 0.1), l * 1.05, l * 0.35);
	rgb = mix(rgb, fall, autumn * green);
	vec3 sn = mix(vec3(0.74, 0.8, 0.93), vec3(1.0), clamp(l * 1.7, 0.0, 1.0));
	rgb = mix(rgb, sn, snow);
	float m = texture(gmask, (world / tile + 1.0) / gmask_size).r;
	m = smoothstep(0.55, 0.95, m);
	COLOR = vec4(rgb, c.a * m);
}
