import AppKit
import Carbon.HIToolbox
import RiftsightCore
import SwiftUI

/// Borderless, non-activating panel that floats above the (borderless/fullscreen) game.
final class OverlayPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        // Above borderless game windows; still below the system's shielding level.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reacts to the very first click although the panel never becomes key
/// (otherwise buttons like the X need two clicks while League has focus).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Creates one panel per widget, shows/hides them with the game, Tab key and interact mode,
/// and stores positions per game mode. Uses only window APIs – no input injection, no game hooks.
@MainActor
@Observable
final class OverlayWindowManager {
    private(set) var interactMode = false
    private(set) var hidden = false
    /// Forces the overlays on screen with demo data (overlay settings → "Vorschau auf dem Bildschirm").
    var previewOnScreen = false {
        didSet { refresh() }
    }

    @ObservationIgnored private var panels: [OverlayWidget: OverlayPanel] = [:]
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var hotKeys: [EventHotKeyRef?] = []
    @ObservationIgnored private var previewModel: LiveOverlayModel?
    @ObservationIgnored private var moveObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastTargetScreenFrame: CGRect?
    @ObservationIgnored private var dragStart: (mouse: CGPoint, origin: CGPoint)?
    @ObservationIgnored private var frontTick = 0
    @ObservationIgnored private var accessoryForGame = false
    private unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    func start() {
        registerHotKeys()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private var modeKey: String {
        if previewOnScreen { return "PREVIEW" }
        return app.overlay.data?.modeBucket.rawValue ?? "CLASSIC"
    }

    private var activeModel: LiveOverlayModel {
        if previewOnScreen {
            if previewModel == nil { previewModel = LiveOverlayModel(app: app, preview: true) }
            return previewModel!
        }
        return app.overlay
    }

    // MARK: Polling (Tab key state, game state)

    private var lastTab = false

    private func tick() {
        // Passive read of the Tab key state (kVK_Tab = 0x30). No events are created or intercepted.
        let tab = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Tab))
        if tab != lastTab {
            lastTab = tab
            app.overlay.tabHeld = tab
            previewModel?.tabHeld = tab
        }
        refresh()
    }

    func refresh() {
        let inGame = app.overlay.isInGame || previewOnScreen
        let model = activeModel
        if inGame {
            let targetFrame = targetScreenFrame()
            if lastTargetScreenFrame != targetFrame {
                lastTargetScreenFrame = targetFrame
                repositionDefaultPanels(on: targetFrame)
            }
        } else {
            lastTargetScreenFrame = nil
        }
        updateActivationPolicy(inGame: inGame && !previewOnScreen)
        // Re-assert z-order about once a second: borderless games can raise their window above ours.
        frontTick += 1
        let reassert = frontTick % 10 == 0
        for widget in OverlayWidget.allCases {
            let mode = app.settings.visibility(widget)
            let enabled = app.settings.overlaysEnabled && mode != .off
            let relevant = isRelevant(widget, model: model)
            let tabOK = mode == .always || model.tabHeld || interactMode || previewOnScreen
            let visible = inGame && enabled && relevant && tabOK && !hidden
            if visible {
                let panel = panel(for: widget, model: model)
                panel.ignoresMouseEvents = false
                fitToContent(panel)
                if !panel.isVisible || reassert { panel.orderFrontRegardless() }
            } else if let panel = panels[widget], panel.isVisible {
                panel.orderOut(nil)
            }
        }
    }

    /// While League runs borderless/fullscreen it lives in its own Space. macOS only lets an app's
    /// panels join another app's fullscreen Space reliably when the app is an accessory (no Dock icon),
    /// so Riftsight switches to accessory for the duration of such a game and back afterwards.
    private func updateActivationPolicy(inGame: Bool) {
        let wantAccessory = inGame && Self.leagueIsBorderless()
        guard wantAccessory != accessoryForGame else { return }
        accessoryForGame = wantAccessory
        NSApp.setActivationPolicy(wantAccessory ? .accessory : .regular)
    }

    private static func leagueIsBorderless() -> Bool {
        guard let rect = leagueGameWindowRect(),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) else { return false }
        return rect.width >= screen.frame.width - 2 && rect.height >= screen.frame.height - 40
    }

    // MARK: Dragging (always available – no hotkey needed)

    func beginDrag(_ widget: OverlayWidget) {
        guard let panel = panels[widget] else { return }
        dragStart = (NSEvent.mouseLocation, panel.frame.origin)
    }

    func drag(_ widget: OverlayWidget) {
        guard let panel = panels[widget], let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(CGPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
    }

    func endDrag(_ widget: OverlayWidget) {
        dragStart = nil
        guard let panel = panels[widget] else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: defaultsKey(widget))
    }

    private func isRelevant(_ widget: OverlayWidget, model: LiveOverlayModel) -> Bool {
        switch widget {
        case .skillUp: model.skillUp != nil
        case .trinket: model.trinketSwap != nil
        case .nextItem: model.nextPurchase != nil
        case .itemSpikes: !model.activeSpikes.isEmpty
        case .augments: model.augmentModeKey != nil || previewOnScreen
        case .matchupGuide: model.laneOpponent != nil
        default: true
        }
    }

    /// Grows/shrinks the panel to the widget's real size (values, scale) while keeping its top-left corner fixed,
    /// so content is never clipped or wrapped.
    private func fitToContent(_ panel: OverlayPanel) {
        guard let host = panel.contentView else { return }
        let fitting = host.fittingSize
        let current = panel.frame
        guard fitting.width > 1, fitting.height > 1,
              abs(fitting.width - current.width) > 0.5 || abs(fitting.height - current.height) > 0.5 else { return }
        panel.setFrame(CGRect(x: current.minX, y: current.maxY - fitting.height, width: fitting.width, height: fitting.height),
                       display: true)
    }

    private func panel(for widget: OverlayWidget, model: LiveOverlayModel) -> OverlayPanel {
        if let existing = panels[widget] {
            if let host = existing.contentView as? FirstMouseHostingView<OverlayWidgetHost>, host.rootView.model !== model {
                host.rootView = OverlayWidgetHost(widget: widget, model: model, manager: self, app: app)
            }
            return existing
        }
        let panel = OverlayPanel(size: widget.defaultSize)
        let host = FirstMouseHostingView(rootView: OverlayWidgetHost(widget: widget, model: model, manager: self, app: app))
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        panel.setFrameOrigin(savedOrigin(for: widget, size: widget.defaultSize))
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let panel else { return }
                self?.savePosition(panel.frame.origin, for: widget)
            }
        }
        moveObservers.append(observer)
        panels[widget] = panel
        return panel
    }

    // MARK: Positions (per game mode)

    private func defaultsKey(_ widget: OverlayWidget) -> String { "overlay.position.\(modeKey).\(widget.rawValue)" }

    /// Finds the screen currently hosting the League of Legends game window (never the League Client),
    /// falling back to the primary display rather than whichever screen holds the Riftsight window.
    private func targetScreenFrame() -> CGRect {
        // Anchor to the game window itself (correct in windowed mode), else its screen.
        if !previewOnScreen, let window = Self.leagueGameWindowRect() {
            return window
        }
        if previewOnScreen, let main = NSScreen.main {
            return main.visibleFrame
        }
        return NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Frame of the League game window in AppKit coordinates (title bar excluded in windowed mode).
    private static func leagueGameWindowRect() -> CGRect? {
        guard let screen = leagueGameScreen(), let rect = lastGameRect else { return nil }
        // Windowed mode: skip the ~28 pt macOS title bar.
        if rect.height < screen.frame.height - 40 {
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0, rect.height - 28))
        }
        return rect
    }

    nonisolated(unsafe) private static var lastGameRect: CGRect?

    private static func leagueGameScreen() -> NSScreen? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var bestWindowRect: CGRect?
        var bestArea: CGFloat = 0

        for info in list {
            let owner = (info[kCGWindowOwnerName as String] as? String) ?? ""
            let name = (info[kCGWindowName as String] as? String) ?? ""
            let isLeagueGame = (owner.contains("League of Legends") || name.contains("League of Legends (TM) Client"))
                && !owner.contains("Client")
            guard isLeagueGame,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  cgRect.width >= 600, cgRect.height >= 400 else { continue }
            let area = cgRect.width * cgRect.height
            if area > bestArea {
                bestArea = area
                // Convert Quartz top-left coordinates into AppKit bottom-left coordinates.
                let appKitY = primaryHeight - cgRect.origin.y - cgRect.height
                bestWindowRect = CGRect(x: cgRect.origin.x, y: appKitY, width: cgRect.width, height: cgRect.height)
            }
        }
        lastGameRect = bestWindowRect
        guard let rect = bestWindowRect else { return nil }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let containing = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return containing
        }
        return NSScreen.screens.max { a, b in
            let ia = a.frame.intersection(rect)
            let ib = b.frame.intersection(rect)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        }
    }

    private func repositionDefaultPanels(on screen: CGRect) {
        for (widget, panel) in panels {
            guard UserDefaults.standard.string(forKey: defaultsKey(widget)) == nil else { continue }
            panel.setFrameOrigin(defaultOrigin(for: widget, size: panel.frame.size, on: screen))
        }
    }

    private func defaultOrigin(for widget: OverlayWidget, size: CGSize, on screen: CGRect) -> CGPoint {
        let anchor = widget.defaultAnchor
        var x = screen.minX + screen.width * anchor.x
        if anchor.x == 0.5 { x -= size.width / 2 }
        let y = screen.maxY - screen.height * anchor.y - size.height
        return CGPoint(x: min(max(screen.minX, x), screen.maxX - size.width),
                       y: min(max(screen.minY, y), screen.maxY - size.height))
    }

    private func savedOrigin(for widget: OverlayWidget, size: CGSize) -> CGPoint {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey(widget)) {
            let point = NSPointFromString(stored)
            if NSScreen.screens.contains(where: { $0.frame.contains(point) }) { return point }
        }
        return defaultOrigin(for: widget, size: size, on: targetScreenFrame())
    }

    private func savePosition(_ origin: CGPoint, for widget: OverlayWidget) {
        guard interactMode else { return }
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: defaultsKey(widget))
    }

    func resetPositions() {
        for widget in OverlayWidget.allCases {
            for mode in ["CLASSIC", "ARAM", "CHERRY", "PREVIEW"] {
                UserDefaults.standard.removeObject(forKey: "overlay.position.\(mode).\(widget.rawValue)")
            }
            if let panel = panels[widget] { panel.setFrameOrigin(savedOrigin(for: widget, size: panel.frame.size)) }
        }
    }

    // MARK: Modes

    func toggleInteractMode() {
        interactMode.toggle()
        refresh()
    }

    func toggleHidden() {
        hidden.toggle()
        refresh()
    }

    func disable(_ widget: OverlayWidget) {
        if app.settings.isEnabled(widget) { app.settings.toggle(widget) }
        refresh()
    }

    // MARK: Global hotkeys (Carbon RegisterEventHotKey – no accessibility permission needed)

    static let hotKeyHelp: [(String, String)] = [
        ("⌃⌥O", "Overlays verschieben (Interaktionsmodus)"),
        ("⌃⌥H", "Overlays ein-/ausblenden"),
        ("⌃⌥R", "Instant Replay speichern"),
        ("⌃⌥A", "Augments erkennen"),
    ]

    private func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let manager = Unmanaged<OverlayWindowManager>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            MainActor.assumeIsolated { manager.handleHotKey(id) }
            return noErr
        }, 1, &spec, selfPointer, nil)

        let modifiers = UInt32(controlKey | optionKey)
        for (index, key) in [kVK_ANSI_O, kVK_ANSI_H, kVK_ANSI_R, kVK_ANSI_A].enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5249_4654), id: UInt32(index + 1)) // 'RIFT'
            RegisterEventHotKey(UInt32(key), modifiers, id, GetApplicationEventTarget(), 0, &ref)
            hotKeys.append(ref)
        }
    }

    private func handleHotKey(_ id: UInt32) {
        switch id {
        case 1: toggleInteractMode()
        case 2: toggleHidden()
        case 3: app.instantReplay()
        case 4: Task { await app.overlay.scanAugments() }
        default: break
        }
    }
}
