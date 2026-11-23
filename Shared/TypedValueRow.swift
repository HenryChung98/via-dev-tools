import SwiftUI
import UniformTypeIdentifiers

// Shared by the app (clipboard inspector) and the share extension. No localized strings here:
// the extension has its own string catalog.

/// One UTType identifier and a preview of its raw value.
struct TypedValueRow: View {
    let type: String
    let preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: type).font(.callout.monospaced())
            if let description = UTType(type)?.localizedDescription {
                Text(verbatim: description).font(.caption).foregroundStyle(.secondary)
            }
            if let preview {
                Text(verbatim: preview).font(.caption.monospaced()).lineLimit(20)
            }
        }
        .textSelection(.enabled)
    }
}

/// Human-readable preview of a pasteboard / item-provider value.
func previewText(_ value: Any) -> String {
    switch value {
    case let s as String: return s
    case let a as NSAttributedString: return a.string
    case let url as URL:
        guard url.isFileURL, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return url.absoluteString }
        return "\(url.absoluteString)\n\(size) bytes"
    case let image as UIImage:
        return "UIImage \(Int(image.size.width))×\(Int(image.size.height)) @\(Int(image.scale))x"
    case let data as Data:
        let hex = data.prefix(256).map { String(format: "%02X", $0) }.joined(separator: " ")
        return "\(data.count) bytes\n" + hex + (data.count > 256 ? " …" : "")
    default:
        return "\(type(of: value))\n\(value)"
    }
}
