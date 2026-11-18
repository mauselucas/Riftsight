import AppKit
import RiftsightCore
import SwiftUI

/// Memory + disk cached image loading for CDN artwork (icons, splashes, emblems).
@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession
    /// Number of loads currently running (the snapshot renderer waits for this to reach 0).
    private(set) var pending = 0

    private init() {
        memory.countLimit = 1500
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 600 << 20,
                                   directory: AppPaths.directory("ImageCache"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        return memory.object(forKey: url as NSURL)
    }

    func load(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }
        let session = session
        let task = Task<NSImage?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
            return NSImage(data: data)
        }
        inFlight[url] = task
        pending += 1
        let image = await task.value
        pending -= 1
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// Global asset context (Data Dragon version for item icons, set once static data loads).
@MainActor
enum AssetContext {
    static var ddragonVersion = "16.23.1"
}

/// An image from the network that fills its frame (cropped), with a neutral placeholder.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var alignment: Alignment = .center
    var template = false
    var placeholder: Color = Theme.cardRaised

    @ViewState private var image: NSImage?

    init(_ url: URL?, contentMode: ContentMode = .fill, alignment: Alignment = .center,
         template: Bool = false, placeholder: Color = Theme.cardRaised) {
        self.url = url
        self.contentMode = contentMode
        self.alignment = alignment
        self.template = template
        self.placeholder = placeholder
        _image = State(initialValue: ImagePipeline.shared.cached(url))
    }

    var body: some View {
        Color.clear
            .overlay(alignment: alignment) {
                if let image {
                    Image(nsImage: image)
                        .renderingMode(template ? .template : .original)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder
                }
            }
            .clipped()
            .task(id: url) {
                if let hit = ImagePipeline.shared.cached(url) {
                    image = hit
                } else {
                    let loaded = await ImagePipeline.shared.load(url)
                    withAnimation(.easeOut(duration: 0.2)) { image = loaded }
                }
            }
    }
}

// MARK: - Game asset shortcuts

struct ChampionIcon: View {
    let id: Int
    var size: CGFloat = 32
    var radius: CGFloat? = nil
    var grayscale = false

    var body: some View {
        RemoteImage(id > 0 ? CDN.championIcon(id) : nil)
            .scaleEffect(1.1)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: radius ?? size * 0.22))
            .saturation(grayscale ? 0 : 1)
            .opacity(grayscale ? 0.55 : 1)
    }
}

struct ItemIcon: View {
    let id: Int
    var size: CGFloat = 28
    var dimmed = false

    var body: some View {
        Group {
            if id > 0 {
                RemoteImage(CDN.itemIcon(id, version: AssetContext.ddragonVersion))
            } else {
                Theme.cardRaised
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: max(4, size * 0.16)))
        .overlay(RoundedRectangle(cornerRadius: max(4, size * 0.16)).strokeBorder(.black.opacity(0.35), lineWidth: 1))
        .saturation(dimmed ? 0 : 1)
        .opacity(dimmed ? 0.45 : 1)
    }
}

struct PerkIcon: View {
    @Environment(AppModel.self) private var app
    let id: Int
    var size: CGFloat = 28

    var body: some View {
        RemoteImage(CDN.gameData(app.gameData.perk(id)?.iconPath ?? app.gameData.perkStyles[id]?.iconPath),
                    contentMode: .fit, placeholder: .clear)
            .frame(width: size, height: size)
    }
}

struct SpellIcon: View {
    @Environment(AppModel.self) private var app
    let id: Int
    var size: CGFloat = 22

    var body: some View {
        RemoteImage(CDN.gameData(app.gameData.spell(id)?.iconPath))
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: 5))
    }
}

struct RoleIcon: View {
    let role: Role?
    var size: CGFloat = 16
    var color: Color = Theme.textSecondary

    var body: some View {
        if let role {
            RemoteImage(CDN.roleIcon(role), contentMode: .fit, template: true, placeholder: .clear)
                .foregroundStyle(color)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "circle.grid.2x2")
                .font(.system(size: size * 0.8))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }
}

struct RankEmblem: View {
    let tier: RankTier
    var size: CGFloat = 28

    var body: some View {
        RemoteImage(CDN.rankCrest(tier), contentMode: .fit, placeholder: .clear)
            .frame(width: size, height: size)
    }
}

struct ProfileIcon: View {
    let id: Int
    var size: CGFloat = 56

    var body: some View {
        RemoteImage(CDN.profileIcon(id))
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: 10))
    }
}

/// Champion splash art (Data Dragon); `centered` uses the cropped centred variant.
struct SplashArt: View {
    @Environment(AppModel.self) private var app
    let championId: Int
    var skinNum = 0
    var style: Style = .splash
    var alignment: Alignment = .center

    enum Style { case splash, centered, loading }

    var body: some View {
        let alias = app.gameData.alias(championId)
        let url: URL? = switch style {
        case .splash: CDN.splash(alias: alias, skinNum: skinNum)
        case .centered: CDN.centeredSplash(alias: alias, skinNum: skinNum)
        case .loading: CDN.loadingArt(alias: alias, skinNum: skinNum)
        }
        RemoteImage(alias.isEmpty ? nil : url, alignment: alignment)
    }
}
