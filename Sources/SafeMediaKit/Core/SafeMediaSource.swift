import CoreGraphics
import Foundation

// @unchecked: CGImage is immutable and documented thread-safe; current Apple
// SDKs declare it `@unchecked Sendable`, but older SDKs in the support window
// may not, so the conformance is asserted here rather than inherited.

/// Local media that an analyzer can evaluate.
public enum SafeMediaSource: @unchecked Sendable {
    /// An image file at a local URL.
    case imageFile(URL)

    /// An in-memory Core Graphics image.
    case cgImage(CGImage)

    /// A video file at a local URL.
    case videoFile(URL)
}
