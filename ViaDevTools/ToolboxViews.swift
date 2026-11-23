import SwiftUI

// MARK: - Helpers

private func prettyJSON(_ object: Any, sorted: Bool = true) -> String? {
    var options: JSONSerialization.WritingOptions = [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed]
    if sorted { options.insert(.sortedKeys) }
    return (try? JSONSerialization.data(withJSONObject: object, options: options)).flatMap { String(data: $0, encoding: .utf8) }
}

/// Accepts standard and URL-safe Base64, with or without padding.
private func base64Decode(_ s: String) -> Data? {
    var b = s.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    b += String(repeating: "=", count: (4 - b.count % 4) % 4)
    return Data(base64Encoded: b)
}

/// Monospaced, selectable output block.
private func output(_ text: String) -> some View {
    Text(verbatim: text).font(.callout.monospaced()).textSelection(.enabled)
}

private func inputField(_ placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
    TextField(placeholder, text: text, axis: .vertical)
        .lineLimit(3...10)
        .font(.callout.monospaced())
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
}

// MARK: - JWT

struct JWTView: View {
    @State private var token = ""

    var body: some View {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ".")
        let header = parts.count == 3 ? base64Decode(parts[0]).flatMap { try? JSONSerialization.jsonObject(with: $0) } : nil
        let payload = parts.count == 3 ? base64Decode(parts[1]).flatMap { try? JSONSerialization.jsonObject(with: $0) } : nil

        List {
            Section { inputField("Paste a JWT", text: $token) }

            if let header, let payload {
                Section("Header") { output(prettyJSON(header) ?? "") }
                Section("Payload") { output(prettyJSON(payload) ?? "") }
                if let claims = payload as? [String: Any] {
                    let times = ["exp", "nbf", "iat"].compactMap { key in (claims[key] as? Double).map { (key, Date(timeIntervalSince1970: $0)) } }
                    if !times.isEmpty {
                        Section("Times") {
                            ForEach(times, id: \.0) { key, date in
                                LabeledContent {
                                    Text(date, format: .dateTime)
                                } label: {
                                    Text(verbatim: key).monospaced()
                                    Text(date, style: .relative)
                                }
                            }
                            if let exp = times.first(where: { $0.0 == "exp" })?.1 {
                                Text(exp < .now ? "Expired" : "Not expired").foregroundStyle(exp < .now ? .red : .green)
                            }
                        }
                    }
                }
                Section {
                    output(parts[2])
                } header: {
                    Text("Signature")
                } footer: {
                    Text("The signature is not verified.")
                }
            } else if !token.isEmpty {
                Text("Not a valid JWT.").foregroundStyle(.red)
            }
        }
        .navigationTitle("JWT")
    }
}

// MARK: - Base64

struct Base64View: View {
    @State private var input = ""
    @State private var urlSafe = false

    var body: some View {
        List {
            Section {
                inputField("Text or Base64", text: $input)
                Toggle("URL-safe, no padding", isOn: $urlSafe)
            }
            if !input.isEmpty {
                Section("Encoded") { output(encoded) }
                Section("Decoded") {
                    if let data = base64Decode(input) {
                        output(String(data: data, encoding: .utf8) ?? data.map { String(format: "%02X", $0) }.joined(separator: " "))
                    } else {
                        Text("Not valid Base64.").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Base64")
    }

    private var encoded: String {
        let s = Data(input.utf8).base64EncodedString()
        guard urlSafe else { return s }
        return s.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - JSON

struct JSONView: View {
    @State private var input = ""
    @State private var sorted = true

    var body: some View {
        let parsed = Result { try JSONSerialization.jsonObject(with: Data(input.utf8), options: .fragmentsAllowed) }

        List {
            Section {
                inputField("Paste JSON", text: $input)
                Toggle("Sort Keys", isOn: $sorted)
            }
            if !input.isEmpty {
                switch parsed {
                case .success(let object):
                    Section("Formatted") { output(prettyJSON(object, sorted: sorted) ?? "") }
                    Section("Minified") {
                        output((try? JSONSerialization.data(withJSONObject: object, options: sorted ? [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes] : [.fragmentsAllowed, .withoutEscapingSlashes]))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? "")
                    }
                case .failure(let error):
                    // NSDebugDescription carries the line/column of the syntax error
                    Text(verbatim: (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("JSON")
    }
}

// MARK: - UUID

struct UUIDView: View {
    @State private var uuids = [UUID()]
    @State private var count = 1
    @State private var lowercase = false

    private var text: String {
        uuids.map { lowercase ? $0.uuidString.lowercased() : $0.uuidString }.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                Stepper("Count: \(count)", value: $count, in: 1...50)
                Toggle("Lowercase", isOn: $lowercase)
                Button("Generate") { uuids = (0..<count).map { _ in UUID() } }
            }
            Section {
                output(text)
                ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
            } footer: {
                Text("Version 4 (random) UUIDs.")
            }
        }
        .navigationTitle("UUID")
    }
}

// MARK: - Timestamp

struct TimestampView: View {
    @State private var input = ""
    @State private var date = Date.now

    var body: some View {
        List {
            Section("Now") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack {
                        valueRow("Seconds", "\(Int(context.date.timeIntervalSince1970))")
                        valueRow("Milliseconds", "\(Int(context.date.timeIntervalSince1970 * 1000))")
                    }
                }
            }

            Section {
                TextField("1700000000", text: $input)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.callout.monospaced())
                if let n = Double(input.trimmingCharacters(in: .whitespaces)) {
                    // ponytail: values above 1e11 are read as milliseconds (1e11 s is year 5138)
                    let d = Date(timeIntervalSince1970: abs(n) > 1e11 ? n / 1000 : n)
                    valueRow("Local", d.formatted(date: .complete, time: .standard))
                    valueRow("UTC", d.formatted(.iso8601))
                    valueRow("ISO 8601", d.formatted(Date.ISO8601FormatStyle(timeZone: .current)))
                    LabeledContent("Relative") { Text(d, style: .relative) }
                }
            } header: {
                Text("Timestamp → Date")
            } footer: {
                Text("Seconds or milliseconds are detected automatically.")
            }

            Section("Date → Timestamp") {
                DatePicker("Date", selection: $date)
                valueRow("Seconds", "\(Int(date.timeIntervalSince1970))")
                valueRow("Milliseconds", "\(Int(date.timeIntervalSince1970 * 1000))")
            }
        }
        .navigationTitle("Timestamp")
    }
}
