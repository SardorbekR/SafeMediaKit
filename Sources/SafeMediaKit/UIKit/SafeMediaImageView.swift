#if canImport(UIKit)
import UIKit

@available(iOS 17.0, macCatalyst 17.0, *)
@MainActor
public final class SafeMediaImageView: UIView {
    private let imageView = UIImageView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let overlayView = UIStackView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let revealButton = UIButton(type: .system)
    private let reportButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var task: Task<Void, Never>?
    private var decision: SafeMediaDecision?
    private var policy: SafeMediaPolicy = .teenMessaging
    private var configuration: SafeMediaImageConfiguration = .default
    private var onReveal: @MainActor @Sendable () -> Void = {}
    private var onReport: @MainActor @Sendable () -> Void = {}
    private var loadGeneration = 0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    deinit {
        task?.cancel()
    }

    public func configure(
        imageURL: URL,
        engine: SafeMediaEngine,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        configuration: SafeMediaImageConfiguration = .default,
        cacheKey: SafeMediaCacheKey? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        task?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        self.policy = policy
        self.configuration = configuration
        self.onReveal = onReveal
        self.onReport = onReport
        self.decision = nil
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
                let data = try await SafeMediaImageView.readData(from: imageURL)
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
        overlayView.spacing = 10
        overlayView.isLayoutMarginsRelativeArrangement = true
        overlayView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 16,
            leading: 16,
            bottom: 16,
            trailing: 16
        )
        overlayView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.86)
        overlayView.isHidden = true
        addSubview(overlayView)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        revealButton.addTarget(self, action: #selector(revealTapped), for: .touchUpInside)
        reportButton.addTarget(self, action: #selector(reportTapped), for: .touchUpInside)

        overlayView.addArrangedSubview(titleLabel)
        overlayView.addArrangedSubview(messageLabel)
        overlayView.addArrangedSubview(revealButton)
        overlayView.addArrangedSubview(reportButton)

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

    private static func readData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
    }

    private func apply(_ decision: SafeMediaDecision) {
        setLoading(false)

        switch decision.action {
        case .allow:
            imageView.isHidden = false
            setHiddenState(false)
        case .block:
            imageView.isHidden = true
            setHiddenState(true)
            titleLabel.text = title(for: decision)
            messageLabel.text = message(for: decision)
            reportButton.setTitle(configuration.reportButtonTitle, for: .normal)
            revealButton.isHidden = true
            reportButton.isHidden = !(configuration.showsReportButton && decision.policy.allowReport)
        case .blur, .blurWithReveal, .interruptVideo, .muteAudio:
            imageView.isHidden = false
            setHiddenState(true)
            titleLabel.text = title(for: decision)
            messageLabel.text = message(for: decision)
            revealButton.setTitle(configuration.revealButtonTitle, for: .normal)
            reportButton.setTitle(configuration.reportButtonTitle, for: .normal)
            revealButton.isHidden = !(
                decision.action == .blurWithReveal
                    && decision.policy.allowReveal
                    && imageView.image != nil
            )
            reportButton.isHidden = !(configuration.showsReportButton && decision.policy.allowReport)
        }
    }

    private func title(for decision: SafeMediaDecision) -> String {
        switch decision.reason {
        case .unavailableByPolicy:
            configuration.unavailableTitle
        default:
            decision.action == .block ? configuration.blockedTitle : configuration.warningTitle
        }
    }

    private func message(for decision: SafeMediaDecision) -> String {
        switch decision.reason {
        case .unavailableByPolicy:
            configuration.unavailableMessage
        default:
            decision.action == .block ? configuration.blockedMessage : configuration.warningMessage
        }
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
        imageView.accessibilityElementsHidden = isHidden
    }

    @objc private func revealTapped() {
        imageView.isHidden = false
        setHiddenState(false)
        onReveal()
    }

    @objc private func reportTapped() {
        onReport()
    }
}
#endif
