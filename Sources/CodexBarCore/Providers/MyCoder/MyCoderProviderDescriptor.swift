import Foundation

public enum MyCoderProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .mycoder,
            metadata: ProviderMetadata(
                id: .mycoder,
                displayName: "MyCoder",
                sessionLabel: "Budget",
                weeklyLabel: "Budget",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "Monthly budget from the MyCoder billing dashboard.",
                toggleTitle: "Show MyCoder usage",
                cliName: "mycoder",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: ProviderBrowserCookieDefaults.mycoderCookieImportOrder,
                dashboardURL: "https://afs-mycoder.asus.com/billing",
                statusPageURL: nil,
                statusLinkURL: nil),
            branding: ProviderBranding(
                iconStyle: .mycoder,
                iconResourceName: "ProviderIcon-mycoder",
                color: ProviderColor(red: 0 / 255, green: 113 / 255, blue: 197 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "MyCoder cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [MyCoderWebFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "mycoder",
                aliases: [],
                versionDetector: nil))
    }
}

struct MyCoderWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "mycoder.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        let cookieSource = context.settings?.mycoder?.cookieSource ?? .auto
        guard cookieSource != .off else { return false }
        if cookieSource == .manual {
            return CookieHeaderNormalizer.normalize(context.settings?.mycoder?.manualCookieHeader) != nil
        }
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let cookieHeader = try Self.resolveCookieHeader(context: context)
        let snapshot = try await MyCoderUsageFetcher.fetchUsage(
            cookieHeader: cookieHeader,
            timeout: context.webTimeout)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "mycoder")
    }

    private static func resolveCookieHeader(context: ProviderFetchContext) throws -> String {
        let cookieSource = context.settings?.mycoder?.cookieSource ?? .auto
        if cookieSource == .manual {
            guard let header = CookieHeaderNormalizer.normalize(context.settings?.mycoder?.manualCookieHeader) else {
                throw MyCoderUsageError.missingCredentials
            }
            return header
        }
        #if os(macOS)
        if let cached = CookieHeaderCache.load(provider: .mycoder),
           !cached.cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return cached.cookieHeader
        }
        let sessions = (try? MyCoderCookieImporter.importSessions()) ?? []
        guard let session = sessions.first, !session.cookieHeader.isEmpty else {
            throw MyCoderUsageError.missingCredentials
        }
        CookieHeaderCache.store(
            provider: .mycoder,
            cookieHeader: session.cookieHeader,
            sourceLabel: session.sourceLabel)
        return session.cookieHeader
        #else
        throw MyCoderUsageError.missingCredentials
        #endif
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
