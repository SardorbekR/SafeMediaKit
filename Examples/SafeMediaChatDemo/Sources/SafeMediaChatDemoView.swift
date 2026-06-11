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

    // Engines live in @State so they (and their caches) are created once per
    // view identity — never build engines inside `body`.
    @State private var safeEngine = SafeMediaEngine(
        analyzer: MockSafeMediaAnalyzer(result: .success(.mockSafe)),
        cache: InMemorySafeMediaVerdictCache()
    )
    @State private var sensitiveEngine = SafeMediaEngine(
        analyzer: MockSafeMediaAnalyzer(result: .success(.mockSensitive)),
        cache: InMemorySafeMediaVerdictCache()
    )
    @State private var unavailableEngine = SafeMediaEngine(
        analyzer: MockSafeMediaAnalyzer(
            result: .success(.mockSafe),
            availability: .unavailable(.analysisPolicyDisabled)
        ),
        cache: InMemorySafeMediaVerdictCache()
    )

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let imageURL {
                        ChatMessageRow(
                            sender: "Alex",
                            caption: "Safe image (mock analyzer)",
                            imageURL: imageURL,
                            engine: safeEngine
                        )

                        ChatMessageRow(
                            sender: "Sam",
                            caption: "Sensitive image (mock analyzer)",
                            imageURL: imageURL,
                            engine: sensitiveEngine
                        )

                        ChatMessageRow(
                            sender: "Riley",
                            caption: "Unavailable analysis (mock analyzer)",
                            imageURL: imageURL,
                            engine: unavailableEngine
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

private struct ChatMessageRow: View {
    let sender: String
    let caption: String
    let imageURL: URL
    let engine: SafeMediaEngine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor.opacity(0.25))
                .frame(width: 34, height: 34)
                .overlay {
                    Text(String(sender.prefix(1)))
                        .font(.subheadline.weight(.semibold))
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(sender)
                    .font(.subheadline.weight(.semibold))

                SafeMediaImage(
                    url: imageURL,
                    engine: engine,
                    context: .incomingMessage,
                    policy: .teenMessaging,
                    onReveal: {
                        print("Reveal tapped for \(caption)")
                    },
                    onReport: {
                        print("Report tapped for \(caption)")
                    }
                )
                .frame(width: 240, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.secondary.opacity(0.12))
            )

            Spacer(minLength: 0)
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
