#if canImport(UIKit)
import UIKit

/// A policy-aware UIKit image view that evaluates an image before displaying it.
///
/// The view keeps the image hidden while it loads and while the engine
/// evaluates it. Non-allow decisions show the bundled intervention overlay or
/// a custom overlay supplied by the host app until a permitted reveal removes
/// the intervention.
@available(iOS 17.0, macCatalyst 17.0, *)
@MainActor
public final class SafeMediaImageView: UIView {
    private let imageView = UIImageView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let overlayView = SafeMediaDefaultOverlay()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var task: Task<Void, Never>?
    private var decision: SafeMediaDecision?
    private var policy: SafeMediaPolicy = .teenMessaging
    private var configuration: SafeMediaImageConfiguration = .default
    private var onReveal: @MainActor @Sendable () -> Void = {}
    private var onReport: @MainActor @Sendable () -> Void = {}
    private var overlayProvider: (@MainActor (SafeMediaOverlayState) -> UIView)?
    private var customOverlayView: UIView?
    private var loadGeneration = 0

    /// Creates a safe media image view with the given frame.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    /// Creates a safe media image view from an archived interface description.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    deinit {
        task?.cancel()
    }

    /// Configures the view for a local image file URL. Other URL schemes
    /// produce a loading failure decision using the policy's `failureAction`.
    ///
    /// Pass `overlayProvider` to replace the built-in message/buttons overlay
    /// with a custom view. The provided view is pinned edge-to-edge above the
    /// redaction blur — the blur itself always stays underneath, so custom
    /// overlays cannot remove redaction. For each non-allow decision, the
    /// provider builds a new overlay view.
    ///
    /// Reconfiguring cancels the previous view task, discards any stale result,
    /// clears its image and decision, and keeps the new image hidden until its
    /// decision is applied.
    public func configure(
        imageURL: URL,
        engine: SafeMediaEngine,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        configuration: SafeMediaImageConfiguration = .default,
        cacheKey: SafeMediaCacheKey? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {},
        overlayProvider: (@MainActor (SafeMediaOverlayState) -> UIView)? = nil
    ) {
        task?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        self.policy = policy
        self.configuration = configuration
        self.onReveal = onReveal
        self.onReport = onReport
        self.overlayProvider = overlayProvider
        self.decision = nil
        removeCustomOverlay()
        imageView.image = nil
        // Stay hidden until a decision is applied (fail closed).
        imageView.isHidden = true
        setLoading(true)
        setHiddenState(false)

        task = Task { [weak self] in
            // Heavy awaits run without retaining the view so a released view
            // can deinit (and cancel this task) while work is in flight.
            let loadedImage: UIImage?
            do {
                let data = try await SafeMediaLocalFileLoader.readData(from: imageURL)
                loadedImage = UIImage(data: data)
            } catch {
                loadedImage = nil
            }

            guard !Task.isCancelled else {
                return
            }

            if let loadedImage {
                let decision = await engine.evaluate(
                    .imageFile(imageURL),
                    context: context,
                    policy: policy,
                    cacheKey: cacheKey
                )

                guard let self, !Task.isCancelled, generation == self.loadGeneration else {
                    return
                }

                // The decision is applied in the same run-loop pass as the
                // image so the raw image is never visible without one.
                self.imageView.image = loadedImage
                self.decision = decision
                self.apply(decision)
            } else {
                guard let self, !Task.isCancelled, generation == self.loadGeneration else {
                    return
                }

                let decision = SafeMediaDecision(
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
                self.decision = decision
                self.apply(decision)
            }
        }
    }

    private func setUp() {
        clipsToBounds = true
        backgroundColor = .secondarySystemBackground

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.isHidden = true
        addSubview(blurView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        addSubview(activityIndicator)

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.isHidden = true
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func apply(_ decision: SafeMediaDecision) {
        setLoading(false)

        let generation = loadGeneration
        let state = SafeMediaOverlayState(
            decision: decision,
            configuration: configuration,
            hasImage: imageView.image != nil,
            onReveal: { [weak self] in
                guard let self, generation == self.loadGeneration else {
                    return
                }
                self.revealMedia()
                self.onReveal()
            },
            onReport: { [weak self] in
                guard let self, generation == self.loadGeneration else {
                    return
                }
                self.onReport()
            }
        )

        switch decision.action {
        case .allow:
            removeCustomOverlay()
            imageView.isHidden = false
            setHiddenState(false)
        case .block, .blur, .blurWithReveal, .interruptVideo, .muteAudio:
            imageView.isHidden = decision.action == .block
            setHiddenState(true)

            if let overlayProvider {
                overlayView.isHidden = true
                installCustomOverlay(overlayProvider(state))
            } else {
                overlayView.apply(state)
            }
        }
    }

    private func installCustomOverlay(_ view: UIView) {
        removeCustomOverlay()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        customOverlayView = view
    }

    private func removeCustomOverlay() {
        customOverlayView?.removeFromSuperview()
        customOverlayView = nil
    }

    private func setLoading(_ isLoading: Bool) {
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func setHiddenState(_ isHidden: Bool) {
        blurView.isHidden = !isHidden
        overlayView.isHidden = !isHidden
        customOverlayView?.isHidden = !isHidden
        imageView.accessibilityElementsHidden = isHidden
    }

    private func revealMedia() {
        removeCustomOverlay()
        imageView.isHidden = false
        setHiddenState(false)
    }
}
#endif
