import AppKit
import RiftsightCore
import SwiftUI

/// Entry point: normal app, or `--snapshot <dir> [route …]` to render every screen offscreen to PNG.
@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            let routes = Array(arguments.dropFirst(index + 2))
            SnapshotRunner.run(outputDirectory: URL(fileURLWithPath: arguments[index + 1]), only: routes)
        } else {
            RiftsightApp.main()
        }
    }
}

enum AppEnvironment {
    static let model = AppModel()
}

struct RiftsightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let app = AppEnvironment.model

    var body: some Scene {
        Window("Riftsight", id: "main") {
            MainWindowView()
                .environment(app)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Navigation") {
                Button("Suchen …") { app.showCommandPalette = true }.keyboardShortcut("k")
                Button("Zurück") { app.router.back() }.keyboardShortcut("[")
                Button("Vor") { app.router.forward() }.keyboardShortcut("]")
                Button("Neu laden") { app.router.reload() }.keyboardShortcut("r")
                Divider()
                Button("Dashboard") { app.router.go(.dashboard) }.keyboardShortcut("1")
                Button("Tierlist & Builds") { app.router.go(.tierlist) }.keyboardShortcut("2")
                Button("Champ Select") { app.router.go(.champSelect) }.keyboardShortcut("3")
                Button("Nach dem Spiel") { app.router.go(.postGame) }.keyboardShortcut("4")
            }
        }

        MenuBarExtra {
            MenuBarView().environment(app)
        } label: {
            Image(systemName: app.overlay.isInGame ? "scope" : "circle.hexagongrid.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(app)
                .frame(width: 720, height: 640)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppEnvironment.model.start()
    }

    /// Overlays, recording and the menu-bar item keep working when the main window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.identifier?.rawValue.contains("main") == true {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

// MARK: - Snapshot mode (visual verification without a running client)

enum SnapshotRunner {
    static let routes: [Route] = [
        .dashboard, .account(DemoData.accounts[0].puuid), .tierlist, .champion(103, .middle), .leaderboards,
        .recordings, .overlays, .spectate, .collection, .dataLens, .matchups,
        .champSelect, .loadingScreen, .postGame, .settings, .debug,
    ]

    private static var delegate: SnapshotDelegate?

    static func run(outputDirectory: URL, only: [String]) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = SnapshotDelegate(output: outputDirectory, only: only)
        Self.delegate = delegate
        application.delegate = delegate
        application.run()
    }
}

final class SnapshotDelegate: NSObject, NSApplicationDelegate {
    let output: URL
    let only: [String]

    init(output: URL, only: [String]) {
        self.output = output
        self.only = only
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await render() }
    }

    private func render() async {
        let app = AppEnvironment.model
        app.demoOverride = true
        await app.startForSnapshot()
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let size = CGSize(width: 1400, height: 880)
        let window = NSWindow(contentRect: CGRect(x: -6000, y: -6000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: AnyView(MainWindowView().environment(app).preferredColorScheme(.dark)))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()

        let selected = SnapshotRunner.routes.filter { only.isEmpty || only.contains($0.slug) }
        for route in selected {
            app.router.go(route)
            await settle(app: app, route: route)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                let file = output.appendingPathComponent("\(route.slug).png")
                try? png.write(to: file)
                print("snapshot: \(file.path)")
            }
        }
        // Overlay widgets on a neutral backdrop.
        await renderOverlays(app: app)
        NSApplication.shared.terminate(nil)
    }

    private func settle(app: AppModel, route: Route) async {
        switch route {
        case .postGame: await app.loadPostGame()
        case .collection: await app.loadCollection()
        default: break
        }
        try? await Task.sleep(for: .milliseconds(400))
        await waitForImages()
        try? await Task.sleep(for: .milliseconds(350))
    }

    /// Waits until no image load has been pending for 600 ms (lazy grids start their loads late), max ~15 s.
    private func waitForImages() async {
        var quiet = 0
        for _ in 0..<75 where quiet < 3 {
            quiet = ImagePipeline.shared.pending == 0 ? quiet + 1 : 0
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func renderOverlays(app: AppModel) async {
        guard only.isEmpty || only.contains("overlay-widgets") else { return }
        let model = LiveOverlayModel(app: app, preview: true)
        model.tabHeld = true
        let view = OverlayGallery(model: model).environment(app)
        let size = CGSize(width: 1400, height: 880)
        let window = NSWindow(contentRect: CGRect(x: -6000, y: -6000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: AnyView(view.preferredColorScheme(.dark)))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(500))
        await waitForImages()
        try? await Task.sleep(for: .milliseconds(300))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("overlay-widgets.png"))
        }
    }
}

/// All overlay widgets laid out on a game-like backdrop (snapshot + overlay settings preview).
struct OverlayGallery: View {
    @Environment(AppModel.self) private var app
    let model: LiveOverlayModel

    var body: some View {
        ZStack {
            SplashArt(championId: 222, skinNum: 0, style: .splash)
                .overlay(Color.black.opacity(0.35))
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    OverlayWidgetView(widget: .winProbability, model: model)
                    Spacer()
                    OverlayWidgetView(widget: .goldBar, model: model)
                    Spacer()
                    OverlayWidgetView(widget: .cooldowns, model: model)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        OverlayWidgetView(widget: .matchupGuide, model: model)
                        OverlayWidgetView(widget: .csBenchmark, model: model)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        OverlayWidgetView(widget: .itemSpikes, model: model)
                    }
                }
                Spacer()
                HStack {
                    OverlayWidgetView(widget: .augments, model: model).frame(width: 640)
                    Spacer()
                }
                Spacer()
                HStack(alignment: .bottom) {
                    OverlayWidgetView(widget: .skillUp, model: model)
                    OverlayWidgetView(widget: .trinket, model: model)
                    Spacer()
                    OverlayWidgetView(widget: .nextItem, model: model)
                }
            }
            .padding(20)
        }
        .frame(width: 1400, height: 880)
        .clipped()
    }
}
