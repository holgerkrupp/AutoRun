//
//  AutoRunApp.swift
//  AutoRun
//
//  Created by Holger Krupp on 15.12.24.
//

import SwiftUI
import SwiftData

@main
struct AutoRunApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TimerItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    @Query private var timers: [TimerItem]

    var body: some Scene {
        MenuBarExtra{

            TimerItemList()
                .modelContainer(sharedModelContainer)

            
            Divider()
            HStack{
                LaunchAtLoginView()
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                }.keyboardShortcut("q")
            }
            
            
            .padding()
            
            
            
        } label: {
            Image(systemName: "figure.run")
            
            /*
            if timers.contains(where: { timer in
                timer.timer?.isValid == true
            }){
                Image(systemName: "figure.run")
            }else{
                Image(systemName: "figure.stand")
            }
            */
        } .menuBarExtraStyle(.window)
        
        
        WindowGroup("Edit Timer", for: TimerItem.self) { $timer in
            TimerEditView(timer: timer)
                .modelContainer(sharedModelContainer)
            
        } defaultValue: {
                TimerItem()// A new message that your model stores.
            }

        }
    }

