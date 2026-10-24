import Foundation

/// The portable protocol shared by the Mac, iPhone, iPad and Watch clients.
/// CloudKit records contain these values as encoded data so the wire format is
/// versioned independently from the UI and local persistence formats.
enum AutoRunSchema {
    static let currentVersion = 1
    static let commandVersion = 2
    static let maximumCommandAge: TimeInterval = 15 * 60
    static let maximumSessionEventText = 8_192
    static let maximumSessionOutput = 64 * 1_024
    static let maximumMessageText = 4_096
}

enum AutoRunPlatform: String, Codable, Sendable, CaseIterable {
    case macOS
    case iOS
    case iPadOS
    case watchOS
}

struct AutoRunDevice: Codable, Hashable, Identifiable, Sendable {
    enum Capability: String, Codable, CaseIterable, Sendable {
        case executeApplications
        case executeScripts
        case receiveMessages
        case sendRemoteCommands
        case interactiveSessions
    }

    let id: UUID
    var displayName: String
    var platform: AutoRunPlatform
    var capabilities: Set<Capability>
    var appVersion: String
    var lastSeen: Date
    var isRetired: Bool
    var signingPublicKey: Data?
    var agreementPublicKey: Data?

    init(
        id: UUID = UUID(),
        displayName: String,
        platform: AutoRunPlatform,
        capabilities: Set<Capability>,
        appVersion: String,
        lastSeen: Date = .now,
        isRetired: Bool = false,
        signingPublicKey: Data? = nil,
        agreementPublicKey: Data? = nil
    ) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.platform = platform
        self.capabilities = capabilities
        self.appVersion = appVersion
        self.lastSeen = lastSeen
        self.isRetired = isRetired
        self.signingPublicKey = signingPublicKey
        self.agreementPublicKey = agreementPublicKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, platform, capabilities, appVersion, lastSeen, isRetired
        case signingPublicKey, agreementPublicKey
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        platform = try values.decode(AutoRunPlatform.self, forKey: .platform)
        capabilities = try values.decodeIfPresent(Set<Capability>.self, forKey: .capabilities) ?? []
        appVersion = try values.decodeIfPresent(String.self, forKey: .appVersion) ?? "unknown"
        lastSeen = try values.decodeIfPresent(Date.self, forKey: .lastSeen) ?? .distantPast
        isRetired = try values.decodeIfPresent(Bool.self, forKey: .isRetired) ?? false
        signingPublicKey = try values.decodeIfPresent(Data.self, forKey: .signingPublicKey)
        agreementPublicKey = try values.decodeIfPresent(Data.self, forKey: .agreementPublicKey)
    }
}

enum AutomationKind: String, Codable, CaseIterable, Sendable {
    case application
    case script
}

enum AutomationParameterType: String, Codable, CaseIterable, Sendable {
    case string
    case integer
    case decimal
    case boolean
    case singleChoice
    case multipleChoice
    case dateTime
    case localResource
    case secureText
}

enum AutoRunJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([AutoRunJSONValue])
    case object([String: AutoRunJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([AutoRunJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: AutoRunJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct AutomationChoice: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
}

struct AutomationParameterDefinition: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var title: String
    var helpText: String?
    var type: AutomationParameterType
    var required: Bool
    var defaultValue: AutoRunJSONValue?
    var choices: [AutomationChoice]
    var persistedOnCompanion: Bool
    var minimum: Double?
    var maximum: Double?
    var maxLength: Int?

    var hasSafeOneTapValue: Bool {
        !required || defaultValue != nil
    }
}

struct AutomationDefinition: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let targetDeviceID: UUID
    var name: String
    var kind: AutomationKind
    var iconSystemName: String
    var enabled: Bool
    var allowsRemoteExecution: Bool
    var watchEligible: Bool
    var schemaVersion: Int
    var parameters: [AutomationParameterDefinition]
    var updatedAt: Date

    var canRunOnWatch: Bool {
        enabled && allowsRemoteExecution && watchEligible && parameters.allSatisfy(\.hasSafeOneTapValue)
    }

    func validate(parameters supplied: [String: AutoRunJSONValue]) -> [String] {
        let known = Set(self.parameters.map(\.id))
        var errors = supplied.keys.filter { !known.contains($0) }.map { "Unknown parameter: \($0)" }
        for definition in self.parameters {
            guard let value = supplied[definition.id] else {
                if definition.required && definition.defaultValue == nil { errors.append("Missing parameter: \(definition.title)") }
                continue
            }
            errors.append(contentsOf: ParameterValidator.validate(value: value, definition: definition))
        }
        return errors
    }
}

enum RemoteCommandState: String, Codable, CaseIterable, Sendable {
    case queued
    case claimed
    case executing
    case succeeded
    case failed
    case rejected
    case expired
    case cancelled
}

struct RemoteCommand: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let automationID: UUID
    let sourceDeviceID: UUID
    let targetDeviceID: UUID
    let createdAt: Date
    let expiresAt: Date
    let schemaVersion: Int
    var parameters: [String: AutoRunJSONValue]
    /// Present only for protocol-v2 commands. V1 records remain decodable but
    /// are not authorized for execution.
    var authenticatedEnvelope: AuthenticatedCommandEnvelope?
    var state: RemoteCommandState
    var claimedAt: Date?

    init(
        id: UUID = UUID(),
        automationID: UUID,
        sourceDeviceID: UUID,
        targetDeviceID: UUID,
        createdAt: Date = .now,
        expiresAt: Date? = nil,
        parameters: [String: AutoRunJSONValue] = [:],
        authenticatedEnvelope: AuthenticatedCommandEnvelope? = nil
    ) {
        self.id = id
        self.automationID = automationID
        self.sourceDeviceID = sourceDeviceID
        self.targetDeviceID = targetDeviceID
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(AutoRunSchema.maximumCommandAge)
        self.schemaVersion = AutoRunSchema.commandVersion
        self.parameters = parameters
        self.authenticatedEnvelope = authenticatedEnvelope
        self.state = .queued
        self.claimedAt = nil
    }

    func validationError(
        now: Date = .now,
        definition: AutomationDefinition?,
        targetDevice: AutoRunDevice?,
        sourceDevice: AutoRunDevice? = nil
    ) -> String? {
        guard schemaVersion == AutoRunSchema.commandVersion else { return "Unsupported command version." }
        guard now < expiresAt else { return "Command expired." }
        guard now.timeIntervalSince(createdAt) <= AutoRunSchema.maximumCommandAge else { return "Command is too old." }
        if let sourceDevice {
            guard sourceDevice.id == sourceDeviceID,
                  sourceDevice.capabilities.contains(.sendRemoteCommands),
                  !sourceDevice.isRetired else { return "Source device is unavailable." }
        }
        guard targetDevice?.id == targetDeviceID, targetDevice?.isRetired == false else { return "Target device is unavailable." }
        guard let definition else { return "Automation is unavailable." }
        guard definition.id == automationID, definition.targetDeviceID == targetDeviceID else { return "Automation target mismatch." }
        guard definition.enabled, definition.allowsRemoteExecution else { return "Remote execution is disabled." }
        let parameterErrors = definition.validate(parameters: parameters)
        guard parameterErrors.isEmpty else { return parameterErrors.joined(separator: " ") }
        guard authenticatedEnvelope != nil else { return "Command is not cryptographically authenticated." }
        return nil
    }
}

enum CommandResultStatus: String, Codable, Sendable {
    case succeeded
    case failed
    case rejected
    case expired
    case cancelled
}

struct CommandResult: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let commandID: UUID
    let automationID: UUID
    let targetDeviceID: UUID
    let sourceDeviceID: UUID
    let status: CommandResultStatus
    let createdAt: Date
    let finishedAt: Date
    let exitCode: Int32?
    let diagnostic: String?

    init(
        command: RemoteCommand,
        status: CommandResultStatus,
        finishedAt: Date = .now,
        exitCode: Int32? = nil,
        diagnostic: String? = nil
    ) {
        self.id = UUID()
        self.commandID = command.id
        self.automationID = command.automationID
        self.targetDeviceID = command.targetDeviceID
        self.sourceDeviceID = command.sourceDeviceID
        self.status = status
        self.createdAt = command.createdAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.diagnostic = diagnostic.map { String($0.prefix(AutoRunSchema.maximumSessionEventText)) }
    }
}

enum AutomationSessionState: String, Codable, CaseIterable, Sendable {
    case queued
    case starting
    case running
    case waitingForInput
    case cancelling
    case succeeded
    case failed
    case cancelled
    case expired
    case rejected
}

struct AutomationSession: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let commandID: UUID
    let automationID: UUID
    let sourceDeviceID: UUID
    let targetDeviceID: UUID
    let createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var lastActivityAt: Date
    var state: AutomationSessionState
    var cancellationRequested: Bool
    let schemaVersion: Int

    init(command: RemoteCommand, createdAt: Date = .now) {
        self.id = UUID()
        self.commandID = command.id
        self.automationID = command.automationID
        self.sourceDeviceID = command.sourceDeviceID
        self.targetDeviceID = command.targetDeviceID
        self.createdAt = createdAt
        self.startedAt = nil
        self.finishedAt = nil
        self.lastActivityAt = createdAt
        self.state = .queued
        self.cancellationRequested = false
        self.schemaVersion = AutoRunSchema.currentVersion
    }
}

enum SessionEventKind: String, Codable, Sendable {
    case started
    case stdout
    case stderr
    case progress
    case status
    case warning
    case promptCreated
    case promptAnswered
    case cancelled
    case completed
    case failed
}

struct SessionEvent: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let sequence: Int
    let createdAt: Date
    let kind: SessionEventKind
    let text: String?
    let progress: Double?
    let promptID: UUID?

    init(
        sessionID: UUID,
        sequence: Int,
        kind: SessionEventKind,
        text: String? = nil,
        progress: Double? = nil,
        promptID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.sessionID = sessionID
        self.sequence = sequence
        self.createdAt = createdAt
        self.kind = kind
        self.text = text.map { String($0.prefix(AutoRunSchema.maximumSessionEventText)) }
        self.progress = progress.map { min(max($0, 0), 1) }
        self.promptID = promptID
    }
}

enum InteractionType: String, Codable, CaseIterable, Sendable {
    case confirmation
    case singleChoice
    case multipleChoice
    case text
    case secureText
}

enum InteractionState: String, Codable, Sendable {
    case pending
    case answered
    case expired
    case cancelled
}

struct InteractionRequest: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let sessionID: UUID
    var title: String
    var body: String?
    var type: InteractionType
    var options: [AutomationChoice]
    var defaultValue: AutoRunJSONValue?
    var required: Bool
    let createdAt: Date
    let expiresAt: Date
    var state: InteractionState
}

struct InteractionResponse: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let requestID: UUID
    let sessionID: UUID
    let responderDeviceID: UUID
    let value: AutoRunJSONValue
    let createdAt: Date
}

struct DeviceMessage: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let sourceDeviceID: UUID
    let targetDeviceID: UUID
    let createdAt: Date
    let text: String
    let sound: Bool
    var isRead: Bool

    init(id: UUID = UUID(), sourceDeviceID: UUID, targetDeviceID: UUID, text: String, sound: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.sourceDeviceID = sourceDeviceID
        self.targetDeviceID = targetDeviceID
        self.createdAt = createdAt
        self.text = String(text.prefix(AutoRunSchema.maximumMessageText))
        self.sound = sound
        self.isRead = false
    }
}

struct AuditEntry: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let commandID: UUID?
    let sessionID: UUID?
    let deviceID: UUID
    let action: String
    let createdAt: Date
    let detail: String?
}

enum ParameterValidator {
    static func validate(value: AutoRunJSONValue, definition: AutomationParameterDefinition) -> [String] {
        var errors: [String] = []
        switch (definition.type, value) {
        case (.string, .string(let value)), (.secureText, .string(let value)):
            if let maximum = definition.maxLength, value.count > maximum { errors.append("\(definition.title) is too long.") }
        case (.integer, .number(let value)):
            guard value.rounded() == value else { errors.append("\(definition.title) must be an integer."); break }
            errors.append(contentsOf: rangeErrors(value, definition: definition))
        case (.decimal, .number(let value)):
            errors.append(contentsOf: rangeErrors(value, definition: definition))
        case (.boolean, .boolean): break
        case (.singleChoice, .string(let value)):
            if !definition.choices.contains(where: { $0.id == value }) { errors.append("Invalid choice for \(definition.title).") }
        case (.multipleChoice, .array(let values)):
            let choices = Set(definition.choices.map(\.id))
            if values.contains(where: { guard case .string(let id) = $0 else { return true }; return !choices.contains(id) }) { errors.append("Invalid choice for \(definition.title).") }
        case (.dateTime, .string): break
        case (.localResource, .string): break
        default: errors.append("Invalid value for \(definition.title).")
        }
        return errors
    }

    private static func rangeErrors(_ value: Double, definition: AutomationParameterDefinition) -> [String] {
        if let minimum = definition.minimum, value < minimum { return ["\(definition.title) is below its minimum."] }
        if let maximum = definition.maximum, value > maximum { return ["\(definition.title) is above its maximum."] }
        return []
    }
}

enum AutoRunJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]
            guard let date = fractionalFormatter.date(from: string) ?? standardFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
            }
            return date
        }
        return decoder
    }()
}
