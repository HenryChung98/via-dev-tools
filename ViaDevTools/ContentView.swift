import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    NavigationLink { DeviceInfoView() } label: {
                        Label("Device Info", systemImage: "iphone.gen3")
                    }
                }
                Section("Hardware") {
                    NavigationLink { NFCView() } label: {
                        Label("NFC", systemImage: "sensor.tag.radiowaves.forward")
                    }
                    NavigationLink { BluetoothView() } label: {
                        Label("Bluetooth LE", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    NavigationLink { HapticsView() } label: {
                        Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }
            }
            .navigationTitle("ViaDevTools")
        }
    }
}

#Preview {
    ContentView()
}
