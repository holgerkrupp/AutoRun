//
//  CountdownView.swift
//  AutoRun
//
//  Created by Holger Krupp on 31.12.24.
//

import SwiftUI

struct CountdownView: View {
    
    //@Binding
    var duration:TimeInterval?
    var finish:Date?
    @State var remaining:Double = 0.0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var remainingString:String = ""
    
    var body: some View {
        HStack{
            
            ProgressView(value: max(progress, 0))
                .progressViewStyle(LinearProgressViewStyle())
            //  .scaleEffect(x: 1, y: 2, anchor: .center) // Makes the bar thicker
                .padding(.horizontal, 20)
            Text(remainingString)
                .onReceive(timer) { time in
                    
                    remaining = finish?.timeIntervalSince(Date()) ?? 0.0
                    
                    let formatter = DateComponentsFormatter()
                    formatter.allowedUnits = [.hour, .minute, .second]
                    formatter.unitsStyle = .positional
                    
                    remainingString = formatter.string(from: TimeInterval(remaining))!
                    
                    //print("remaining: \(remaining.formatted()) - progress: \(progress.formatted())")
                }
        }
    }
    
    private var progress: Double {
        guard let duration = duration, duration > 0 else { return 0.0 }
        
        return 1.0 - (remaining / duration)
    }
}

#Preview {
    //@Previewable @State
    var finish: Date? = Date(timeIntervalSinceNow: 100.0)
    var duration: TimeInterval? = 500.0
    CountdownView(duration: duration, finish: finish)
}
