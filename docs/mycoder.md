---
summary: "MyCoder monthly usage and token budget from the ASUS internal dashboard."
provider_id: mycoder
provider_name: MyCoder
provider_source: ASUS MyCoder internal quota API, authenticated with a browser SSO cookie.
plugin_scope: Internal MyCoder quota and per-model usage via the selected Chrome session; access requires the corporate network.
read_when:
  - Setting up MyCoder in a CodexBar fork
  - Troubleshooting MyCoder quotas or browser credentials
---

# MyCoder

MyCoder is a fork-specific provider intended for users who already have access to the
ASUS MyCoder dashboard and internal services. It is disabled by default.

Enable **MyCoder** in CodexBar and sign in to the MyCoder dashboard in Chrome.
CodexBar can import the browser session cookie, or accept a manually supplied
cookie header in MyCoder settings. Access requires the relevant internal network
and account permissions. Never share or commit browser cookies or SSO tokens.

MyCoder reports a monthly quota and optional per-model token usage. The quota
may be unavailable when an SSO session expires or internal API access is blocked.
Check the selected browser session and network access when refresh fails.

This provider belongs to the `louisje/CodexBar` fork and is not part of the
upstream `steipete/CodexBar` release.
