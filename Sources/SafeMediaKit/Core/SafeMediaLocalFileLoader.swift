import Foundation

enum SafeMediaLocalFileLoader {
    static func readData(from url: URL) async throws -> Data {
        guard url.isFileURL else {
            throw SafeMediaError.imageLoadingFailed
        }

        return try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
    }
}
