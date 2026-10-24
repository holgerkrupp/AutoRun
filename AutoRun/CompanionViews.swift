import SwiftUI

#if os(iOS)
import UIKit
#endif

enum DeviceIdentity {
    static var id: UUID {
        if let value = UserDefaults.standard.string(forKey: "AutoRun.deviceID"), let id = UUID(uuidString: value) {
            try? DeviceKeychain.storeDeviceID(id)
            return id
        }
        if let keychainID = try? DeviceKeychain.deviceID() {
            UserDefaults.standard.set(keychainID.uuidString, forKey: "AutoRun.deviceID")
            return keychainID
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: "AutoRun.deviceID")
        return id
    }

    static var signingPublicKey: Data? {
        try? DeviceKeychain.signingPrivateKey().publicKey.x963Representation
    }

    static var agreementPublicKey: Data? {
        try? DeviceKeychain.agreementPrivateKey().publicKey.x963Representation
    }

    static var displayName: String {
        #if os(macOS)
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        return UIDevice.current.name
        #endif
    }

    static var platform: AutoRunPlatform {
        #if os(macOS)
        return .macOS
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPadOS : .iOS
        #else
        return .watchOS
        #endif
    }
}

@MainActor
final class CompanionStore: ObservableObject {
    @Published private(set) var devices: [AutoRunDevice] = []
    @Published private(set) var automations: [AutomationDefinition] = []
    @Published private(set) var sessions: [AutomationSession] = []
    @Published private(set) var events: [SessionEvent] = []
    @Published private(set) var messages: [DeviceMessage] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedDeviceID: UUID?

    let deviceID = DeviceIdentity.id
    private let repository = CloudKitRepository.shared

    func start() async {
        await repository.prepare()
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let device = AutoRunDevice(
                id: deviceID,
                displayName: DeviceIdentity.displayName,
                platform: DeviceIdentity.platform,
                capabilities: [.sendRemoteCommands, .interactiveSessions],
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                signingPublicKey: DeviceIdentity.signingPublicKey,
                agreementPublicKey: DeviceIdentity.agreementPublicKey
            )
            try await repository.upsertDevice(device)
            async let loadedDevices = repository.devices()
            async let loadedAutomations = repository.automations()
            async let loadedSessions = repository.sessions()
            async let loadedEvents = repository.events()
            async let loadedMessages = repository.messages()
            devices = try await loadedDevices.filter { !$0.isRetired }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            automations = try await loadedAutomations.filter { $0.enabled && $0.allowsRemoteExecution }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            sessions = try await loadedSessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
            events = try await loadedEvents.sorted { $0.createdAt > $1.createdAt }
            messages = try await loadedMessages.sorted { $0.createdAt > $1.createdAt }
            if selectedDeviceID == nil { selectedDeviceID = devices.first?.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func run(_ automation: AutomationDefinition, parameters: [String: AutoRunJSONValue] = [:]) async {
        _ = automation
        _ = parameters
        errorMessage = String(localized: "Secure device pairing is not available in this build.")
    }

    func canRun(_ automation: AutomationDefinition) -> Bool {
        _ = automation
        return false
    }

    func cancel(_ session: AutomationSession) async {
        var updated = session
        updated.cancellationRequested = true
        updated.state = .cancelling
        updated.lastActivityAt = .now
        do {
            try await repository.upsertSession(updated)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CompanionRootView: View {
    @StateObject private var store = CompanionStore()
    @State private var selectedAutomationID: UUID?
    @State private var selectedSessionID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedDeviceID) {
                Section("Macs") {
                    ForEach(store.devices) { device in
                        Label {
                            VStack(alignment: .leading) {
                                Text(device.displayName)
                                Text(device.lastSeen, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: device.platform == .macOS ? "desktopcomputer" : "laptopcomputer")
                        }
                        .tag(device.id)
                    }
                }
                Section("Automations") {
                    ForEach(filteredAutomations) { automation in
                        Label(automation.name, systemImage: automation.iconSystemName)
                            .tag(automation.id)
                            .contextMenu {
                                Button("Run Now") { Task { await store.run(automation) } }
                                    .disabled(!store.canRun(automation))
                            }
                    }
                }
                Section("Recent Sessions") {
                    ForEach(store.sessions.prefix(12)) { session in
                        Button {
                            selectedSessionID = session.id
                        } label: {
                            Label(session.state.rawValue.localizedCapitalized, systemImage: sessionSymbol(session.state))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("AutoRun")
            .refreshable { await store.reload() }
        } detail: {
            Group {
                if let selectedSessionID, let session = store.sessions.first(where: { $0.id == selectedSessionID }) {
                    SessionDetailView(session: session, store: store)
                } else if let selectedAutomationID, let automation = store.automations.first(where: { $0.id == selectedAutomationID }) {
                    AutomationDetailView(automation: automation, store: store)
                } else {
                    ContentUnavailableView("Choose an automation", systemImage: "bolt.horizontal.circle", description: Text("Select a Mac and a remotely enabled automation."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await store.start() }
        .onReceive(NotificationCenter.default.publisher(for: .autoRunRemoteDataDidChange)) { _ in
            Task { await store.reload() }
        }
        .onChange(of: store.selectedDeviceID) { _, _ in selectedAutomationID = nil }
        .overlay(alignment: .bottom) {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding()
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    private var filteredAutomations: [AutomationDefinition] {
        guard let selectedDeviceID = store.selectedDeviceID else { return [] }
        return store.automations.filter { $0.targetDeviceID == selectedDeviceID }
    }

    private func sessionSymbol(_ state: AutomationSessionState) -> String {
        switch state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed, .rejected, .expired: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .running, .starting, .waitingForInput, .cancelling: return "progress.indicator"
        case .queued: return "clock"
        }
    }
}

private struct AutomationDetailView: View {
    let automation: AutomationDefinition
    @ObservedObject var store: CompanionStore
    @State private var values: [String: AutoRunJSONValue] = [:]

    var body: some View {
        Form {
            Section {
                Label(automation.name, systemImage: automation.iconSystemName)
                    .font(.title2.weight(.semibold))
                Text(automation.kind == .application ? "Launches an approved Mac application." : "Runs an approved script stored on the Mac.")
                    .foregroundStyle(.secondary)
            }
            if !automation.parameters.isEmpty {
                Section("Configuration") {
                    ForEach(automation.parameters) { parameter in
                        ParameterField(definition: parameter, value: binding(for: parameter))
                    }
                }
            }
            Section {
                if !store.canRun(automation) {
                    Label("Secure remote pairing is not available in this build.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await store.run(automation, parameters: values) }
                } label: {
                    Label("Run on Mac", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canRun(automation))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(automation.name)
        .onAppear {
            values = Dictionary(uniqueKeysWithValues: automation.parameters.compactMap { parameter in
                parameter.defaultValue.map { (parameter.id, $0) }
            })
        }
    }

    private func binding(for parameter: AutomationParameterDefinition) -> Binding<AutoRunJSONValue> {
        Binding(
            get: { values[parameter.id] ?? parameter.defaultValue ?? .string("") },
            set: { values[parameter.id] = $0 }
        )
    }
}

private struct ParameterField: View {
    let definition: AutomationParameterDefinition
    @Binding var value: AutoRunJSONValue

    var body: some View {
        switch definition.type {
        case .boolean:
            Toggle(definition.title, isOn: boolBinding)
        case .integer, .decimal:
            TextField(definition.title, text: numberBinding)
        case .singleChoice:
            Picker(definition.title, selection: choiceBinding) {
                ForEach(definition.choices) { choice in Text(choice.label).tag(choice.id) }
            }
        case .multipleChoice:
            TextField(definition.title, text: textBinding)
        case .secureText:
            SecureField(definition.title, text: textBinding)
        case .dateTime, .localResource, .string:
            TextField(definition.title, text: textBinding)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { if case .string(let text) = value { return text }; return "" },
            set: { value = .string($0) }
        )
    }

    private var numberBinding: Binding<String> {
        Binding(
            get: { if case .number(let number) = value { return String(number) }; return "" },
            set: { value = .number(Double($0) ?? 0) }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { if case .boolean(let boolean) = value { return boolean }; return false },
            set: { value = .boolean($0) }
        )
    }

    private var choiceBinding: Binding<String> {
        Binding(
            get: { if case .string(let choice) = value { return choice }; return definition.choices.first?.id ?? "" },
            set: { value = .string($0) }
        )
    }
}

private struct SessionDetailView: View {
    let session: AutomationSession
    @ObservedObject var store: CompanionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(session.state.rawValue.localizedCapitalized, systemImage: "bolt.horizontal.circle.fill")
                    .font(.title2.weight(.semibold))
                Text("Last update (session.lastActivityAt, style: .relative)")
                    .foregroundStyle(.secondary)
                ForEach(store.events.filter { $0.sessionID == session.id }.sorted { $0.sequence < $1.sequence }) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.kind.rawValue.localizedCapitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let text = event.text { Text(text).textSelection(.enabled) }
                        if let progress = event.progress { ProgressView(value: progress) }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                if [.queued, .starting, .running, .waitingForInput].contains(session.state) {
                    Button("Cancel", role: .destructive) { Task { await store.cancel(session) } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Session")
    }
}
