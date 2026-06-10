import CoreGraphics
import Foundation

// `@unchecked Sendable` solely because of the `CGImage` payload: `CGImage`
// is documented as immutable and safe to share across threads, but some SDKs
// do not mark it `Sendable`. The URL payloads are value types.
public enum SafeMediaSource: @unchecked Sendable {
    case imageFile(URL)
    case cgImage(CGImage)
    case videoFile(URL)
}
