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
        level = .screenSaver
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
        for widget in OverlayWidget.allCases {
            let enabled = app.settings.overlaysEnabled && app.settings.isEnabled(widget)
            let relevant = isRelevant(widget, model: model)
            let tabOK = widget.visibility == .always || model.tabHeld || interactMode || previewOnScreen
            let visible = inGame && enabled && relevant && tabOK && !hidden
            if visible {
                let panel = panel(for: widget, model: model)
                panel.ignoresMouseEvents = !(interactMode || widget.isInteractive)
                panel.isMovableByWindowBackground = interactMode
                if !panel.isVisible { panel.orderFrontRegardless() }
            } else if let panel = panels[widget], panel.isVisible {
                panel.orderOut(nil)
            }
        }
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

    private func panel(for widget: OverlayWidget, model: LiveOverlayModel) -> OverlayPanel {
        if let existing = panels[widget] {
            if let host = existing.contentView as? NSHostingView<OverlayWidgetHost>, host.rootView.model !== model {
                host.rootView = OverlayWidgetHost(widget: widget, model: model, manager: self, app: app)
            }
            return existing
        }
        let panel = OverlayPanel(size: widget.defaultSize)
        let host = NSHostingView(rootView: OverlayWidgetHost(widget: widget, model: model, manager: self, app: app))
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

    private func savedOrigin(for widget: OverlayWidget, size: CGSize) -> CGPoint {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey(widget)) {
            let point = NSPointFromString(stored)
            if NSScreen.screens.contains(where: { $0.frame.contains(point) }) { return point }
        }
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = widget.defaultAnchor
        var x = screen.minX + screen.width * anchor.x
        if anchor.x == 0.5 { x -= size.width / 2 }
        let y = screen.maxY - screen.height * anchor.y - size.height
        return CGPoint(x: min(max(screen.minX, x), screen.maxX - size.width), y: y)
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
