import RiftsightCore
import SwiftUI

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var fill: Color = Theme.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: padding, fill: fill)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var icon: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, icon: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).foregroundStyle(Theme.textSecondary)
            }
            Text(title).font(Typo.headline).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// Page header: big icon + title, optional subtitle blurb and trailing controls.
struct PageHeader<Trailing: View>: View {
    let title: String
    var icon: String?
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, icon: String? = nil, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.text)
                }
                Text(title).font(Typo.pageTitle).foregroundStyle(Theme.text)
            }
            if let subtitle {
                Rectangle().fill(Theme.border).frame(width: 1, height: 34)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: 300, alignment: .leading)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

// MARK: - Badges & pills

struct TierBadge: View {
    let tier: Tier
    var size: CGFloat = 18

    var body: some View {
        Text(tier.rawValue)
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(Theme.tierColor(tier))
            .shadow(color: Theme.tierColor(tier).opacity(0.35), radius: 6)
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var filled = false
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(Typo.micro)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(filled ? .white : color)
        .background(filled ? color : color.opacity(0.16), in: .rect(cornerRadius: 5))
    }
}

/// "+0.8" with a round up/down marker, like the KPI tiles.
struct DeltaPill: View {
    let value: Double
    var format: Format = .number(decimals: 1)
    var invert = false

    enum Format {
        case number(decimals: Int)
        case percent
        case integer
    }

    var body: some View {
        let good = invert ? value < 0 : value > 0
        let neutral = abs(value) < 0.0001
        let color = neutral ? Theme.textSecondary : (good ? Theme.win : Theme.loss)
        HStack(spacing: 4) {
            Image(systemName: neutral ? "minus" : (value > 0 ? "arrow.up" : "arrow.down"))
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Theme.window)
                .frame(width: 12, height: 12)
                .background(color, in: .circle)
            Text(text).font(Typo.number(11, .semibold)).foregroundStyle(color)
        }
    }

    private var text: String {
        switch format {
        case .number(let d): (value >= 0 ? "+" : "") + String(format: "%.\(d)f", locale: .riftsight, value)
        case .percent: value.signedPercentString()
        case .integer: (value >= 0 ? "+" : "") + Int(value.rounded()).groupedString
        }
    }
}

struct SampleDataBadge: View {
    var body: some View {
        Pill(text: "Beispieldaten", color: Theme.gold, icon: "flask")
            .help("Bis die Daten-Pipeline läuft, zeigt Riftsight synthetische Beispielwerte (meta.sample = true).")
    }
}

struct KDAText: View {
    let kills: Int
    let deaths: Int
    let assists: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 3) {
            Text("\(kills)")
            Text("/").foregroundStyle(Theme.textTertiary)
            Text("\(deaths)").foregroundStyle(Theme.loss)
            Text("/").foregroundStyle(Theme.textTertiary)
            Text("\(assists)")
        }
        .font(Typo.number(size, .semibold))
        .foregroundStyle(Theme.text)
    }
}

// MARK: - Controls

/// Segmented control in the reference style (pill track, accent selection).
struct SegmentedPills<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let selected = value == selection
                Button {
                    withAnimation(.snappy(duration: 0.18)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: compact ? 11 : 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
                        .padding(.horizontal, compact ? 10 : 16)
                        .padding(.vertical, compact ? 5 : 7)
                        .background(selected ? Theme.accent.opacity(0.85) : .clear, in: .rect(cornerRadius: 6))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.field, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
    }
}

/// Separate boxed buttons (Ranked / Aram / Arena / Duo).
struct BoxedTabs<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { value, label in
                let selected = value == selection
                Button { selection = value } label: {
                    Text(label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(selected ? Theme.accent.opacity(0.35) : Theme.card, in: .rect(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Theme.accent.opacity(0.6) : Theme.border))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .foregroundStyle(Theme.text)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .frame(width: width)
        .background(Theme.field, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
    }
}

/// "Group  Acquisition year ▾" style dropdown.
struct DropdownChip<Value: Hashable>: View {
    var label: String?
    let options: [(Value, String)]
    @Binding var selection: Value
    var icon: String?

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { value, title in
                Button {
                    selection = value
                } label: {
                    if value == selection { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.textSecondary) }
                if let label { Text(label).foregroundStyle(Theme.textTertiary) }
                Text(options.first { $0.0 == selection }?.1 ?? "–").foregroundStyle(Theme.text)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(Theme.field, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct AccentButton: View {
    let title: String
    var icon: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.accent.gradient, in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

struct GhostButton: View {
    let title: String
    var icon: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let systemName: String
    var help: String = ""
    var size: CGFloat = 28
    var action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(hovering ? Theme.text : Theme.textSecondary)
                .frame(width: size, height: size)
                .background(hovering ? Theme.hover : .clear, in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct ProgressBar: View {
    let value: Double
    var color: Color = Theme.accent
    var track: Color = Theme.border
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(height, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

struct Checkbox: View {
    let isOn: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(isOn ? Theme.accent : Theme.textTertiary.opacity(0.6), lineWidth: 1.2)
            .background(isOn ? Theme.accent : .clear, in: .rect(cornerRadius: 4))
            .overlay {
                if isOn { Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(.white) }
            }
            .frame(width: 15, height: 15)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.textTertiary)
            Text(title).font(Typo.headline).foregroundStyle(Theme.text)
            Text(message).font(Typo.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

/// Small labelled value (e.g. "Bans" row, rune stat).
struct LabeledValue: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Typo.number(16, .bold)).foregroundStyle(valueColor)
            Text(label).font(Typo.caption).foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Formatting helpers

extension Date {
    /// "vor 12 Min.", "vor 3 Std.", "gestern" …
    var relativeGerman: String {
        let seconds = Date().timeIntervalSince(self)
        switch seconds {
        case ..<60: return "gerade eben"
        case ..<3600: return "vor \(Int(seconds / 60)) Min."
        case ..<86_400: return "vor \(Int(seconds / 3600)) Std."
        case ..<172_800: return "gestern"
        default: return "vor \(Int(seconds / 86_400)) Tagen"
        }
    }

    /// Compact: "55 Min.", "3 Std.", "2 T."
    var relativeShortGerman: String {
        let seconds = Date().timeIntervalSince(self)
        switch seconds {
        case ..<60: return "jetzt"
        case ..<3600: return "\(Int(seconds / 60)) Min."
        case ..<86_400: return "\(Int(seconds / 3600)) Std."
        default: return "\(Int(seconds / 86_400)) T."
        }
    }
}
