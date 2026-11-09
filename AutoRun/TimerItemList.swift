#if os(macOS)
//
//  TimerItemList.swift
//  AutoRun
//
//  Created by Holger Krupp on 15.12.24.
//

import SwiftUI
import SwiftData

struct TimerItemList: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) var openWindow

    @Query private var timers: [TimerItem]

    private var sortedTimers: [TimerItem] {
        timers.sorted { lhs, rhs in
            let lhsOrder = lhs.order ?? .max
            let rhsOrder = rhs.order ?? .max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            return (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
        }
    }

    private var activeTimerCount: Int {
        timers.filter(\.isEnabled).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("AutoRun")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("Launch apps and run scripts on a schedule—right from the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    HStack(spacing: 8) {
                        Label("\(sortedTimers.count) timer\(sortedTimers.count == 1 ? "" : "s")", systemImage: "timer")
                        if activeTimerCount > 0 {
                            Label("\(activeTimerCount) active", systemImage: "play.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.clear, in: Capsule())

                    Spacer()

                    Button {
                        createNewTimer()
                    } label: {
                        Label("New Timer", systemImage: "plus")
                    }
                    .keyboardShortcut("n")
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                }
            }
            .autoRunGlassPanel(tint: .cyan)

            if sortedTimers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("No timers yet", systemImage: "clock.badge.exclamationmark")
                        .font(.headline)

                    Text("Create your first timer to launch an app or run a script on schedule.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .autoRunGlassPanel(tint: .mint)
            } else {
                List{
                    ForEach(sortedTimers) { timer in
                        TimerSummaryView(timer: timer)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove( perform: move )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220, maxHeight: 520)
            }
        }
    }
    
    
    private func createNewTimer(){
        let newTimer = TimerItem()
        newTimer.isNewlyCreated = true
        newTimer.order = (timers.compactMap(\.order).max() ?? -1) + 1
        modelContext.insert(newTimer)
        try? modelContext.save()
        openWindow(value: newTimer)

    }
    
    private func move( from source: IndexSet, to destination: Int)
    {
        // Make an array of items from fetched results
        var revisedItems = sortedTimers
        
        // change the order of the items in the array
        revisedItems.move(fromOffsets: source, toOffset: destination )
        
        // update the userOrder attribute in revisedItems to
        // persist the new order. This is done in reverse order
        // to minimize changes to the indices.
        for reverseIndex in stride( from: revisedItems.count - 1,
                                    through: 0,
                                    by: -1 )
        {
            revisedItems[ reverseIndex ].order =
            Int( reverseIndex )
        }
        try? modelContext.save()
    }
    
}
#Preview {
    TimerItemList()
}
#endif
