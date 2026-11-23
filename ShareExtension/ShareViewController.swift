import UIKit
import SwiftUI

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let host = UIHostingController(rootView: ShareInspectorView(items: items) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

struct ShareInspectorView: View {
    let items: [NSExtensionItem]
    let done: () -> Void
    @State private var previews: [String: String] = [:]  // "item-attachment-type" → preview

    var body: some View {
        NavigationStack {
            List {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    Section("Item \(i + 1)") {
                        if let title = item.attributedTitle?.string {
                            LabeledContent("Title") { Text(verbatim: title) }
                        }
                        if let text = item.attributedContentText?.string {
                            LabeledContent("Content Text") { Text(verbatim: text) }
                        }
                        ForEach((item.attachments ?? []).indices, id: \.self) { j in
                            ForEach(item.attachments![j].registeredTypeIdentifiers, id: \.self) { type in
                                TypedValueRow(type: type, preview: previews[key(i, j, type)] ?? String(localized: "Loading…"))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shared Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done", action: done)
            }
            .task { await load() }
        }
    }

    private func key(_ i: Int, _ j: Int, _ type: String) -> String { "\(i)-\(j)-\(type)" }

    /// Loads every registered representation, the way a receiving app would.
    private func load() async {
        for (i, item) in items.enumerated() {
            for (j, provider) in (item.attachments ?? []).enumerated() {
                for type in provider.registeredTypeIdentifiers {
                    do {
                        previews[key(i, j, type)] = previewText(try await provider.loadItem(forTypeIdentifier: type))
                    } catch {
                        previews[key(i, j, type)] = error.localizedDescription
                    }
                }
            }
        }
    }
}
