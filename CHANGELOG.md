# Changelog

All notable changes to this gem are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the gem uses
[Semantic Versioning](https://semver.org/). While the version is 0.x, a minor
bump may change the public API described in the README; such changes are listed
under **Breaking**.

## 0.1.0 — 2026-10-19

### Added

- Provider registry with a DSL for shared and per-channel inputs, capabilities
  and per-message-type templates.
- Bundled providers: MSG91 (email, SMS, WhatsApp), SMTP (email), Gupshup
  (WhatsApp), and a Log provider for non-production environments.
- Per-store provider configuration with encrypted secrets, readiness and
  priority ordering per channel.
- Router with failover on definite failures only, bulk sends without failover,
  and one Delivery log row per attempt.
- Admin screens: Notification providers, per-provider test send, Delivery log.
- Action Mailer delivery method `:spree_notification_providers`.
- Gupshup delivery webhook with per-store secrets.
- Env importer generator for apps moving from environment variables.
