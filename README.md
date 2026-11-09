# AutoRun

AutoRun is a native Apple-platform app for launching macOS applications and
running local scripts on one-shot or repeating timers. The Mac app retains its
menu-bar interface, SwiftData timers, and existing Mac App Store distribution.
The same main Xcode target is configured for macOS, iOS, and iPadOS; macOS-only
execution code stays behind platform guards.

The companion and remote-management foundation is under active development.
Remote execution remains disabled until Mac-side pairing approval, capability
grants, revocation, authenticated command claiming, and background processing
are integrated. No remotely received shell source is executable. See
[`docs/architecture.md`](docs/architecture.md) for the implementation audit,
security boundaries, distribution decisions, and Phase 0 verification status.

AutoRun is available on the [Mac App Store](https://apps.apple.com/de/app/autorun-run-apps/id6739644500?l=en-GB&mt=12).
<a href="https://apps.apple.com/de/app/autorun-run-apps/id6739644500?l=en-GB&mt=12"><img src="mac-app-store-badge.svg" alt="Mac App Store" height="50"/></a>
