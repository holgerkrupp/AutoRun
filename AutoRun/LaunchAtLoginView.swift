#if os(macOS)
//
//  LaunchAtLoginView.swift
//  AutoRun
//
//  Created by Holger Krupp on 17.08.23.
//

import ServiceManagement
import SwiftUI

struct LaunchAtLoginView: View {
    @State private var status = SMAppService.mainApp.status
    @State private var isApplyingChange = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: launchAtLoginBinding) {
                Label("Launch at Login", systemImage: "power.circle")
            }
            .toggleStyle(.switch)

            if status == .requiresApproval {
                Button("Allow in System Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .font(.caption)
                .buttonStyle(.link)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .onAppear {
            status = SMAppService.mainApp.status
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            status == .enabled
        } set: { shouldEnable in
            updateLaunchAtLogin(shouldEnable)
        }
    }

    private func updateLaunchAtLogin(_ shouldEnable: Bool) {
        guard isApplyingChange == false else { return }
        isApplyingChange = true
        defer {
            status = SMAppService.mainApp.status
            isApplyingChange = false
        }

        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#Preview {
    LaunchAtLoginView()
}
#endif
