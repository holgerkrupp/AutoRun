#if os(macOS)
//
//  TimerView.swift
//  AutoRun
//
//  Created by Holger Krupp on 15.12.24.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TimerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State var timer: TimerItem
    @State private var importing = false
    @State private var originalConfiguration: Configuration?
    @State private var wasEnabled = false

    var body: some View {
        ZStack {
            AutoRunLiquidGlassBackground()

            ScrollView {
                GlassEffectContainer(spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerSection
                        launchSection
                        scheduleSection
                        remoteSection
                    }
                }
                .padding(22)
                .backgroundExtensionEffect()
            }
            .scrollIndicators(.hidden)
        }
        .frame(minWidth: 520, minHeight: 560)
        .onAppear {
            timer.synchronizeLaunchConfiguration()
            originalConfiguration = Configuration(timer: timer)
            wasEnabled = timer.isEnabled
        }
        .onDisappear {
            if timer.isNewlyCreated, timer.isPristine {
                timer.delete()
            } else {
                timer.isNewlyCreated = false
                try? modelContext.save()
                if wasEnabled, originalConfiguration != Configuration(timer: timer) {
                    timer.restartIfNeeded()
                }
                Task { @MainActor in
                    await RemoteAutomationCatalog.publish(timers: [timer])
                }
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.application]
        ) { result in
            switch result {
            case .success(let file):
                do {
                    try timer.storeAppURL(file.absoluteURL)
                } catch {
                    timer.lastErrorMessage = error.localizedDescription
                }
            case .failure(let error):
                timer.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Edit Timer")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
            }

            TextField("Set custom name", text: $timer.name.toUnwrapped(defaultValue: ""))
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .help("Set custom name")

            Picker("", selection: $timer.launchType) {
                ForEach(TimerItem.LaunchType.allCases) { option in
                    Text(String(describing: option))
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .autoRunGlassPanel(tint: .cyan)
    }

    @ViewBuilder
    private var launchSection: some View {
        switch timer.launchType {
        case .app:
            VStack(alignment: .leading, spacing: 14) {
                Text("App")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button {
                        importing = true
                    } label: {
                        Label("Select App", systemImage: "app.badge.plus")
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)

                    if let appURL = timer.appURL {
                        Text(appURL.lastPathComponent)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    } else {
                        Text("No app selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(timer.appURL?.path(percentEncoded: false) ?? "Choose a macOS app bundle to launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let error = timer.launchConfigurationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .autoRunGlassPanel(tint: .mint)

        case .script:
            VStack(alignment: .leading, spacing: 14) {
                Text("Shell Script")
                    .font(.headline)

                HighlightrTextView(text: $timer.launchValue, language: "bash")
                    .frame(minHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                if let error = timer.launchConfigurationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .autoRunGlassPanel(tint: .indigo)
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Schedule")
                .font(.headline)

            TimerInputView(totalSeconds: $timer.interval)

            HStack(spacing: 8) {
                Text("Quick set")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach([300, 900, 3600], id: \.self) { seconds in
                    Button(presetTitle(for: seconds)) {
                        timer.interval = TimeInterval(seconds)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }

            Toggle(isOn: $timer.doesRepeat) {
                Label((timer.doesRepeat ? "Repeats automatically" : "Runs once"), systemImage: (timer.doesRepeat ? "repeat.circle.fill" : "timer"))
            }
            .toggleStyle(.switch)

            if timer.interval <= 0 {
                Label("Set a duration greater than zero.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .autoRunGlassPanel(tint: .orange)
    }

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Remote Access", systemImage: "iphone.and.arrow.forward")
                .font(.headline)

            Toggle("Allow companion runs", isOn: $timer.allowsRemoteExecution)
                .toggleStyle(.switch)

            Toggle("Show as a Watch quick action", isOn: $timer.watchEligible)
                .toggleStyle(.switch)
                .disabled(!timer.allowsRemoteExecution)

            Text(timer.allowsRemoteExecution
                 ? "Only safe metadata is shared. The script source and local file path stay on this Mac."
                 : "Remote execution is off by default for existing timers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .autoRunGlassPanel(tint: .purple)
    }

    private func presetTitle(for seconds: Int) -> String {
        switch seconds {
        case 300: "5 min"
        case 900: "15 min"
        default: "1 hour"
        }
    }

    private struct Configuration: Equatable {
        let launchType: TimerItem.LaunchType
        let launchValue: String
        let fileName: URL?
        let interval: TimeInterval
        let doesRepeat: Bool

        init(timer: TimerItem) {
            launchType = timer.launchType
            launchValue = timer.launchValue
            fileName = timer.fileName
            interval = timer.interval
            doesRepeat = timer.doesRepeat
        }
    }
}
#Preview {
    let timer = TimerItem()
    TimerEditView(timer: timer)
}

extension Binding {
    func toUnwrapped<T>(defaultValue: T) -> Binding<T> where Value == Optional<T>  {
        Binding<T>(get: { self.wrappedValue ?? defaultValue }, set: { self.wrappedValue = $0 })
    }
}
#endif
