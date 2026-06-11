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
        } else if let image {
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
            placeholder

            if shouldShowOverlayWithoutImage {
                overlay
            }
        }
    }

    private var placeholder: some View {
        let isInProgress = loadState == .loading || loadState == .scanning || loadState == .idle

        return ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.16))

            if isInProgress {
                ProgressView(configuration.loadingTitle)
                    .controlSize(.regular)
            }
        }
        .accessibilityLabel(configuration.loadingTitle)
        // After failure the overlay (if any) carries the information; a bare
        // backdrop labeled "scanning" would mislead VoiceOver users.
        .accessibilityHidden(!isInProgress)
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
        if isRevealed {
            return false
        }

        guard let decision else {
            // No decision yet: fail closed.
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
        guard image != nil, let decision else {
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

        if activeEngine == nil {
            assertionFailure(
                "SafeMediaImage requires a SafeMediaEngine via init(engine:) or .environment(\\.safeMediaEngine, _)."
            )
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

            let evaluatedDecision: SafeMediaDecision
            if let engine = activeEngine {
                loadState = .scanning
                evaluatedDecision = await engine.evaluate(
                    .imageFile(url),
                    context: context,
                    policy: policy,
                    cacheKey: cacheKey
                )
            } else {
                evaluatedDecision = failureDecision()
            }

            guard !Task.isCancelled else {
                return
            }

            // Decision must land before the image so the raw image is never
            // rendered without an intervention decision (fail closed).
            decision = evaluatedDecision
            image = loadedImage
            loadState = .loaded
        } catch {
            guard !Task.isCancelled else {
                return
            }
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
