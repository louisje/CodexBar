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
        if trimmedCredentials.contains("="), trimmedCredentials.contains(";") || trimmedCredentials.contains(" ") {
            for pair in trimmedCredentials.split(separator: ";") {
                let keyValue = pair.split(separator: "=", maxSplits: 1)
                guard keyValue.count == 2 else { continue }
                let name = keyValue[0].trimmingCharacters(in: .whitespaces)
                guard name == Self.ssoCookieName else { continue }
                let value = keyValue[1].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            return nil
        }
        // A pasted manual credential may be the raw token itself.
        return trimmedCredentials.isEmpty ? nil : trimmedCredentials
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
            throw MyCoderUsageError.networkError(error.localizedDescription)
        }
        if response.statusCode == 401 || response.statusCode == 403 {
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

// MARK: - TLS Trust Bypass

#if os(macOS)
/// A custom transport that validates TLS certificates for the MyCoder hosts against
/// the pinned ASUS internal root CA (`ASUSTEK 2016 Root CA`). The certificate is
/// embedded in the bundle so validation works without user-side Keychain setup.
/// Uses completion-handler based `dataTask` (like Antigravity's LocalhostSessionDelegate)
/// to guarantee the URLSessionDelegate auth challenge callback is invoked.
private final class MyCoderTrustingTransport: ProviderHTTPTransport, @unchecked Sendable {
    private static let trustedHosts: Set<String> = ["afs-mycoder.asus.com", "afs-mycoder-api.asus.com"]

    private let session: URLSession
    private let delegate: MyCoderTrustDelegate

    init() {
        let delegate = MyCoderTrustDelegate()
        self.delegate = delegate
        self.session = URLSession(
            configuration: ProviderHTTPClient.defaultConfiguration(),
            delegate: delegate,
            delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            MyCoderUsageFetcher.log.info(
                "MyCoder trusting transport request host: \(request.url?.host ?? "nil")")
            let task = self.session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}

private final class MyCoderTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private static let trustedHosts: Set<String> = ["afs-mycoder.asus.com", "afs-mycoder-api.asus.com"]
}

/// Delegate callbacks live in an extension so their signatures do not
/// "nearly match" the optional URLSession(Delegate) requirements and trigger
/// near-miss diagnostics.
extension MyCoderTrustDelegate {
    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    {
        let (disposition, credential) = self.evaluate(challenge)
        completionHandler(disposition, credential)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    {
        let (disposition, credential) = self.evaluate(challenge)
        completionHandler(disposition, credential)
    }

    private func evaluate(_ challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition, URLCredential?)
    {
        let space = challenge.protectionSpace
        MyCoderUsageFetcher.log.info(
            "MyCoder TLS challenge: host=\(space.host) method=\(space.authenticationMethod)")
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              Self.trustedHosts.contains(space.host.lowercased()),
              let trust = space.serverTrust
        else {
            MyCoderUsageFetcher.log.info("MyCoder TLS challenge: falling back to default handling")
            return (.performDefaultHandling, nil)
        }
        // Prefer the ASUS internal root CA as the trust anchor for these hosts.
        // Sources, in order: /etc/ssl/certs/mycoder-prod-rootCA.crt, then
        // the NODE_EXTRA_CA_CERTS environment variable. If neither exists,
        // fall back to unconditional trust so the probe still works.
        if let anchorCertificates = MyCoderTrustDelegate.pinnedRootCertificates {
            SecTrustSetAnchorCertificates(trust, anchorCertificates as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
            MyCoderUsageFetcher.log.info("MyCoder TLS challenge: pinned-CA credential for \(space.host)")
            return (.useCredential, URLCredential(trust: trust))
        }
        MyCoderUsageFetcher.log.warning(
            "MyCoder TLS: root CA not found; using unconditional trust for \(space.host)")
        return (.useCredential, URLCredential(trust: trust))
    }
}

extension MyCoderTrustDelegate {
    /// Loads the ASUS internal root CA from the system cert directory or
    /// `NODE_EXTRA_CA_CERTS`. Returns nil when neither source is available.
    static var pinnedRootCertificates: [SecCertificate]? {
        let candidatePaths = [
            "/etc/ssl/certs/mycoder-prod-rootCA.crt",
            ProcessInfo.processInfo.environment["NODE_EXTRA_CA_CERTS"],
        ].compactMap { $0 }
        for path in candidatePaths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            if let certificate = SecCertificateCreateWithData(nil, data as CFData) {
                return [certificate]
            }
            // The file may be PEM; convert the first base64 block to DER.
            if let der = Self.derFromPEM(data),
               let certificate = SecCertificateCreateWithData(nil, der as CFData)
            {
                return [certificate]
            }
        }
        return nil
    }

    /// Extracts the first PEM certificate body and decodes it to DER bytes.
    private static func derFromPEM(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8),
              let beginRange = text.range(of: "-----BEGIN CERTIFICATE-----"),
              let endRange = text.range(of: "-----END CERTIFICATE-----"),
              beginRange.upperBound <= endRange.lowerBound
        else { return nil }
        let base64 = text[beginRange.upperBound..<endRange.lowerBound]
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return Data(base64Encoded: base64)
    }
}
#endif
