import SwiftUI
import Combine
import Network
import AdSupport
import AppTrackingTransparency

struct DeviceInfoView: View {
    @State private var attStatus = ATTrackingManager.trackingAuthorizationStatus
    @State private var size = CGSize.zero  // re-render on rotation so safe area/screen values refresh
    @State private var tick = 0  // re-render on system changes SwiftUI doesn't observe (locale, power, ...)
    @State private var path: NWPath?
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private static let refreshEvents = Publishers.MergeMany([
        UIApplication.didBecomeActiveNotification,
        .NSProcessInfoPowerStateDidChange,
        ProcessInfo.thermalStateDidChangeNotification,
        UIAccessibility.voiceOverStatusDidChangeNotification,
        NSLocale.currentLocaleDidChangeNotification,
        .NSSystemTimeZoneDidChange,
    ].map { NotificationCenter.default.publisher(for: $0) })
        .receive(on: DispatchQueue.main)  // ProcessInfo posts these off the main thread

    private var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.first as? UIWindowScene
    }

    var body: some View {
        let _ = (size, tick)  // read so SwiftUI tracks them
        let screen = scene?.screen
        let insets = scene?.keyWindow?.safeAreaInsets ?? .zero
        let device = UIDevice.current

        List {
            Section("Device") {
                valueRow("Model Identifier", modelIdentifier)
                valueRow("Model", deviceModelNames[modelIdentifier] ?? device.model)
                valueRow("OS", "\(device.systemName) \(device.systemVersion)")
                valueRow("Physical Memory", Int64(ProcessInfo.processInfo.physicalMemory).formatted(.byteCount(style: .memory)))
                valueRow("Low Power Mode", onOff(ProcessInfo.processInfo.isLowPowerModeEnabled))
                valueRow("Thermal State", thermalText(ProcessInfo.processInfo.thermalState))
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

            displaySection
            localeSection
            networkSection

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
        .task {
            for await p in NWPathMonitor() { path = p }
        }
        .onReceive(Self.refreshEvents) { _ in
            attStatus = ATTrackingManager.trackingAuthorizationStatus  // returning from Settings
            tick += 1
        }
    }

    private var displaySection: some View {
        Section("Display & Accessibility") {
            valueRow("Appearance", colorScheme == .dark ? String(localized: "Dark Mode") : String(localized: "Light Mode"))
            valueRow("Dynamic Type", "\(dynamicTypeSize) (body \(Int(UIFont.preferredFont(forTextStyle: .body).pointSize))pt)")
            valueRow("Bold Text", onOff(legibilityWeight == .bold))
            valueRow("Reduce Motion", onOff(reduceMotion))
            valueRow("Reduce Transparency", onOff(reduceTransparency))
            valueRow("Increase Contrast", onOff(contrast == .increased))
            valueRow("VoiceOver", onOff(UIAccessibility.isVoiceOverRunning))
        }
    }

    private var localeSection: some View {
        let locale = Locale.current
        let tz = TimeZone.current
        let twelveHour = [.zeroToEleven, .oneToTwelve].contains(locale.hourCycle)
        return Section("Language & Region") {
            valueRow("Locale", locale.identifier)
            valueRow("Region", locale.region?.identifier ?? "-")
            valueRow("Preferred Languages", Locale.preferredLanguages.joined(separator: ", "))
            valueRow("Time Zone", "\(tz.identifier) (\(tz.abbreviation() ?? "-"))")
            valueRow("Calendar", "\(locale.calendar.identifier)")
            valueRow("Time Format", twelveHour ? String(localized: "12-hour") : String(localized: "24-hour"))
            valueRow("Measurement System", locale.measurementSystem.identifier)
        }
    }

    private var networkSection: some View {
        Section("Network") {
            if let path {
                valueRow("Connection", connectionText(path))
                valueRow("Expensive", yesNo(path.isExpensive))
                valueRow("Low Data Mode", onOff(path.isConstrained))
                valueRow("IPv4", yesNo(path.supportsIPv4))
                valueRow("IPv6", yesNo(path.supportsIPv6))
            }
        }
    }

    private func fmt(_ s: CGSize) -> String { "\(Int(s.width)) × \(Int(s.height))" }
    private func onOff(_ b: Bool) -> String { b ? String(localized: "On") : String(localized: "Off") }
    private func yesNo(_ b: Bool) -> String { b ? String(localized: "Yes") : String(localized: "No") }

    private func connectionText(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return String(localized: "Offline") }
        if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if path.usesInterfaceType(.cellular) { return String(localized: "Cellular") }
        if path.usesInterfaceType(.wiredEthernet) { return String(localized: "Wired") }
        return String(localized: "Other")
    }

    private func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: String(localized: "Nominal")
        case .fair: String(localized: "Fair")
        case .serious: String(localized: "Serious")
        case .critical: String(localized: "Critical")
        @unknown default: String(localized: "Unknown")
        }
    }

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
