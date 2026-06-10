#if canImport(SwiftUI)
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias SafeMediaPlatformImage = UIImage

private func makePlatformImage(data: Data) -> SafeMediaPlatformImage? {
    UIImage(data: data)
}

private func swiftUIImage(from image: SafeMediaPlatformImage) -> Image {
    Image(uiImage: image)
}
#elseif canImport(AppKit)
import AppKit
private typealias SafeMediaPlatformImage = NSImage

private func makePlatformImage(data: Data) -> SafeMediaPlatformImage? {
    NSImage(data: data)
}

private func swiftUIImage(from image: SafeMediaPlatformImage) -> Image {
    Image(nsImage: image)
}
#endif

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, *)
public struct SafeMediaImage: View {
    private enum LoadState: Equatable {
        case idle
        case loading
        case scanning
        case loaded
        case failed
    }

    private let url: URL
    private let explicitEngine: SafeMediaEngine?
    private let context: SafeMediaContext
    private let policy: SafeMediaPolicy
    private let configuration: SafeMediaImageConfiguration
    private let cacheKey: SafeMediaCacheKey?
    private let onReveal: @MainActor @Sendable () -> Void
    private let onReport: @MainActor @Sendable () -> Void

    @Environment(\.safeMediaEngine) private var environmentEngine
    @State private var image: SafeMediaPlatformImage?
    @State private var decision: SafeMediaDecision?
    @State private var loadState: LoadState = .idle
    @State private var isRevealed = false

    public init(
        url: URL,
        engine: SafeMediaEngine,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        configuration: SafeMediaImageConfiguration = .default,
        cacheKey: SafeMediaCacheKey? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.url = url
        self.explicitEngine = engine
        self.context = context
        self.policy = policy
        self.configuration = configuration
        self.cacheKey = cacheKey
        self.onReveal = onReveal
        self.onReport = onReport
    }

    public init(
        url: URL,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        configuration: SafeMediaImageConfiguration = .default,
        cacheKey: SafeMediaCacheKey? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.url = url
        self.explicitEngine = nil
        self.context = context
        self.policy = policy
        self.configuration = configuration
        self.cacheKey = cacheKey
        self.onReveal = onReveal
        self.onReport = onReport
    }

    public var body: some View {
        ZStack {
            content
        }
        .clipped()
        .task(id: evaluationID) {
            await loadAndEvaluate()
        }
        .onChange(of: evaluationID) {
            isRevealed = false
        }
    }

    @ViewBuilder
    private var content: some View {
        if isBlocked {
            neutralBackground
            overlay
        } else if let image, decision != nil {
            let hidden = shouldHideImage

            swiftUIImage(from: image)
                .resizable()
                .scaledToFill()
                .blur(radius: hidden ? effectiveBlurRadius : 0)
                .accessibilityHidden(hidden)

            if hidden {
                overlay
            }
        } else {
            // The loaded image is never rendered before a decision exists,
            // so sensitive content cannot flash unblurred while scanning.
            placeholder

            if shouldShowOverlayWithoutImage {
                overlay
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.16))

            if loadState == .loading || loadState == .scanning || loadState == .idle {
                ProgressView(configuration.loadingTitle)
                    .controlSize(.regular)
            }
        }
        .accessibilityLabel(configuration.loadingTitle)
    }

    private var neutralBackground: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.16))
            .accessibilityHidden(true)
    }

    private var overlay: some View {
        SensitiveMediaOverlay(
            title: overlayTitle,
            message: overlayMessage,
            revealButtonTitle: configuration.revealButtonTitle,
            reportButtonTitle: configuration.reportButtonTitle,
            showsRevealButton: canReveal,
            showsReportButton: canReport,
            onReveal: reveal,
            onReport: {
                onReport()
            }
        )
    }

    private var activeEngine: SafeMediaEngine? {
        explicitEngine ?? environmentEngine
    }

    private var effectiveBlurRadius: CGFloat {
        CGFloat(configuration.blurRadius)
    }

    private var evaluationID: EvaluationID {
        EvaluationID(
            url: url,
            context: context,
            policy: policy,
            cacheKey: cacheKey
        )
    }

    private var isBlocked: Bool {
        decision?.action == .block
    }

    private var shouldHideImage: Bool {
        guard !isRevealed else {
            return false
        }

        // Fail safe: treat a missing decision as not-yet-cleared.
        guard let decision else {
            return true
        }

        switch decision.action {
        case .allow:
            return false
        case .blur, .blurWithReveal, .block, .interruptVideo, .muteAudio:
            return true
        }
    }

    private var shouldShowOverlayWithoutImage: Bool {
        guard let decision else {
            return loadState == .failed
        }
        return decision.action != .allow
    }

    private var canReveal: Bool {
        guard let decision else {
            return false
        }
        return decision.action == .blurWithReveal && decision.policy.allowReveal
    }

    private var canReport: Bool {
        guard let decision else {
            return false
        }
        return configuration.showsReportButton && decision.policy.allowReport
    }

    private var overlayTitle: String {
        guard let decision else {
            return configuration.blockedTitle
        }

        switch decision.reason {
        case .unavailableByPolicy:
            return configuration.unavailableTitle
        case .analysisFailed where decision.action == .block:
            return configuration.blockedTitle
        default:
            return decision.action == .block
                ? configuration.blockedTitle
                : configuration.warningTitle
        }
    }

    private var overlayMessage: String {
        guard let decision else {
            return configuration.blockedMessage
        }

        switch decision.reason {
        case .unavailableByPolicy:
            return configuration.unavailableMessage
        case .analysisFailed where decision.action == .block:
            return configuration.blockedMessage
        default:
            return decision.action == .block
                ? configuration.blockedMessage
                : configuration.warningMessage
        }
    }

    @MainActor
    private func reveal() {
        isRevealed = true
        onReveal()
    }

    @MainActor
    private func loadAndEvaluate() async {
        isRevealed = false
        decision = nil
        image = nil

        guard let engine = activeEngine else {
            decision = failureDecision()
            loadState = .failed
            return
        }

        do {
            loadState = .loading
            let data = try await Self.readData(from: url)

            guard !Task.isCancelled else {
                return
            }

            guard let loadedImage = makePlatformImage(data: data) else {
                throw SafeMediaError.imageLoadingFailed
            }

            image = loadedImage
            loadState = .scanning
            let evaluatedDecision = await engine.evaluate(
                .imageFile(url),
                context: context,
                policy: policy,
                cacheKey: cacheKey
            )

            guard !Task.isCancelled else {
                return
            }

            decision = evaluatedDecision
            loadState = .loaded
        } catch {
            decision = failureDecision()
            loadState = .failed
        }
    }

    private static func readData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
    }

    private func failureDecision() -> SafeMediaDecision {
        SafeMediaDecision(
            action: policy.failureAction,
            verdict: SafeMediaVerdict(
                sensitivity: .unknown,
                contentTypes: [],
                guidance: .none,
                availability: .available
            ),
            context: context,
            policy: policy,
            reason: .analysisFailed
        )
    }
}

private struct EvaluationID: Hashable {
    let url: URL
    let context: SafeMediaContext
    let policy: SafeMediaPolicy
    let cacheKey: SafeMediaCacheKey?
}
#endif
