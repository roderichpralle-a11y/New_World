shader_type canvas_item;
// Feiner Boden von josh (2026-10-30): Gras je Jahreszeit und gelber Sand als nahtlose Bilder für 4 x 4 Felder
// (World._update_fine_ground). Gezeichnet nach Weltkoordinaten; die Kachel (dieselbe wie im alten Gras- oder
// Sandlayer) gibt mit ihrer Deckkraft nur die Form vor, so passen Ränder und Übergänge genau.
// ga und gb: Bild der laufenden und der nächsten Jahreszeit, gmix blendet am Ende der Jahreszeit über.
uniform sampler2D ga : filter_linear_mipmap, repeat_enable;
uniform sampler2D gb : filter_linear_mipmap, repeat_enable;
uniform float gmix : hint_range(0.0, 1.0) = 0.0;
uniform float period = 64.0;
uniform vec4 tint : source_color = vec4(1.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = world / period;
	vec4 c = mix(texture(ga, uv), texture(gb, uv), gmix);
	COLOR = vec4(c.rgb * tint.rgb, COLOR.a);
}
