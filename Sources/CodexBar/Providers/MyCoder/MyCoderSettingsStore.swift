import CodexBarCore
import Foundation

extension SettingsStore {
    var mycoderCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .mycoder)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .mycoder) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .mycoder, field: "cookieHeader", value: newValue)
        }
    }

    var mycoderCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .mycoder, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .mycoder) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .mycoder, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func ensureMyCoderCookieLoaded() {}
}

extension SettingsStore {
    func mycoderSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot
        .MyCoderProviderSettings
    {
        self.resolvedCookieSettings(
            provider: .mycoder,
            configuredSource: self.mycoderCookieSource,
            configuredHeader: self.mycoderCookieHeader,
            tokenOverride: tokenOverride)
    }
}
