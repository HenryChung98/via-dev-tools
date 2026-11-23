import SwiftUI

struct ClipboardView: View {
    @State private var items: [[String: String]] = []  // per item: type → preview
    @State private var types: [String] = []
    @State private var changeCount = 0
    @State private var read = false

    var body: some View {
        List {
            Section {
                valueRow("Items", "\(UIPasteboard.general.numberOfItems)")
                valueRow("Change Count", "\(changeCount)")
                Button("Read Clipboard", action: readClipboard)
            } footer: {
                Text("Type identifiers are listed without reading the contents. Reading the values shows the system paste prompt.")
            }

            if read {
                ForEach(items.indices, id: \.self) { i in
                    Section("Item \(i + 1)") {
                        ForEach(items[i].keys.sorted(), id: \.self) { type in
                            TypedValueRow(type: type, preview: items[i][type])
                        }
                    }
                }
                if items.isEmpty { Text("The clipboard is empty.").foregroundStyle(.secondary) }
            } else if !types.isEmpty {
                Section("Types") {
                    ForEach(types, id: \.self) { TypedValueRow(type: $0, preview: nil) }
                }
            }
        }
        .navigationTitle("Clipboard")
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        let pb = UIPasteboard.general
        if pb.changeCount != changeCount { read = false }  // contents changed since the last read
        changeCount = pb.changeCount
        types = pb.types  // metadata only: no paste prompt
    }

    private func readClipboard() {
        items = UIPasteboard.general.items.map { $0.mapValues(previewText) }
        changeCount = UIPasteboard.general.changeCount
        read = true
    }
}
