import SwiftUI

#if os(macOS)
import SwiftData
import AppKit

@main
struct AutoRunApp: App {
    @NSApplicationDelegateAdaptor(AutoRunRemoteNotificationDelegate.self) private var appDelegate
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([TimerItem.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            ZStack {
                AutoRunLiquidGlassBackground()
                VStack(spacing: 18) {
                    TimerItemList().modelContainer(sharedModelContainer)
                    HStack(spacing: 12) {
                        LaunchAtLoginView()
                        Spacer()
                        Button {
                            NSApplication.shared.terminate(nil)
                        } label: {
                            Label("Quit", systemImage: "power")
                        }
                        .keyboardShortcut("q")
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    }
                    .autoRunGlassPanel(tint: .indigo)
                }
                .padding(18)
                .frame(width: 460)
                .backgroundExtensionEffect()
            }
        } label: {
            TimerStatusIcon().modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Edit Timer", for: TimerItem.self) { $timer in
            TimerEditView(timer: timer).modelContainer(sharedModelContainer)
        } defaultValue: {
            TimerItem()
        }

        Settings {
            Text("Remote access is opt-in per timer. Published metadata never contains script source or local paths.")
                .padding()
        }
    }
}

private struct TimerStatusIcon: View {
    @Query private var timers: [TimerItem]

    var body: some View {
        Image(systemName: timers.contains(where: \.isEnabled) ? "figure.run.circle.fill" : "figure.stand")
            .accessibilityLabel(timers.contains(where: \.isEnabled) ? "AutoRun, timers active" : "AutoRun, no active timers")
            .onAppear {
                for timer in timers {
                    timer.synchronizeLaunchConfiguration()
                    timer.resumeIfNeeded()
                }
                Task { @MainActor in
                    await MacRemoteCommandProcessor.shared.reconcile(timers: timers)
                }
            }
            .onChange(of: timers.count) { _, _ in
                Task { @MainActor in
                    await MacRemoteCommandProcessor.shared.reconcile(timers: timers)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .autoRunRemoteDataDidChange)) { _ in
                Task { @MainActor in
                    await MacRemoteCommandProcessor.shared.reconcile(timers: timers)
                }
            }
    }
}
#else

#if os(iOS)
import UIKit
#endif

@main
struct AutoRunApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AutoRunRemoteNotificationDelegate.self) private var appDelegate
    #endif
    var body: some Scene {
        WindowGroup {
            CompanionRootView()
        }
    }
}
#endif
