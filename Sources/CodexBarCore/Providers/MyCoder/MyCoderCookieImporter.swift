import Foundation

#if os(macOS)
import SweetCookieKit

public enum MyCoderCookieImporter {
    private static let log = CodexBarLog.logger(LogCategories.mycoderUsage)
    private static let cookieClient = BrowserCookieClient()
    private static let cookieDomains = ["afs-mycoder.asus.com"]
    private static let cookieImportOrder: BrowserCookieImportOrder =
        ProviderDefaults.metadata[.mycoder]?.browserCookieOrder ?? Browser.defaultImportOrder

    public struct SessionInfo: Sendable {
        public let cookies: [HTTPCookie]
        public let sourceLabel: String

        public var cookieHeader: String {
            self.cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }

    public static func importSessions(
        browserDetection: BrowserDetection = BrowserDetection(),
        logger: ((String) -> Void)? = nil) throws -> [SessionInfo]
    {
        let installedBrowsers = self.cookieImportOrder.cookieImportCandidates(using: browserDetection)
        var sessions: [SessionInfo] = []
        let query = BrowserCookieQuery(domains: self.cookieDomains, domainMatch: .exact)

        for browserSource in installedBrowsers {
            do {
                let sources = try self.cookieClient.codexBarRecords(
                    matching: query,
                    in: browserSource,
                    logger: { msg in self.log.debug("\(msg)") })
                for source in sources where !source.records.isEmpty {
                    let cookies = BrowserCookieClient.makeHTTPCookies(
                        source.records,
                        origin: query.origin)
                    guard !cookies.isEmpty else { continue }
                    sessions.append(SessionInfo(cookies: cookies, sourceLabel: source.label))
                }
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
                self.log.debug(
                    "MyCoder cookie import failed for \(browserSource.displayName): \(error.localizedDescription)")
            }
        }

        return sessions
    }
}
#endif
