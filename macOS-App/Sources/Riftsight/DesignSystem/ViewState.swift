import SwiftUI

/// The macOS 27 SDK declares `@State` as a macro whose compiler plugin ships only with Xcode.
/// Builds with the Command Line Tools use the `State` property wrapper directly through this alias.
typealias ViewState<Value> = SwiftUI.State<Value>
