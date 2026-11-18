import RiftsightCore
import SwiftUI

/// Queue filter used by dashboard / account pages.
enum QueueFilter: String, CaseIterable, Hashable {
    case all, solo, flex, aram, normal

    var title: String {
        switch self {
        case .all: "Alle"
        case .solo: "Solo"
        case .flex: "Flex"
        case .aram: "ARAM"
        case .normal: "Normal"
        }
    }

    func matches(_ queueId: Int) -> Bool {
        switch self {
        case .all: true
        case .solo: queueId == 420
        case .flex: queueId == 440
        case .aram: queueId == 450 || queueId == 2400
        case .normal: queueId == 400 || queueId == 430 || queueId == 480 || queueId == 490
        }
    }
}

/// Per-match numbers for the local player.
struct MatchLine: Identifiable {
    let match: MatchRecord
    let me: ParticipantRecord
    let score: PlayerScore?

    var id: Int64 { match.gameId }
    var minutes: Double { match.durationMinutes }
    var kda: Double { me.kda }
    var csPerMin: Double { Double(me.cs) / minutes }
    var damagePerMin: Double { Double(me.damageToChampions) / minutes }
    var goldPerMin: Double { Double(me.gold) / minutes }
    var visionPerMin: Double { Double(me.visionScore) / minutes }
    var killParticipation: Double { score?.killParticipation ?? 0 }
    var damageShare: Double { score?.damageShare ?? 0 }
    var queueName: String { Queue(rawValue: match.queueId)?.displayName ?? match.gameMode.capitalized }

    static func lines(_ matches: [MatchRecord]) -> [MatchLine] {
        matches.compactMap { match in
            guard let me = match.local else { return nil }
            return MatchLine(match: match, me: me, score: PostGameAnalyzer.scores(for: match)[me.participantId])
        }
    }
}

/// One headline stat with history (for sparklines + "vs. dein Schnitt").
struct StatSeries: Identifiable {
    let id: String
    let title: String
    let values: [Double]
    let format: (Double) -> String
    var higherIsBetter = true

    /// Average of the last five games compared with the whole sample.
    var current: Double { values.suffix(5).average }
    var average: Double { values.average }
    var delta: Double { current - average }
}

extension Array where Element == Double {
    var average: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}

extension MatchRecord {
    var localWin: Bool { local?.win ?? false }
}

/// "+22 LP 1h ago Ranked Solo" row with champion, KDA and score ring – reference dashboard style.
struct MatchRow: View {
    @Environment(AppModel.self) private var app
    let line: MatchLine
    var compact = false

    var body: some View {
        let win = line.me.win
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let lp = line.match.lpChange {
                        Text(lp >= 0 ? "+\(lp)" : "−\(abs(lp))").font(.system(size: 15, weight: .bold).monospacedDigit())
                            + Text(" LP").font(.system(size: 10, weight: .bold))
                    } else {
                        Text(formatClock(Double(line.match.durationSeconds))).font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                    Text(line.match.creation.relativeShortGerman).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(line.match.lpChange == nil ? Theme.text : (win ? Color(hex: 0x8FB2FF) : Theme.loss))
                Text(line.queueName).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            ZStack(alignment: .bottomLeading) {
                ChampionIcon(id: line.me.championId, size: 36, radius: 18)
                RoleIcon(role: line.me.role, size: 10, color: .white)
                    .padding(2)
                    .background(Color.black.opacity(0.8), in: .rect(cornerRadius: 3))
                    .offset(x: -3, y: 3)
            }
            VStack(alignment: .trailing, spacing: 1) {
                KDAText(kills: line.me.kills, deaths: line.me.deaths, assists: line.me.assists, size: 13.5)
                Text(String(format: "%.1f KDA", locale: .riftsight, line.kda)).font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 74, alignment: .trailing)
            if let score = line.score {
                HStack(spacing: 6) {
                    VStack(spacing: 0) {
                        Text("\(score.score)").font(.system(size: 13, weight: .bold).monospacedDigit())
                        Text(score.badge).font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.textSecondary)
                    }
                    ScoreRing(score: score.score, size: 30, lineWidth: 3, showsValue: false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 7 : 9)
        .background(
            LinearGradient(colors: [(win ? Color(hex: 0x1C2650) : Color(hex: 0x3A1C26)).opacity(0.9),
                                    (win ? Color(hex: 0x161C33) : Color(hex: 0x24161C)).opacity(0.9)],
                           startPoint: .leading, endPoint: .trailing),
            in: .rect(cornerRadius: 9)
        )
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder((win ? Theme.accent : Theme.loss).opacity(0.18)))
        .contentShape(.rect)
        .onTapGesture {
            Task {
                await app.loadPostGame(line.match)
                app.router.go(.postGame)
            }
        }
        .help("Analyse nach dem Spiel öffnen")
    }
}

/// Stat tile with sparkline (reference: "KDA 4.2 +0.8").
struct StatTile: View {
    let series: StatSeries

    var body: some View {
        let positive = series.higherIsBetter ? series.delta >= 0 : series.delta <= 0
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(series.title).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Text(series.format(series.current)).font(.system(size: 21, weight: .semibold).monospacedDigit()).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: positive ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 11))
                    Text((series.delta >= 0 ? "+" : "−") + series.format(abs(series.delta)))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(positive ? Theme.win : Theme.loss)
            }
            Spacer(minLength: 0)
            Sparkline(values: Array(series.values.suffix(12)), color: positive ? Theme.text.opacity(0.85) : Theme.loss, lineWidth: 1.5)
                .frame(width: 62, height: 38)
                .padding(.bottom, 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x10141C).opacity(0.72), in: .rect(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.07)))
    }
}

func headlineSeries(_ lines: [MatchLine]) -> [StatSeries] {
    let ordered = lines.reversed() // oldest → newest
    func s(_ id: String, _ title: String, _ value: (MatchLine) -> Double, _ format: @escaping (Double) -> String, higher: Bool = true) -> StatSeries {
        StatSeries(id: id, title: title, values: ordered.map(value), format: format, higherIsBetter: higher)
    }
    return [
        s("kda", "KDA", \.kda, { String(format: "%.1f", locale: .riftsight, $0) }),
        s("score", "Score", { Double($0.score?.score ?? 0) }, { String(format: "%.1f", locale: .riftsight, $0) }),
        s("kp", "KP", \.killParticipation, { $0.percentString(digits: 0) }),
        s("csm", "CS/Min", \.csPerMin, { String(format: "%.1f", locale: .riftsight, $0) }),
        s("dpm", "DMG/Min", \.damagePerMin, { String(format: "%.0f", locale: .riftsight, $0) }),
        s("share", "DMG-Anteil", \.damageShare, { $0.percentString(digits: 0) }),
        s("gpm", "Gold/Min", \.goldPerMin, { String(format: "%.0f", locale: .riftsight, $0) }),
        s("vision", "Vision/Min", \.visionPerMin, { String(format: "%.1f", locale: .riftsight, $0) }),
    ]
}

/// Shared card shell for dashboard tiles with a title + arrow link.
struct LinkCard<Content: View>: View {
    var title: String?
    var icon: String?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
            .clipShape(.rect(cornerRadius: Theme.cornerRadius))
            .overlay(alignment: .bottomLeading) {
                if let title {
                    Button { action?() } label: {
                        HStack(spacing: 6) {
                            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                            Text(title).font(.system(size: 15, weight: .semibold))
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(16)
                    }
                    .buttonStyle(.plain)
                }
            }
    }
}
