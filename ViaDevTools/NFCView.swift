import SwiftUI
import CoreNFC

@Observable
final class NFCController: NSObject, NFCNDEFReaderSessionDelegate {
    var records: [NFCNDEFPayload] = []
    var tagInfo: String?
    var error: String?
    private var session: NFCNDEFReaderSession?
    private var pending: NFCNDEFMessage?  // nil = read, otherwise write this

    func begin(writing message: NFCNDEFMessage? = nil) {
        pending = message
        error = nil
        session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
        session?.alertMessage = message == nil
            ? String(localized: "Hold your iPhone near an NFC tag to read it.")
            : String(localized: "Hold your iPhone near an NFC tag to write to it.")
        session?.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code
        // invalidate() after success and the user's Cancel both report userCanceled
        if code != .readerSessionInvalidationErrorUserCanceled && code != .readerSessionInvalidationErrorFirstNDEFTagRead {
            self.error = error.localizedDescription
        }
        self.session = nil
    }

    // Required by the protocol; not called because didDetect(tags:) is implemented.
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = String(localized: "More than one tag detected. Present only one.")
            session.restartPolling()
            return
        }
        Task {
            do {
                try await session.connect(to: tag)
                let (status, capacity) = try await tag.queryNDEFStatus()
                tagInfo = "\(Self.name(status)) · \(capacity) bytes"

                if let message = pending {
                    guard status == .readWrite else {
                        return fail(session, status == .readOnly
                            ? String(localized: "This tag is read-only.")
                            : String(localized: "This tag is not NDEF formatted."))
                    }
                    guard message.length <= capacity else {
                        return fail(session, String(localized: "The message is larger than the tag's capacity."))
                    }
                    try await tag.writeNDEF(message)
                    session.alertMessage = String(localized: "Write complete.")
                } else {
                    guard status != .notSupported else {
                        return fail(session, String(localized: "This tag is not NDEF formatted."))
                    }
                    do {
                        records = try await tag.readNDEF().records
                    } catch let e as NFCReaderError where e.code == .ndefReaderSessionErrorZeroLengthMessage {
                        records = []  // formatted but empty tag
                    }
                    session.alertMessage = String(localized: "Read complete.")
                }
                session.invalidate()
            } catch {
                fail(session, error.localizedDescription)
            }
        }
    }

    private func fail(_ session: NFCNDEFReaderSession, _ message: String) {
        error = message
        session.invalidate(errorMessage: message)
    }

    private static func name(_ status: NFCNDEFStatus) -> String {
        switch status {
        case .readWrite: "Read/Write"
        case .readOnly: "Read-only"
        case .notSupported: "Not NDEF"
        @unknown default: "Unknown"
        }
    }
}

struct NFCView: View {
    @State private var nfc = NFCController()
    @State private var writeURL = true
    @State private var writeValue = ""
    private let available = NFCNDEFReaderSession.readingAvailable

    var body: some View {
        List {
            if !available {
                Text("This device does not support NFC.").foregroundStyle(.secondary)
            }
            if let error = nfc.error {
                Text(verbatim: error).foregroundStyle(.red)
            }

            Section {
                Button("Read Tag") { nfc.begin() }.disabled(!available)
                if let info = nfc.tagInfo { valueRow("Tag", info) }
                ForEach(nfc.records.indices, id: \.self) { i in
                    record(nfc.records[i], index: i)
                }
            } header: {
                Text("Read")
            } footer: {
                if nfc.tagInfo != nil && nfc.records.isEmpty { Text("The tag has no NDEF records.") }
            }

            Section("Write") {
                Picker("Type", selection: $writeURL) {
                    Text("URL").tag(true)
                    Text("Text").tag(false)
                }
                .pickerStyle(.segmented)
                TextField(writeURL ? "https://example.com" : "Text", text: $writeValue)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(writeURL ? .URL : .default)
                Button("Write to Tag", action: write).disabled(!available || writeValue.isEmpty)
            }
        }
        .navigationTitle("NFC")
    }

    private func write() {
        let payload = writeURL
            ? NFCNDEFPayload.wellKnownTypeURIPayload(string: writeValue)
            : NFCNDEFPayload.wellKnownTypeTextPayload(string: writeValue, locale: .current)
        guard let payload else {
            nfc.error = String(localized: "Invalid value.")
            return
        }
        nfc.begin(writing: NFCNDEFMessage(records: [payload]))
    }

    private func record(_ r: NFCNDEFPayload, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "#\(index + 1) · \(tnf(r.typeNameFormat)) · \(String(decoding: r.type, as: UTF8.self))")
                .font(.caption).foregroundStyle(.secondary)
            if let decoded = decode(r) {
                Text(verbatim: decoded)
            }
            Text(verbatim: r.payload.map { String(format: "%02X", $0) }.joined(separator: " "))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }

    private func decode(_ r: NFCNDEFPayload) -> String? {
        if let url = r.wellKnownTypeURIPayload() { return url.absoluteString }
        let (text, locale) = r.wellKnownTypeTextPayload()
        if let text { return locale.map { "\(text) (\($0.identifier))" } ?? text }
        return String(data: r.payload, encoding: .utf8)
    }

    private func tnf(_ f: NFCTypeNameFormat) -> String {
        switch f {
        case .empty: "Empty"
        case .nfcWellKnown: "Well Known"
        case .media: "Media"
        case .absoluteURI: "Absolute URI"
        case .nfcExternal: "External"
        case .unknown: "Unknown"
        case .unchanged: "Unchanged"
        @unknown default: "?"
        }
    }
}
