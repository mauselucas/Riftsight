# Riftsight – Design-Notiz (2026-11-18)

Grundlage ist das Nutzer-Spec `gemini-code-1795025602528.md` (Ziel, Features, Design-Tokens, Ordnerstruktur).
Diese Notiz hält nur die **Abweichungen und Architekturentscheidungen** fest.

## Entscheidungen
- **Name:** Riftsight. Designsprache der DPM-Screenshots ja, aber kein DPM-/Rift-Companion-Name oder -Logo.
  Interne Typen heißen deshalb neutral (`Theme`, `Card` statt `DPMTheme`, `DPMCard`).
- **Build:** Nur Command Line Tools vorhanden → Swift Package (`swift build`) + `Scripts/build-app.sh`
  (erzeugt `Riftsight.app` mit Info.plist, ad-hoc signiert). `project.yml` für xcodegen liegt bei,
  sobald Xcode installiert ist.
- **Targets:** `RiftsightCore` (Library: Modelle, LCU, Live Client, Daten, Algorithmen, Recording; testbar),
  `Riftsight` (App: Design-System, Shell, Views, Overlays; MainActor-Default-Isolation),
  `RiftsightCoreTests` (Swift Testing).
- **Daten:** Pipeline-JSONs laut Schema in `docs/gemini-recherche-datenpipeline.md`. Bis die Pipeline
  mit Riot-Key läuft, liefert die App Beispiel-JSONs im exakten Format aus (`meta.sample = true`,
  in der UI als „Beispieldaten“ markiert). Die Beispiel-JSONs erzeugt `data-pipeline/sample.py`.
- **Demo-Modus:** Ohne laufenden Client/Match zeigen Champ Select, Post-Game und Overlays einen
  klar markierten Demo-Zustand, damit alle Views prüfbar sind.
- **Overlays:** `NSPanel` (nonactivating, borderless, `.screenSaver`-Level, `fullScreenAuxiliary`),
  Tab/Shop-Erkennung per `CGEventSource.keyState`-Polling, Interaktionsmodus per globalem
  Carbon-Hotkey (⌃⌥O), Positionen pro Spielmodus in UserDefaults.
- **Augment-Overlay:** Die Live Client API liefert keine angebotenen Augments → Erkennung per
  ScreenCaptureKit-Screenshot + Vision-OCR (nur Bildschirminhalt, kein Memory-Reading).
- **Cooldown-Tracker:** nur manuell per Klick gestartet; Ult-Rang wird aus dem Level geschätzt (≈).
- **Visuelle Prüfung:** `Riftsight --snapshot <ordner>` rendert jede Route offscreen als PNG.
