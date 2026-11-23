import SwiftUI

@main
struct ViaDevToolsApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { KeyboardDismisser.shared.install() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationStore.shared  // before launch finishes, so a tap that launched the app is logged
        return true
    }
}

/// Tapping anywhere outside a text field dismisses the keyboard, on every screen.
/// A window-level recognizer that doesn't cancel touches, so buttons and rows still work.
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()
    private var installed = false

    func install() {
        guard !installed, let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        installed = true
    }

    @objc private func dismiss(_ tap: UITapGestureRecognizer) {
        tap.view?.endEditing(true)
    }

    // Ignore taps on (or inside) a text input, so moving between fields keeps the keyboard up.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        return !sequence(first: view, next: \.superview).contains { $0 is UITextInput }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
