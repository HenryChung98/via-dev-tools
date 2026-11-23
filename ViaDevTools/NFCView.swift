import SwiftUI
import CoreNFC

/// Uses a tag reader session (not an NDEF one) so the tag's UID and chip type are available.
/// ponytail: polls ISO 14443/15693 only; FeliCa needs system codes declared in Info.plist.
@Observable
final class NFCController: NSObject, NFCTagReaderSessionDelegate {
    var records: [NFCNDEFPayload] = []
    var tagInfo: String?
    var uid: String?
    var error: String?
    private var session: NFCTagReaderSession?
    private var pending: NFCNDEFMessage?  // nil = read, otherwise write this

    func begin(writing message: NFCNDEFMessage? = nil) {
        pending = message
        error = nil
        session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
        session?.alertMessage = message == nil
            ? String(localized: "Hold your iPhone near an NFC tag to read it.")
            : String(localized: "Hold your iPhone near an NFC tag to write to it.")
        session?.begin()
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // invalidate() after success and the user's Cancel both report userCanceled
        if (error as? NFCReaderError)?.code != .readerSessionInvalidationErrorUserCanceled {
            self.error = error.localizedDescription
        }
        self.session = nil
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let tag = tags.first, let described = Self.describe(tag) else {
            session.alertMessage = String(localized: "More than one tag detected. Present only one.")
            session.restartPolling()
            return
        }
        let ndefTag = described.ndef
        Task {
            do {
                try await session.connect(to: tag)
                uid = described.uid.map { String(format: "%02X", $0) }.joined(separator: ":")
                let (status, capacity) = try await ndefTag.queryNDEFStatus()
                tagInfo = "\(described.kind) · \(Self.name(status)) · \(capacity) bytes"

                if let message = pending {
                    guard status == .readWrite else {
                        return fail(session, status == .readOnly
                            ? String(localized: "This tag is read-only.")
                            : String(localized: "This tag is not NDEF formatted."))
                    }
                    guard message.length <= capacity else {
                        return fail(session, String(localized: "The message is larger than the tag's capacity."))
                    }
                    try await ndefTag.writeNDEF(message)
                    session.alertMessage = String(localized: "Write complete.")
                } else {
                    guard status != .notSupported else {
                        return fail(session, String(localized: "This tag is not NDEF formatted."))
                    }
                    do {
                        records = try await ndefTag.readNDEF().records
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

    private func fail(_ session: NFCTagReaderSession, _ message: String) {
        error = message
        session.invalidate(errorMessage: message)
    }

    private static func describe(_ tag: NFCTag) -> (kind: String, uid: Data, ndef: any NFCNDEFTag)? {
        switch tag {
        case .miFare(let t):
            let family = switch t.mifareFamily {
            case .ultralight: " Ultralight"
            case .plus: " Plus"
            case .desfire: " DESFire"
            default: ""
            }
            return ("MIFARE\(family)", t.identifier, t)
        case .iso15693(let t): return ("ISO 15693", t.identifier, t)
        case .iso7816(let t): return ("ISO 7816", t.identifier, t)
        case .feliCa(let t): return ("FeliCa", t.currentIDm, t)
        @unknown default: return nil
        }
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
    enum WriteKind { case url, text, mime }

    @State private var nfc = NFCController()
    @State private var kind = WriteKind.url
    @State private var mimeType = "application/json"
    @State private var writeValue = ""
    private let available = NFCTagReaderSession.readingAvailable

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
                if let uid = nfc.uid { valueRow("UID", uid) }
                ForEach(nfc.records.indices, id: \.self) { i in
                    record(nfc.records[i], index: i)
                }
            } header: {
                Text("Read")
            } footer: {
                if nfc.tagInfo != nil && nfc.records.isEmpty { Text("The tag has no NDEF records.") }
            }

            Section("Write") {
                Picker("Type", selection: $kind) {
                    Text("URL").tag(WriteKind.url)
                    Text("Text").tag(WriteKind.text)
                    Text("MIME").tag(WriteKind.mime)
                }
                .pickerStyle(.segmented)
                if kind == .mime {
                    TextField("MIME Type", text: $mimeType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                TextField(placeholder, text: $writeValue, axis: kind == .url ? .horizontal : .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(kind == .url ? .URL : .default)
                Button("Write to Tag", action: write).disabled(!available || writeValue.isEmpty)
            }
        }
        .navigationTitle("NFC")
    }

    private var placeholder: LocalizedStringKey {
        switch kind {
        case .url: "https://example.com"
        case .text: "Text"
        case .mime: "Payload"
        }
    }

    private func write() {
        let type = mimeType.trimmingCharacters(in: .whitespaces)
        let payload: NFCNDEFPayload? = switch kind {
        case .url: NFCNDEFPayload.wellKnownTypeURIPayload(string: writeValue)
        case .text: NFCNDEFPayload.wellKnownTypeTextPayload(string: writeValue, locale: .current)
        case .mime: type.contains("/")
            ? NFCNDEFPayload(format: .media, type: Data(type.utf8), identifier: Data(), payload: Data(writeValue.utf8))
            : nil
        }
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
