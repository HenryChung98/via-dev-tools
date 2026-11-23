import SwiftUI
import AdSupport
import AppTrackingTransparency

struct DeviceInfoView: View {
    @State private var attStatus = ATTrackingManager.trackingAuthorizationStatus
    @State private var size = CGSize.zero  // re-render on rotation so safe area/screen values refresh
    @Environment(\.openURL) private var openURL

    private var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.first as? UIWindowScene
    }

    var body: some View {
        let _ = size  // read so SwiftUI tracks it
        let screen = scene?.screen
        let insets = scene?.keyWindow?.safeAreaInsets ?? .zero
        let device = UIDevice.current

        List {
            Section("Device") {
                valueRow("Model Identifier", modelIdentifier)
                valueRow("Model", deviceModelNames[modelIdentifier] ?? device.model)
                valueRow("OS", "\(device.systemName) \(device.systemVersion)")
            }

            if let screen {
                Section("Screen") {
                    valueRow("Size (pt)", fmt(screen.bounds.size))
                    valueRow("Resolution (px)", fmt(screen.nativeBounds.size))
                    valueRow("Scale", "\(screen.scale)x (native \(screen.nativeScale)x)")
                }
            }

            Section("Safe Area") {
                valueRow("Top", "\(insets.top)")
                valueRow("Bottom", "\(insets.bottom)")
                valueRow("Leading", "\(insets.left)")
                valueRow("Trailing", "\(insets.right)")
            }

            Section {
                valueRow("ATT Status", statusText)
                valueRow("IDFA", ASIdentifierManager.shared().advertisingIdentifier.uuidString)
                valueRow("IDFV", device.identifierForVendor?.uuidString ?? "-")
                if attStatus == .notDetermined {
                    Button("Request Tracking Permission") {
                        Task { attStatus = await ATTrackingManager.requestTrackingAuthorization() }
                    }
                } else if attStatus != .authorized {
                    Button("Change in Settings") {
                        openURL(URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            } header: {
                Text("Advertising Identifiers")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Without permission, IDFA shows as all zeros. Long-press a value to copy it.")
                    // Denied can mean the system-wide switch is off; then the app's Settings page has no Tracking toggle.
                    if attStatus == .denied {
                        Text("No Tracking toggle in Settings? First turn on Settings > Privacy & Security > Tracking > Allow Apps to Request to Track.")
                    }
                }
            }
        }
        .navigationTitle("Device Info")
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            attStatus = ATTrackingManager.trackingAuthorizationStatus  // returning from Settings
        }
    }

    private func fmt(_ s: CGSize) -> String { "\(Int(s.width)) × \(Int(s.height))" }

    private var statusText: String {
        switch attStatus {
        case .notDetermined: String(localized: "Not Determined")
        case .restricted: String(localized: "Restricted")
        case .denied: String(localized: "Denied")
        case .authorized: String(localized: "Authorized")
        @unknown default: String(localized: "Unknown")
        }
    }

    private var modelIdentifier: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var sys = utsname()
        uname(&sys)
        return withUnsafeBytes(of: sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

/// Title + selectable monospaced value, shared by the info screens.
func valueRow(_ title: LocalizedStringKey, _ value: String) -> some View {
    LabeledContent(title) {
        Text(verbatim: value).textSelection(.enabled).monospaced()
    }
}
