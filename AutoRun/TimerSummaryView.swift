#if os(macOS)
//
//  TimerSummaryView.swift
//  AutoRun
//
//  Created by Holger Krupp on 15.12.24.
//

import SwiftUI

struct TimerSummaryView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var timer: TimerItem
    @State private var isConfirmingDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                timerIcon

                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        timer.launchType == .app ? "App Timer" : "Script Timer",
                        systemImage: timer.launchType == .app ? "app.connected.to.app.below.fill" : "terminal.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Text(displayName)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .lineLimit(2)

                    Text(secondaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    Label(statusTitle, systemImage: statusSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .glassEffect(.clear, in: Capsule())

                    Toggle("Active", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .help(timer.isActive ? "Stop timer" : "Start timer")
                        .accessibilityLabel("Timer active")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(scheduleDescription, systemImage: timer.doesRepeat ? "repeat" : "timer")
                    .font(.subheadline.weight(.medium))

                if timer.isActive, let fireDate = timer.nextFireDate {
                    CountdownView(duration: timer.interval, finish: fireDate)
                        .help(
                            Text("Next run: \(fireDate.formatted(date: .abbreviated, time: .standard))")
                        )
                } else {
                    Text(timer.configurationError ?? "Timer not running")
                        .font(.caption)
                        .foregroundStyle(timer.configurationError == nil ? Color.secondary : Color.orange)
                }

                if let error = timer.lastErrorMessage, error != timer.configurationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                } else if let lastRunDate = timer.lastRunDate {
                    Text("Last run \(lastRunDate.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isConfirmingDeletion {
                inlineDeleteConfirmation
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                actionButtons
                    .transition(.opacity)
            }
        }
        .autoRunGlassPanel(tint: accentTint)
        .onAppear {
            timer.synchronizeLaunchConfiguration()
            timer.resumeIfNeeded()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                timer.runNow()
            } label: {
                Label("Run now", systemImage: "bolt.fill")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .disabled(timer.launchConfigurationError != nil)
            .help(timer.launchConfigurationError ?? "Run without changing the timer")

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(value: timer)
            } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                withAnimation(.snappy) {
                    isConfirmingDeletion = true
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .help("Remove this timer")
        }
    }

    private var inlineDeleteConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Delete \(displayName)?", systemImage: "trash.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text("This action cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Cancel") {
                    withAnimation(.snappy) {
                        isConfirmingDeletion = false
                    }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    withAnimation(.snappy) {
                        timer.delete()
                    }
                } label: {
                    Label("Delete Timer", systemImage: "trash.fill")
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(.red)
            }
        }
        .padding(14)
        .glassEffect(
            .clear.tint(.red.opacity(0.12)),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            timer.isEnabled
        } set: { shouldEnable in
            if shouldEnable {
                timer.startTimer()
            } else {
                timer.stopTimer()
            }
        }
    }

    @ViewBuilder
    private var timerIcon: some View {
        if timer.launchType == .app, let fileIcon = timer.fileIcon {
            Image(nsImage: fileIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 42, height: 42)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var displayName: String {
        if let trimmedName = timer.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           trimmedName.isEmpty == false {
            return trimmedName
        }

        switch timer.launchType {
        case .app:
            return timer.appURL?.deletingPathExtension().lastPathComponent ?? "Untitled App Timer"
        case .script:
            return "Script Timer"
        }
    }

    private var secondaryText: String {
        switch timer.launchType {
        case .app:
            return timer.appURL?.path(percentEncoded: false) ?? "Choose an app to launch"
        case .script:
            return "Runs the saved shell script in zsh"
        }
    }

    private var scheduleDescription: String {
        if timer.interval <= 0 {
            return "No schedule set"
        }
        if timer.doesRepeat {
            return "Repeats every \(timer.durationDescription)"
        }
        return "Runs once after \(timer.durationDescription)"
    }

    private var statusTitle: LocalizedStringKey {
        if timer.lastErrorMessage != nil {
            return "Attention"
        }
        return timer.isActive ? "Armed" : "Idle"
    }

    private var statusSymbol: String {
        if timer.lastErrorMessage != nil {
            return "exclamationmark.triangle.fill"
        }
        return timer.isActive ? "checkmark.circle.fill" : "pause.circle.fill"
    }

    private var statusColor: Color {
        if timer.lastErrorMessage != nil {
            return .orange
        }
        return timer.isActive ? .green : .secondary
    }

    private var accentTint: Color {
        timer.launchType == .app ? .cyan : .indigo
    }
}
#Preview {
    let timer = TimerItem()
    TimerSummaryView(timer: timer)
}
#endif
