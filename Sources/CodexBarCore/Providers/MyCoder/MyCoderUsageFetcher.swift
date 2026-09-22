import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MyCoderUsageFetcher {
    fileprivate static let log = CodexBarLog.logger(LogCategories.mycoderUsage)
    /// The quota API lives on a separate host from the SPA; the SPA's
    /// `PUBLIC_USER_SSO_TOKEN` cookie is forwarded as a Bearer token.
    private static let apiBaseURL = "https://afs-mycoder-api.asus.com"
    private static let webBaseURL = "https://afs-mycoder.asus.com"
    private static let ssoCookieName = "PUBLIC_USER_SSO_TOKEN"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"

    /// A transport that validates `afs-mycoder.asus.com` against the pinned ASUS internal root CA.
    /// Uses the completion-handler based dataTask to ensure the delegate's auth challenge is invoked.
    public static let trustingTransport: any ProviderHTTPTransport = {
        #if os(macOS)
        return MyCoderTrustingTransport()
        #else
        return ProviderHTTPClient.shared
        #endif
    }()

    public static func fetchUsage(
        cookieHeader: String,
        transport: any ProviderHTTPTransport = MyCoderUsageFetcher.trustingTransport,
        now: Date = Date(),
        timeout: TimeInterval = 15) async throws -> MyCoderUsageSnapshot
    {
        guard let token = ssoToken(fromCredentials: cookieHeader) else {
            throw MyCoderUsageError.missingCredentials
        }
        guard let userId = Self.userId(fromSSOToken: token) else {
            throw MyCoderUsageError.invalidCredentials
        }
        Self.logTokenDiagnostics(token)
        let quotaData = try await self.sendRequest(
            path: "/mycoder-quota/api/v1/user/\(userId)/quota",
            token: token,
            transport: transport,
            timeout: timeout)
        return try self.parseQuota(data: quotaData, now: now)
    }

    /// Extracts the SSO token from a browser cookie header (or accepts a raw JWT).
    static func ssoToken(fromCredentials credentials: String) -> String? {
        let trimmedCredentials = credentials.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCredentials.hasPrefix("\(Self.ssoCookieName)=") {
            let value = trimmedCredentials.dropFirst(Self.ssoCookieName.count + 1)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        if trimmedCredentials.contains("="), trimmedCredentials.contains(";") || trimmedCredentials.contains(" ") {
            for pair in trimmedCredentials.split(separator: ";") {
                let keyValue = pair.split(separator: "=", maxSplits: 1)
                guard keyValue.count == 2 else { continue }
                let name = keyValue[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard name == Self.ssoCookieName else { continue }
                let value = keyValue[1].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            return nil
        }
        // A pasted manual credential may be the raw token itself.
        return trimmedCredentials.isEmpty ? nil : trimmedCredentials
    }

    /// Logs the JWT exp/iat claims for credential diagnostics (never the token itself).
    static func logTokenDiagnostics(_ token: String) {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            Self.log.info("MyCoder token diagnostics: not a 3-part JWT (parts=\(parts.count))")
            return
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Self.log.info("MyCoder token diagnostics: payload not decodable")
            return
        }
        let exp = claims["exp"] as? TimeInterval
        let iat = claims["iat"] as? TimeInterval
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        let expText = exp.map { formatter.string(from: Date(timeIntervalSince1970: $0)) } ?? "nil"
        let iatText = iat.map { formatter.string(from: Date(timeIntervalSince1970: $0)) } ?? "nil"
        Self.log.info("MyCoder token diagnostics: iat=\(iatText) exp=\(expText) now=\(formatter.string(from: Date()))")
    }

    /// Decodes the JWT payload and returns the user id from its `aud` claim.
    static func userId(fromSSOToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        switch claims["aud"] {
        case let audience as [String]:
            return audience.first { !$0.isEmpty }
        case let audience as String:
            return audience.isEmpty ? nil : audience
        default:
            return nil
        }
    }

    private static func sendRequest(
        path: String,
        token: String,
        transport: any ProviderHTTPTransport,
        timeout: TimeInterval) async throws -> Data
    {
        guard let url = URL(string: self.apiBaseURL + path) else {
            throw MyCoderUsageError.networkError("invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, */*", forHTTPHeaderField: "Accept")
        request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(self.webBaseURL, forHTTPHeaderField: "Origin")
        request.setValue(self.webBaseURL + "/token_usage/usages", forHTTPHeaderField: "Referer")

        let response: ProviderHTTPResponse
        do {
            response = try await transport.response(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            Self.log.error("MyCoder request failed: \(error.localizedDescription)")
            throw MyCoderUsageError.networkError(error.localizedDescription)
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            Self.log.error(
                "MyCoder API rejected credentials (\(response.statusCode); token subject/aud may be expired)")
            throw MyCoderUsageError.invalidCredentials
        }
        guard (200..<300).contains(response.statusCode) else {
            Self.log.error("MyCoder API \(path) returned \(response.statusCode)")
            throw MyCoderUsageError.apiError(response.statusCode)
        }
        return response.data
    }

    static func parseQuota(data: Data, now: Date = Date()) throws -> MyCoderUsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MyCoderUsageError.parseFailed("invalid JSON")
        }
        if let success = root["success"] as? Bool, !success {
            throw MyCoderUsageError.parseFailed("unsuccessful response")
        }

        let quota = self.quotaObject(from: root) ?? root
        guard self.payloadContainsQuotaField(quota) else {
            throw MyCoderUsageError.parseFailed("missing quota data")
        }

        let totalQuota = self.double(from: quota["totalQuota"])
            ?? self.double(from: quota["quota"])
            ?? self.double(from: quota["limit"])
            ?? self.double(from: quota["total"])
            ?? self.double(from: quota["totalBudget"])
            ?? self.double(from: quota["budget"])
        let availableQuota = self.double(from: quota["availableQuota"])
            ?? self.double(from: quota["remainingQuota"])
            ?? self.double(from: quota["balance"])
            ?? self.double(from: quota["remaining"])
            ?? self.double(from: quota["available"])
            ?? self.double(from: quota["remainingBudget"])
            ?? self.double(from: quota["availableBudget"])
        guard let totalQuota, let availableQuota else {
            throw MyCoderUsageError.parseFailed("missing total/available quota values")
        }
        let used = totalQuota - availableQuota
        return MyCoderUsageSnapshot(
            usedBudget: max(0, used),
            totalBudget: totalQuota,
            availableBudget: availableQuota,
            account: self.string(from: quota["account"]),
            updatedAt: now)
    }

    private static let expectedQuotaKeys: Set<String> = [
        "account", "totalQuota", "availableQuota", "quota", "limit", "remainingQuota",
        "balance", "total", "remaining", "available", "totalBudget", "availableBudget",
        "remainingBudget", "budget",
    ]

    private static func quotaObject(from root: [String: Any]) -> [String: Any]? {
        for key in ["data", "quota", "result"] {
            if let nested = root[key] as? [String: Any] {
                return nested
            }
        }
        return nil
    }

    private static func payloadContainsQuotaField(_ payload: [String: Any]) -> Bool {
        !self.expectedQuotaKeys.isDisjoint(with: payload.keys)
    }

    private static func double(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            let result = number.doubleValue
            return result.isFinite ? result : nil
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Double(trimmed)
        default:
            return nil
        }
    }

    private static func string(from value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - TLS via curl subprocess

#if os(macOS)
/// MyCoder's API host uses the ASUS internal CA, which macOS trust evaluation
/// rejects ("certificate exceeds maximum temporal validity period" — the leaf
/// is valid ~4 years, beyond the 398-day policy cap). URLSession delegate
/// bypasses proved unreliable in the CLI process (the auth challenge callback
/// is never invoked there), so this transport shells out to `/usr/bin/curl`
/// with `--cacert`, which validates the chain against the pinned ASUS root CA
/// directly and is immune to CFNetwork's QUIC/trust-evaluation behavior.
private final class MyCoderTrustingTransport: ProviderHTTPTransport, @unchecked Sendable {
    /// Candidate PEM root-CA paths, in priority order.
    private static let caCandidatePaths: [String?] = [
        "/etc/ssl/certs/mycoder-prod-rootCA.crt",
        ProcessInfo.processInfo.environment["NODE_EXTRA_CA_CERTS"],
    ]

    private let curlPath: String

    init() {
        self.curlPath = Self.locateCurl()
    }

    private static func locateCurl() -> String {
        for candidate in ["/usr/bin/curl", "/usr/local/bin/curl", "/opt/homebrew/bin/curl"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "/usr/bin/curl"
    }

    /// Returns the first existing PEM CA path, or nil when none is available.
    private static func resolvedCAPath() -> String? {
        for path in caCandidatePaths.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        MyCoderUsageFetcher.log.info("MyCoder curl transport request host: \(url.host ?? "nil")")

        var arguments = [
            "-sS",
            "--max-time", String(format: "%.0f", request.timeoutInterval),
            "-w", "\n%{http_code}",
        ]
        if let caPath = Self.resolvedCAPath() {
            arguments.append("--cacert")
            arguments.append(caPath)
        } else {
            MyCoderUsageFetcher.log.warning(
                "MyCoder curl transport: no pinned CA found; using -k (insecure)")
            arguments.append("-k")
        }
        for (field, value) in request.allHTTPHeaderFields ?? [:] {
            arguments.append("-H")
            arguments.append("\(field): \(value)")
        }
        MyCoderUsageFetcher.log.info(
            "MyCoder curl transport headers: \((request.allHTTPHeaderFields ?? [:]).keys.sorted().joined(separator: ","))")
        if request.httpMethod != "GET", let body = request.httpBody {
            arguments.append("--data-binary")
            arguments.append("@-")
        }
        arguments.append("--")
        arguments.append(url.absoluteString)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: self.curlPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if request.httpMethod != "GET", let body = request.httpBody {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            try process.run()
            stdinPipe.fileHandleForWriting.write(body)
            stdinPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            MyCoderUsageFetcher.log.error("MyCoder curl transport failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            throw MyCoderUsageError.networkError(
                "curl exited \(process.terminationStatus): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // Split the trailing status code line from the body.
        guard let stdout = String(data: stdoutData, encoding: .utf8),
              let lastNewline = stdout.lastIndex(of: "\n"),
              lastNewline > stdout.startIndex,
              let statusCode = Int(stdout[stdout.index(after: lastNewline)...].trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw MyCoderUsageError.networkError("curl produced no parseable HTTP response")
        }
        let body = Data(stdout[..<lastNewline].utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil) ?? URLResponse(url: url, mimeType: nil, expectedContentLength: body.count, textEncodingName: nil)
        return (body, response)
    }
}
#endif
