#if os(macOS)
//
//  Item.swift
//  AutoRun
//
//  Created by Holger Krupp on 15.12.24.
//

import Foundation
import SwiftData
import AppKit



@Model
final class TimerItem: Codable, ObservableObject {
    enum LaunchType:Int, Codable, CaseIterable, Identifiable, CustomStringConvertible {
        var id: Self { self }
        
        var description: String {
            switch self {
            case .app:
                "Launch App"
            case .script:
                "Run Script"
            }
        }
        
        case app, script
    }
    
    enum TimerError: LocalizedError {
        case invalidURL(url: URL?)
        case invalidItem
        case invalidInterval

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return String(localized: "Choose an app before running this timer.")
            case .invalidItem:
                return String(localized: "Enter a shell script before running this timer.")
            case .invalidInterval:
                return String(localized: "Set a duration greater than zero.")
            }
        }
    }
    
    
    var creationDate: Date?
    var name: String?

    var fileName: URL?
    var appBookmark: Data?
    var launchType: LaunchType = LaunchType.app
    var launchValue: String = ""

    /// The user's persisted intent. Runtime timers are recreated when the app launches.
    var isEnabled: Bool = false
    @Transient @Published var isActive: Bool = false
    @Transient @Published var nextFireDate: Date?
    @Transient @Published var lastErrorMessage: String?
    @Transient @Published var lastRunDate: Date?
    @Transient var isNewlyCreated: Bool = false
    var interval: TimeInterval = 0.0
    var doesRepeat: Bool = false
    var order: Int? = 0
    // Preserve the existing system schedule preference and its cadence when
    // restoring a timer after app relaunch. These defaults are migration-safe.
    var isSystemScheduleEnabled: Bool = false
    var systemScheduleStartDate: Date?

    // Remote execution is opt-in for every existing and migrated automation.
    // These fields are local Mac policy; only the safe catalog projection is
    // published to CloudKit.
    var remoteID: UUID = UUID()
    var allowsRemoteExecution: Bool = false
    var watchEligible: Bool = false
    var remoteParametersData: Data?

    var remoteParameters: [AutomationParameterDefinition] {
        get {
            guard let data = remoteParametersData else { return [] }
            return (try? AutoRunJSON.decoder.decode([AutomationParameterDefinition].self, from: data)) ?? []
        }
        set {
            remoteParametersData = try? AutoRunJSON.encoder.encode(newValue)
        }
    }

    var remoteDisplayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return launchType == .app ? (appURL?.deletingPathExtension().lastPathComponent ?? "Untitled App Timer") : "Script Timer"
    }
    
    @Transient var fileIcon: NSImage? {
        if let filePath = appURL?.path {
            return NSWorkspace.shared.icon(forFile: filePath)
        }else{
            return nil
        }
    }
    var icon: Data?
    
    @Transient @Published var timer: Timer?

    @Transient var isSystemScheduled: Bool {
        isSystemScheduleEnabled && isActive && timer == nil && LaunchAgentScheduler.isSupported(timer: self)
    }

    
    @Transient var durationDescription:String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        
        return formatter.string(from: max(interval, 0)) ?? "0 seconds"
    }

    @Transient var appURL: URL? {
        if let appBookmark {
            var isStale = false
            if let bookmarkedURL = try? URL(
                resolvingBookmarkData: appBookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return bookmarkedURL
            }
        }

        if let fileName {
            return fileName
        }

        guard let url = URL(string: launchValue), url.isFileURL else {
            return nil
        }

        return url
    }
    
    init() {
        self.creationDate = Date()
      //  active = false
    }
    
    enum CodingKeys: CodingKey{
        case creationDate, name, active, fileName, appBookmark, fireDate, interval, doesRepeat, order, launchItem, launchType, remoteID, allowsRemoteExecution, watchEligible, remoteParametersData, isSystemScheduleEnabled, systemScheduleStartDate
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(name, forKey: .name)
  //      try container.encode(active, forKey: .active)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(appBookmark, forKey: .appBookmark)
        try container.encode(isEnabled, forKey: .active)
        try container.encode(nextFireDate, forKey: .fireDate)
        try container.encode(interval, forKey: .interval)
        try container.encode(doesRepeat, forKey: .doesRepeat)
        try container.encode(order, forKey: .order)
        
        try container.encode(launchValue, forKey: .launchItem)
        try container.encode(launchType, forKey: .launchType)
        try container.encode(remoteID, forKey: .remoteID)
        try container.encode(allowsRemoteExecution, forKey: .allowsRemoteExecution)
        try container.encode(watchEligible, forKey: .watchEligible)
        try container.encode(remoteParametersData, forKey: .remoteParametersData)
        try container.encode(isSystemScheduleEnabled, forKey: .isSystemScheduleEnabled)
        try container.encode(systemScheduleStartDate, forKey: .systemScheduleStartDate)

    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        launchValue = try container.decodeIfPresent(String.self, forKey: .launchItem) ?? ""
        launchType = try container.decodeIfPresent(LaunchType.self, forKey: .launchType) ?? .app
     //   active = try container.decode(Bool.self, forKey: .active)
        fileName = try container.decodeIfPresent(URL.self, forKey: .fileName)
        appBookmark = try container.decodeIfPresent(Data.self, forKey: .appBookmark)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false
        
        nextFireDate = try container.decodeIfPresent(Date.self, forKey: .fireDate)
        interval = try container.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? 0
        
        doesRepeat = try container.decodeIfPresent(Bool.self, forKey: .doesRepeat) ?? false
        order = try container.decodeIfPresent(Int.self, forKey: .order)
        remoteID = try container.decodeIfPresent(UUID.self, forKey: .remoteID) ?? UUID()
        allowsRemoteExecution = try container.decodeIfPresent(Bool.self, forKey: .allowsRemoteExecution) ?? false
        watchEligible = try container.decodeIfPresent(Bool.self, forKey: .watchEligible) ?? false
        remoteParametersData = try container.decodeIfPresent(Data.self, forKey: .remoteParametersData)
        isSystemScheduleEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSystemScheduleEnabled) ?? false
        systemScheduleStartDate = try container.decodeIfPresent(Date.self, forKey: .systemScheduleStartDate)
    }
    
    func delete(){
        stopTimer()
        if let modelContext {
            modelContext.delete(self)
            try? modelContext.save()
        }
    }
    
    func startStop(){
        if let timer, timer.isValid == true{
            stopTimer()
          
        }else{
            _ = startTimer()
        }
    }
    
    func stopTimer(disable: Bool = true){
        timer?.invalidate()
        timer = nil
        LaunchAgentScheduler.uninstall(timer: self)
        isSystemScheduleEnabled = false
        systemScheduleStartDate = nil
        nextFireDate = nil
        isActive = false
        if disable {
            isEnabled = false
        }
        try? modelContext?.save()
    }

    func synchronizeLaunchConfiguration() {
        guard launchType == .app else { return }

        if launchValue.isEmpty, let fileName {
            launchValue = fileName.absoluteString
        }

        if fileName == nil, let appURL {
            fileName = appURL
        }

        if appBookmark == nil, let fileName {
            try? storeAppURL(fileName)
        }
    }

    func storeAppURL(_ url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        appBookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        fileName = url
        launchValue = url.absoluteString
        lastErrorMessage = nil
    }

    @discardableResult
    func startTimer() -> Bool{
        synchronizeLaunchConfiguration()

        if let configurationError {
            lastErrorMessage = configurationError
            stopTimer()
            return false
        }

        // launchd is available only to builds that can manage a per-user
        // LaunchAgent. Sandboxed Mac App Store builds use the in-app timer.
        if LaunchAgentScheduler.isSupported(timer: self) {
            do {
                try LaunchAgentScheduler.install(timer: self)
                systemScheduleStartDate = .now
                isSystemScheduleEnabled = true
                nextFireDate = nextSystemFireDate()
                isActive = true
                isEnabled = true
                lastErrorMessage = nil
                try? modelContext?.save()
                return true
            } catch {
                isSystemScheduleEnabled = false
                systemScheduleStartDate = nil
                lastErrorMessage = error.localizedDescription
            }
        }

        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, repeats: doesRepeat) { [weak self] _ in
            self?.fireTimer()
        }
        newTimer.tolerance = min(max(interval * 0.05, 0.1), 30)
        RunLoop.main.add(newTimer, forMode: .common)

        timer = newTimer
        nextFireDate = newTimer.fireDate
        isActive = newTimer.isValid
        isEnabled = newTimer.isValid
        lastErrorMessage = nil
        try? modelContext?.save()
        return newTimer.isValid
    }

    func resumeIfNeeded() {
        guard isEnabled, timer?.isValid != true else { return }
        if isSystemScheduleEnabled {
            reconcileSystemScheduleState()
            if isSystemScheduleEnabled { return }
        }
        _ = startTimer()
    }

    func restartIfNeeded() {
        guard isEnabled else { return }
        _ = startTimer()
    }

    func reconcileSystemScheduleState() {
        guard isSystemScheduleEnabled else { return }
        guard LaunchAgentScheduler.isSupported(timer: self), LaunchAgentScheduler.isInstalled(timer: self) else {
            isSystemScheduleEnabled = false
            systemScheduleStartDate = nil
            nextFireDate = nil
            isActive = false
            return
        }
        timer?.invalidate()
        timer = nil
        isActive = true
        nextFireDate = nextSystemFireDate()
    }

    func nextSystemFireDate(after date: Date = .now) -> Date? {
        guard let systemScheduleStartDate, interval > 0 else { return nil }
        let firstFireDate = systemScheduleStartDate.addingTimeInterval(interval)
        guard firstFireDate > date else {
            let elapsedIntervals = floor(date.timeIntervalSince(firstFireDate) / interval) + 1
            return firstFireDate.addingTimeInterval(elapsedIntervals * interval)
        }
        return firstFireDate
    }

    private func fireTimer() {
        do {
            try launch()
            lastRunDate = Date()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        if doesRepeat {
            nextFireDate = timer?.fireDate
        } else {
            stopTimer()
        }
    }
    
    
    func openApp() throws {
        guard let fileName = appURL else { throw TimerError.invalidURL(url: appURL) }
        try openApp(fileName: fileName)

    }
    
    
    func openApp(fileName: URL) throws{
        let didAccess = fileName.startAccessingSecurityScopedResource()
        guard FileManager.default.fileExists(atPath: fileName.path) else {
            if didAccess {
                fileName.stopAccessingSecurityScopedResource()
            }
            throw TimerError.invalidURL(url: fileName)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: fileName,
                                           configuration: configuration,
                                           completionHandler: { [weak self] _, error in
            if didAccess {
                fileName.stopAccessingSecurityScopedResource()
            }
            if let error {
                DispatchQueue.main.async {
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        })
    }
    
    func launch() throws {
        synchronizeLaunchConfiguration()
        
        switch launchType {
        case .app:
            guard let url = appURL else { throw TimerError.invalidURL(url: nil) }
            try openApp(fileName: url)
        case .script:
            guard launchValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw TimerError.invalidItem
            }
            try runScript(script: launchValue)
      
        }
    }
    
    func runScript(script: String) throws{
        let task = Process()

        // AutoRun does not display process output. Sending it to /dev/null avoids a
        // full, unread pipe blocking scripts that produce a lot of output.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.arguments = ["-c", script]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.standardInput = nil
        
        try task.run()
    }

    @discardableResult
    func runNow() -> Bool {
        do {
            try launch()
            lastRunDate = Date()
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    @Transient var configurationError: String? {
        guard interval > 0 else {
            return TimerError.invalidInterval.localizedDescription
        }

        return launchConfigurationError
    }

    @Transient var launchConfigurationError: String? {
        switch launchType {
        case .app:
            guard let appURL else {
                return TimerError.invalidURL(url: appURL).localizedDescription
            }
            let didAccess = appURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    appURL.stopAccessingSecurityScopedResource()
                }
            }
            guard FileManager.default.fileExists(atPath: appURL.path) else {
                return TimerError.invalidURL(url: appURL).localizedDescription
            }
        case .script:
            guard launchValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return TimerError.invalidItem.localizedDescription
            }
        }

        return nil
    }

    @Transient var isPristine: Bool {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty
            && launchValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fileName == nil
            && interval <= 0
    }
    
    func calcProgress() -> Double? {
        if isSystemScheduled {
            guard let nextFireDate, interval > 0 else { return nil }
            return min(max(Date().timeIntervalSince(nextFireDate.addingTimeInterval(-interval)) / interval, 0), 1)
        }
        if timer?.isValid == true, interval > 0 {
            guard (nextFireDate != nil) else {
                return nil
            }

            guard let lastDate = nextFireDate?.addingTimeInterval(-interval) else { return nil }
            let now = Date()
            let elapsedTime = now.timeIntervalSince(lastDate)
            return elapsedTime/interval
        }else{
            return nil
        }
    }
    
    
}
#endif
