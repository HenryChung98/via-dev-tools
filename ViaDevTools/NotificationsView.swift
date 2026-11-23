import SwiftUI
import UserNotifications

@Observable
final class NotificationStore: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationStore()

    enum Event { case presented, opened, silent }

    struct Received: Identifiable {
        let id = UUID()
        let date = Date()
        let event: Event
        let isRemote: Bool
        let title: String?
        let body: String?
        let payload: String
    }

    var authorization = UNAuthorizationStatus.notDetermined
    var deviceToken: String?
    var registrationError: String?
    var received: [Received] = []

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    nonisolated static func json(_ userInfo: [AnyHashable: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: userInfo, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\(userInfo)"
    }

    func record(_ event: Event, title: String?, body: String?, payload: String, isRemote: Bool = true) {
        received.insert(Received(event: event, isRemote: isRemote, title: title, body: body, payload: payload), at: 0)
    }

    private func record(_ event: Event, _ n: UNNotification) {
        let c = n.request.content
        record(event, title: c.title, body: c.body, payload: Self.json(c.userInfo),
               isRemote: n.request.trigger is UNPushNotificationTrigger)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        record(.presented, notification)
        return [.banner, .list, .sound]  // show banners even while the app is open
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        record(.opened, response.notification)
    }

    var authorizationText: String {
        switch authorization {
        case .notDetermined: String(localized: "Not Determined")
        case .denied: String(localized: "Denied")
        case .authorized: String(localized: "Authorized")
        case .provisional: String(localized: "Provisional")
        case .ephemeral: String(localized: "Ephemeral")
        @unknown default: String(localized: "Unknown")
        }
    }
}

/// Permission row + request/settings button, shared by both notification screens.
struct NotificationPermissionSection: View {
    let store = NotificationStore.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("Permission") {
            valueRow("Status", store.authorizationText)
            if store.authorization == .notDetermined {
                Button("Request Permission") { Task { await store.requestAuthorization() } }
            } else if store.authorization == .denied {
                Button("Open App Settings") { openURL(URL(string: UIApplication.openNotificationSettingsURLString)!) }
            }
        }
        .task { await store.refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refreshAuthorization() }
        }
    }
}

struct PushView: View {
    let store = NotificationStore.shared
    private let topic = Bundle.main.bundleIdentifier ?? ""
    // ponytail: build config approximates the APNs environment; a Release build signed for development would actually be sandbox
    #if DEBUG
    private let host = "api.sandbox.push.apple.com"
    #else
    private let host = "api.push.apple.com"
    #endif

    var body: some View {
        List {
            NotificationPermissionSection()

            Section {
                if let token = store.deviceToken {
                    Text(verbatim: token).font(.callout.monospaced()).textSelection(.enabled)
                    ShareLink(item: token) { Label("Share Token", systemImage: "square.and.arrow.up") }
                } else if let error = store.registrationError {
                    Text(verbatim: error).foregroundStyle(.red)
                } else {
                    ProgressView()
                }
                valueRow("APNs Server", host)
                valueRow("Topic", topic)
            } header: {
                Text("Device Token")
            } footer: {
                Text("Debug builds use the sandbox server. TestFlight and App Store builds use production.")
            }

            Section {
                Link(destination: URL(string: "https://icloud.developer.apple.com/dashboard/notifications")!) {
                    Label("Open Push Notifications Console", systemImage: "safari")
                }
                if store.deviceToken != nil {
                    ShareLink(item: curlScript) { Label("Share curl Command", systemImage: "terminal") }
                }
            } header: {
                Text("Send a Test Push")
            } footer: {
                Text("Paste the device token into Apple's console, or run the curl command on your Mac with your .p8 key.")
            }

            Section("Received") {
                if store.received.isEmpty {
                    Text("Notifications received by this app appear here.").foregroundStyle(.secondary)
                }
                ForEach(store.received) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(label(r))
                            Spacer()
                            Text(r.date, style: .time)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if let title = r.title, !title.isEmpty { Text(verbatim: title).bold() }
                        if let body = r.body, !body.isEmpty { Text(verbatim: body) }
                        Text(verbatim: r.payload).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                if !store.received.isEmpty {
                    Button("Clear", role: .destructive) { store.received.removeAll() }
                }
            }
        }
        .navigationTitle("Push (APNs)")
    }

    private func label(_ r: NotificationStore.Received) -> LocalizedStringKey {
        switch (r.event, r.isRemote) {
        case (.silent, _): "Silent Push"
        case (.presented, true): "Push · Received in Foreground"
        case (.opened, true): "Push · Opened"
        case (.presented, false): "Local · Received in Foreground"
        case (.opened, false): "Local · Opened"
        }
    }

    // Apple's documented command-line recipe: sign an ES256 JWT with openssl, send with curl over HTTP/2.
    private var curlScript: String {
        """
        TEAM_ID=YOUR_TEAM_ID
        KEY_ID=YOUR_KEY_ID
        AUTH_KEY_PATH=AuthKey_$KEY_ID.p8
        TOPIC=\(topic)
        DEVICE_TOKEN=\(store.deviceToken ?? "")
        APNS_HOST=\(host)

        b64() { openssl base64 -e -A | tr -- '+/' '-_' | tr -d =; }
        HEADER=$(printf '{"alg":"ES256","kid":"%s"}' "$KEY_ID" | b64)
        CLAIMS=$(printf '{"iss":"%s","iat":%d}' "$TEAM_ID" "$(date +%s)" | b64)
        SIG=$(printf '%s' "$HEADER.$CLAIMS" | openssl dgst -binary -sha256 -sign "$AUTH_KEY_PATH" | b64)

        curl -v --http2 \\
          -H "apns-topic: $TOPIC" -H "apns-push-type: alert" \\
          -H "authorization: bearer $HEADER.$CLAIMS.$SIG" \\
          -d '{"aps":{"alert":{"title":"ViaDevTools","body":"Test push"},"sound":"default"}}' \\
          "https://$APNS_HOST/3/device/$DEVICE_TOKEN"
        """
    }
}

struct LocalNotificationsView: View {
    @State private var title = "ViaDevTools"
    @State private var message = "Test notification"
    @State private var delay = 5
    @State private var repeats = false
    @State private var sound = true
    @State private var pending: [UNNotificationRequest] = []
    @State private var error: String?
    private let center = UNUserNotificationCenter.current()

    var body: some View {
        List {
            NotificationPermissionSection()

            Section {
                TextField("Title", text: $title)
                TextField("Body", text: $message)
                LabeledContent("Delay (seconds)") {
                    TextField("5", value: $delay, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Repeat", isOn: $repeats)
                Toggle("Sound", isOn: $sound)
                Button("Schedule") { Task { await schedule() } }
                if let error { Text(verbatim: error).foregroundStyle(.red) }
            } header: {
                Text("Schedule")
            } footer: {
                Text("Repeating notifications need a delay of at least 60 seconds.")
            }

            Section("Pending") {
                if pending.isEmpty { Text("No pending notifications.").foregroundStyle(.secondary) }
                ForEach(pending, id: \.identifier) { r in
                    VStack(alignment: .leading) {
                        Text(verbatim: r.content.title)
                        if let next = (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() {
                            Text(next, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    center.removePendingNotificationRequests(withIdentifiers: offsets.map { pending[$0].identifier })
                    pending.remove(atOffsets: offsets)
                }
                if !pending.isEmpty {
                    Button("Remove All", role: .destructive) {
                        center.removeAllPendingNotificationRequests()
                        pending = []
                    }
                }
            }
        }
        .navigationTitle("Local Notifications")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func schedule() async {
        error = nil
        let store = NotificationStore.shared
        if store.authorization == .notDetermined { await store.requestAuthorization() }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if sound { content.sound = .default }
        let seconds = TimeInterval(max(delay, repeats ? 60 : 1))
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: repeats))
        do {
            try await center.add(request)
        } catch {
            self.error = error.localizedDescription
        }
        await reload()
    }

    private func reload() async {
        pending = await center.pendingNotificationRequests()
    }
}
