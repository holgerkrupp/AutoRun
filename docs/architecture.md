# AutoRun architecture and Phase 0 status

AutoRun's intended remote-management design is serverless: the shared
macOS/iOS/iPadOS application uses the user's private CloudKit database for
durable catalogs, requests, results, and synchronization. CloudKit pushes are
best-effort wake hints. A client must reconcile authoritative records after
launch, activation, and notification delivery. The Mac remains the execution
host and the authority for local automation definitions and permissions.

## Source reconciliation

The default branch inspected for Phase 0 was `origin/main` at
`b829602d1642bf9bf192a12b42f29a4fe9e36388`. It contains a macOS target and
LaunchAgent timer support, but no iOS/iPadOS target, CloudKit repository,
companion, remote command models, or test target. PRs #1–#3 are the only PRs
found; none contains the claimed #10/#14 implementation. The closing comments
on #10 and #14 refer to a working tree, not a merged commit. The companion and
CloudKit files present in the October 24, 2026 local working tree had no Git
history or PR provenance. This branch preserves and audits that local work; it
does not treat the issue comments as evidence of a completed release.

## Current code paths

- `SharedDomain.swift` contains portable device, automation, command, session,
  result, and audit value types. Newly added timer fields default remote
  execution off, preserving existing timer records.
- `CloudKitRepository.swift` owns private-database access in an actor, uses a
  custom record zone and subscription, persists `CKSyncEngine` state, and
  reconciles records. It currently serializes values in a `payload` field.
- `CompanionViews.swift` and `RemoteAutomationCatalog.swift` contain the
  companion UI and Mac catalog projection. These paths are not yet a complete,
  authenticated command lifecycle.
- `RemoteSecurity.swift` provides CryptoKit P-256 signing and agreement,
  AES-GCM command envelopes, a signed short-lived pairing challenge/proof,
  independent capability names, device-only Keychain storage, and a durable
  replay ledger. The keys are Keychain protected with
  `WhenUnlockedThisDeviceOnly`; this version does not claim Secure Enclave
  backing.
- `MacRemoteCommandProcessor` rejects pending CloudKit commands because a
  Mac-local grant store and user approval workflow are not yet integrated.
  `CloudKitRepository.createCommand` rejects unsigned or plaintext-parameter
  commands. No CloudKit record alone can launch an automation.
- `TimerItem.swift` retains its SwiftData data and script/app fields, adds
  opt-in remote metadata with safe migration defaults, and restores the
  LaunchAgent scheduler path from `origin/main`. Sandboxed builds use the
  in-process timer fallback.

## Records and lifecycle

The existing private zone uses record types `AutoRunDevice`,
`AutoRunAutomation`, `AutoRunRemoteCommand`, `AutoRunCommandResult`,
`AutoRunSession`, `AutoRunSessionEvent`, `AutoRunInteractionRequest`,
`AutoRunInteractionResponse`, `AutoRunDeviceMessage`, and `AutoRunAuditEntry`.
The target lifecycle is: create an authenticated expiring command; save it;
reconcile it on the Mac; validate its target, local grant, signature, expiry,
nonce, capability, and automation; claim it with a server-conditional write;
execute only an enabled local automation; then persist a bounded result and
audit record. The notification is never the command itself.

The current CloudKit layer does not yet provide an atomic claim or a complete
CloudKit integration test. The replay ledger protects cryptographic envelope
validation on one installation, but the currently disabled processor does not
call it. Do not re-enable command execution until the trust/grant store,
conditional CloudKit claim, result authentication, and interruption recovery
are implemented together.

## Pairing and trust boundaries

The pairing challenge format contains a random nonce, target Mac ID, public
signing/agreement keys, creation and expiry times, and a Mac signature. A
companion proof binds its device ID and public keys to the challenge. The
challenge expires after three minutes. The command envelope signs canonical
versioned metadata and encrypts its payload with AES-GCM using an ephemeral
P-256 ECDH key and HKDF-SHA256. The private command keys never enter CloudKit.

These primitives are implemented and unit tested; the QR presentation/scanner,
Mac approval UI, processor integration with the Keychain-backed grant registry,
capability revocation UI, and signed result verification are not. The grant
registry supports independent grants and local revocation, and the one-time
pairing challenge ledger exists, but neither is connected to a pairing
coordinator or command executor. CloudKit
device records are discovery metadata only and are not trusted grants. Every
new device starts with an empty capability set. Device key loss, replacement,
or reinstall must require re-pairing; a public key change invalidates the old
grant. The Mac's local grant is authoritative. Revocation must remove the
grant before further processing and make queued commands fail closed.

## Capability policy

`RemoteCapability` is the shared stable vocabulary:

| Capability | Default | Phase 0 state |
| --- | --- | --- |
| `automation.execute` | Off | Envelope primitive exists; Mac execution disabled pending local approval integration |
| `system.read` | Off | Not implemented |
| `files.read` | Off | Not implemented |
| `files.write` | Off | Not implemented |
| `terminal.execute` | Off | Not implemented; arbitrary remote shell is out of scope |
| `terminal.interactive` | Off | Not implemented |
| `screen.control` | Off | Not implemented |

Do not infer any grant from iCloud account membership, a CloudKit device
record, a legacy capability value, or approval of a different capability.

## Mac App Store and helper decision

The app's Mac target has App Sandbox enabled and only the user-selected
read-only file entitlement. SDK-specific entitlement files keep those Mac
entitlements off iOS/iPadOS; Release entitlements use the production APNs
environment, while Debug uses development. The in-app timer, SwiftData
persistence, SwiftUI, CloudKit, and user-selected read access stay in the store
app.
`LaunchAgentScheduler` writes outside the app container and invokes `launchctl`;
it is disabled when `APP_SANDBOX_CONTAINER_ID` is present and the local timer
continues in-process. This code-level gate is not a signed Mac App Store runtime
test.

The existing `TimerItem.runScript` uses `Process` to launch `/bin/zsh -c`.
Whether the shipped Mac App Store build can run the user's selected scripts
was not experimentally validated with a production-signed store build. A
successful Xcode build does not establish sandbox behavior. Keep that risk
visible and test with the actual store-signed app before release. Do not route
remote commands to that method in Phase 0.

Future background reconciliation can use an `SMAppService` LaunchAgent bundled
inside the Mac app, registered only after explicit user action and system
approval. No such helper target is implemented. The helper must run as the
normal user, expose only the approved command queue, and report disabled or
failed status. `SMAppService.mainApp` launch-at-login support is not equivalent
to an independent background processor after the user quits AutoRun.

General shell execution, broad filesystem access, PTY sessions, and some
screen-control workflows may require a separate Developer ID signed and
notarized product/helper. No helper is currently shipped or installed. Any
future helper needs an explicit user download/installation and approval,
authenticated and versioned XPC, narrowly scoped operations, revocation,
upgrade compatibility, diagnostics, and an uninstall path. It must not use
root privileges or bypass App Sandbox/TCC. The Mac App Store app remains
usable without it.

## Background and synchronization limits

CloudKit does not provide an always-on RPC channel. AutoRun registers with
Apple's push service so CloudKit can deliver subscription hints without any
developer APNs provider credential in the app. The iOS target does not declare
the Remote Notifications background mode in this phase, so it does not claim
background wake behavior. The Mac may be asleep,
logged out, offline, or prevented from running in the background by the user.
CloudKit pushes can be delayed or coalesced; reconciliation provides eventual
discovery but not a wake guarantee. The currently registered app-level login
item starts the main app at login; an independent `SMAppService` processor is
still a prerequisite for command handling when the interface is closed.

## Future implementation rules

1. Extend the models in `SharedDomain.swift`; keep IDs durable and command
   schemas versioned. Decode older stored timer records with remote access off.
2. Keep the private-database actor as the only CloudKit access path. Use
   conditional writes/change tags for command claims and deduplication.
3. Treat CloudKit records, user-provided parameters, imported files, and
   notifications as untrusted. Authenticate the envelope and compare it with
   the Mac-local device grant before decrypting or performing an operation.
4. Route approved automation through one local executor; never accept remote
   shell source. Keep file, terminal, and screen capabilities separate.
5. Add focused unit tests plus CloudKit sandbox integration tests and cover
   restart, account-unavailable, revocation, and conflict paths.
6. Preserve the single macOS/iOS/iPadOS app target. Keep AppKit, `Process`,
   `NSWorkspace`, launchd, and `SMAppService` code behind macOS-only source
   boundaries. Add targets, entitlements, App Groups, and permissions only by
   explicit project decision.
7. Localize user-facing messages and verify VoiceOver, keyboard, Dynamic Type,
   compact phone layouts, and resizable iPad layouts.

## Manual verification checklist

- Install the Mac App Store build on a clean Mac; create and run a local app
  timer and script timer, restart the app, and confirm existing timers remain.
- In a sandboxed Mac build, confirm repeating timer fallback works and no
  `~/Library/LaunchAgents` modification or `launchctl` call is attempted.
- Select a script/app through the standard picker and verify persisted access
  after relaunch. Record actual production behavior of `Process` scripts.
- On signed Mac and iPhone builds in the same iCloud account, verify private
  CloudKit availability, offline/retry behavior, and catalog reconciliation.
- Pair only after the UI/grant store is implemented: verify challenge expiry,
  fingerprint confirmation, per-capability approval, revocation, key loss, and
  re-pairing. Confirm unsigned, modified, stale, replayed, and wrong-target
  records are rejected without launching any timer.
- Sleep/wake and quit/reopen the Mac to validate the eventual `SMAppService`
  processor once its target is implemented and approved.

## Apple platform references

- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [SMAppService registration and user approval](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- [CKSyncEngine scheduling and state persistence](https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9)
