import SwiftUI

struct UniversalLinksView: View {
    struct Check: Identifiable {
        let id = UUID()
        let ok: Bool
        let text: String
    }

    struct Report: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let url: URL
        var checks: [Check] = []
        var json: String?
    }

    @State private var domain = ""
    @State private var appID = ""
    @State private var reports: [Report] = []
    @State private var loading = false
    @State private var link = ""
    @State private var openResult: String?

    var body: some View {
        List {
            Section {
                TextField("example.com", text: $domain)
                    .keyboardType(.URL)
                TextField("TEAMID.com.example.app (optional)", text: $appID)
                Button("Check AASA", action: { Task { await check() } })
                    .disabled(host == nil || loading)
            } header: {
                Text("apple-app-site-association")
            } footer: {
                Text("Devices download the file from Apple's CDN, not from your server, so both are checked.")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if loading { ProgressView() }

            ForEach(reports) { r in
                Section {
                    Text(verbatim: r.url.absoluteString).font(.caption.monospaced()).foregroundStyle(.secondary)
                    ForEach(r.checks) { c in
                        Label {
                            Text(verbatim: c.text).textSelection(.enabled)
                        } icon: {
                            Image(systemName: c.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(c.ok ? .green : .red)
                        }
                    }
                    if let json = r.json {
                        Text(verbatim: json).font(.caption.monospaced()).textSelection(.enabled)
                    }
                } header: {
                    Text(r.title)
                }
            }

            Section {
                TextField("https://example.com/path", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Open as Universal Link Only") { Task { await open(universalOnly: true) } }
                    .disabled(URL(string: link) == nil)
                Button("Open") { Task { await open(universalOnly: false) } }
                    .disabled(URL(string: link) == nil)
                if let openResult { Text(verbatim: openResult).foregroundStyle(.secondary) }
            } header: {
                Text("Open Link")
            } footer: {
                Text("“Universal Link Only” succeeds only if an installed app claims the URL; it never falls back to Safari.")
            }
        }
        .navigationTitle("Universal Links")
    }

    /// Accepts "example.com" or a full URL.
    private var host: String? {
        let trimmed = domain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")?.host()
    }

    private func check() async {
        guard let host else { return }
        loading = true
        reports = []
        reports.append(await fetch("Your Server", URL(string: "https://\(host)/.well-known/apple-app-site-association")!))
        reports.append(await fetch("Apple CDN", URL(string: "https://app-site-association.cdn-apple.com/a/v1/\(host)")!))
        loading = false
    }

    private func fetch(_ title: LocalizedStringKey, _ url: URL) async -> Report {
        var r = Report(title: title, url: url)
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            let (data, response) = try await URLSession.shared.data(for: request, delegate: NoRedirect())
            guard let http = response as? HTTPURLResponse else { return r }

            r.checks.append(Check(ok: http.statusCode == 200, text: "HTTP \(http.statusCode)"))
            if let location = http.value(forHTTPHeaderField: "Location") {
                r.checks.append(Check(ok: false, text: String(localized: "Redirects to \(location). Apple does not follow redirects.")))
            }
            guard http.statusCode == 200 else { return r }

            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "-"
            r.checks.append(Check(ok: contentType.hasPrefix("application/json"), text: "Content-Type: \(contentType)"))
            r.checks.append(Check(ok: data.count <= 128 * 1024, text: String(localized: "\(data.count) bytes (limit 128 KB)")))

            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                r.checks.append(Check(ok: false, text: String(localized: "Invalid JSON")))
                return r
            }
            r.checks.append(Check(ok: true, text: String(localized: "Valid JSON")))

            let ids = appIDs(in: object)
            r.checks.append(Check(ok: !ids.isEmpty, text: "applinks: " + (ids.isEmpty ? "-" : ids.joined(separator: ", "))))
            let wanted = appID.trimmingCharacters(in: .whitespaces)
            if !wanted.isEmpty {
                r.checks.append(ids.contains(wanted)
                    ? Check(ok: true, text: String(localized: "\(wanted) is listed"))
                    : Check(ok: false, text: String(localized: "\(wanted) is not listed")))
            }
            r.json = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
                .flatMap { String(data: $0, encoding: .utf8) }
        } catch {
            r.checks.append(Check(ok: false, text: error.localizedDescription))
        }
        return r
    }

    /// applinks.details[].appIDs (current format) and .appID (legacy).
    private func appIDs(in object: [String: Any]) -> [String] {
        let details = (object["applinks"] as? [String: Any])?["details"] as? [[String: Any]] ?? []
        return details.flatMap { ($0["appIDs"] as? [String] ?? []) + [$0["appID"] as? String].compactMap { $0 } }
    }

    private func open(universalOnly: Bool) async {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)) else { return }
        let opened = await UIApplication.shared.open(url, options: universalOnly ? [.universalLinksOnly: true] : [:])
        openResult = opened
            ? String(localized: "Opened.")
            : universalOnly ? String(localized: "No installed app claims this URL.") : String(localized: "Could not open the URL.")
    }
}

/// Returns the 3xx response itself instead of following it, because Apple's crawler doesn't follow redirects.
nonisolated final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
