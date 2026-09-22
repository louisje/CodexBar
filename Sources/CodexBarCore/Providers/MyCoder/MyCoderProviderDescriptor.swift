import Foundation

public enum MyCoderProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    /// MyCoder sessions are accessed via Chrome on the internal ASUS network.
    private static var browserCookieOrder: BrowserCookieImportOrder? {
        #if os(macOS)
        [.chrome]
        #else
        nil
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .mycoder,
            settingsSection: .init(MyCoderProviderSettingsKey.self, cookieSettings: MyCoderProviderSettings.self),
            metadata: ProviderMetadata(
                id: .mycoder,
                displayName: "MyCoder",
                sessionLabel: "Budget",
                weeklyLabel: "Budget",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "Monthly budget from the MyCoder token usage dashboard.",
                toggleTitle: "Show MyCoder usage",
                cliName: "mycoder",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: self.browserCookieOrder,
                dashboardURL: "https://afs-mycoder.asus.com/token_usage/usages",
                statusPageURL: nil,
                statusLinkURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .mycoder),
                iconResourceName: "ProviderIcon-mycoder",
                color: ProviderColor(hex: 0x0071C5),
                confettiPalette: [
                    ProviderColor(hex: 0x0071C5),
                    ProviderColor(hex: 0x4DA3E8),
                    ProviderColor(hex: 0xFFFFFF),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "MyCoder cost summary is not supported." }),
            presentation: ProviderUsagePresentation(
                planUtilizationSeriesResolver: { snapshot in
                    snapshot.primary != nil ? [.monthly] : nil
                }),
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
        let cookieSource = context.settings?.mycoder?.cookieSource ?? .auto
        do {
            let cookieHeader = try Self.resolveCookieHeader(context: context, allowCached: true)
            let snapshot = try await MyCoderUsageFetcher.fetchUsage(
                cookieHeader: cookieHeader,
                timeout: context.webTimeout)
            return self.makeResult(
                usage: snapshot.toUsageSnapshot(),
                sourceLabel: "mycoder")
        } catch MyCoderUsageError.invalidCredentials where cookieSource != .manual {
            #if os(macOS)
            CookieHeaderCache.clear(provider: .mycoder)
            let cookieHeader = try Self.resolveCookieHeader(context: context, allowCached: false)
            let snapshot = try await MyCoderUsageFetcher.fetchUsage(
                cookieHeader: cookieHeader,
                timeout: context.webTimeout)
            return self.makeResult(
                usage: snapshot.toUsageSnapshot(),
                sourceLabel: "mycoder")
            #else
            throw MyCoderUsageError.invalidCredentials
            #endif
        }
    }

    private static func resolveCookieHeader(context: ProviderFetchContext, allowCached: Bool) throws -> String {
        let cookieSource = context.settings?.mycoder?.cookieSource ?? .auto
        if cookieSource == .manual {
            guard let header = CookieHeaderNormalizer.normalize(context.settings?.mycoder?.manualCookieHeader) else {
                throw MyCoderUsageError.missingCredentials
            }
            return header
        }
        #if os(macOS)
        if allowCached,
           let cached = CookieHeaderCache.load(provider: .mycoder),
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
