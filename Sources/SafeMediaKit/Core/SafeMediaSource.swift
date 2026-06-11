import CoreGraphics
import Foundation

// @unchecked: CGImage is immutable and documented thread-safe; current Apple
// SDKs declare it `@unchecked Sendable`, but older SDKs in the support window
// may not, so the conformance is asserted here rather than inherited.
public enum SafeMediaSource: @unchecked Sendable {
    case imageFile(URL)
    case cgImage(CGImage)
    case videoFile(URL)
}
