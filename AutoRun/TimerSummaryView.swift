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
        
        TimerDetailView(timer: $timer, isActive: $isActive)
    }
}
    
    struct TimerDetailView: View {
        @Environment(\.openWindow) var openWindow
        @Binding var timer:TimerItem
        @Binding var isActive:Bool
        @State private var maxWidth: CGFloat = .zero
 
        var body: some View {
            VStack{
                
                Toggle(isOn: $isActive) {
                    Label(($isActive.wrappedValue ? "active" : "inactive"), systemImage: ($isActive.wrappedValue ? "figure.run" : "figure.stand"))
                        .foregroundStyle(($isActive.wrappedValue ? .secondary : .primary))
                }
                .toggleStyle(.switch)
                .onAppear(){
                    Task{
                        print("Timer isValid \(timer.timer?.isValid.description ?? "nil")")
                        print("View isActive \($isActive.wrappedValue.description)")
                        
                    }
                }
                .onChange(of: isActive) { oldValue, newValue in
                    if newValue == false{
                        
                        timer.stopTimer()
                        
                    }else{
                        let start = timer.startTimer()
                        print("Timer Start: \(start)")
                        isActive = start
                    }
                }
                
                if let icon = timer.fileIcon
                {
                    Image(nsImage: icon)
                }
                Text($timer.name.wrappedValue ?? "")
                    .font(.headline)
                Text(timer.fileName?.lastPathComponent ?? "no app selected")
                    .font(.body)
                if $isActive.wrappedValue == true{
                    if timer.doesRepeat{
                        Text("App is launched every \(timer.durationDescription)")
                    }else{
                        
                    }
                    if let fireDate = timer.timer?.fireDate, fireDate > Date() {
                        
                        CountdownView(finish: fireDate )
                            .help(
                                Text("Next run: \(fireDate.formatted(date: .abbreviated, time: .standard))")
                            )
                        
                    }else{
                        Text("Fire Date: \(timer.timer?.fireDate.formatted(date: .abbreviated, time: .standard) ?? "unknown")")
                    }
                   

                }else {
                    Text("Timer invalid")
                }
                HStack{
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



