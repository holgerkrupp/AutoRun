//
//  LaunchAgentScheduler.swift
//  AutoRun
//
//  Created by OpenAI on 21.07.26.
//

import Foundation
import Darwin

/// Installs per-user LaunchAgent jobs so repeating timers can run even when
/// AutoRun is not actively counting down in the foreground.
enum LaunchAgentScheduler {
    enum SchedulerError: Error {
        case invalidInterval
        case invalidLaunchValue
        case unsupportedOneShotTimer
        case unsupportedHomeDirectory
    }

    static func isSupported(timer: TimerItem) -> Bool {
        timer.doesRepeat && timer.interval >= 1
    }

    static func install(timer: TimerItem) throws {
        guard isSupported(timer: timer) else { throw SchedulerError.unsupportedOneShotTimer }
        guard timer.interval >= 1 else { throw SchedulerError.invalidInterval }

        let launchAgentsDirectory = try launchAgentsDirectory()
        try FileManager.default.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let plistURL = plistURL(for: timer)
        let plist = try propertyList(for: timer)
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)

        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", plistURL.path], allowFailure: true)
        try runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", plistURL.path])
        try runLaunchctl(arguments: ["enable", "gui/\(getuid())/\(label(for: timer))"])
    }

    static func uninstall(timer: TimerItem) {
        let plistURL = plistURL(for: timer)
        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", plistURL.path], allowFailure: true)
        try? FileManager.default.removeItem(at: plistURL)
    }

    static func label(for timer: TimerItem) -> String {
        let identifier = timer.persistentModelID.id.description
            .replacingOccurrences(of: "[^A-Za-z0-9.-]", with: "-", options: .regularExpression)
        return "de.holgerkrupp.AutoRun.timer.\(identifier)"
    }

    private static func propertyList(for timer: TimerItem) throws -> [String: Any] {
        let arguments = try programArguments(for: timer)
        return [
            "Label": label(for: timer),
            "ProgramArguments": arguments,
            "StartInterval": Int(timer.interval.rounded()),
            "RunAtLoad": false,
            "StandardOutPath": logURL(for: timer, suffix: "out").path,
            "StandardErrorPath": logURL(for: timer, suffix: "err").path
        ]
    }

    private static func programArguments(for timer: TimerItem) throws -> [String] {
        switch timer.launchType {
        case .app:
            guard let url = URL(string: timer.launchValue) else { throw SchedulerError.invalidLaunchValue }
            return ["/usr/bin/open", url.path]
        case .script:
            guard timer.launchValue.isEmpty == false else { throw SchedulerError.invalidLaunchValue }
            return ["/bin/zsh", "-c", timer.launchValue]
        }
    }

    private static func launchAgentsDirectory() throws -> URL {
        guard let home = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw SchedulerError.unsupportedHomeDirectory
        }
        return home.appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private static func plistURL(for timer: TimerItem) -> URL {
        (try? launchAgentsDirectory())?.appendingPathComponent("\(label(for: timer)).plist")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(label(for: timer)).plist")
    }

    private static func logURL(for timer: TimerItem, suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(label(for: timer)).\(suffix).log")
    }

    @discardableResult
    private static func runLaunchctl(arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 && allowFailure == false {
            throw NSError(
                domain: "LaunchAgentScheduler",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? outputText : errorText]
            )
        }
        return outputText
    }
}
