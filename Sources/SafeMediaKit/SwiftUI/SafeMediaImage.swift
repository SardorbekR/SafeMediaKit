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

/// A policy-aware image view that evaluates an image before displaying it.
///
/// The view keeps the image concealed while it loads and while the engine
/// evaluates it. Non-allow decisions use either the bundled intervention
/// overlay or the custom overlay supplied by the host app until a permitted
/// reveal removes the intervention.
///
/// The view accepts local file URLs only. Other URL schemes produce a loading
/// failure decision using the policy's `failureAction`.
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, *)
public struct SafeMediaImage<Overlay: View>: View {
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
    private let overlayContent: (SafeMediaOverlayState) -> Overlay

    @Environment(\.safeMediaEngine) private var environmentEngine
    @State private var image: SafeMediaPlatformImage?
    @State private var decision: SafeMediaDecision?
    @State private var loadState: LoadState = .idle
    @State private var isRevealed = false

    /// Creates an image view for a local file with a custom intervention
    /// overlay. The overlay closure receives a ``SafeMediaOverlayState`` and
    /// replaces the built-in overlay for every non-allow state.
    public init(
        url: URL,
        engine: SafeMediaEngine,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        configuration: SafeMediaImageConfiguration = .default,
        cacheKey: SafeMediaCacheKey? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {},
        @ViewBuilder overlay: @escaping (SafeMediaOverlayState) -> Overlay
    ) {
        self.url = url
        self.explicitEngine = engine
        self.context = context
        self.policy = policy
        self.configuration = configuration
        self.cacheKey = cacheKey
        self.onReveal = onReveal
        self.onReport = onReport
        self.overlayContent = overlay
    }

    /// Creates an image view for a local file with a custom overlay and an
    /// engine from the environment.
    ///
    /// Install the engine with `.environment(\.safeMediaEngine, engine)`. A
    /// missing engine triggers a debug assertion; builds with assertions
    /// disabled use `policy.failureAction`.
    public init(
        url: URL,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        configuration: SafeMediaImageConfiguration = .default,
        cacheKey: SafeMediaCacheKey? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {},
        @ViewBuilder overlay: @escaping (SafeMediaOverlayState) -> Overlay
    ) {
        self.url = url
        self.explicitEngine = nil
        self.context = context
        self.policy = policy
        self.configuration = configuration
        self.cacheKey = cacheKey
        self.onReveal = onReveal
        self.onReport = onReport
        self.overlayContent = overlay
    }

    /// The view's evaluated image, placeholder, and intervention overlay.
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
        overlayContent(makeOverlayState())
    }

    private func makeOverlayState() -> SafeMediaOverlayState {
        let revealed = $isRevealed
        let hostOnReveal = onReveal

        return SafeMediaOverlayState(
            decision: decision ?? failureDecision(),
            configuration: configuration,
            hasImage: image != nil,
            onReveal: {
                revealed.wrappedValue = true
                hostOnReveal()
            },
            onReport: onReport
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
            let data = try await SafeMediaLocalFileLoader.readData(from: url)

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

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, *)
public extension SafeMediaImage where Overlay == SensitiveMediaOverlay {
    /// Creates an image view for a local file with the bundled default
    /// intervention overlay.
    init(
        url: URL,
        engine: SafeMediaEngine,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        configuration: SafeMediaImageConfiguration = .default,
        cacheKey: SafeMediaCacheKey? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.init(
            url: url,
            engine: engine,
            context: context,
            policy: policy,
            configuration: configuration,
            cacheKey: cacheKey,
            onReveal: onReveal,
            onReport: onReport,
            overlay: { SensitiveMediaOverlay(state: $0) }
        )
    }

    /// Creates an image view for a local file with the bundled overlay and an
    /// engine from the environment.
    ///
    /// Install the engine with `.environment(\.safeMediaEngine, engine)`. A
    /// missing engine triggers a debug assertion; builds with assertions
    /// disabled use `policy.failureAction`.
    init(
        url: URL,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        configuration: SafeMediaImageConfiguration = .default,
        cacheKey: SafeMediaCacheKey? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.init(
            url: url,
            context: context,
            policy: policy,
            configuration: configuration,
            cacheKey: cacheKey,
            onReveal: onReveal,
            onReport: onReport,
            overlay: { SensitiveMediaOverlay(state: $0) }
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
