import RiftsightCore
import SwiftUI

/// Overlay configuration: live preview, per-widget toggles (policy-sensitive ones opt-in), hotkeys.
struct OverlaySettingsView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var previewModel: LiveOverlayModel?
    @ViewState private var pendingOptIn: OverlayWidget?
    @ViewState private var pendingVisibility: OverlayVisibility = .always

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
                            WidgetRow(widget: widget,
                                      visibility: app.settings.visibility(widget),
                                      scale: app.settings.scale(widget),
                                      setVisibility: { mode in
                                          if widget.isPolicySensitive && app.settings.visibility(widget) == .off && mode != .off {
                                              pendingVisibility = mode
                                              pendingOptIn = widget
                                          } else {
                                              app.settings.setVisibility(mode, for: widget)
                                          }
                                      },
                                      setScale: { app.settings.setScale($0, for: widget) })
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
                  primaryButton: .destructive(Text("Trotzdem aktivieren")) { app.settings.setVisibility(pendingVisibility, for: widget) },
                  secondaryButton: .cancel(Text("Abbrechen")))
        }
    }

    private var preview: some View {
        @Bindable var windows = app.overlayWindows
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Vorschau", icon: "eye") {
                Toggle("Auf dem Bildschirm testen", isOn: $windows.previewOnScreen)
                    .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                GhostButton(title: "Layout zurücksetzen", icon: "arrow.counterclockwise") {
                    app.settings.resetOverlayLayout()
                    app.overlayWindows.resetPositions()
                }
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
                Text("Halten zeigt alle Overlays mit „Nur bei Tab“").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .cardStyle(padding: 16)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Hinweise", icon: "info.circle")
            Group {
                Text("Overlays einfach mit der Maus ziehen, um sie zu verschieben – auch mitten im Spiel. Das X blendet ein Overlay aus.")
                Text("Funktioniert im Fenstermodus und „Randlos“. Im echten Vollbild kann macOS nichts über das Spiel legen.")
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
    let visibility: OverlayVisibility
    let scale: Double
    let setVisibility: (OverlayVisibility) -> Void
    let setScale: (Double) -> Void

    var body: some View {
        let enabled = visibility != .off
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: widget.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(enabled ? Theme.accent : Theme.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(enabled ? Theme.accentSoft : Theme.field, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(widget.title).font(.system(size: 13, weight: .semibold))
                    Text(widget.detail).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = widget.policyNote {
                        Label(note, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Picker("", selection: Binding(get: { visibility }, set: setVisibility)) {
                    ForEach(OverlayVisibility.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 210)
                Spacer(minLength: 4)
                Image(systemName: "textformat.size.smaller").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                Slider(value: Binding(get: { scale }, set: setScale), in: 0.6...1.6)
                    .controlSize(.mini).frame(maxWidth: 110)
                    .disabled(!enabled)
                Text("\(Int((scale * 100).rounded())) %")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(widget.isPolicySensitive ? Theme.gold.opacity(0.35) : Theme.border))
        .opacity(enabled ? 1 : 0.75)
    }
}
