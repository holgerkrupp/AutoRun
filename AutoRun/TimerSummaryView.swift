//
//  TimerView.swift
//  AutoRun
//
//  Created by Holger Krupp on 15.12.24.
//

import SwiftUI
import UniformTypeIdentifiers
struct TimerSummaryView: View {
    @State var timer: TimerItem
    @State var isActive: Bool
    

    
    var body: some View {
        
        TimerDetailView(timer: timer, isActive: $isActive)
    }
}
    
    struct TimerDetailView: View {
        @Environment(\.openWindow) var openWindow
        @ObservedObject var timer:TimerItem
        @Binding var isActive:Bool
        @State private var maxWidth: CGFloat = .zero
 
        var body: some View {
            VStack{
                
                Toggle(isOn: $isActive) {
                    Label(($isActive.wrappedValue ? "active" : "inactive"), systemImage: ($isActive.wrappedValue ? "figure.run" : "figure.stand"))
                        .foregroundStyle(($isActive.wrappedValue ? .secondary : .primary))
                }
                .toggleStyle(.switch)

                .onChange(of: isActive) { oldValue, newValue in
                    
                    if newValue == false{
                        
                        timer.stopTimer()
                        
                    }else{
                        let start = timer.startTimer()
                        print("Timer Start: \(start)")
                        isActive = start
                    }
                }
                
                /*
                if let icon = timer.fileIcon
                {
                    Image(nsImage: icon)
                }
                if let imagedata = timer.icon{
                    if let icon2 = NSImage(data: imagedata)
                    {
                        Image(nsImage: icon2)
                            .resizable()
                            .frame(width: 100, height: 100)
                    }
                }
                 */
                Text($timer.name.wrappedValue ?? "")
                    .font(.headline)
                switch timer.launchType {
                case .app:
                    Text(URL(string: timer.launchValue)?.lastPathComponent ?? "")
                        .font(.body)
                case .script:
                    Text("running shell script")
                        .font(.body)
                }
               
                    
                if $isActive.wrappedValue == true{
                    if timer.doesRepeat{
                        Text("App is launched every \(timer.durationDescription)")
                    }else{
                        
                    }
                    if let fireDate = timer.nextFireDate{
                        
                        CountdownView(duration:timer.interval, finish: fireDate)
                            .help(
                                Text("Next run: \(fireDate.formatted(date: .abbreviated, time: .standard))")
                            )
                        
                    }else{
                        Text("Fire Date: \(timer.timer?.fireDate.formatted(date: .abbreviated, time: .standard) ?? "unknown")")
                    }
                   

                }else {
                    Text("Timer not running")
                }
                
                
                
                
                HStack{
                    Button("Run now") {
                        try? timer.launch()
                    }
                    Button("Edit") {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        openWindow(value: timer)
                    }
                    Button(role: .destructive) {
                        withAnimation{
                            timer.delete()
                        }
                        
                        
                    } label: {
                        Image(systemName: "trash")
                            .background(rectReader($maxWidth))
                            .frame(minWidth: maxWidth)
                    }
                    .help("Remove this timer")

                    
                    
                }
            }
            .onReceive(timer.$isActive) { active in
               
                isActive = active
            }
        }
        
        private func rectReader(_ binding: Binding<CGFloat>) -> some View {
            return GeometryReader { gp -> Color in
                DispatchQueue.main.async {
                    binding.wrappedValue = max(binding.wrappedValue, gp.frame(in: .local).width)
                }
                return Color.clear
            }
        }
    }
    
    

    


#Preview {
    let timer = TimerItem()
    TimerEditView(timer: timer)
}



