# Insel-Siedler: KI-Training für das ganze Spiel

Dieses Paket lässt die KI von Version 3 auf einem Mac lernen, das ganze Spiel allein zu steuern:
vom Start mit 2 Siedlern bis alles erforscht ist und die Zukunftsstadt steht.

## Starten

1. Die zip-Datei auspacken (Doppelklick).
2. Der Mac blockiert die Startdatei, weil sie aus dem Internet kommt und nicht von Apple geprüft ist.
   So geht es trotzdem (Weg A ist der sicherste, B ist der Weg ohne Terminal):
   - **Weg A, Terminal:** Programm „Terminal“ öffnen und diese zwei Zeilen eingeben, jeweils mit Eingabetaste
     (der Pfad ist der Ordner, in den du die zip ausgepackt hast; am einfachsten tippst du `cd ` mit Leerzeichen
     und ziehst den Ordner `Insel-KI-Training` ins Fenster):
     ```
     cd ~/Downloads/Insel-KI-Training
     xattr -dr com.apple.quarantine . && bash START.command
     ```
     Die erste Zeile nimmt dem Ordner die Sperre ab, die zweite startet das Training. Das genügt, es ist nur dieser Ordner betroffen.
   - **Weg B, Einstellungen:** `START.command` doppelklicken, die Meldung wegklicken, dann **Systemeinstellungen >
     Datenschutz & Sicherheit** öffnen, ganz nach unten scrollen, bei der Meldung zu `START.command` auf
     **Dennoch öffnen** klicken, Passwort eingeben. Danach noch einmal doppelklicken. Auf neuem macOS (ab 15) geht
     Rechtsklick > Öffnen nicht mehr.
3. Beim ersten Start lädt das Programm Godot (die Spiel-Engine, etwa 130 MB) und bereitet das Spiel vor.
   Das dauert ein paar Minuten und braucht Internet. Danach nicht mehr.
4. Im Browser öffnet sich die Oberfläche: http://127.0.0.1:8765/
   Das Training läuft sofort los. Das Terminal-Fenster muss offen bleiben.

Die Oberfläche öffnet sich, das Training startet aber nicht von selbst. Oben wählst du die **Stufe** und wie viele **Durchgänge** laufen sollen und drückst **Start**. Nach so vielen Durchgängen hält das Training von selbst an. **Stopp** hält es sofort an; ein angefangener Durchgang wird beim nächsten Start wiederholt. Ein Durchgang ist eine Lernrunde: 32 Spiele vom Anfang, danach werden die Gewichte verbessert. Die Statusseite zeigt „Durchgang x von N“ und eine geschätzte Restzeit.

Beenden: „Stopp“ drücken, dann das Terminal-Fenster schließen. Beim nächsten Start lernt die KI mit den bisherigen Gewichten weiter (Ordner `lauf`).

Der Mac braucht Python 3. Fehlt es, sagt die Startdatei, was zu tun ist (`xcode-select --install`).

## Die Oberfläche

- **Status**: Runde, Spiellänge, wie weit die KI bisher kam, welche Spiele gerade laufen (Spieltag, Siedler,
  Zeitalter, Forschung), Bilder zum Verlauf, alle Prüfungen.
- **Was die KI gelernt hat**: ein ganzes Prüfspiel zum Ansehen (jede Entscheidung der KI mit Spieltag),
  der Vergleich über die Prüfungen und die Gewichte in Worten („eher, wenn ...“).
- **Spiel live ansehen** (im Reiter „Was die KI gelernt hat“): öffnet das Spiel in einem eigenen Fenster, die KI spielt dort
  vom Anfang mit den besten oder den jetzigen Gewichten, du siehst ihr zu. Tempo und Würfel wählbar, Fenster schließen
  beendet es. Deine eigenen Spielstände bleiben unberührt.
- **Programmcode**: das Trainingsprogramm und die KI im Spiel zum Lesen, dazu alle Dateien des Spiels.
- **Freischalt-Liste**: welches Gebäude der KI im Spiel welche Entscheidungen freigibt.

## Wie die KI lernt

Die KI ist eine Tabelle von Zahlen (Gewichte): je eine Zeile für jeden Beruf, für jede Handlung
(z. B. „Haus bauen“, „Schiff bauen“, „Überstunden für Bauern“) und für die Wahl der Forschung.
Gelernt wird durch Ausprobieren mit Belohnung (Reinforcement Learning, Verfahren „Augmented Random Search“):

1. Die Gewichte werden zufällig ein wenig verändert, in mehrere Richtungen.
2. Jede Fassung spielt ein ganzes Spiel ohne Grafik, **immer vom Anfang**.
3. Das Spiel zählt Punkte: satte und zufriedene Siedler, Nahrung, Winterreserve, Forschung, neue Zeitalter,
   besiedelte Inseln, arbeitende Droiden, die Zukunftsstadt; Abzug für Hunger, Kälte und Tote.
4. Die Gewichte wandern dorthin, wo es mehr Punkte gab.

Die Spiele werden mit der Zeit länger (am Anfang 36 Spieltage, später bis 3000), damit die KI erst den Anfang
lernt und dann immer weiter kommt. Ein Spiel endet, wenn die Zukunftsstadt steht, wenn alle tot sind oder wenn
40 Tage lang nichts Neues entsteht.

Was fest im Spiel steht und nicht gelernt wird: **wo** ein Gebäude hinkommt, und **welches** Gebäude eine
Handlung trifft (z. B. welches leere Haus abgerissen wird). Gelernt wird, **was** die KI **wann** tut.

## Einstellungen

Am einfachsten auf der Seite: Knopf **Einstellungen** links. Dort hat jeder Wert ein eigenes Feld; **Übernehmen** prüft die Zahlen, speichert sie und lädt die Seite neu.

`lauf/einstellungen.json` (gilt ab dem nächsten Start des Trainings):

- `arbeiter`: Spiele gleichzeitig. 0 = Zahl der Prozessorkerne minus 1.
- `richtungen`: Zufallsrichtungen je Runde. 0 = so viele wie Arbeiter, mindestens 16. Mehr Richtungen lernen sicherer, aber langsamer.
- `stufen`: die Stufen des Lernens. Jede hat ein Ziel (`alter` = dieses Zeitalter erreichen, 1 = Antike; oder `ziel` = Zukunftsstadt) und eine Spiellänge `tage`. Erreichen `ziel_in_folge` (10) Prüfspiele in Folge das Ziel, zeigt die Statusseite die Stufe als geschafft. Ein Spiel endet, sobald das Ziel erreicht ist; jeder gesparte Tag bringt `tempo_punkte` (300) Punkte. Welche Stufe trainiert wird, wählst du oben in der Oberfläche. Die Gewichte bleiben beim Wechsel erhalten.
- `stillstand_tage`, `pruefung_alle`, `pruefung_wuerfel`, `rauschen`, `lernrate`.

Neu anfangen: den Ordner `lauf` löschen (oder umbenennen).

Mit einem alten Training weitermachen: den alten Ordner `lauf` in den neuen Ordner kopieren. Das Training lernt dann mit den bisherigen Gewichten weiter, in der Stufe, die du wählst.

## Ergebnis ins Spiel bringen

Die besten Gewichte stehen in `lauf/best.json`. Diese Datei ersetzt im Spiel `data/ki_brain.json`.
Schick sie Claude im Projekt, dann kommt sie in Version 3.

## Ordner

- `training/`: Trainingsprogramm (`trainer.py`), Oberfläche (`server.py`, `web/index.html`). Nur Python, keine Zusatzpakete.
- `spiel/`: das Spiel (Godot-Projekt, Version 3) mit der erweiterten KI (`scripts/autoload/ki_brain.gd`, `ki_acts.gd`).
- `lauf/`: Zustand und Ergebnisse des Trainings.
- `godot/`: entsteht beim ersten Start.

## Kleines neuronales Netz und Import (2026-11-16)

Das Paket **Insel-KI-Netz** ist dasselbe Training mit eingeschaltetem neuronalen Netz (in `lauf/einstellungen.json`: `"netz": true`).

- Die bisherige Tabelle aus Gewichten bleibt und rechnet wie vorher. Dazu kommt ein Netz mit zwei verdeckten Schichten (96 Eingänge, 24 Zellen, 24 Zellen, eine Korrektur je Handlung und Beruf, 5.528 Zahlen). Die Korrektur wird zum Wert der Tabelle addiert.
- Am Anfang ist die Korrektur 0. Die KI spielt dann genau wie die Tabelle allein, das Gelernte geht also nicht verloren.
- Gelernt wird mit demselben Verfahren, aber nur das Netz. Die übernommene Tabelle bleibt stehen (`"lerne_linear": true` lässt beide lernen). Ohne Import ist die Tabelle leer, dann lernen Tabelle und Netz zusammen.
- **Import:** Auf der Seite Status im Kasten „Gelerntes aus einem anderen Training übernehmen“ den Ordner des bisherigen Trainings nennen (eintippen, aus dem Finder ins Feld ziehen oder „Ordner wählen“). Das Programm sucht dort `best.json` (auch im Unterordner `lauf`). Übernommen wird beim nächsten Start. Das Zählen der Runden beginnt neu; der alte Stand bleibt als `zustand_vor_import_<Zeit>.json` liegen. Der andere Ordner wird nicht verändert.
- Der Import geht in beiden Paketen. Ein Stand mit Netz lässt sich später genauso in einen anderen Ordner übernehmen.
- Beide Pakete benutzen dieselbe Adresse im Browser, deshalb immer nur eines zur selben Zeit starten.

## Alles bleibt auf dem Laufwerk des Trainings (2026-11-17)

- Das Training schreibt nur noch in den eigenen Ordner, also auf das Laufwerk, auf dem du es entpackt hast (zum Beispiel ein externes Laufwerk): Arbeitsdateien der Spiele in `lauf/arbeit`, Godot-Einstellungen, Zwischenspeicher und Temp-Dateien in `lauf/arbeit_*`.
- Beim Start holt das Training alte Arbeitsordner früherer Läufe (`insel_ki_...`) aus dem Temp-Ordner des Mac-Systemlaufwerks nach `lauf/alte_temp_dateien`. Die kannst du danach löschen, sie werden nicht mehr gebraucht.
- Sind auf dem Laufwerk des Trainings weniger als 2 GB frei (`min_frei_gb` in `lauf/einstellungen.json`), hält das Training sauber an. Der Stand bis zur letzten fertigen Runde bleibt erhalten.
- Was das Programm nicht steuern kann: Wenn der Arbeitsspeicher knapp wird, lagert macOS selbst auf das Systemlaufwerk aus. Weniger gleichzeitige Spiele (`arbeiter` in `lauf/einstellungen.json`) verringern das.
