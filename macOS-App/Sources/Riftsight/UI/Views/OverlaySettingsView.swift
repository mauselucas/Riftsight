import RiftsightCore
import SwiftUI

/// Overlay configuration: live preview, per-widget toggles (policy-sensitive ones opt-in), hotkeys.
struct OverlaySettingsView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var previewModel: LiveOverlayModel?
    @ViewState private var pendingOptIn: OverlayWidget?

    var body: some View {
        @Bindable var settings = app.settings
        Page(spacing: 16) {
            PageHeader("Overlays", icon: "square.on.square.fill",
                       subtitle: "Transluzente In-Game-Widgets – gespeist ausschließlich aus der Live Client API.") {
                Toggle("Overlays aktiv", isOn: $settings.overlaysEnabled)
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12.5, weight: .medium))
            }
            preview
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Widgets", icon: "rectangle.3.group")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(OverlayWidget.allCases) { widget in
                            WidgetRow(widget: widget, enabled: app.settings.isEnabled(widget)) {
                                if widget.isPolicySensitive && !app.settings.isEnabled(widget) {
                                    pendingOptIn = widget
                                } else {
                                    app.settings.toggle(widget)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 16) {
                    hotkeys
                    tips
                }
                .frame(width: 300)
            }
        }
        .onAppear {
            if previewModel == nil {
                let model = LiveOverlayModel(app: app, preview: true)
                model.tabHeld = true
                previewModel = model
            }
        }
        .alert(item: $pendingOptIn) { widget in
            Alert(title: Text("\(widget.title) aktivieren?"),
                  message: Text("\(widget.policyNote ?? "")\n\nDu aktivierst diese Funktion auf eigenes Risiko."),
                  primaryButton: .destructive(Text("Trotzdem aktivieren")) { app.settings.toggle(widget) },
                  secondaryButton: .cancel(Text("Abbrechen")))
        }
    }

    private var preview: some View {
        @Bindable var windows = app.overlayWindows
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Vorschau", icon: "eye") {
                Toggle("Auf dem Bildschirm testen", isOn: $windows.previewOnScreen)
                    .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                GhostButton(title: "Positionen zurücksetzen", icon: "arrow.counterclockwise") { app.overlayWindows.resetPositions() }
            }
            GeometryReader { proxy in
                let scale = proxy.size.width / 1400
                if let previewModel {
                    OverlayGallery(model: previewModel)
                        .frame(width: 1400, height: 880)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: proxy.size.width, height: 880 * scale, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
            }
            .aspectRatio(1400 / 880, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        }
    }

    private var hotkeys: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Tastenkürzel", icon: "keyboard")
            ForEach(OverlayWindowManager.hotKeyHelp, id: \.0) { key, action in
                HStack(spacing: 10) {
                    HStack(spacing: 2) {
                        ForEach(Array(key).map(String.init), id: \.self) { KeyCap($0) }
                    }
                    .frame(width: 70, alignment: .leading)
                    Text(action).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 10) {
                KeyCap("Tab").frame(width: 70, alignment: .leading)
                Text("Halten zeigt Matchup-Guide & CS-Benchmark").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .cardStyle(padding: 16)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Hinweise", icon: "info.circle")
            Group {
                Text("Spiele im Fenstermodus „Randlos“, damit die Overlays über dem Spiel liegen.")
                Text("Positionen werden pro Spielmodus gespeichert (Kluft, ARAM, Arena).")
                Text("Overlays lesen nur die offizielle Live Client API (Port 2999) – kein Speicherzugriff, keine Eingaben.")
            }
            .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle(padding: 16)
    }
}

private struct WidgetRow: View {
    let widget: OverlayWidget
    let enabled: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: widget.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(enabled ? Theme.accent : Theme.textTertiary)
                .frame(width: 34, height: 34)
                .background(enabled ? Theme.accentSoft : Theme.field, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(widget.title).font(.system(size: 13, weight: .semibold))
                    if widget.visibility == .onTab { KeyCap("Tab") }
                }
                Text(widget.detail).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = widget.policyNote {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(get: { enabled }, set: { _ in toggle() }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(widget.isPolicySensitive ? Theme.gold.opacity(0.35) : Theme.border))
    }
}
