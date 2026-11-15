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

Beenden: in der Oberfläche „Anhalten“ drücken, dann das Terminal-Fenster schließen.
Beim nächsten Start geht das Training dort weiter, wo es war (Ordner `lauf`).

Der Mac braucht Python 3. Fehlt es, sagt die Startdatei, was zu tun ist (`xcode-select --install`).

## Die Oberfläche

- **Status**: Runde, Spiellänge, wie weit die KI bisher kam, welche Spiele gerade laufen (Spieltag, Siedler,
  Zeitalter, Forschung), Bilder zum Verlauf, alle Prüfungen.
- **Was die KI gelernt hat**: ein ganzes Prüfspiel zum Ansehen (jede Entscheidung der KI mit Spieltag),
  der Vergleich über die Prüfungen und die Gewichte in Worten („eher, wenn ...“).
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

`lauf/einstellungen.json` (gilt ab dem nächsten Start des Trainings):

- `arbeiter`: Spiele gleichzeitig. 0 = Zahl der Prozessorkerne minus 1.
- `richtungen`: Zufallsrichtungen je Runde. 0 = so viele wie Arbeiter, mindestens 8. Mehr Richtungen lernen sicherer, aber langsamer.
- `start_tage`, `wachstum`, `runden_je_stufe`, `max_tage`: wie die Spiele länger werden.
- `stillstand_tage`, `pruefung_alle`, `pruefung_wuerfel`, `rauschen`, `lernrate`.

Neu anfangen: den Ordner `lauf` löschen (oder umbenennen).

## Ergebnis ins Spiel bringen

Die besten Gewichte stehen in `lauf/best.json`. Diese Datei ersetzt im Spiel `data/ki_brain.json`.
Schick sie Claude im Projekt, dann kommt sie in Version 3.

## Ordner

- `training/`: Trainingsprogramm (`trainer.py`), Oberfläche (`server.py`, `web/index.html`). Nur Python, keine Zusatzpakete.
- `spiel/`: das Spiel (Godot-Projekt, Version 3) mit der erweiterten KI (`scripts/autoload/ki_brain.gd`, `ki_acts.gd`).
- `lauf/`: Zustand und Ergebnisse des Trainings.
- `godot/`: entsteht beim ersten Start.
