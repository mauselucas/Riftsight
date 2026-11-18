import RiftsightCore
import SwiftUI

enum Route: Hashable {
    case dashboard
    case account(String)
    case tierlist
    case champion(Int, Role?)
    case leaderboards
    case recordings
    case overlays
    case spectate
    case collection
    case dataLens
    case matchups
    case champSelect
    case loadingScreen
    case postGame
    case settings
    case debug

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .account: "Konto"
        case .tierlist: "Tierlist & Builds"
        case .champion: "Champion"
        case .leaderboards: "Ranglisten"
        case .recordings: "Aufnahmen"
        case .overlays: "Overlays"
        case .spectate: "Zuschauen"
        case .collection: "Sammlung"
        case .dataLens: "Data Lens"
        case .matchups: "Matchups"
        case .champSelect: "Champ Select"
        case .loadingScreen: "Ladebildschirm"
        case .postGame: "Nach dem Spiel"
        case .settings: "Einstellungen"
        case .debug: "Protokoll"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard, .account: "house.fill"
        case .tierlist, .champion: "chart.bar.fill"
        case .leaderboards: "trophy.fill"
        case .recordings: "film.stack.fill"
        case .overlays: "square.on.square.fill"
        case .spectate: "display"
        case .collection: "shield.lefthalf.filled"
        case .dataLens: "doc.text.magnifyingglass"
        case .matchups: "figure.fencing"
        case .champSelect: "sparkles"
        case .loadingScreen: "person.3.sequence.fill"
        case .postGame: "flag.checkered"
        case .settings: "gearshape.fill"
        case .debug: "ladybug.fill"
        }
    }

    /// Stable identifier for snapshots / command-line routing.
    var slug: String {
        switch self {
        case .dashboard: "dashboard"
        case .account: "account"
        case .tierlist: "tierlist"
        case .champion: "champion"
        case .leaderboards: "leaderboards"
        case .recordings: "recordings"
        case .overlays: "overlays"
        case .spectate: "spectate"
        case .collection: "collection"
        case .dataLens: "datalens"
        case .matchups: "matchups"
        case .champSelect: "champselect"
        case .loadingScreen: "loading"
        case .postGame: "postgame"
        case .settings: "settings"
        case .debug: "debug"
        }
    }
}

/// Navigation with browser-like back/forward history.
@MainActor
@Observable
final class Router {
    private(set) var current: Route = .dashboard
    private var backStack: [Route] = []
    private var forwardStack: [Route] = []
    var reloadToken = 0

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func go(_ route: Route) {
        guard route != current else { return }
        backStack.append(current)
        forwardStack.removeAll()
        current = route
    }

    func back() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(current)
        current = previous
    }

    func forward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(current)
        current = next
    }

    func reload() { reloadToken += 1 }
}
