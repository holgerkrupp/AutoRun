import Foundation

#if canImport(CloudKit)
import CloudKit

enum AutoRunRecordType {
    static let device = "AutoRunDevice"
    static let automation = "AutoRunAutomation"
    static let command = "AutoRunRemoteCommand"
    static let result = "AutoRunCommandResult"
    static let session = "AutoRunSession"
    static let event = "AutoRunSessionEvent"
    static let request = "AutoRunInteractionRequest"
    static let response = "AutoRunInteractionResponse"
    static let message = "AutoRunDeviceMessage"
    static let audit = "AutoRunAuditEntry"
}

enum CloudKitRepositoryError: LocalizedError {
    case unavailable
    case malformedRecord(String)
    case duplicateCommand
    case invalidCommand(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return String(localized: "iCloud is unavailable. Check the iCloud account and try again.")
        case .malformedRecord(let type): return "The iCloud record \(type) is not valid."
        case .duplicateCommand: return "This command has already been accepted."
        case .invalidCommand(let message): return message
        }
    }
}

private enum AutoRunRecordCodec {
    static func record<T: Codable>(for value: T, type: String, id: UUID, zoneID: CKRecordZone.ID) throws -> CKRecord {
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID))
        record["schemaVersion"] = AutoRunSchema.currentVersion as NSNumber
        record["updatedAt"] = Date() as NSDate
        record["payload"] = try AutoRunJSON.encoder.encode(value) as NSData
        return record
    }

    static func value<T: Codable>(from record: CKRecord, as type: T.Type) throws -> T {
        guard let payload = record["payload"] as? Data else {
            throw CloudKitRepositoryError.malformedRecord(record.recordType)
        }
        do {
            return try AutoRunJSON.decoder.decode(type, from: payload)
        } catch {
            throw CloudKitRepositoryError.malformedRecord(record.recordType)
        }
    }
}

private final class AutoRunSyncDelegate: NSObject, CKSyncEngineDelegate, @unchecked Sendable {
    let onEvent: @Sendable (CKSyncEngine.Event) async -> Void

    init(onEvent: @escaping @Sendable (CKSyncEngine.Event) async -> Void) {
        self.onEvent = onEvent
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await onEvent(event)
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // The repository writes records through CKDatabase.modifyRecords. The
        // sync engine still owns server-change tokens and wake/sync scheduling;
        // returning an empty batch prevents a duplicate send path.
        CKSyncEngine.RecordZoneChangeBatch()
    }

    func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        CKSyncEngine.FetchChangesOptions(scope: .all)
    }
}

/// One actor owns all CloudKit access. Notifications are only wake hints: UI
/// and command processing call `reconcile()` to fetch authoritative records.
actor CloudKitRepository {
    static let shared = CloudKitRepository()

    private let containerIdentifier: String
    private var database: CKDatabase?
    private let zoneID: CKRecordZone.ID
    private var syncEngine: CKSyncEngine?
    private var lastSyncError: String?

    init(containerIdentifier: String = "iCloud.de.holgerkrupp.AutoRun") {
        self.containerIdentifier = containerIdentifier
        self.zoneID = CKRecordZone.ID(zoneName: "AutoRun", ownerName: CKCurrentUserDefaultName)
    }

    func prepare() async {
        do {
            try await ensureZoneAndSubscription()
            try await reconcile()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    func reconcile() async throws {
        let syncEngine = try configuredSyncEngine()
        try await syncEngine.fetchChanges()
        try await syncEngine.sendChanges()
        lastSyncError = nil
    }

    func errorDescription() -> String? { lastSyncError }

    func save<T: Codable>(_ value: T, type: String, id: UUID) async throws {
        let record = try AutoRunRecordCodec.record(for: value, type: type, id: id, zoneID: zoneID)
        _ = try await configuredDatabase().save(record)
    }

    func delete(type: String, id: UUID) async throws {
        try await configuredDatabase().deleteRecord(withID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID))
    }

    func fetchAll<T: Codable>(_ type: String, as valueType: T.Type) async throws -> [T] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        let records = try await configuredDatabase().records(matching: query, inZoneWith: zoneID)
        return try records.matchResults.map { try AutoRunRecordCodec.value(from: try $0.1.get(), as: valueType) }
    }

    func fetch<T: Codable>(_ id: UUID, type: String, as valueType: T.Type) async throws -> T? {
        do {
            let record = try await configuredDatabase().record(for: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID))
            return try AutoRunRecordCodec.value(from: record, as: valueType)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func upsertDevice(_ device: AutoRunDevice) async throws { try await save(device, type: AutoRunRecordType.device, id: device.id) }
    func upsertAutomation(_ automation: AutomationDefinition) async throws { try await save(automation, type: AutoRunRecordType.automation, id: automation.id) }
    func upsertSession(_ session: AutomationSession) async throws { try await save(session, type: AutoRunRecordType.session, id: session.id) }
    func append(_ event: SessionEvent) async throws { try await save(event, type: AutoRunRecordType.event, id: event.id) }
    func save(_ request: InteractionRequest) async throws { try await save(request, type: AutoRunRecordType.request, id: request.id) }
    func save(_ response: InteractionResponse) async throws { try await save(response, type: AutoRunRecordType.response, id: response.id) }
    func save(_ result: CommandResult) async throws { try await save(result, type: AutoRunRecordType.result, id: result.id) }
    func save(_ message: DeviceMessage) async throws { try await save(message, type: AutoRunRecordType.message, id: message.id) }
    func save(_ entry: AuditEntry) async throws { try await save(entry, type: AutoRunRecordType.audit, id: entry.id) }

    func createCommand(_ command: RemoteCommand) async throws {
        guard let envelope = command.authenticatedEnvelope else {
            throw CloudKitRepositoryError.invalidCommand("Device pairing is required before creating remote commands.")
        }
        guard envelope.header.commandID == command.id,
              envelope.header.sourceDeviceID == command.sourceDeviceID,
              envelope.header.targetDeviceID == command.targetDeviceID,
              envelope.header.operationID == command.automationID,
              envelope.header.capability == .automationExecute,
              command.parameters.isEmpty else {
            throw CloudKitRepositoryError.invalidCommand("The command envelope does not match its CloudKit record.")
        }
        if try await fetch(command.id, type: AutoRunRecordType.command, as: RemoteCommand.self) != nil {
            throw CloudKitRepositoryError.duplicateCommand
        }
        try await save(command, type: AutoRunRecordType.command, id: command.id)
    }

    func commands() async throws -> [RemoteCommand] { try await fetchAll(AutoRunRecordType.command, as: RemoteCommand.self) }
    func automations() async throws -> [AutomationDefinition] { try await fetchAll(AutoRunRecordType.automation, as: AutomationDefinition.self) }
    func devices() async throws -> [AutoRunDevice] { try await fetchAll(AutoRunRecordType.device, as: AutoRunDevice.self) }
    func sessions() async throws -> [AutomationSession] { try await fetchAll(AutoRunRecordType.session, as: AutomationSession.self) }
    func events() async throws -> [SessionEvent] { try await fetchAll(AutoRunRecordType.event, as: SessionEvent.self) }
    func messages() async throws -> [DeviceMessage] { try await fetchAll(AutoRunRecordType.message, as: DeviceMessage.self) }

    private func ensureZoneAndSubscription() async throws {
        let database = try configuredDatabase()
        do {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        } catch let error as CKError where error.code == .serverRejectedRequest || error.code == .zoneNotFound {
            // The custom zone already exists, or the account is temporarily not ready.
            if error.code == .zoneNotFound { throw error }
        }

        let subscriptionID = "AutoRun.zone.subscription"
        do {
            _ = try await database.subscription(for: subscriptionID)
        } catch let error as CKError where error.code == .unknownItem {
            let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try await database.save(subscription)
        }
    }

    private func configuredDatabase() throws -> CKDatabase {
        if let database { return database }
        guard !ProcessInfo.processInfo.isRunningUnderXCTest else {
            throw CloudKitRepositoryError.unavailable
        }

        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        self.database = database

        let stateData = UserDefaults.standard.data(forKey: "AutoRun.cloudKitSyncState")
        let stateSerialization = stateData.flatMap { try? AutoRunJSON.decoder.decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let delegate = AutoRunSyncDelegate { event in
            if case .stateUpdate(let update) = event,
               let data = try? AutoRunJSON.encoder.encode(update.stateSerialization) {
                UserDefaults.standard.set(data, forKey: "AutoRun.cloudKitSyncState")
            }
        }
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateSerialization,
            delegate: delegate
        )
        syncEngine = CKSyncEngine(configuration)
        return database
    }

    private func configuredSyncEngine() throws -> CKSyncEngine {
        _ = try configuredDatabase()
        guard let syncEngine else { throw CloudKitRepositoryError.unavailable }
        return syncEngine
    }
}
#endif

private extension ProcessInfo {
    var isRunningUnderXCTest: Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCInjectBundle"] != nil
    }
}
