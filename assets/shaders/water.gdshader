shader_type canvas_item;
// Wasser in Version 2 (josh 2026-10-28): ruhige blaue Fläche, offenes Meer dunkler mit wenigen
// Lichtreflexen, zur Küste hin heller und türkis, am Strand eine schmale Wellenkante, die langsam
// anläuft und zurückgeht, dazu kurze waagerechte Wellenlinien, die zeitversetzt erscheinen und
// verblassen (ein Durchlauf etwa 5 Sekunden).
// shore: Abstand jedes Geländepunkts zum nächsten Land in Feldern / 6 (World._update_shore).
uniform sampler2D shore : filter_linear, repeat_disable;
uniform vec2 shore_origin = vec2(0.0);  // Geländepunkt des ersten Bildpunkts
uniform vec2 shore_size = vec2(1.0);
uniform float tile = 16.0;
uniform vec3 deep : source_color = vec3(0.16, 0.39, 0.64);
uniform vec3 mid : source_color = vec3(0.20, 0.50, 0.74);
uniform vec3 shallow : source_color = vec3(0.33, 0.70, 0.76);
uniform vec3 foam : source_color = vec3(0.92, 0.97, 1.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 px = floor(world * 2.0) / 2.0;  // halbe Spielpixel wie die Figuren
	vec2 g = px / tile;
	float d = texture(shore, (g - shore_origin + 0.5) / shore_size).r * 6.0;
	// Farbe nach Wassertiefe in ruhigen Stufen
	float k = clamp((d - 0.6) / 2.6, 0.0, 1.0);
	k = floor(k * 6.0 + 0.5) / 6.0;
	vec3 c = k < 0.5 ? mix(shallow, mid, k * 2.0) : mix(mid, deep, (k - 0.5) * 2.0);
	float t = TIME;
	// Wellenlinien: je Rasterfeld (28 x 12 Spielpixel) höchstens eine kurze Linie, die langsam wandert
	vec2 cell_size = vec2(28.0, 12.0);
	vec2 wp = px + vec2(t * 1.2, 0.0);
	vec2 cid = floor(wp / cell_size);
	vec2 inner = wp - cid * cell_size;
	float r = hash(cid);
	if (r < 0.45 && d > 1.0) {
		float len = 5.0 + floor(hash(cid + 7.1) * 6.0);
		float x0 = floor(hash(cid + 3.3) * (cell_size.x - len - 2.0)) + 1.0;
		float y0 = floor(hash(cid + 5.7) * (cell_size.y - 3.0)) + 1.0;
		float phase = fract(t / 5.0 + hash(cid + 9.9));
		float a = smoothstep(0.0, 0.25, phase) * (1.0 - smoothstep(0.45, 0.7, phase));
		if (inner.y >= y0 && inner.y < y0 + 1.0 && inner.x >= x0 && inner.x < x0 + len) {
			c = mix(c, mix(c, vec3(1.0), 0.35), a);
		}
		// wenige Lichtreflexe im offenen Meer: ein heller Punkt am Ende einer Linie
		if (r < 0.08 && d > 3.0 && inner.y >= y0 - 1.0 && inner.y < y0 && inner.x >= x0 + len - 1.5 && inner.x < x0 + len) {
			c = mix(c, vec3(1.0), 0.6 * a);
		}
	}
	// Wellenkante am Strand: läuft langsam an und zurück, entlang der Küste leicht versetzt
	float along = hash(floor(g * 0.5)) * 0.8 + (px.x + px.y) * 0.01;
	float w = 0.5 + 0.5 * sin(t * 6.2832 / 5.0 + along);
	float edge = 0.62 + 0.22 * w;
	if (d < edge) {
		c = foam;
	} else if (d < edge + 0.12) {
		c = mix(c, foam, 0.45);
	} else if (d < edge + 0.30) {
		c = mix(c, shallow * 1.12, 0.5);
	}
	COLOR = vec4(c, 1.0);
}
