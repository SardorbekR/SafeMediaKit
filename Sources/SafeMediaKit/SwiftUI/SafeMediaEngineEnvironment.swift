#if canImport(SwiftUI)
import SwiftUI

private struct SafeMediaEngineKey: EnvironmentKey {
    static let defaultValue: SafeMediaEngine? = nil
}

public extension EnvironmentValues {
    var safeMediaEngine: SafeMediaEngine? {
        get { self[SafeMediaEngineKey.self] }
        set { self[SafeMediaEngineKey.self] = newValue }
    }
}
#endif
