import SwiftUI
import CoreBluetooth

@Observable
final class BLEScanner: NSObject, CBCentralManagerDelegate {
    struct Peripheral: Identifiable {
        let id: UUID
        var name: String?
        var rssi: Int
        var advertisement: [String: Any]
    }

    var state = CBManagerState.unknown
    var wantsScan = false
    var peripherals: [Peripheral] = []  // discovery order, so rows don't jump around
    private var manager: CBCentralManager?

    func setScanning(_ on: Bool) {
        wantsScan = on
        if manager == nil { manager = CBCentralManager(delegate: self, queue: nil) }  // first use shows the permission prompt
        update()
    }

    private func update() {
        guard let manager, manager.state == .poweredOn else { return }
        if wantsScan {
            // ponytail: every advertisement re-renders the list; throttle if crowded places get choppy
            manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else {
            manager.stopScan()
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        update()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let i = peripherals.firstIndex(where: { $0.id == peripheral.identifier }) else {
            peripherals.append(Peripheral(id: peripheral.identifier, name: name, rssi: rssi.intValue, advertisement: advertisementData))
            return
        }
        if let name { peripherals[i].name = name }
        if rssi.intValue != 127 { peripherals[i].rssi = rssi.intValue }  // 127 = RSSI unavailable
        peripherals[i].advertisement.merge(advertisementData) { $1 }  // scan responses carry different keys
    }

    var stateMessage: String? {
        switch state {
        case .poweredOff: String(localized: "Bluetooth is turned off.")
        case .unauthorized: String(localized: "Bluetooth permission is denied. Allow it in Settings.")
        case .unsupported: String(localized: "This device does not support Bluetooth LE.")
        default: nil
        }
    }
}

struct BluetoothView: View {
    @State private var scanner = BLEScanner()
    @State private var search = ""

    private var filtered: [BLEScanner.Peripheral] {
        guard !search.isEmpty else { return scanner.peripherals }
        return scanner.peripherals.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(search) || $0.id.uuidString.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if let message = scanner.stateMessage {
                Text(message).foregroundStyle(.secondary)
            }
            ForEach(filtered) { p in
                NavigationLink { BLEPeripheralView(scanner: scanner, id: p.id) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name ?? String(localized: "Unnamed"))
                            Text(verbatim: p.id.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: "\(p.rssi) dBm").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Bluetooth LE")
        .toolbar {
            Button(scanner.wantsScan ? "Stop" : "Scan") { scanner.setScanning(!scanner.wantsScan) }
        }
        .onAppear { if scanner.state == .unknown { scanner.setScanning(true) } }
        // Scanning stops when this screen is popped: the scanner and its CBCentralManager are deallocated.
    }
}

struct BLEPeripheralView: View {
    let scanner: BLEScanner
    let id: UUID

    var body: some View {
        List {
            if let p = scanner.peripherals.first(where: { $0.id == id }) {
                Section {
                    valueRow("Name", p.name ?? "-")
                    valueRow("Identifier", p.id.uuidString)
                    valueRow("RSSI", "\(p.rssi) dBm")
                } footer: {
                    Text("iOS does not expose MAC addresses. The identifier is assigned by this iPhone.")
                }
                Section("Advertisement Data") {
                    ForEach(p.advertisement.keys.sorted(), id: \.self) { key in
                        valueRow(LocalizedStringKey(key.replacingOccurrences(of: "kCBAdvData", with: "")),
                                 describe(key, p.advertisement[key]!))
                    }
                }
            }
        }
        .navigationTitle(scanner.peripherals.first { $0.id == id }?.name ?? String(localized: "Unnamed"))
    }

    private func describe(_ key: String, _ value: Any) -> String {
        switch value {
        case let data as Data where key == CBAdvertisementDataManufacturerDataKey && data.count >= 2:
            // First two bytes are the Bluetooth SIG company ID, little-endian.
            String(format: "Company 0x%04X\n", UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8) + hex(data)
        case let data as Data: hex(data)
        case let uuids as [CBUUID]: uuids.map(\.uuidString).joined(separator: "\n")
        case let dict as [CBUUID: Data]: dict.map { "\($0.key.uuidString): \(hex($0.value))" }.joined(separator: "\n")
        default: "\(value)"
        }
    }

    private func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
}
