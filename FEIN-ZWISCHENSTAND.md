# Insel-Siedler Fein 1.1.0 – Zwischenstand

## Grafikschritt 1: Heimatinsel

Der Startbildschirm kennzeichnet diesen Stand mit **Heimatinsel 1**.
Neu überarbeitet und im Spiel geprüft sind die zusammenhängende Wiese mit Gras,
die drei Baumvarianten, Stumpf und Setzling, Beerensträucher, die Strohhütte samt
Baustelle sowie Lena und Jonas mit Geh-, Holzfäll- und Sammelphasen. Die Figuren
werden aus vollständigen, registrierten Bildern dargestellt; Hände, Korb und Axt
gehören jeweils zum Körperbild. Ab der dritten Holzfällphase sind zwei gespaltene
Holzstücke sichtbar. Vorhandene Fein-Spielstände erkennen die beiden Gründer wieder.

Dieser Schritt ist bewusst auf die Heimatinsel und die beiden Gründer beschränkt.
Weitere Figuren, Gebäude, Oberfläche, Meeresgrafiken und andere Inseln enthalten
weiterhin die bereits dokumentierten offenen Grafikabweichungen. Sie gehören zu
späteren Schritten und sind nicht als visuell abgenommen zu verstehen.

Bildquellen, Arbeitsanweisungen und Importbeschreibung: `art/home-v2/PROMPTS.md`.
Produktionsbilder: `assets/home_v2`; Import: `tools/import_home_art.py`.
Die technischen Prüfungen und die Sichtkontrolle der vier Arbeitsphasen ergänzen
sich; die persönliche Beurteilung des Stils erfolgt weiter durch den Nutzer.

Testadresse: https://roderichpralle-a11y.github.io/New_World/fein/

Diese getrennte Variante nutzt eigene Spielstände. Alte Spielstände der normalen
Version werden nicht importiert. Die normale Veröffentlichung bleibt erhalten.

## Enthalten

- Eigene Grafikdateien für Gebäude, Natur, Symbole und Oberfläche.
- Figuren mit höher aufgelösten Kleidungsschichten und vier Arbeitsphasen.
- Holzspalten mit gespaltenem Holz ab Phase drei und sichtbarer Baufortschritt.
- Ruderboot, Bodenschlaf ohne Bett, Mühle mit rechtwinkligen Flügeln,
  Fischgrund ohne Ufer und Spritzer sowie ein fester Hologrammsockel.
- Holz-Scrollleisten mit angepassten Trefferflächen und getrennten Griffgesten.
- Automatisierter Grafiktest und Laufzeittest einschließlich Scrollgriff,
  Speichern, Kleidungsschichten und Gebäudeankern.

## Noch offen

Dies ist ausdrücklich eine spielbare Vorschau, keine abschließend geprüfte Version.
Die vollständige Sichtprüfung aller Gebäude, Arbeitsposen, Hüte, Jahreszeiten und
Platzierungen auf Desktop und Handy steht noch aus. Einige ergänzende Boden- und
Verbindungsflächen verwenden bisher die ursprünglichen Grundformen mit angepasster
Textur. Die Figuren sind eine erste Umsetzung und können weiter verfeinert werden.

Bitte insbesondere die Siedlerliste auf dem Handy, den Bildausschnitt von Gebäuden,
Arbeitsgeräte und Kopfbedeckungen prüfen. Bei Grafikfehlern helfen der Gebäudename
bzw. Beruf und die Angabe, auf welchem Gerät sie auftreten.

## Reproduzierbarkeit

Die Entwürfe stehen unter `art/source`, die eingebundenen Atlanten unter
`assets/sprites_fine`. `tools/build_fine_art.py` erstellt die Produktionsgrafiken;
`tools/verify_fine_art.py` prüft die Zuordnung. Der eigene GitHub-Workflow exportiert
diesen Zweig nach `/fein/`, ohne die normale Variante zu ersetzen.
