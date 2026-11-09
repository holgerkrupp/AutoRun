#if os(macOS)
import Foundation
import SwiftData

enum RemoteAutomationCatalog {
    static func definition(for timer: TimerItem, deviceID: UUID) -> AutomationDefinition {
        AutomationDefinition(
            id: timer.remoteID,
            targetDeviceID: deviceID,
            name: timer.remoteDisplayName,
            kind: timer.launchType == .app ? .application : .script,
            iconSystemName: timer.launchType == .app ? "app.connected.to.app.below.fill" : "terminal.fill",
            enabled: timer.isEnabled || timer.allowsRemoteExecution,
            allowsRemoteExecution: timer.allowsRemoteExecution,
            watchEligible: timer.watchEligible,
            schemaVersion: AutoRunSchema.currentVersion,
            parameters: timer.remoteParameters,
            updatedAt: .now
        )
    }

    @MainActor
    static func publish(timers: [TimerItem]) async {
        let repository = CloudKitRepository.shared
        let device = AutoRunDevice(
            id: DeviceIdentity.id,
            displayName: DeviceIdentity.displayName,
            platform: .macOS,
            capabilities: [.executeApplications, .executeScripts, .receiveMessages, .interactiveSessions],
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            signingPublicKey: DeviceIdentity.signingPublicKey,
            agreementPublicKey: DeviceIdentity.agreementPublicKey
        )
        do {
            try await repository.upsertDevice(device)
            for timer in timers {
                try await repository.upsertAutomation(definition(for: timer, deviceID: device.id))
            }
        } catch {
            // CloudKit is optional for local scheduling. The next launch or
            // activation retries publication and the local app remains usable.
        }
    }
}

@MainActor
final class MacRemoteCommandProcessor {
    static let shared = MacRemoteCommandProcessor()

    private let repository = CloudKitRepository.shared

    func reconcile(timers: [TimerItem]) async {
        await RemoteAutomationCatalog.publish(timers: timers)
        do {
            let devices = try await repository.devices()
            let commands = try await repository.commands()
            let localDeviceID = DeviceIdentity.id
            guard let localDevice = devices.first(where: { $0.id == localDeviceID }) else { return }

            for command in commands where command.targetDeviceID == localDevice.id && command.state == .queued {
                // A CloudKit record is untrusted input. Phase 0's signed
                // envelope primitives are not a substitute for an approved,
                // Mac-local pairing grant; until that grant store and pairing
                // UI are wired up, no cloud command is executable.
                try await finish(
                    command,
                    status: .rejected,
                    diagnostic: "This Mac has no active cryptographic pairing authorization."
                )
            }
        } catch {
            // The processor is retried on the next activation. Never turn a
            // transient iCloud failure into a local timer failure.
        }
    }

    private func finish(_ command: RemoteCommand, status: CommandResultStatus, diagnostic: String?) async throws {
        var updated = command
        updated.state = RemoteCommandState(rawValue: status.rawValue) ?? .failed
        try await repository.save(updated, type: AutoRunRecordType.command, id: updated.id)
        try await repository.save(CommandResult(command: command, status: status, diagnostic: diagnostic))
        try await repository.save(AuditEntry(id: UUID(), commandID: command.id, sessionID: nil, deviceID: DeviceIdentity.id, action: "remote_\(status.rawValue)", createdAt: .now, detail: diagnostic))
    }
}

struct ScriptProtocolMessage: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case progress, status, prompt }
    let kind: Kind
    let payload: [String: AutoRunJSONValue]
}

enum ScriptProtocolParser {
    static let prefix = "AUTORUN:1 "

    static func parse(line: String) -> ScriptProtocolMessage? {
        guard line.hasPrefix(prefix) else { return nil }
        let body = String(line.dropFirst(prefix.count))
        guard let data = body.data(using: .utf8),
              let object = try? AutoRunJSON.decoder.decode([String: AutoRunJSONValue].self, from: data),
              case .string(let kindString) = object["kind"],
              let kind = ScriptProtocolMessage.Kind(rawValue: kindString),
              case .object(let payload) = object["payload"] else { return nil }
        return ScriptProtocolMessage(kind: kind, payload: payload)
    }
}
#endif
