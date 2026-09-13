import SafeMediaKit
import SafeMediaKitTesting
import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
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
        _ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions
    ) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = OverlayGalleryController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

@MainActor
private final class OverlayGalleryController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(
                equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SafeMediaUIKitQA-placeholder.png")
        do {
            guard let data = image.pngData() else { return }
            try data.write(to: url)
        } catch { return }
        let engine = SafeMediaEngine(
            analyzer: MockSafeMediaAnalyzer(result: .success(.mockSensitive)))
        for (name, size) in [
            ("Thumbnail 240 × 170", CGSize(width: 240, height: 170)),
            ("Compact 240 × 140", CGSize(width: 240, height: 140)),
            ("Large 400 × 600", CGSize(width: 400, height: 600)),
        ] {
            let label = UILabel()
            label.text = name
            label.font = .preferredFont(forTextStyle: .headline)
            stack.addArrangedSubview(label)
            let media = SafeMediaImageView()
            media.configure(
                imageURL: url, engine: engine, context: .incomingMessage, policy: .teenMessaging)
            media.widthAnchor.constraint(equalToConstant: size.width).isActive = true
            media.heightAnchor.constraint(equalToConstant: size.height).isActive = true
            stack.addArrangedSubview(media)
        }
    }
}
