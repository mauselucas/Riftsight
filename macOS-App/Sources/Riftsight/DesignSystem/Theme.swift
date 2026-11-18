import RiftsightCore
import SwiftUI

/// Riftsight design tokens: a dark, card-based look with an indigo accent.
enum Theme {
    // Surfaces
    static let window = Color(hex: 0x0B0D12)
    static let sidebar = Color(hex: 0x0D0F14)
    static let canvas = Color(hex: 0x12151C)
    static let card = Color(hex: 0x181C25)
    static let cardRaised = Color(hex: 0x1D222D)
    static let border = Color(hex: 0x232836)
    static let hover = Color(hex: 0x1F2430)
    static let field = Color(hex: 0x151922)

    // Text
    static let text = Color(hex: 0xECEEF4)
    static let textSecondary = Color(hex: 0xA3A9B8)
    static let textTertiary = Color(hex: 0x6B7183)

    // Accent & semantic
    static let accent = Color(hex: 0x6C7BFF)
    static let accentSoft = Color(hex: 0x6C7BFF).opacity(0.18)
    static let win = Color(hex: 0x2ECC71)
    static let winBackground = Color(hex: 0x142E27)
    static let loss = Color(hex: 0xFF6B6B)
    static let lossBackground = Color(hex: 0x2E171B)
    static let gold = Color(hex: 0xF5B041)
    static let blueSide = Color(hex: 0x4A90E2)
    static let blueSideBar = Color(hex: 0x6C7BFF)
    static let redSide = Color(hex: 0xE74C3C)
    static let redSideBar = Color(hex: 0xFF5A5F)
    static let overlayGlass = Color(hex: 0x141822).opacity(0.86)

    static let cornerRadius: CGFloat = 12
    static let smallRadius: CGFloat = 8

    static func tierColor(_ tier: Tier) -> Color {
        switch tier {
        case .sPlus: Color(hex: 0xF5B041)
        case .s: Color(hex: 0xA569BD)
        case .a: Color(hex: 0x5DADE2)
        case .b: Color(hex: 0x2ECC71)
        case .c: Color(hex: 0xE67E22)
        case .d: Color(hex: 0xE74C3C)
        }
    }

    static func rarityColor(_ rarity: SkinRarity) -> Color {
        switch rarity {
        case .standard: Color(hex: 0x9AA3B5)
        case .rare: Color(hex: 0x5DADE2)
        case .epic: Color(hex: 0x3FB6E8)
        case .legendary: Color(hex: 0xE67E22)
        case .mythic: Color(hex: 0xA569BD)
        case .ultimate: Color(hex: 0xF5B041)
        case .exalted: Color(hex: 0xEC4F8C)
        case .transcendent: Color(hex: 0x2BD9B5)
        }
    }

    static func rankColor(_ tier: RankTier) -> Color {
        switch tier {
        case .unranked: textTertiary
        case .iron: Color(hex: 0x8C7B75)
        case .bronze: Color(hex: 0xB07A57)
        case .silver: Color(hex: 0xAAB7C4)
        case .gold: Color(hex: 0xE5B85C)
        case .platinum: Color(hex: 0x4FC6B8)
        case .emerald: Color(hex: 0x2ECC71)
        case .diamond: Color(hex: 0x6C9BFF)
        case .master: Color(hex: 0xB76DE0)
        case .grandmaster: Color(hex: 0xFF5A5F)
        case .challenger: Color(hex: 0x5EC8F2)
        }
    }

    /// Green ≥ +0.5 %, red ≤ −0.5 %, neutral in between.
    static func deltaColor(_ delta: Double, threshold: Double = 0.0005) -> Color {
        delta > threshold ? win : delta < -threshold ? loss : textSecondary
    }

    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: gold
        case 60..<80: Color(hex: 0x7FD8F0)
        case 45..<60: Color(hex: 0x9AA3B5)
        default: Color(hex: 0xF0A04B)
        }
    }

    static func winrateColor(_ winrate: Double) -> Color {
        winrate >= 0.515 ? win : winrate <= 0.485 ? loss : text
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Typography scale (SF Pro, tightened like the reference UI).
enum Typo {
    static let pageTitle = Font.system(size: 30, weight: .bold)
    static let title = Font.system(size: 20, weight: .bold)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)
    static let micro = Font.system(size: 10, weight: .semibold)
    static let sectionLabel = Font.system(size: 10.5, weight: .semibold)
    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

extension View {
    /// Standard card surface.
    func cardStyle(padding: CGFloat = 14, radius: CGFloat = Theme.cornerRadius, fill: Color = Theme.card) -> some View {
        self.padding(padding)
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.border, lineWidth: 1))
    }

    func sectionLabelStyle() -> some View {
        self.font(Typo.sectionLabel).tracking(0.8).foregroundStyle(Theme.textTertiary).textCase(.uppercase)
    }
}
