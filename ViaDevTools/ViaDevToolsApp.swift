import SwiftUI

@main
struct ViaDevToolsApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationStore.shared  // before launch finishes, so a tap that launched the app is logged
        application.registerForRemoteNotifications()  // the token arrives even before alert permission is granted
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationStore.shared.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationStore.shared.registrationError = error.localizedDescription
    }

    // ponytail: no remote-notification background mode, so silent pushes are only logged while the app is in the foreground
    nonisolated func application(_ application: UIApplication,
                                 didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let payload = NotificationStore.json(userInfo)  // convert before hopping to the main actor
        await NotificationStore.shared.record(.silent, title: nil, body: nil, payload: payload)
        return .noData
    }
}
