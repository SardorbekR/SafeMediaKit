import Foundation

/// A stable identifier for a cached media verdict.
public struct SafeMediaCacheKey: Sendable, Hashable {
    /// The string value that identifies the cached media.
    public let rawValue: String

    /// Creates a cache key from a string value.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Derives cache keys from file URLs.
public enum SafeMediaCacheKeyFactory {
    /// Builds a key from the file's standardized path, size, and modification
    /// date without hashing its contents. When metadata is unreadable the key
    /// degrades to path-only (`unknown` markers) and cannot detect file content
    /// changes — prefer supplying your own stable key in that situation.
    public static func fileURL(_ url: URL) -> SafeMediaCacheKey {
        let standardizedURL = url.standardizedFileURL
        let metadata = fileMetadata(for: standardizedURL)
        let fileSize = metadata?.size.map(String.init) ?? "unknown"
        let modificationDate = metadata?.mtime?
            .timeIntervalSince1970
            .description ?? "unknown"

        return SafeMediaCacheKey(
            rawValue: "file:\(standardizedURL.path)|size:\(fileSize)|mtime:\(modificationDate)"
        )
    }

    /// Engine-internal key derivation. Returns nil (skip caching) when file
    /// metadata is entirely unreadable: a path-only key could go stale when
    /// the file's content changes.
    static func cacheKey(for source: SafeMediaSource) -> SafeMediaCacheKey? {
        switch source {
        case .imageFile(let url), .videoFile(let url):
            let standardizedURL = url.standardizedFileURL
            guard let metadata = fileMetadata(for: standardizedURL),
                  metadata.size != nil || metadata.mtime != nil else {
                return nil
            }
            return fileURL(standardizedURL)
        case .cgImage:
            return nil
        }
    }

    private static func fileMetadata(
        for standardizedURL: URL
    ) -> (size: Int?, mtime: Date?)? {
        guard let values = try? standardizedURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey
        ]) else {
            return nil
        }
        return (values.fileSize, values.contentModificationDate)
    }
}
