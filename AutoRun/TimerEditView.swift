//
//  TimerView.swift
//  AutoRun
//
//  Created by Holger Krupp on 15.12.24.
//

import SwiftUI
import UniformTypeIdentifiers
struct TimerEditView: View {
    @State private var maxWidth: CGFloat = .zero
    @State var timer: TimerItem
    @State private var importing = false{
        didSet{
            print("importing changed to \(self)")
        }
        
    }

    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0
    

    
    var body: some View {
        VStack{
         
                TextField("Set custom name" , text: $timer.name.toUnwrapped(defaultValue: ""))
                    .textFieldStyle(.roundedBorder)
                    .help("Set custom name" )
            HStack{
                Button("Select App") {
                    importing = true
                    
                }
                Text(timer.fileName?.lastPathComponent ?? "no app selected")
            }
            HStack{
                TimerInputView(totalSeconds: $timer.interval)
                Toggle(isOn: $timer.doesRepeat) {
                    Label((timer.doesRepeat ? "repeat" : "fire once"), systemImage: (timer.doesRepeat ? "repeat.circle" : "1.circle"))
                }
                .toggleStyle(.switch)
            }
                Text("Timer duration: \(timer.interval.description)")
            Text(timer.durationDescription)
            

        }
        .padding()
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.application]
        ) { result in
            switch result {
            case .success(let file):
                print(file.absoluteString)
                timer.fileName = file.absoluteURL
            
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
    
    private func updateTime(){
        timer.interval = Double(seconds + minutes * 60 + hours * 60 * 60)
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


extension Binding {
    func toUnwrapped<T>(defaultValue: T) -> Binding<T> where Value == Optional<T>  {
        Binding<T>(get: { self.wrappedValue ?? defaultValue }, set: { self.wrappedValue = $0 })
    }
}


