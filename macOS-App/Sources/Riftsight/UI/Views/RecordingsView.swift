import AVKit
import RiftsightCore
import SwiftUI

/// Unified card model for real recordings and demo clips.
struct ClipCardModel: Identifiable, Hashable {
    let id: String
    let title: String
    let championId: Int?
    let skinNum: Int
    let kills: Int?
    let deaths: Int?
    let assists: Int?
    let queue: String
    let date: Date
    let duration: Double
    let isFullGame: Bool
    var favorite: Bool
    let fileURL: URL?
    let thumbnail: URL?
    let markers: [TimelineMarker]

    var kda: Double? {
        guard let k = kills, let d = deaths, let a = assists else { return nil }
        return Double(k + a) / Double(max(1, d))
    }
}

struct RecordingsView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var query = ""
    @ViewState private var kind = "all"
    @ViewState private var champion = 0
    @ViewState private var favoritesOnly = false
    @ViewState private var grouping = "day"
    @ViewState private var playing: ClipCardModel?

    var body: some View {
        let all = cards
        let shown = filter(all)
        let groups = group(shown)
        Page(spacing: 14) {
            HStack(spacing: 10) {
                Text("Aufnahmen").font(.system(size: 22, weight: .bold))
                if usesDemo { Pill(text: "Demo-Clips", color: Theme.gold, icon: "film") }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text("\(all.count)").font(.system(size: 12.5, weight: .semibold))
                    Text("Clips").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                }
                Text(storageLabel).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                IconButton(systemName: "folder", help: "Ordner im Finder öffnen") {
                    NSWorkspace.shared.open(app.library.clipsDirectory.deletingLastPathComponent())
                }
                IconButton(systemName: "slider.horizontal.3", help: "Aufnahme-Einstellungen") { app.router.go(.settings) }
            }
            HStack(spacing: 10) {
                SearchField(text: $query, placeholder: "Clips durchsuchen", width: 220)
                SegmentedPills(options: [("all", "Alle"), ("clips", "Clips"), ("full", "Ganze Spiele")], selection: $kind, compact: true)
                DropdownChip(options: championOptions(all), selection: $champion)
                Button { favoritesOnly.toggle() } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star").font(.system(size: 12))
                        .foregroundStyle(favoritesOnly ? Theme.gold : Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.field, in: .rect(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                }
                .buttonStyle(.plain)
                .help("Nur Favoriten")
                Spacer()
                Text("\(shown.count) Clips").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                DropdownChip(options: [("day", "Tag"), ("champion", "Champion"), ("none", "Keine Gruppierung")], selection: $grouping)
            }
            HStack(spacing: 14) {
                Text("⌃⌥R speichert die letzten \(Int(app.recorder.replaySeconds)) s als Instant Replay").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                if !ScreenCaptureRecorder.hasPermission {
                    Label("Bildschirmaufnahme-Berechtigung fehlt", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.gold)
                }
            }

            if shown.isEmpty {
                EmptyStateView(icon: "film.stack", title: "Keine Clips", message: "Aktiviere die Aufnahme in den Einstellungen – Highlights werden dann automatisch gespeichert.")
            }
            ForEach(groups, id: \.title) { group in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.title).font(.system(size: 15, weight: .semibold))
                    Text("\(group.items.count) Clips").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(group.items) { clip in
                        ClipCard(clip: clip) { playing = clip }
                    }
                }
            }
        }
        .sheet(item: $playing) { clip in
            ClipPlayerSheet(clip: clip).environment(app)
        }
        .task { app.library.reload() }
    }

    private var usesDemo: Bool { app.library.items.isEmpty }

    private var storageLabel: String {
        let used = usesDemo ? 2.5 : Double(app.library.usedBytes) / 1_073_741_824
        return String(format: "%.1f GB / %.1f GB", locale: .riftsight, used, app.library.storageQuotaGB)
    }

    private var cards: [ClipCardModel] {
        if usesDemo {
            return DemoData.clips.map {
                ClipCardModel(id: $0.id, title: $0.title, championId: $0.championId, skinNum: $0.skinNum, kills: $0.kills, deaths: $0.deaths,
                              assists: $0.assists, queue: $0.queue, date: $0.date, duration: $0.duration, isFullGame: $0.isFullGame,
                              favorite: $0.favorite, fileURL: nil, thumbnail: nil, markers: [])
            }
        }
        return app.library.items.map { item in
            let m = item.metadata
            return ClipCardModel(id: item.url.path, title: m.title, championId: m.championId, skinNum: 0, kills: m.kills, deaths: m.deaths,
                                 assists: m.assists, queue: m.queueName ?? "", date: m.createdAt, duration: m.duration,
                                 isFullGame: m.kind == .fullGame, favorite: m.favorite, fileURL: item.url, thumbnail: item.thumbnail,
                                 markers: m.markers)
        }
    }

    private func championOptions(_ all: [ClipCardModel]) -> [(Int, String)] {
        let ids = Set(all.compactMap(\.championId)).sorted { app.gameData.championName($0) < app.gameData.championName($1) }
        return [(0, "Champion")] + ids.map { ($0, app.gameData.championName($0)) }
    }

    private func filter(_ all: [ClipCardModel]) -> [ClipCardModel] {
        all.filter { clip in
            (kind == "all" || (kind == "full") == clip.isFullGame)
                && (champion == 0 || clip.championId == champion)
                && (!favoritesOnly || clip.favorite)
                && (query.isEmpty || clip.title.localizedCaseInsensitiveContains(query) || clip.queue.localizedCaseInsensitiveContains(query))
        }
        .sorted { $0.date > $1.date }
    }

    private func group(_ clips: [ClipCardModel]) -> [(title: String, items: [ClipCardModel])] {
        switch grouping {
        case "champion":
            let grouped = Dictionary(grouping: clips) { $0.championId ?? 0 }
            return grouped.map { (app.gameData.championName($0.key), $0.value) }.sorted { $0.items.count > $1.items.count }
        case "none":
            return clips.isEmpty ? [] : [("Alle Clips", clips)]
        default:
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: clips) { calendar.startOfDay(for: $0.date) }
            return grouped.keys.sorted(by: >).map { day in
                let title = calendar.isDateInToday(day) ? "Heute" : calendar.isDateInYesterday(day) ? "Gestern"
                    : day.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "de_DE")))
                return (title, grouped[day] ?? [])
            }
        }
    }
}

private struct ClipCard: View {
    @Environment(AppModel.self) private var app
    let clip: ClipCardModel
    let play: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let thumb = clip.thumbnail {
                            RemoteImage(thumb)
                        } else if let champ = clip.championId {
                            SplashArt(championId: champ, skinNum: clip.skinNum, style: .centered)
                        } else {
                            Theme.cardRaised
                        }
                    }
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                    if hovering {
                        Image(systemName: "play.circle.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.92))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    HStack(spacing: 6) {
                        Text(clip.date.relativeGerman)
                        Rectangle().fill(.white.opacity(0.4)).frame(width: 1, height: 10)
                        Text(formatClock(clip.duration)).monospacedDigit()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(8)
                }
                .overlay(alignment: .topLeading) {
                    if clip.isFullGame {
                        Text("GANZES SPIEL").font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.accent, in: .rect(cornerRadius: 4)).padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if clip.favorite { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Theme.gold).padding(9) }
                }
                HStack(spacing: 9) {
                    ChampionIcon(id: clip.championId ?? 0, size: 30, radius: 15)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clip.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 6) {
                            if let k = clip.kills, let d = clip.deaths, let a = clip.assists {
                                Text("\(k) / \(d) / \(a)").font(.system(size: 11, weight: .medium))
                                if let kda = clip.kda {
                                    Text(String(format: "%.1f", locale: .riftsight, kda)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x9DB0FF))
                                    + Text(" KDA").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Text(clip.queue).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                        }
                    }
                }
                .padding(10)
            }
            .background(Theme.card, in: .rect(cornerRadius: 10))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(hovering ? Theme.accent.opacity(0.6) : Theme.border))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            if let url = clip.fileURL {
                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                if let item = app.library.items.first(where: { $0.url == url }) {
                    Button(item.metadata.favorite ? "Favorit entfernen" : "Als Favorit markieren") { app.library.toggleFavorite(item) }
                    Divider()
                    Button("In den Papierkorb legen", role: .destructive) { app.library.delete(item) }
                }
            }
        }
    }
}

private struct ClipPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let clip: ClipCardModel
    @ViewState private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(clip.title).font(.system(size: 17, weight: .bold))
                Spacer()
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ZStack {
                        if let champ = clip.championId { SplashArt(championId: champ, skinNum: clip.skinNum, style: .centered) }
                        Color.black.opacity(0.55)
                        VStack(spacing: 6) {
                            Image(systemName: "film").font(.system(size: 30))
                            Text("Demo-Clip – echte Aufnahmen werden hier abgespielt.").font(.system(size: 13))
                        }
                    }
                }
            }
            .frame(height: 420)
            .clipShape(.rect(cornerRadius: 10))
            if !clip.markers.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(clip.markers) { marker in
                            Button {
                                player?.seek(to: CMTime(seconds: marker.videoTime, preferredTimescale: 600))
                            } label: {
                                Text("\(formatClock(marker.gameTime)) · \(marker.label)").font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Theme.field, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 780)
        .background(Theme.canvas)
        .onAppear {
            if let url = clip.fileURL { player = AVPlayer(url: url) }
        }
        .onDisappear { player?.pause() }
    }
}
