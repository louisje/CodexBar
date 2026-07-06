import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct MyCoderProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .mycoder

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.mycoderCookieSource
        _ = settings.mycoderCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .mycoder(context.settings.mycoderSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.mycoderCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.mycoderCookieSource != .manual {
            settings.mycoderCookieSource = .manual
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.mycoderCookieSource.rawValue },
            set: { raw in
                context.settings.mycoderCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.mycoderCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Automatic imports browser cookies from afs-mycoder.asus.com.",
                manual: "Paste a Cookie header from a MyCoder billing request.",
                off: "MyCoder cookies are disabled.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "mycoder-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies from afs-mycoder.asus.com.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.loadForDisplay(provider: .mycoder) else { return nil }
                    let when = entry.storedAt.relativeDescription()
                    return "Cached: \(entry.sourceLabel) • \(when)"
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "mycoder-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: \u{2026}\n\nor paste a Cookie header from the MyCoder billing page",
                binding: context.stringBinding(\.mycoderCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "mycoder-open-billing",
                        title: "Open MyCoder Billing",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://afs-mycoder.asus.com/billing") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.mycoderCookieSource == .manual },
                onActivate: { context.settings.ensureMyCoderCookieLoaded() }),
        ]
    }
}
