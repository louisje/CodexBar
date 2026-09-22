import Foundation

public struct MyCoderUsageSnapshot: Sendable {
    /// One model's cost/token contribution within the lookback window, used to populate
    /// a `ProviderDetailSection` breakdown. Not persisted standalone; derived from the
    /// `/usage` API each fetch.
    public struct ModelUsageRow: Sendable, Equatable {
        public let model: String
        public let costUSD: Double
        public let totalTokens: Double

        public init(model: String, costUSD: Double, totalTokens: Double) {
            self.model = model
            self.costUSD = costUSD
            self.totalTokens = totalTokens
        }
    }

    public let usedBudget: Double
    public let totalBudget: Double
    public let availableBudget: Double
    public let account: String?
    public let updatedAt: Date
    /// Per-model cost breakdown for the last 30 days, sorted by cost descending. Empty when
    /// the `/usage` API call failed or was skipped — non-fatal, quota remains the primary data.
    public var modelUsageRows: [ModelUsageRow] = []

    public init(
        usedBudget: Double,
        totalBudget: Double,
        availableBudget: Double,
        account: String?,
        updatedAt: Date = Date())
    {
        self.usedBudget = usedBudget
        self.totalBudget = totalBudget
        self.availableBudget = availableBudget
        self.account = account
        self.updatedAt = updatedAt
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let usagePercentage = self.totalBudget > 0
            ? min(100, max(0, (self.usedBudget / self.totalBudget) * 100))
            : 0
        let resetDescription = String(format: "$%.2f / $%.2f", self.usedBudget, self.totalBudget)
        let primary = RateWindow(
            usedPercent: usagePercentage,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: resetDescription)

        let identity = ProviderIdentitySnapshot(
            providerID: .mycoder,
            accountEmail: self.account,
            accountOrganization: nil,
            loginMethod: nil)

        let cost = ProviderCostSnapshot(
            used: self.usedBudget,
            limit: self.totalBudget,
            currencyCode: "USD",
            period: "Monthly",
            updatedAt: self.updatedAt)

        let modelRows = self.modelUsageRows.prefix(5).compactMap { row -> ProviderDetailSection.Row? in
            try? ProviderDetailSection.Row(
                label: row.model,
                value: String(format: "$%.2f", row.costUSD),
                secondaryValue: "\(Int(row.totalTokens.rounded())) tokens")
        }
        let details = (try? [ProviderDetailSection](arrayLiteral: ProviderDetailSection(
            title: "Top Models (30d)",
            rows: Array(modelRows)))) ?? []
        let visibleDetails = modelRows.isEmpty ? [] : details

        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: cost,
            details: visibleDetails,
            updatedAt: self.updatedAt,
            identity: identity)
    }
}
