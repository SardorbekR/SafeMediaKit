import SafeMediaKit
import SafeMediaKitTesting
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct SafeMediaChatDemoView: View {
    @State private var imageURL: URL?

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let imageURL {
                        DemoRow(
                            title: "Safe image",
                            imageURL: imageURL,
                            engine: SafeMediaEngine(
                                analyzer: MockSafeMediaAnalyzer(result: .success(.mockSafe)),
                                cache: InMemorySafeMediaVerdictCache()
                            )
                        )

                        DemoRow(
                            title: "Sensitive image",
                            imageURL: imageURL,
                            engine: SafeMediaEngine(
                                analyzer: MockSafeMediaAnalyzer(result: .success(.mockSensitive)),
                                cache: InMemorySafeMediaVerdictCache()
                            )
                        )

                        DemoRow(
                            title: "Unavailable analysis",
                            imageURL: imageURL,
                            engine: SafeMediaEngine(
                                analyzer: MockSafeMediaAnalyzer(
                                    result: .success(.mockSafe),
                                    availability: .unavailable(.analysisPolicyDisabled)
                                ),
                                cache: InMemorySafeMediaVerdictCache()
                            )
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("SafeMediaKit")
        }
        .task {
            imageURL = try? DemoImageFactory.makePlaceholderImage()
        }
    }
}

private struct DemoRow: View {
    let title: String
    let imageURL: URL
    let engine: SafeMediaEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            SafeMediaImage(
                url: imageURL,
                engine: engine,
                context: .incomingMessage,
                policy: .teenMessaging,
                onReveal: {
                    print("Reveal tapped for \(title)")
                },
                onReport: {
                    print("Report tapped for \(title)")
                }
            )
            .frame(width: 260, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private enum DemoImageFactory {
    static func makePlaceholderImage() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafeMediaKitDemoPlaceholder.png")

        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 520, height: 360))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 520, height: 360))
            UIColor.white.setFill()
            context.fill(CGRect(x: 48, y: 48, width: 424, height: 264))
        }
        guard let data = image.pngData() else {
            throw SafeMediaError.imageLoadingFailed
        }
        try data.write(to: url, options: .atomic)
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: 520, height: 360))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 520, height: 360).fill()
        NSColor.white.setFill()
        NSRect(x: 48, y: 48, width: 424, height: 264).fill()
        image.unlockFocus()
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw SafeMediaError.imageLoadingFailed
        }
        try data.write(to: url, options: .atomic)
        #endif

        return url
    }
}
