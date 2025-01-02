import SwiftUI

struct TimerInputView: View {
    // Binding for total seconds from external source
    @Binding var totalSeconds: Double
    
    // State properties for user inputs (hours, minutes, seconds)
    @State private var hours: String = "0"
    @State private var minutes: String = "0"
    @State private var seconds: String = "0"
    
    var body: some View {
        VStack {
            HStack {
                // Hours input
                VStack {
                    Text("Hours")
                    TextField("0", text: $hours)
                        .onChange(of: hours) { old, new in updateTotalSeconds() }
                }
                .padding()
                
                // Minutes input
                VStack {
                    Text("Minutes")
                    TextField("0", text: $minutes)
                        .onChange(of: minutes) { old, new  in updateTotalSeconds() }
                }
                .padding()
                
                // Seconds input
                VStack {
                    Text("Seconds")
                    TextField("0", text: $seconds)
                        .onChange(of: seconds) { old, new  in updateTotalSeconds() }
                }
                .padding()
                
                
            }
            
        }
        .padding()
        .onAppear {
            // Initialize fields from binding value
            updateInputFields()
        }
    }
    
    // Helper to calculate total seconds from input fields and update the binding
    private func updateTotalSeconds() {
        let h = Double(hours) ?? 0
        let m = Double(minutes) ?? 0
        let s = Double(seconds) ?? 0
        totalSeconds = h * 3600 + m * 60 + s
    }
    
    // Helper to update the input fields based on total seconds
    private func updateInputFields() {
        let total = Int(totalSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        
        hours = String(h)
        minutes = String(m)
        seconds = String(s)
    }
}


