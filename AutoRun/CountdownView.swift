//
//  CountdownView.swift
//  AutoRun
//
//  Created by Holger Krupp on 31.12.24.
//

import SwiftUI

struct CountdownView: View {
    
    @Binding var finish:Date?
    @State var remaining:Double = 0.0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var remainingString:String = ""
    
    var body: some View {
        Text(remainingString)
            .onReceive(timer) { time in
                
                    remaining = finish?.timeIntervalSince(Date()) ?? 0.0
                    
                    let formatter = DateComponentsFormatter()
                    formatter.allowedUnits = [.hour, .minute, .second]
                formatter.unitsStyle = .positional
                    
                    remainingString = formatter.string(from: TimeInterval(remaining))!
                
                
            }
    }
}

#Preview {
    @Previewable @State var finish: Date? = Date(timeIntervalSinceNow: 100.0)
    CountdownView(finish: $finish)
}
