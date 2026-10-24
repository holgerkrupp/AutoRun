import SwiftUI

@main
struct AutoRunWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}

@MainActor
private final class WatchStore: ObservableObject {
    @Published var devices: [AutoRunDevice] = []
    @Published var automations: [AutomationDefinition] = []
    @Published var sessions: [AutomationSession] = []
    @Published var selectedDeviceID: UUID?
    @Published var errorMessage: String?

    private let repository = CloudKitRepository.shared
    private let deviceID: UUID = {
        if let raw = UserDefaults.standard.string(forKey: "AutoRun.deviceID"), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: "AutoRun.deviceID")
        return id
    }()

    func load() async {
        do {
            await repository.prepare()
            devices = try await repository.devices().filter { !$0.isRetired && $0.platform == .macOS }
            automations = try await repository.automations().filter { $0.canRunOnWatch }
            sessions = try await repository.sessions().sorted { $0.lastActivityAt > $1.lastActivityAt }
            selectedDeviceID = selectedDeviceID ?? devices.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func run(_ automation: AutomationDefinition) async {
        guard let target = devices.first(where: { $0.id == automation.targetDeviceID }), let source = devices.first(where: { $0.id == deviceID }) else { return }
        let command = RemoteCommand(automationID: automation.id, sourceDeviceID: source.id, targetDeviceID: target.id)
        do {
            try await repository.createCommand(command)
            try await repository.upsertSession(AutomationSession(command: command))
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WatchHomeView: View {
    @StateObject private var store = WatchStore()

    var body: some View {
        NavigationStack {
            List {
                Section("Target Mac") {
                    ForEach(store.devices) { device in
                        Button {
                            store.selectedDeviceID = device.id
                        } label: {
                            Label(device.displayName, systemImage: store.selectedDeviceID == device.id ? "checkmark.circle.fill" : "desktopcomputer")
                        }
                    }
                }
                Section("Quick Actions") {
                    ForEach(filteredAutomations) { automation in
                        Button {
                            Task { await store.run(automation) }
                        } label: {
                            Label(automation.name, systemImage: automation.iconSystemName)
                        }
                        .disabled(!automation.canRunOnWatch)
                    }
                }
                Section("Recent") {
                    ForEach(store.sessions.prefix(5)) { session in
                        Label(session.state.rawValue.localizedCapitalized, systemImage: symbol(for: session.state))
                    }
                }
            }
            .navigationTitle("AutoRun")
            .task { await store.load() }
            .refreshable { await store.load() }
            .alert("AutoRun", isPresented: errorBinding) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private var filteredAutomations: [AutomationDefinition] {
        guard let target = store.selectedDeviceID else { return [] }
        return store.automations.filter { $0.targetDeviceID == target }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }

    private func symbol(for state: AutomationSessionState) -> String {
        switch state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed, .rejected, .expired: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        default: return "clock"
        }
    }
}
