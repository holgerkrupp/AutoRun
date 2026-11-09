import Foundation

#if os(iOS)
import UIKit

final class AutoRunRemoteNotificationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit owns push delivery. Registration does not request alert or
        // sound permissions and no APNs provider credentials are embedded.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // CloudKit pushes are wake hints. The repository fetches authoritative
        // changes and remains correct if this callback is coalesced or missed.
        Task {
            do {
                try await CloudKitRepository.shared.reconcile()
                await MainActor.run {
                    NotificationCenter.default.post(name: .autoRunRemoteDataDidChange, object: nil)
                }
                completionHandler(.newData)
            } catch {
                completionHandler(.failed)
            }
        }
    }
}
#elseif os(macOS)
import AppKit

final class AutoRunRemoteNotificationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task {
            try? await CloudKitRepository.shared.reconcile()
            await MainActor.run {
                NotificationCenter.default.post(name: .autoRunRemoteDataDidChange, object: nil)
            }
        }
    }
}
#endif

extension Notification.Name {
    static let autoRunRemoteDataDidChange = Notification.Name("AutoRun.remoteDataDidChange")
}
