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
    private let overlayView = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let revealButton = UIButton(type: .system)
    private let reportButton = UIButton(type: .system)
    private let buttonsStack = UIStackView()
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
        overlayView.axis = .vertical
        overlayView.alignment = .center
        overlayView.spacing = 12
        overlayView.isHidden = true
        addSubview(overlayView)

        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            textStyle: .title2,
            scale: .large
        )
        iconView.tintColor = .secondaryLabel
        iconView.adjustsImageSizeForAccessibilityContentSizeCategory = true
        iconView.isAccessibilityElement = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.textColor = .secondaryLabel
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        var revealConfiguration = UIButton.Configuration.filled()
        revealConfiguration.cornerStyle = .capsule
        revealConfiguration.buttonSize = .small
        revealButton.configuration = revealConfiguration
        revealButton.addTarget(self, action: #selector(revealTapped), for: .touchUpInside)

        var reportConfiguration = UIButton.Configuration.gray()
        reportConfiguration.cornerStyle = .capsule
        reportConfiguration.buttonSize = .small
        reportButton.configuration = reportConfiguration
        reportButton.addTarget(self, action: #selector(reportTapped), for: .touchUpInside)

        buttonsStack.axis = .horizontal
        buttonsStack.spacing = 8
        buttonsStack.addArrangedSubview(revealButton)
        buttonsStack.addArrangedSubview(reportButton)

        overlayView.addArrangedSubview(iconView)
        overlayView.addArrangedSubview(titleLabel)
        overlayView.addArrangedSubview(messageLabel)
        overlayView.addArrangedSubview(buttonsStack)
        overlayView.setCustomSpacing(4, after: titleLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlayView.centerXAnchor.constraint(equalTo: centerXAnchor),
            overlayView.centerYAnchor.constraint(equalTo: centerYAnchor),
            overlayView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            overlayView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            overlayView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            // Lower priority so cramped frames compress the overlay (clipping
            // the icon edge) instead of breaking the layout.
            prioritized(overlayView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16)),
            prioritized(overlayView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16)),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func prioritized(
        _ constraint: NSLayoutConstraint,
        _ priority: UILayoutPriority = .defaultHigh
    ) -> NSLayoutConstraint {
        constraint.priority = priority
        return constraint
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
                applyDefaultOverlay(with: state)
            }
        }
    }

    private func applyDefaultOverlay(with state: SafeMediaOverlayState) {
        iconView.image = UIImage(
            systemName: SafeMediaOverlayGlyph.systemImageName(for: state.decision)
        )
        titleLabel.text = state.title
        messageLabel.text = state.message

        revealButton.configuration?.title = state.configuration.revealButtonTitle
        reportButton.configuration?.title = state.configuration.reportButtonTitle
        revealButton.isHidden = !state.canReveal
        reportButton.isHidden = !state.canReport
        buttonsStack.isHidden = !state.canReveal && !state.canReport
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

    @objc private func revealTapped() {
        revealMedia()
        onReveal()
    }

    @objc private func reportTapped() {
        onReport()
    }
}
#endif
