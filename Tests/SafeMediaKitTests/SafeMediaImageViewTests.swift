#if canImport(UIKit)
@testable import SafeMediaKit
import SafeMediaKitTesting
import UIKit
import XCTest

@MainActor
final class SafeMediaImageViewTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(
            Bundle.main.bundleURL.pathExtension != "app",
            "Run these UIKit tests with the SafeMediaUIKitQA app host."
        )
    }

    func testThumbnailKeepsTextAndActionsVisible() throws {
        let overlay = makeOverlay(size: CGSize(width: 240, height: 170))
        try assertContentFits(overlay)
        attach(overlay, name: "thumbnail-240x170")
    }

    func testCompactSelectionAndResizeBackToFull() throws {
        let overlay = makeOverlay(size: CGSize(width: 400, height: 600))
        let icon = try icon(in: overlay)
        let scroll = try scrollView(in: overlay)
        XCTAssertFalse(icon.isHidden)
        XCTAssertEqual(scroll.frame.minX, 16)
        overlay.frame.size = CGSize(width: 240, height: 140)
        overlay.layoutIfNeeded()
        XCTAssertTrue(icon.isHidden)
        XCTAssertEqual(scroll.frame.minX, 12)
        try assertContentFits(overlay)
        let compactFrame = try contentStack(in: overlay).frame
        for _ in 0..<5 {
            overlay.setNeedsLayout()
            overlay.layoutIfNeeded()
            XCTAssertTrue(icon.isHidden)
            XCTAssertEqual(try contentStack(in: overlay).frame, compactFrame)
        }
        attach(overlay, name: "compact-240x140")
        overlay.frame.size = CGSize(width: 400, height: 600)
        overlay.layoutIfNeeded()
        XCTAssertFalse(icon.isHidden)
        XCTAssertEqual(scroll.frame.minX, 16)
        XCTAssertFalse(scroll.isScrollEnabled)
        try assertContentFits(overlay)
    }

    func testLargeLayoutMatchesExistingGeometry() throws {
        let overlay = makeOverlay(size: CGSize(width: 400, height: 600))
        let stack = try contentStack(in: overlay)
        let frame = stack.convert(stack.bounds, to: overlay)
        // Measured from the original UIKit overlay at the default text size.
        XCTAssertEqual(frame.width, 210.667, accuracy: 1)
        XCTAssertEqual(frame.height, 118.333, accuracy: 1)
        XCTAssertEqual(frame.midX, 200, accuracy: 0.5)
        XCTAssertEqual(frame.midY, 300, accuracy: 0.5)
        XCTAssertFalse(try icon(in: overlay).isHidden)
        attach(overlay, name: "large-400x600")
    }

    func testLongCopyScrollsAndAllActionsAreReachable() throws {
        var configuration = SafeMediaImageConfiguration.default
        configuration.warningMessage = String(
            repeating:
                "Please review this warning before choosing whether to reveal the media. ",
            count: 8)
        configuration.revealButtonTitle = "Show this image anyway"
        configuration.reportButtonTitle = "Report this image"
        let overlay = makeOverlay(
            size: CGSize(width: 240, height: 170), configuration: configuration)
        let scroll = try scrollView(in: overlay)
        let buttons = descendants(of: overlay).compactMap { $0 as? UIButton }
        XCTAssertTrue(try icon(in: overlay).isHidden)
        XCTAssertTrue(scroll.isScrollEnabled)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        let buttonStack = try XCTUnwrap(buttons.first?.superview as? UIStackView)
        XCTAssertEqual(buttonStack.axis, .vertical)
        try assertTextIsNotTruncated(in: overlay)
        for button in buttons {
            let rect = button.convert(button.bounds, to: scroll)
            scroll.scrollRectToVisible(rect, animated: false)
            XCTAssertTrue(scroll.bounds.insetBy(dx: -1, dy: -1).contains(rect))
        }
        attach(overlay, name: "long-copy-scrolled-to-actions")
    }

    func testLongIndividualButtonTitlesWrapWithoutTruncation() throws {
        var configuration = SafeMediaImageConfiguration.default
        configuration.revealButtonTitle = "Show this image anyway after reading the warning"
        configuration.reportButtonTitle = "Report this image to the conversation moderator"
        let overlay = makeOverlay(
            size: CGSize(width: 240, height: 170), configuration: configuration)
        let scroll = try scrollView(in: overlay)
        for button in descendants(of: overlay).compactMap({ $0 as? UIButton }) {
            let label = try XCTUnwrap(button.titleLabel)
            XCTAssertEqual(label.text, button.configuration?.title)
            XCTAssertGreaterThan(label.bounds.width, 0)
            let required = label.sizeThatFits(
                CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
            XCTAssertGreaterThan(
                required.height, label.font.lineHeight, "This fixture must exercise wrapping")
            XCTAssertGreaterThanOrEqual(label.bounds.height + 1, required.height)
            XCTAssertTrue(button.bounds.contains(label.convert(label.bounds, to: button)))
            let rect = button.convert(button.bounds, to: scroll)
            scroll.scrollRectToVisible(rect, animated: false)
            XCTAssertTrue(scroll.bounds.insetBy(dx: -1, dy: -1).contains(rect))
        }
        attach(overlay, name: "wrapped-action-titles")
    }

    func testDynamicTypeChangesRemeasureAndRestoreLayout() throws {
        let overlay = makeOverlay(size: CGSize(width: 240, height: 170))
        let originalHeight = try contentStack(in: overlay).frame.height
        let label = try XCTUnwrap(descendants(of: overlay).compactMap { $0 as? UILabel }.first)
        let originalFontSize = label.font.pointSize
        overlay.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        overlay.updateTraitsIfNeeded()
        overlay.layoutIfNeeded()
        XCTAssertGreaterThan(label.font.pointSize, originalFontSize)
        XCTAssertGreaterThan(try contentStack(in: overlay).frame.height, originalHeight)
        XCTAssertTrue(try scrollView(in: overlay).isScrollEnabled)
        try assertTextIsNotTruncated(in: overlay)
        attach(overlay, name: "accessibility-largest")
        overlay.traitOverrides.preferredContentSizeCategory = .large
        overlay.updateTraitsIfNeeded()
        overlay.layoutIfNeeded()
        XCTAssertEqual(try contentStack(in: overlay).frame.height, originalHeight, accuracy: 1)
        XCTAssertFalse(try scrollView(in: overlay).isScrollEnabled)
    }

    func testVoiceOverCombinesTextAndKeepsActionsSeparateInBothLayouts() throws {
        for size in [CGSize(width: 400, height: 600), CGSize(width: 240, height: 140)] {
            let overlay = makeOverlay(size: size)
            let textGroup = try XCTUnwrap(
                descendants(of: overlay).first {
                    $0.accessibilityLabel
                        == "This may be sensitive. You can choose whether to view it."
                })
            XCTAssertTrue(textGroup.isAccessibilityElement)
            XCTAssertTrue(textGroup.accessibilityTraits.contains(.staticText))
            XCTAssertTrue(textGroup.subviews.allSatisfy { !$0.isAccessibilityElement })
            let buttons = descendants(of: overlay).compactMap { $0 as? UIButton }
            XCTAssertEqual(buttons.count, 2)
            for button in buttons {
                let title = button.configuration?.title ?? "Action"
                XCTAssertTrue(
                    button.isAccessibilityElement, "\(title) must be an accessibility element")
                XCTAssertFalse(button.isHidden, "\(title) must be visible")
            }
            XCTAssertFalse(try icon(in: overlay).isAccessibilityElement)
        }
    }

    func testContentAndPolicyChangesResetScrolledOverlay() throws {
        let overlay = makeOverlay(size: CGSize(width: 240, height: 140))
        var configuration = SafeMediaImageConfiguration.default
        configuration.warningMessage = String(repeating: "Long warning. ", count: 100)
        overlay.apply(makeState(configuration: configuration))
        overlay.layoutIfNeeded()
        let scroll = try scrollView(in: overlay)
        scroll.contentOffset.y = scroll.contentSize.height - scroll.bounds.height
        overlay.apply(makeState(policy: .childStrict))
        overlay.layoutIfNeeded()
        XCTAssertEqual(scroll.contentOffset, .zero)
        let buttons = descendants(of: overlay).compactMap { $0 as? UIButton }
        XCTAssertTrue(
            try XCTUnwrap(buttons.first { $0.configuration?.title == "Show" }).isHidden)
        XCTAssertFalse(
            try XCTUnwrap(buttons.first { $0.configuration?.title == "Report" }).isHidden)
        try assertContentFits(overlay)
    }

    func testDefaultActionsAndImageRedaction() async throws {
        var reveals = 0
        var reports = 0
        let view = try await makeImageView(
            onReveal: { reveals += 1 }, onReport: { reports += 1 })
        let image = try XCTUnwrap(view.subviews.compactMap { $0 as? UIImageView }.first)
        let blur = try XCTUnwrap(view.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        let overlay = try XCTUnwrap(
            view.subviews.compactMap { $0 as? SafeMediaDefaultOverlay }.first)
        XCTAssertFalse(blur.isHidden)
        XCTAssertTrue(image.accessibilityElementsHidden)
        let buttons = descendants(of: overlay).compactMap { $0 as? UIButton }
        try XCTUnwrap(buttons.first { $0.configuration?.title == "Report" }).sendActions(
            for: .touchUpInside)
        XCTAssertEqual(reports, 1)
        XCTAssertFalse(blur.isHidden)
        try XCTUnwrap(buttons.first { $0.configuration?.title == "Show" }).sendActions(
            for: .touchUpInside)
        XCTAssertEqual(reveals, 1)
        XCTAssertTrue(blur.isHidden)
        XCTAssertTrue(overlay.isHidden)
        XCTAssertFalse(image.isHidden)
        XCTAssertFalse(image.accessibilityElementsHidden)
    }

    func testCustomOverlayRemainsEdgeToEdgeAboveRedaction() async throws {
        let custom = UIView()
        var creations = 0
        let view = try await makeImageView(overlayProvider: { _ in
            creations += 1
            return custom
        })
        for size in [CGSize(width: 240, height: 140), CGSize(width: 400, height: 600)] {
            view.frame.size = size
            view.layoutIfNeeded()
            XCTAssertEqual(custom.frame, view.bounds)
            XCTAssertTrue(view.subviews.last === custom)
            XCTAssertTrue(
                try XCTUnwrap(view.subviews.compactMap { $0 as? SafeMediaDefaultOverlay }.first)
                    .isHidden)
            XCTAssertFalse(
                try XCTUnwrap(view.subviews.compactMap { $0 as? UIVisualEffectView }.first)
                    .isHidden)
        }
        XCTAssertEqual(creations, 1)
    }

    func testCustomAndDefaultTransitionsIgnoreStaleActions() async throws {
        let firstCustom = UIView()
        let secondCustom = UIView()
        var firstState: SafeMediaOverlayState?
        var staleRevealCount = 0
        let view = try await makeImageView(
            onReveal: { staleRevealCount += 1 },
            overlayProvider: { state in
                firstState = state
                return firstCustom
            })
        _ = try await makeImageView(reusing: view)
        XCTAssertNil(firstCustom.superview)
        let defaultOverlay = try XCTUnwrap(
            view.subviews.compactMap { $0 as? SafeMediaDefaultOverlay }.first)
        let blur = try XCTUnwrap(view.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        XCTAssertFalse(defaultOverlay.isHidden)
        try XCTUnwrap(firstState).reveal()
        XCTAssertFalse(
            blur.isHidden, "A stale custom state cannot reveal the newly configured image")
        XCTAssertEqual(staleRevealCount, 0)

        _ = try await makeImageView(reusing: view, overlayProvider: { _ in secondCustom })
        XCTAssertTrue(defaultOverlay.isHidden)
        XCTAssertFalse(blur.isHidden)
        XCTAssertEqual(secondCustom.frame, view.bounds)
        XCTAssertTrue(view.subviews.last === secondCustom)
    }

    private func makeOverlay(
        size: CGSize, configuration: SafeMediaImageConfiguration = .default
    ) -> SafeMediaDefaultOverlay {
        let overlay = SafeMediaDefaultOverlay(frame: CGRect(origin: .zero, size: size))
        overlay.overrideUserInterfaceStyle = .light
        overlay.traitOverrides.preferredContentSizeCategory = .large
        overlay.backgroundColor = .secondarySystemBackground
        overlay.apply(makeState(configuration: configuration))
        overlay.layoutIfNeeded()
        return overlay
    }

    private func makeState(
        configuration: SafeMediaImageConfiguration = .default,
        policy: SafeMediaPolicy = .teenMessaging
    ) -> SafeMediaOverlayState {
        SafeMediaOverlayState(
            decision: SafeMediaDecision(
                action: policy.sensitiveAction, verdict: .mockSensitive,
                context: .incomingMessage, policy: policy, reason: .sensitiveDetected),
            configuration: configuration, hasImage: true, onReveal: {}, onReport: {}
        )
    }

    private func makeImageView(
        reusing existingView: SafeMediaImageView? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {},
        overlayProvider: (@MainActor (SafeMediaOverlayState) -> UIView)? = nil
    ) async throws -> SafeMediaImageView {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        ).appendingPathExtension("png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image {
            context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let view =
            existingView ?? SafeMediaImageView(frame: CGRect(x: 0, y: 0, width: 240, height: 170))
        view.configure(
            imageURL: url,
            engine: SafeMediaEngine(
                analyzer: MockSafeMediaAnalyzer(result: .success(.mockSensitive))),
            context: .incomingMessage, policy: .teenMessaging,
            onReveal: onReveal, onReport: onReport, overlayProvider: overlayProvider
        )
        let displayedImage = try XCTUnwrap(
            view.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertTrue(displayedImage.isHidden, "The image must remain hidden during analysis")
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        // The public view has no completion callback; observe its rendered state.
        while displayedImage.image == nil {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "SafeMediaImageViewTests", code: 1)
            }
            await Task.yield()
        }
        view.layoutIfNeeded()
        return view
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func scrollView(in overlay: UIView) throws -> UIScrollView {
        try XCTUnwrap(overlay.subviews.compactMap { $0 as? UIScrollView }.first)
    }

    private func contentStack(in overlay: UIView) throws -> UIStackView {
        try XCTUnwrap(scrollView(in: overlay).subviews.compactMap { $0 as? UIStackView }.first)
    }

    private func icon(in overlay: UIView) throws -> UIImageView {
        try XCTUnwrap(
            contentStack(in: overlay).arrangedSubviews.compactMap { $0 as? UIImageView }.first)
    }

    private func assertContentFits(
        _ overlay: UIView, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let scroll = try scrollView(in: overlay)
        XCTAssertFalse(scroll.isScrollEnabled, file: file, line: line)
        XCTAssertTrue(
            scroll.bounds.insetBy(dx: -1, dy: -1).contains(try contentStack(in: overlay).frame),
            file: file, line: line)
        try assertTextIsNotTruncated(in: overlay, file: file, line: line)
        for button in descendants(of: overlay).compactMap({ $0 as? UIButton }).filter({
            !$0.isHidden
        }) {
            XCTAssertTrue(
                overlay.bounds.contains(button.convert(button.bounds, to: overlay)), file: file,
                line: line)
            XCTAssertGreaterThan(button.frame.height, 0, file: file, line: line)
        }
    }

    private func assertTextIsNotTruncated(
        in overlay: UIView, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for label in descendants(of: overlay).compactMap({ $0 as? UILabel })
        where !(label.superview is UIButton) {
            guard !label.isHidden, label.frame.width > 0 else { continue }
            let required = label.sizeThatFits(
                CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
            XCTAssertGreaterThanOrEqual(
                label.bounds.height + 1, required.height, label.text ?? "", file: file,
                line: line)
        }
    }

    private func attach(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
