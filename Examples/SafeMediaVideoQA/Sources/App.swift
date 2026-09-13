import AVFoundation
import SafeMediaKit
import SensitiveContentAnalysis
import UIKit
import UniformTypeIdentifiers

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if CommandLine.arguments.contains("--qa-policy-preflight") {
            // Diagnostic mode emits only policy availability, never constructs
            // a media source, then exits before an operator can start media.
            print(
                SCSensitivityAnalyzer().analysisPolicy == .disabled
                    ? "QA readiness: system analysis policy disabled"
                    : "QA readiness: system analysis policy enabled")
            exit(EXIT_SUCCESS)
        }
        if CommandLine.arguments.contains("--qa-decode-attachment-smoke") {
            Task { @MainActor in
                let passed = await DecodeAttachmentSmoke.run()
                exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) {
        // The no-frame diagnostic exposes no controls that could start media.
        guard !CommandLine.arguments.contains("--qa-decode-attachment-smoke") else { return }
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = QAViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
    func sceneWillResignActive(_ scene: UIScene) {
        (window?.rootViewController as? QAViewController)?.stop()
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        (window?.rootViewController as? QAViewController)?.dispose()
    }
}

@MainActor
final class QAViewController: UIViewController, UIDocumentPickerDelegate {
    private let status = UILabel()
    private let metrics = UILabel()
    private let preview = UIView()
    private let decoded = UIImageView()
    private let cover = UILabel()
    private let mode = UISegmentedControl(items: ["Camera", "Local decode"])
    private let cancelStartup = UISwitch()
    private let resume = UIButton(type: .system)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var capture: CapturePipeline?
    private var decoder: DecodePipeline?
    private var analyzer: AppleSensitiveContentStreamAnalyzer?
    private var events: Task<Void, Never>?
    private var teardown: Task<Void, Never>?
    private var selectedURL: URL?
    private var securityScope = false
    private var generation = 0
    private var participantID = UUID().uuidString
    private var sessionCount = 0
    private var readyAt: ContinuousClock.Instant?
    private var stimulusAt: ContinuousClock.Instant?
    private var permitsFrames = false

    isolated deinit {
        if securityScope { selectedURL?.stopAccessingSecurityScopedResource() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "Live video QA"
        title.font = .preferredFont(forTextStyle: .title1)
        let explanation = UILabel()
        explanation.text =
            "Stopped by default. No microphone, recording, network, analytics, or saved results. Media observations stay on this device."
        explanation.numberOfLines = 0
        explanation.font = .preferredFont(forTextStyle: .footnote)
        mode.selectedSegmentIndex = 0
        status.numberOfLines = 0
        status.text = "Stopped · choose a source and check policy"
        metrics.numberOfLines = 0
        metrics.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cover.text = "Stream concealed"
        cover.textAlignment = .center
        cover.backgroundColor = .secondarySystemBackground
        decoded.contentMode = .scaleAspectFit
        preview.backgroundColor = .black
        for child in [decoded, cover] {
            child.translatesAutoresizingMaskIntoConstraints = false
            preview.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
                child.topAnchor.constraint(equalTo: preview.topAnchor),
                child.bottomAnchor.constraint(equalTo: preview.bottomAnchor),
            ])
        }
        preview.heightAnchor.constraint(equalToConstant: 210).isActive = true
        let cancellationLabel = UILabel()
        cancellationLabel.text = "Probe startup cancellation"
        cancellationLabel.font = .preferredFont(forTextStyle: .footnote)
        let cancellationRow = UIStackView(arrangedSubviews: [cancellationLabel, cancelStartup])
        cancellationRow.axis = .horizontal
        let controls = UIStackView(arrangedSubviews: [
            button("Check policy", action: #selector(checkPolicy)),
            button("Choose local video", action: #selector(chooseFile)),
            button("Start / repeat", action: #selector(start)),
            button("Stop", action: #selector(stop)),
        ])
        controls.axis = .horizontal
        controls.distribution = .fillEqually
        resume.setTitle("Resume", for: .normal)
        resume.addTarget(self, action: #selector(continueStream), for: .touchUpInside)
        resume.isEnabled = false
        let extra = UIStackView(arrangedSubviews: [
            button("Mark stimulus", action: #selector(markStimulus)), resume,
            button("New participant", action: #selector(newParticipant)),
        ])
        extra.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [
            title, explanation, mode, preview,
            status, metrics, cancellationRow, controls, extra,
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = preview.bounds
    }

    private func button(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func checkPolicy() {
        status.text =
            SCSensitivityAnalyzer().analysisPolicy == .disabled
            ? "System analysis policy is disabled. Change it manually if you choose."
            : "System policy enabled. Attachment still requires valid signing and device support."
    }

    @objc private func chooseFile() {
        stop()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: false)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
    ) {
        if securityScope { selectedURL?.stopAccessingSecurityScopedResource() }
        selectedURL = urls.first
        securityScope = selectedURL?.startAccessingSecurityScopedResource() ?? false
        mode.selectedSegmentIndex = 1
        status.text = "Local video selected. Press Start when ready."
    }

    @objc private func start() {
        stop()
        let current = generation
        let previousTeardown = teardown
        let useCamera = mode.selectedSegmentIndex == 0
        let shouldCancel = cancelStartup.isOn
        let url = selectedURL
        status.text = "Preparing"
        events = Task { @MainActor [weak self] in
            guard let self else { return }
            await previousTeardown?.value
            guard current == generation, !Task.isCancelled else { return }
            do {
                if useCamera {
                    let allowed = await AVCaptureDevice.requestAccess(for: .video)
                    guard current == generation, !Task.isCancelled else { return }
                    guard allowed else {
                        status.text = "Camera permission not granted"
                        return
                    }
                    let capture = try CapturePipeline()
                    self.capture = capture
                    let layer = AVCaptureVideoPreviewLayer(session: capture.session)
                    layer.videoGravity = .resizeAspect
                    layer.frame = preview.bounds
                    preview.layer.insertSublayer(layer, at: 0)
                    previewLayer = layer
                    analyzer = AppleSensitiveContentStreamAnalyzer(
                        participantID: participantID, captureDeviceInput: capture.input)
                } else {
                    guard let url else {
                        status.text = "Choose a local test video first"
                        return
                    }
                    let decoder = try await DecodePipeline(url: url)
                    guard current == generation, !Task.isCancelled else {
                        decoder.stop()
                        return
                    }
                    self.decoder = decoder
                    analyzer = AppleSensitiveContentStreamAnalyzer(
                        participantID: participantID, decompressionSession: decoder.session)
                }
                guard let analyzer else { return }
                let availability = await analyzer.availability()
                guard current == generation, !Task.isCancelled else { return }
                guard availability == .available else {
                    stop()
                    status.text = "Analysis unavailable. Check policy, entitlement, and platform."
                    return
                }
                let startTime = ContinuousClock.now
                let attachment = Task { @MainActor in try await analyzer.startAnalysis() }
                if shouldCancel {
                    // Yield gives startup an opportunity to begin, but does not
                    // guarantee job order or where cancellation is observed.
                    await Task.yield()
                    attachment.cancel()
                }
                let stream = try await withTaskCancellationHandler {
                    try await attachment.value
                } onCancel: {
                    attachment.cancel()
                }
                guard current == generation, !Task.isCancelled else {
                    analyzer.endAnalysis()
                    return
                }
                if shouldCancel {
                    stop()
                    status.text =
                        "Cancellation probe returned a stream before cancellation; repeat probe."
                    return
                }
                sessionCount += 1
                readyAt = .now
                metrics.text =
                    "Session \(sessionCount) · participant reused\nAttachment: \(milliseconds(startTime.duration(to: .now))) ms"
                status.text = "Attached · readiness is not a safe-frame verdict"
                permitsFrames = true
                cover.isHidden = true
                if let capture { await capture.start() }
                guard current == generation, !Task.isCancelled else { return }
                decoder?.start(
                    frame: { [weak self] image in
                        guard let self, self.generation == current, self.permitsFrames else {
                            return
                        }
                        self.decoded.image = UIImage(cgImage: image)
                    },
                    completion: { [weak self] in
                        guard let self, self.generation == current else { return }
                        self.stop()
                        self.status.text =
                            "Local playback ended or decoder stopped. Start repeats from the beginning."
                    })
                for try await _ in stream {
                    guard current == generation, !Task.isCancelled else { return }
                    // Test-only direct adapter use: conceal every delivered
                    // result, avoiding policy-based automatic resume.
                    conceal()
                    resume.isEnabled = true
                    status.text = "Local intervention · Resume explicitly continues analysis"
                    if let stimulusAt {
                        metrics.text =
                            "Local stimulus-to-handler: \(milliseconds(stimulusAt.duration(to: .now))) ms\nManual timing includes operator delay."
                    }
                }
                guard current == generation, !Task.isCancelled else { return }
                stop()
                status.text = "Analysis ended; pipeline concealed and stopped"
            } catch {
                guard current == generation else { return }
                let cancelled = error is CancellationError || Task.isCancelled
                stop()
                status.text =
                    cancelled
                    ? "Startup cancelled; pipeline stopped"
                    : "Setup or analysis failed; pipeline stopped"
            }
        }
    }

    @objc func stop() {
        conceal()
        generation += 1
        events?.cancel()
        events = nil
        analyzer?.endAnalysis()
        analyzer = nil
        decoder?.stop()
        decoder = nil
        let oldCapture = capture
        capture = nil
        let prior = teardown
        teardown = Task {
            await prior?.value
            await oldCapture?.stop()
        }
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        decoded.image = nil
        readyAt = nil
        stimulusAt = nil
        resume.isEnabled = false
        status.text = "Stopped"
    }

    func dispose() {
        stop()
        if securityScope { selectedURL?.stopAccessingSecurityScopedResource() }
        securityScope = false
        selectedURL = nil
    }

    private func conceal() {
        permitsFrames = false
        cover.isHidden = false
        decoded.image = nil
        decoder?.discardPendingFrames()
    }

    @objc private func continueStream() {
        guard resume.isEnabled, analyzer != nil else { return }
        analyzer?.continueStream()
        decoder?.discardPendingFrames()
        permitsFrames = true
        cover.isHidden = true
        resume.isEnabled = false
        stimulusAt = nil
        status.text = "Resumed locally"
    }

    @objc private func markStimulus() {
        guard readyAt != nil else { return }
        stimulusAt = .now
        metrics.text = "Stimulus marker set locally; show the approved test marker now."
    }

    @objc private func newParticipant() {
        stop()
        participantID = UUID().uuidString
        sessionCount = 0
        metrics.text = "New call-scoped participant. Subsequent starts reuse this ID."
    }

    private func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        return String(
            format: "%.1f",
            Double(components.seconds) * 1_000
                + Double(components.attoseconds) / 1e15)
    }
}
