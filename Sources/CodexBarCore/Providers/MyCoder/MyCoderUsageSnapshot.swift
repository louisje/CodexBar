import Foundation

public struct MyCoderUsageSnapshot: Sendable {
    public let usedBudget: Double
    public let totalBudget: Double
    public let availableBudget: Double
    public let account: String?
    public let updatedAt: Date

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
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil)

        let cost = ProviderCostSnapshot(
            used: self.usedBudget,
            limit: self.totalBudget,
            currencyCode: "USD",
            period: "Monthly",
            updatedAt: self.updatedAt)

        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: cost,
            updatedAt: self.updatedAt,
            identity: identity)
    }
}
