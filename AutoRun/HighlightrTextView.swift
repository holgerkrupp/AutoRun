import SwiftUI
import Highlightr

struct HighlightrTextView: NSViewRepresentable {
    @Binding var text: String
    private let highlightr = Highlightr()!
    
    var language: String = "bash"
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = NSColor.black
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.allowsUndo = true // Enable undo support
        
        highlightr.setTheme(to: "dracula")
        
        // Configure ScrollView
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true
        
        // Set minimum height to 10 lines
        let lineHeight = textView.font?.boundingRectForFont.height ?? 18
        scrollView.frame.size.height = lineHeight * 10
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        let newText = text 
        let oldText = textView.string
        
        // Preserve cursor position
        let selectedRange = textView.selectedRange()
        
        // Only update if the text actually changed
        if newText != oldText {
            let highlightedCode = highlightr.highlight(newText, as: language) ?? NSAttributedString(string: newText)
            textView.textStorage?.setAttributedString(highlightedCode)
            
            // Restore cursor position
            let updatedPosition = min(selectedRange.location, newText.count)
            textView.setSelectedRange(NSMakeRange(updatedPosition, 0))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightrTextView
        
        init(_ parent: HighlightrTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text =  textView.string
            }
        }
    }
}
