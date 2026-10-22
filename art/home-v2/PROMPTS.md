# Heimatinsel – Grafikschritt 1

Erstellt mit der eingebauten Bildgenerierung (`imagegen`), nicht mit einem API-/CLI-Fallback.
Die PNG-Originale in diesem Ordner werden unverändert aufbewahrt. Die Spielbilder
entstehen durch Freistellungsgrenzen, gleichmäßige Verkleinerung und Registrierung
der Fußpunkte im Importskript. Das Skript zeichnet keine Ersatzfiguren oder Materialien.

## Verbindliche Referenzen

- `art/source/figuren_varianten.png`: Identität, Körperproportionen und Figurenstil.
- `art/source/animationen_arbeit.png`: Arbeitshaltungen, Axt und Sammelbewegung.
- `art/source/landschaft_rohstoffe.png`: Baumkronen, Stamm, Stumpf und Beerenstrauch.
- `art/source/gebaeude_wohnen_1.png`: Strohhütte mit Holzwänden, Tür und Holzstapel.
- `art/source/landschaft_boden.png`: gemäßigte Wiese mit Grasbüscheln und kleinen Blumen.

## Promptset

### Jonas (`jonas-source.png`)

Production pixel-art sprite atlas. Young brown-haired male villager in a blue
collared rolled-sleeve shirt, brown trousers, belt and sturdy boots. Match the
approved detailed villager's silhouette, hair, face, warm outlines and material
shading, not flat geometric forms. Genuine alpha transparency. Four columns and
six rows: down/back/right walking, then down/back/right axe chopping. Four phases
per row. Chopping phases: raised axe held in both hands; forward swing; bent-knee
low strike; low follow-through. Hands and axe are one coherent drawing. Consistent
body size and feet baseline. No hats, target, grass, shadows, captions or scenery.
Requested canvas 1024×1536, cells 256×256. Preserve clear margin around tools.

### Lena (`lena-source.png`)

Production pixel-art atlas matching Jonas and the approved shoulder-haired female
villager. Warm brown shoulder-length hair, muted brick-red collared rolled-sleeve
shirt, dark muted plum-brown trousers, belt and sturdy boots. Genuine alpha.
Four columns and six rows: down/back/right walking, then down/back/right berry
gathering. Four gathering phases: bend/reach with right hand, pick two berries,
bring hand back, deposit berries in woven basket. Basket always supported by the
left hand. No floating berries. Game supplies bush separately. Same scale and
baseline in all cells; face hidden in back views. Detailed clustered shading,
anatomically coherent hands, no geometric placeholders. No background, labels,
grass, extra props or shadows. Requested canvas 1024×1536.

### Natur und Hütte (`nature-hut-source.png`)

Transparent nine-object production atlas, three columns and three rows. Faithfully
follow the approved rich pixel-art foliage, bark, timber and straw textures.
Objects: broad deciduous tree, second narrower deciduous tree, conical fir; fresh
stump, leafy sapling, berry bush full of red berries; same bush without berries,
completed straw-roof hut, same hut under construction. Preserve chimney, warm
window, closed central door and stacked logs to the right. Clear access to door.
Construction uses timber foundation, partial wall boards and detailed scaffolding.
No rectangular grass platform, cut-away earth, floating terrain island, scene,
figures, captions or separate shadow blobs. Only small root-level plants touching
objects. Light from upper left. Requested 1536×1536; delivered layout uses unequal
row heights, recorded explicitly by the importer rather than assuming a grid.

### Wiese (`meadow-source.png`)

One flat top-down seamless meadow texture matching the first temperate-grass panel
of the approved landscape reference. Clean detailed pixel clusters, warm natural
medium greens, small grass tufts, clover, occasional white daisies, subtle irregular
yellow-green and darker patches. Quiet readable grass surface, even illumination.
No vignette, directional gradient, stripes, rows, rectangles, perspective, borders,
words, paths, trees, rocks, water, hills, cutaway earth or large flowers. Fill the
whole square. Opposite edges requested to match. The runtime blends offset samples
at repeating edges without mirroring, keeping every tuft upright.

### Holzfällziel (`chop-props-source.png`)

Transparent four-column, one-row production atlas in the approved work-scene style.
Same detailed stump, same scale and baseline in every cell. Phases one/two: upright
small round log with pale rings and bark. Phases three/four: two visibly split wood
halves leaning apart, freshly cut pale wood exposed. No person, axe, grass, terrain
island, text, dividers, floating chips or other objects. Rich bark, woodgrain and
warm dark pixel outlines. Requested canvas 1536×384; importer uses delivered size.

## Produktion und Prüfung

Produktionsbilder liegen in `assets/home_v2`. Die Figuren haben je 24 Bilder mit
160×144 nativen Pixeln und gemeinsamer Fußposition (80,136). Anzeige mit Faktor
0,25 bewahrt die zusätzliche Texturauflösung. Objektanker und Quellenrechtecke
stehen in `assets/home_v2/registration.json`.

`verify_home_art.py` prüft Transparenz, Vollständigkeit, registrierte Fußpunkte und
unterschiedliche Arbeitsphasen. `HomeArtTest` prüft die echten Spielobjekte und
verhindert, dass alte Figurenlagen über den neuen Körpern sichtbar bleiben.
Die vier Arbeitsphasen werden zusätzlich als tatsächliche Spielansichten geprüft.
