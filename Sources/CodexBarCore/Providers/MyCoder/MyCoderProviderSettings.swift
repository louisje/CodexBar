import Foundation

public struct MyCoderProviderSettings: ProviderCookieSettings {
    public let cookieSource: ProviderCookieSource
    public let manualCookieHeader: String?

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?) {
        self.cookieSource = cookieSource
        self.manualCookieHeader = manualCookieHeader
    }
}

public enum MyCoderProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.mycoder
    public typealias Section = MyCoderProviderSettings
}

extension ProviderSettingsSnapshot {
    public typealias MyCoderProviderSettings = CodexBarCore.MyCoderProviderSettings
    public var mycoder: MyCoderProviderSettings? {
        self[MyCoderProviderSettingsKey.self]
    }

    public static func make(mycoder: MyCoderProviderSettings?) -> Self {
        self.make(mycoder, for: MyCoderProviderSettingsKey.self)
    }
}

extension ProviderSettingsSnapshotContribution {
    public static func mycoder(_ section: MyCoderProviderSettings) -> Self {
        Self(section, for: MyCoderProviderSettingsKey.self)
    }
}
