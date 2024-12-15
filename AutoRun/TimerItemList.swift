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
    var body: some View {
        Text("Auto Run - Development")
            .font(.headline)
        Button("Create new Timer") {
            createNewTimer()
        }.keyboardShortcut("n")
        .padding()
        Divider()
        List{
            ForEach(timers.sorted(by: {$0.order ?? 0 < $1.order ?? 0})) { timer in
                TimerSummaryView(timer: timer, isActive: timer.timer?.isValid ?? false)
            }
            .onMove( perform: move )
        }
        if timers.count == 0{
            Text("no Timers saved")
        }
        
        
        
    }
    
    
    private func createNewTimer(){
        let newTimer = TimerItem()
        modelContext.insert(newTimer)
        openWindow(value: newTimer)

    }
    
    private func move( from source: IndexSet, to destination: Int)
    {
        // Make an array of items from fetched results
        var revisedItems: [ TimerItem  ] = timers.map{ $0 }
        
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
    }
    
}

#Preview {
    TimerItemList()
}
