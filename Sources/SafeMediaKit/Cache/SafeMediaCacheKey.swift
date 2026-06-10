import Foundation

public struct SafeMediaCacheKey: Sendable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum SafeMediaCacheKeyFactory {
    public static func fileURL(_ url: URL) -> SafeMediaCacheKey {
        let standardizedURL = url.standardizedFileURL
        let values = try? standardizedURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let fileSize = values?.fileSize.map(String.init) ?? "unknown"
        let modificationDate = values?.contentModificationDate?
            .timeIntervalSince1970
            .description ?? "unknown"

        return SafeMediaCacheKey(
            rawValue: "file:\(standardizedURL.path)|size:\(fileSize)|mtime:\(modificationDate)"
        )
    }

    static func cacheKey(for source: SafeMediaSource) -> SafeMediaCacheKey? {
        switch source {
        case .imageFile(let url), .videoFile(let url):
            fileURL(url)
        case .cgImage:
            nil
        }
    }
}
