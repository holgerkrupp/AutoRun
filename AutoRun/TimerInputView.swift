import SwiftUI

struct TimerInputView: View {
    @Binding var totalSeconds: Double

    @State private var hours: String = "0"
    @State private var minutes: String = "0"
    @State private var seconds: String = "0"

    var body: some View {
        HStack(spacing: 12) {
            durationField(title: "Hours", text: $hours, maximum: 999)
            durationField(title: "Minutes", text: $minutes, maximum: 59)
            durationField(title: "Seconds", text: $seconds, maximum: 59)
        }
        .onAppear {
            updateInputFields()
        }
        .onChange(of: totalSeconds) { _, newValue in
            if abs(currentTotal - newValue) > 0.5 {
                updateInputFields()
            }
        }
    }

    private func durationField(title: String, text: Binding<String>, maximum: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("0", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel(title)
                .onChange(of: text.wrappedValue) { _, new in
                    let sanitized = sanitizedValue(new, maximum: maximum)
                    if sanitized != new {
                        text.wrappedValue = sanitized
                        return
                    }
                    updateTotalSeconds()
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func updateTotalSeconds() {
        let h = Double(hours) ?? 0
        let m = Double(minutes) ?? 0
        let s = Double(seconds) ?? 0
        totalSeconds = h * 3600 + m * 60 + s
    }

    private var currentTotal: TimeInterval {
        let h = Double(hours) ?? 0
        let m = Double(minutes) ?? 0
        let s = Double(seconds) ?? 0
        return h * 3600 + m * 60 + s
    }

    private func sanitizedValue(_ value: String, maximum: Int) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.isEmpty == false else { return "" }
        return String(min(Int(digits) ?? 0, maximum))
    }

    private func updateInputFields() {
        let total = max(Int(totalSeconds), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60

        hours = String(h)
        minutes = String(m)
        seconds = String(s)
    }
}

#Preview {
    @Previewable @State var seconds = 20.0
    TimerInputView(totalSeconds: $seconds)
}
