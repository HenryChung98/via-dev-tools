import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    link("Device Info", "iphone.gen3") { DeviceInfoView() }
                }
                Section("Notifications") {
                    link("Notification Playground", "bell.badge") { NotificationPlaygroundView() }
                }
                Section {
                    link("Clipboard", "doc.on.clipboard") { ClipboardView() }
                    link("Universal Links", "link") { UniversalLinksView() }
                } header: {
                    Text("Inspectors")
                } footer: {
                    Label("To inspect share sheet data, share anything to ViaDevTools from another app.", systemImage: "square.and.arrow.up")
                }
                Section("Hardware") {
                    link("NFC", "sensor.tag.radiowaves.forward") { NFCView() }
                    link("Bluetooth LE", "antenna.radiowaves.left.and.right") { BluetoothView() }
                    link("Haptics", "iphone.radiowaves.left.and.right") { HapticsView() }
                }
                Section("Toolbox") {
                    link("JWT", "key.horizontal") { JWTView() }
                    link("Base64", "textformat.abc") { Base64View() }
                    link("JSON", "curlybraces") { JSONView() }
                    link("UUID", "number") { UUIDView() }
                    link("Timestamp", "clock") { TimestampView() }
                }
            }
            .navigationTitle("ViaDevTools")
        }
    }

    private func link(_ title: LocalizedStringKey, _ symbol: String, destination: () -> some View) -> some View {
        NavigationLink(destination: destination()) { Label(title, systemImage: symbol) }
    }
}

#Preview {
    ContentView()
}
