# Verbrauch – Menüleisten-App

**Zweck:** Zeigt neben dem Batteriesymbol, welche Programme Energie, CPU und RAM verbrauchen,
und erlaubt, sie direkt aus dem Menü zu beenden. Ersatz für Apples Batteriemenü, das nur
„Erheblicher Energieverbrauch“ ohne Zahlen zeigt. Ins Apple-Menü selbst kann man nichts einbauen.

**Bauen/Installieren:** `./build.sh` – baut Universal-Binary, Icon, signiert ad hoc, beendet die
laufende Instanz, kopiert nach `/Applications` und startet neu. Ein Swift-File, kein Xcode-Projekt.

**Prüfen:** Menü per `cliclick c:<x+10>,14` öffnen (x aus
`osascript -e 'tell application "System Events" to tell process "Verbrauch" to get position of menu bar item 1 of menu bar 1'`),
dann `screencapture -x -R …`. AX-Lesen der Menüeinträge nach dem Klick hängt (Menü ist modal) – nur Screenshot.
Beenden-Test mit TextEdit: `open -a TextEdit`, Zeile im Screenshot suchen, `cliclick m:` auf die Zeile,
Untermenü liegt links vom Menü, „Beenden“ ca. 35 pt unter der Zeile.

**Messung:** `top -l 2 -s 1 -stats pid,cpu,mem,power,uid,ppid,command` – zweiter Durchlauf zählt
(der erste hat keine CPU-Differenz). `power` ist dieselbe Energiespalte wie in der Aktivitätsanzeige.

## Fallen
- **Menü nie umbauen, solange es offen ist.** Sonst sortieren sich Zeilen unter dem Mauszeiger um
  und man beendet das falsche Programm (so fast Claude erwischt, 07.11.2026). `menuOpen` prüfen.
- Helper-Bundles (`Claude Helper.app` in `Claude.app`) tauchen in `runningApplications` auf: beim
  Zuordnen gewinnt das **kürzeste** Bundle-Präfix, sonst landen Helfer als eigene Programme.
- Eigener `top`-Prozess über `ppid == eigene PID` ausblenden, sonst steht „top“ in der Liste.
- `pid 0` (kernel_task) hat keinen Pfad: Name aus der top-COMMAND-Spalte (steht zuletzt in -stats,
  weil er Leerzeichen enthalten kann).
- Titel in der Leiste: Summe aller Prozess-CPU durch Kernzahl, sonst stehen 93 % da.
