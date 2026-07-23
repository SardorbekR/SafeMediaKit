#if canImport(SwiftUI)
import SwiftUI

private struct SafeMediaEngineKey: EnvironmentKey {
    static let defaultValue: SafeMediaEngine? = nil
}

/// SafeMediaKit values available through the SwiftUI environment.
public extension EnvironmentValues {
    /// The engine used by ``SafeMediaImage`` instances without an explicit engine.
    var safeMediaEngine: SafeMediaEngine? {
        get { self[SafeMediaEngineKey.self] }
        set { self[SafeMediaEngineKey.self] = newValue }
    }
}
#endif
