#if os(macOS)
//
//  CountdownView.swift
//  AutoRun
//
//  Created by Holger Krupp on 31.12.24.
//

import SwiftUI

struct CountdownView: View {
    let duration: TimeInterval
    let finish: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(finish.timeIntervalSince(context.date), 0)

            HStack(spacing: 12) {
                ProgressView(value: progress(for: remaining))
                    .progressViewStyle(.linear)

                Text(Self.formatter.string(from: remaining) ?? "00:00:00")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(countsDown: true))
                    .frame(minWidth: 66, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Time remaining")
            .accessibilityValue(Self.formatter.string(from: remaining) ?? "")
        }
    }

    private func progress(for remaining: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - (remaining / duration), 0), 1)
    }

    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}
#Preview {
    CountdownView(duration: 500, finish: Date(timeIntervalSinceNow: 100))
}
#endif
