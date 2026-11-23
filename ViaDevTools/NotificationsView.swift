import SwiftUI
import UserNotifications

@Observable
final class NotificationStore: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationStore()

    struct Received: Identifiable {
        let id = UUID()
        let date = Date()
        let opened: Bool
        let title: String
        let thread: String
        let action: String?  // action identifier, plus typed text for the reply action
    }

    var authorization = UNAuthorizationStatus.notDetermined
    var received: [Received] = []

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    private func record(_ n: UNNotification, opened: Bool, action: String? = nil) {
        let c = n.request.content
        received.insert(Received(opened: opened, title: c.title, thread: c.threadIdentifier, action: action), at: 0)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        record(notification, opened: false)
        return [.banner, .list, .sound, .badge]  // show banners even while the app is open
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        var action: String?
        if response.actionIdentifier != UNNotificationDefaultActionIdentifier { action = response.actionIdentifier }
        if let text = (response as? UNTextInputNotificationResponse)?.userText { action = "\(action ?? "") “\(text)”" }
        record(response.notification, opened: true, action: action)
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

struct NotificationPlaygroundView: View {
    enum Level: String, CaseIterable {
        case passive, active, timeSensitive = "time-sensitive"  // raw value = APNs "interruption-level"

        var value: UNNotificationInterruptionLevel {
            switch self {
            case .passive: .passive
            case .active: .active
            case .timeSensitive: .timeSensitive
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .passive: "Passive"
            case .active: "Active"
            case .timeSensitive: "Time Sensitive"
            }
        }
    }

    private static let category = "VIADEVTOOLS_PLAYGROUND"

    let store = NotificationStore.shared
    @Environment(\.openURL) private var openURL
    @State private var title = "ViaDevTools"
    @State private var subtitle = ""
    @State private var message = "Test notification"
    @State private var level = Level.active
    @State private var thread = ""
    @State private var badgeOn = false
    @State private var badge = 1
    @State private var sound = true
    @State private var image = false
    @State private var actions = false
    @State private var delay = 3
    @State private var pendingCount = 0
    @State private var error: String?
    private let center = UNUserNotificationCenter.current()

    var body: some View {
        List {
            Section("Permission") {
                valueRow("Status", store.authorizationText)
                if store.authorization == .notDetermined {
                    Button("Request Permission") { Task { await store.requestAuthorization() } }
                } else if store.authorization == .denied {
                    Button("Open App Settings") { openURL(URL(string: UIApplication.openNotificationSettingsURLString)!) }
                }
            }

            Section("Content") {
                TextField("Title", text: $title)
                TextField("Subtitle", text: $subtitle)
                TextField("Body", text: $message, axis: .vertical)
            }

            Section {
                Picker("Interruption Level", selection: $level) {
                    ForEach(Level.allCases, id: \.self) { Text($0.label) }
                }
                TextField("Thread ID", text: $thread)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Badge", isOn: $badgeOn)
                if badgeOn { Stepper(value: $badge, in: 0...999) { Text(verbatim: "\(badge)") } }
                Toggle("Sound", isOn: $sound)
                Toggle("Image Attachment", isOn: $image)
                Toggle("Action Buttons", isOn: $actions)
            } header: {
                Text("Options")
            } footer: {
                Text("Send several with the same Thread ID to see grouping. Long-press a notification to see its image and actions. Passive notifications arrive silently, without lighting the screen.")
            }

            Section {
                LabeledContent("Delay (seconds)") {
                    TextField("3", value: $delay, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Button("Send") { Task { await send() } }
                if let error { Text(verbatim: error).foregroundStyle(.red) }
            } footer: {
                Text("Lock the iPhone or leave the app before it fires to see it on the Lock Screen.")
            }

            Section {
                Text(verbatim: payloadJSON).font(.caption.monospaced()).textSelection(.enabled)
                let size = Data(compactPayloadJSON.utf8).count
                valueRow("Size", "\(size) / 4096 bytes")
                    .foregroundStyle(size > 4096 ? .red : .primary)
                ShareLink(item: payloadJSON) { Label("Share", systemImage: "square.and.arrow.up") }
            } header: {
                Text("APNs Payload")
            } footer: {
                Text("The same options as a remote push. Images need a Notification Service Extension in your app to download and attach them, and the category must be registered by your app.")
            }

            Section("Received") {
                if store.received.isEmpty {
                    Text("Notifications appear here when they arrive or are opened.").foregroundStyle(.secondary)
                }
                ForEach(store.received) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(r.opened ? "Opened" : "Received in Foreground")
                            Spacer()
                            Text(r.date, style: .time)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: r.title)
                        if !r.thread.isEmpty { valueRow("Thread ID", r.thread).font(.caption) }
                        if let action = r.action { valueRow("Action", action).font(.caption) }
                    }
                }
            }

            Section {
                Button("Clear Badge") { center.setBadgeCount(0) }
                Button("Remove Pending (\(pendingCount)) and Delivered", role: .destructive) {
                    center.removeAllPendingNotificationRequests()
                    center.removeAllDeliveredNotifications()
                    store.received.removeAll()
                    pendingCount = 0
                }
            }
        }
        .navigationTitle("Notification Playground")
        .task {
            await store.refreshAuthorization()
            await refreshPending()
        }
        .onChange(of: store.received.count) { Task { await refreshPending() } }  // one just fired while the app was open
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await store.refreshAuthorization()
                await refreshPending()
            }
        }
    }

    private func send() async {
        error = nil
        if store.authorization == .notDetermined { await store.requestAuthorization() }

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = message
        content.interruptionLevel = level.value
        content.threadIdentifier = thread
        if badgeOn { content.badge = badge as NSNumber }
        if sound { content.sound = .default }
        if actions {
            center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [
                UNNotificationAction(identifier: "ACCEPT", title: String(localized: "Accept")),
                UNTextInputNotificationAction(identifier: "REPLY", title: String(localized: "Reply"), textInputButtonTitle: String(localized: "Send"), textInputPlaceholder: ""),
                UNNotificationAction(identifier: "DELETE", title: String(localized: "Delete"), options: .destructive),
            ], intentIdentifiers: [])])
            content.categoryIdentifier = Self.category
        }
        do {
            if image { content.attachments = [try sampleAttachment()] }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(delay, 1)), repeats: false)
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
        } catch {
            self.error = error.localizedDescription
        }
        await refreshPending()
    }

    /// The system moves attachment files into its own store, so write a fresh one each time.
    private func sampleAttachment() throws -> UNNotificationAttachment {
        let symbol = UIImage(systemName: "hammer.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 160))!
            .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        let png = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).pngData { ctx in
            UIColor.secondarySystemBackground.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            symbol.draw(at: CGPoint(x: 200 - symbol.size.width / 2, y: 150 - symbol.size.height / 2))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try png.write(to: url)
        return try UNNotificationAttachment(identifier: "image", url: url)
    }

    private func refreshPending() async {
        pendingCount = await center.pendingNotificationRequests().count
    }

    private var payload: [String: Any] {
        var alert = ["title": title, "body": message]
        if !subtitle.isEmpty { alert["subtitle"] = subtitle }
        var aps: [String: Any] = ["alert": alert, "interruption-level": level.rawValue]
        if !thread.isEmpty { aps["thread-id"] = thread }
        if badgeOn { aps["badge"] = badge }
        if sound { aps["sound"] = "default" }
        if actions { aps["category"] = Self.category }
        if image { aps["mutable-content"] = 1 }
        return ["aps": aps]
    }

    private var payloadJSON: String { json([.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
    private var compactPayloadJSON: String { json([.sortedKeys, .withoutEscapingSlashes]) }  // what APNs counts toward 4 KB

    private func json(_ options: JSONSerialization.WritingOptions) -> String {
        (try? JSONSerialization.data(withJSONObject: payload, options: options)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
