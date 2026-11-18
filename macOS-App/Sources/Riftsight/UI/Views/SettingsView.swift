import RiftsightCore
import SwiftUI

/// Riot's required legal boilerplate (must appear in any public product).
let riotLegalNotice = "Riftsight isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games, and all associated properties are trademarks or registered trademarks of Riot Games, Inc."

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var pipelineDraft = ""
    @ViewState private var reloading = false
    @ViewState private var replaySeconds = 90.0
    @ViewState private var quota = 20.0

    var body: some View {
        @Bindable var settings = app.settings
        Page(spacing: 16) {
            PageHeader("Einstellungen", icon: "gearshape.fill")
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    section("Verbindung", icon: "cable.connector") {
                        HStack(spacing: 8) {
                            Circle().fill(app.lcu.isConnected ? Theme.win : Theme.textTertiary).frame(width: 8, height: 8)
                            Text(app.lcu.isConnected ? "Mit dem League-Client verbunden (\(app.lcu.region))" : "League-Client nicht gefunden – Riftsight verbindet sich automatisch, sobald er läuft.")
                                .font(.system(size: 12.5))
                        }
                        settingToggle("Automatisch zu Champ Select, Ladebildschirm und Post-Game wechseln", isOn: $settings.autoNavigate)
                        settingToggle("Demo-Daten anzeigen, auch wenn der Client verbunden ist", isOn: $settings.forceDemo)
                    }
                    section("Daten-Pipeline", icon: "server.rack") {
                        Text("Basis-URL der täglich erzeugten JSON-Dateien (z. B. GitHub Pages oder Releases). Leer = mitgelieferte Beispieldaten.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 8) {
                            TextField("https://…/riftsight-data/", text: $pipelineDraft)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { apply() }
                            AccentButton(title: reloading ? "Lädt …" : "Übernehmen", icon: "arrow.clockwise") { apply() }
                                .disabled(reloading)
                        }
                        HStack(spacing: 8) {
                            if app.staticData.usingSampleData { SampleDataBadge() }
                            Text(dataStatus).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    section("Aufnahme", icon: "record.circle") {
                        HStack(spacing: 8) {
                            Image(systemName: ScreenCaptureRecorder.hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(ScreenCaptureRecorder.hasPermission ? Theme.win : Theme.gold)
                            Text(ScreenCaptureRecorder.hasPermission ? "Bildschirmaufnahme erlaubt" : "Bildschirmaufnahme-Berechtigung fehlt")
                                .font(.system(size: 12.5))
                            Spacer()
                            if !ScreenCaptureRecorder.hasPermission {
                                GhostButton(title: "Berechtigung anfragen", icon: "lock.open") { ScreenCaptureRecorder.requestPermission() }
                            }
                        }
                        settingToggle("Ganze Spiele aufnehmen", isOn: $settings.recordGames)
                        settingToggle("Highlights automatisch als Clips speichern (Multikills, Baron, Drache, Ace)", isOn: $settings.autoClips)
                        HStack {
                            Text("Instant Replay (⌃⌥R)").font(.system(size: 12.5))
                            Spacer()
                            Picker("", selection: $replaySeconds) {
                                ForEach([30.0, 60, 90, 120], id: \.self) { Text("\(Int($0)) s").tag($0) }
                            }
                            .labelsHidden().frame(width: 90)
                            .onChange(of: replaySeconds) { _, value in app.recorder.replaySeconds = value }
                        }
                        HStack {
                            Text("Speicherlimit").font(.system(size: 12.5))
                            Slider(value: $quota, in: 5...200)
                                .onChange(of: quota) { _, value in app.library.storageQuotaGB = value.rounded() }
                            Text("\(Int(quota)) GB").font(.system(size: 12).monospacedDigit()).frame(width: 52, alignment: .trailing)
                        }
                        Button("Aufnahme-Ordner im Finder öffnen") {
                            NSWorkspace.shared.open(app.library.clipsDirectory.deletingLastPathComponent())
                        }
                        .buttonStyle(.link).font(.system(size: 12))
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    section("Fairplay & Datenschutz", icon: "checkmark.shield") {
                        bullet("Nur offizielle Schnittstellen: League-Client (LCU) und Live Client API auf diesem Mac.")
                        bullet("Kein Speicherzugriff, keine Code-Injection, keine automatisierten Eingaben – Vanguard-konform.")
                        bullet("Kein Riot-API-Key in der App: Statistiken kommen aus der eigenen Daten-Pipeline.")
                        bullet("Änderungen im Client (Runen, Spells, Hover, Zuschauen) passieren nur nach deinem Klick.")
                        bullet("Deine Spiele, Aufnahmen und Konten bleiben lokal auf diesem Mac.")
                    }
                    section("Rechtliches", icon: "doc.text") {
                        Text(riotLegalNotice)
                            .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Divider().overlay(Theme.border)
                        credit("Pro-Spieler-Zuordnung", "Leaguepedia (lol.fandom.com), lizenziert unter CC BY-SA 3.0 – Daten wurden für Riftsight aufbereitet.")
                        credit("Spieldaten & Grafiken", "CommunityDragon und Riot Data Dragon.")
                        credit("Rollen-Wahrscheinlichkeiten", "Meraki Analytics.")
                    }
                    section("Über", icon: "info.circle") {
                        LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                        LabeledContent("Spieldaten-Patch", value: app.gameData.patch)
                        LabeledContent("Statistik-Patch", value: app.staticData.dataPatch ?? "–")
                        LabeledContent("Gespeicherte Matchup-Guides", value: "\(app.guides.count)")
                        Button("Protokoll öffnen") { app.router.go(.debug) }.buttonStyle(.link).font(.system(size: 12))
                    }
                }
                .frame(width: 400)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear {
            pipelineDraft = app.settings.pipelineURL
            replaySeconds = app.recorder.replaySeconds
            quota = app.library.storageQuotaGB
        }
    }

    private var dataStatus: String {
        guard let loaded = app.staticData.lastLoaded else { return "Noch nicht geladen" }
        return "Patch \(app.staticData.dataPatch ?? "–") · geladen \(loaded.relativeGerman)"
    }

    private func apply() {
        app.settings.pipelineURL = pipelineDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        reloading = true
        Task {
            await app.staticData.load()
            reloading = false
            app.toast = app.staticData.usingSampleData ? "Pipeline nicht erreichbar – Beispieldaten aktiv" : "Statistiken aktualisiert"
        }
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeader(title, icon: icon)
            content()
        }
        .font(.system(size: 12.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.system(size: 12.5)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.win).padding(.top, 3)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func credit(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Protokoll

struct DebugLogView: View {
    @ViewState private var errorsOnly = false
    @ViewState private var category = "ALL"

    var body: some View {
        let all = DebugLog.shared.entries
        let entries = all.reversed().filter { (!errorsOnly || $0.isError) && (category == "ALL" || $0.category == category) }
        Page(spacing: 14) {
            PageHeader("Protokoll", icon: "ladybug.fill", subtitle: "Verbindungen, Datenabrufe und Fehler dieser Sitzung.") {
                GhostButton(title: "Kopieren", icon: "doc.on.doc") {
                    let text = entries.map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.category)] \($0.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            HStack(spacing: 10) {
                SegmentedPills(options: [(false, "Alle"), (true, "Nur Fehler")], selection: $errorsOnly, compact: true)
                DropdownChip(label: "Bereich", options: [("ALL", "Alle")] + Set(all.map(\.category)).sorted().map { ($0, $0) }, selection: $category)
                Spacer()
                Text("\(entries.count) Einträge").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            if entries.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "Keine Einträge", message: "Alles ruhig.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(entry.date.formatted(date: .omitted, time: .standard)).foregroundStyle(Theme.textTertiary)
                            Text(entry.category.uppercased()).font(.system(size: 10, weight: .bold))
                                .foregroundStyle(entry.isError ? Theme.loss : Theme.accent)
                                .frame(width: 70, alignment: .leading)
                            Text(entry.message).foregroundStyle(entry.isError ? Theme.loss : Theme.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 11.5, design: .monospaced))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                    }
                }
                .padding(.vertical, 8)
                .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
            }
        }
    }
}
