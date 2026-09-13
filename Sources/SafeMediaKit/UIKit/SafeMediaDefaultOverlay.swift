#if canImport(UIKit)
import UIKit

/// The bundled UIKit overlay. Oversized copy scrolls without exposing the image.
@available(iOS 17.0, macCatalyst 17.0, *)
@MainActor
final class SafeMediaDefaultOverlay: UIView {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let textStack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let buttonsStack = UIStackView()
    private let revealButton = UIButton(type: .system)
    private let reportButton = UIButton(type: .system)
    private var state: SafeMediaOverlayState?
    private var measuredBounds: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func apply(_ state: SafeMediaOverlayState) {
        self.state = state
        iconView.image = UIImage(
            systemName: SafeMediaOverlayGlyph.systemImageName(for: state.decision))
        titleLabel.text = state.title
        messageLabel.text = state.message
        textStack.accessibilityLabel = "\(state.title). \(state.message)"
        revealButton.configuration?.title = state.configuration.revealButtonTitle
        reportButton.configuration?.title = state.configuration.reportButtonTitle
        revealButton.isHidden = !state.canReveal
        reportButton.isHidden = !state.canReport
        buttonsStack.isHidden = !state.canReveal && !state.canReport
        scrollView.contentOffset = .zero
        invalidateMeasurement()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, measuredBounds != bounds else { return }

        // Always measure the full candidate first, independently of the last
        // selected variant. No subviews are rebuilt during layout.
        var padding: CGFloat = 16
        var size = measure(showsIcon: true, padding: padding)
        if size.height + 2 * padding > bounds.height {
            padding = 12
            size = measure(showsIcon: false, padding: padding)
        }

        let horizontalInset = min(padding, bounds.width / 2)
        let verticalInset = min(padding, bounds.height / 2)
        scrollView.frame = bounds.insetBy(dx: horizontalInset, dy: verticalInset)
        stack.frame = CGRect(
            x: max(0, (scrollView.bounds.width - size.width) / 2),
            y: max(0, (scrollView.bounds.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
        scrollView.contentSize = CGSize(
            width: scrollView.bounds.width,
            height: max(scrollView.bounds.height, size.height)
        )
        scrollView.isScrollEnabled = size.height > scrollView.bounds.height
        scrollView.contentOffset = CGPoint(
            x: 0,
            y: min(
                max(0, scrollView.contentOffset.y),
                max(0, size.height - scrollView.bounds.height))
        )
        measuredBounds = bounds
    }

    private func measure(showsIcon: Bool, padding: CGFloat) -> CGSize {
        iconView.isHidden = !showsIcon
        let availableWidth = max(1, min(280, bounds.width - 2 * padding))
        let buttons = [revealButton, reportButton].filter { !$0.isHidden }
        let rowWidth =
            buttons.reduce(CGFloat.zero) {
                $0 + $1.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
            } + CGFloat(max(0, buttons.count - 1)) * buttonsStack.spacing
        buttonsStack.axis = rowWidth > availableWidth ? .vertical : .horizontal

        let naturalWidth = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            .width
        let width = min(availableWidth, naturalWidth)
        let size = stack.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(
            width: width,
            height: ceil(size.height * traitCollection.displayScale)
                / traitCollection.displayScale)
    }

    private func setUp() {
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delaysContentTouches = false
        addSubview(scrollView)
        scrollView.addSubview(stack)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12

        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            textStyle: .title2, scale: .large)
        iconView.tintColor = .secondaryLabel
        iconView.adjustsImageSizeForAccessibilityContentSizeCategory = true
        iconView.isAccessibilityElement = false
        stack.addArrangedSubview(iconView)

        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.isAccessibilityElement = true
        textStack.accessibilityTraits = .staticText
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isAccessibilityElement = false
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.isAccessibilityElement = false
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(textStack)

        var revealConfiguration = UIButton.Configuration.filled()
        revealConfiguration.cornerStyle = .capsule
        revealConfiguration.buttonSize = .small
        revealConfiguration.titleLineBreakMode = .byWordWrapping
        revealConfiguration.titleAlignment = .center
        revealButton.configuration = revealConfiguration
        revealButton.isAccessibilityElement = true
        revealButton.addTarget(self, action: #selector(revealTapped), for: .touchUpInside)
        var reportConfiguration = UIButton.Configuration.gray()
        reportConfiguration.cornerStyle = .capsule
        reportConfiguration.buttonSize = .small
        reportConfiguration.titleLineBreakMode = .byWordWrapping
        reportConfiguration.titleAlignment = .center
        reportButton.configuration = reportConfiguration
        reportButton.isAccessibilityElement = true
        reportButton.addTarget(self, action: #selector(reportTapped), for: .touchUpInside)
        buttonsStack.spacing = 8
        buttonsStack.addArrangedSubview(revealButton)
        buttonsStack.addArrangedSubview(reportButton)
        stack.addArrangedSubview(buttonsStack)

        updateFonts()
        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self, UITraitDisplayScale.self,
        ]) {
            (view: SafeMediaDefaultOverlay, _: UITraitCollection) in
            view.updateFonts()
            view.invalidateMeasurement()
        }
    }

    private func updateFonts() {
        titleLabel.font = .preferredFont(
            forTextStyle: .headline, compatibleWith: traitCollection)
        messageLabel.font = .preferredFont(
            forTextStyle: .footnote, compatibleWith: traitCollection)
    }

    private func invalidateMeasurement() {
        measuredBounds = nil
        setNeedsLayout()
    }

    @objc private func revealTapped() { state?.reveal() }
    @objc private func reportTapped() { state?.report() }
}
#endif
