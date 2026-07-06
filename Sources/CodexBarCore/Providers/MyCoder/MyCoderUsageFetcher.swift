import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MyCoderUsageFetcher {
    private static let log = CodexBarLog.logger(LogCategories.mycoderUsage)
    private static let baseURL = "https://afs-mycoder.asus.com/billing"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"

    public static func fetchUsage(
        cookieHeader: String,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        now: Date = Date(),
        timeout: TimeInterval = 15) async throws -> MyCoderUsageSnapshot
    {
        let quotaData = try await self.sendRequest(
            path: "/api/quota/me",
            cookieHeader: cookieHeader,
            transport: transport,
            timeout: timeout)
        return try self.parseQuota(data: quotaData, now: now)
    }

    private static func sendRequest(
        path: String,
        cookieHeader: String,
        transport: any ProviderHTTPTransport,
        timeout: TimeInterval) async throws -> Data
    {
        guard let url = URL(string: self.baseURL + path) else {
            throw MyCoderUsageError.networkError("invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json, */*", forHTTPHeaderField: "Accept")
        request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(self.baseURL, forHTTPHeaderField: "Referer")

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
        let response: MyCoderQuotaResponse
        do {
            response = try JSONDecoder().decode(MyCoderQuotaResponse.self, from: data)
        } catch {
            throw MyCoderUsageError.parseFailed("invalid JSON: \(error.localizedDescription)")
        }
        guard response.success, let quota = response.data else {
            throw MyCoderUsageError.parseFailed("missing quota data")
        }
        let used = quota.totalQuota - quota.availableQuota
        return MyCoderUsageSnapshot(
            usedBudget: max(0, used),
            totalBudget: quota.totalQuota,
            availableBudget: quota.availableQuota,
            account: quota.account,
            updatedAt: now)
    }
}

private struct MyCoderQuotaResponse: Decodable {
    let success: Bool
    let data: MyCoderQuotaData?
}

private struct MyCoderQuotaData: Decodable {
    let account: String?
    let totalQuota: Double
    let availableQuota: Double

    private enum CodingKeys: String, CodingKey {
        case account
        case totalQuota
        case availableQuota
    }
}
