#if os(macOS)
import SwiftUI
import Highlightr

struct HighlightrTextView: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String

    var language: String = "bash"
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.allowsUndo = true
        
        // Configure ScrollView
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        
        // Set minimum height to 10 lines
        let lineHeight = textView.font?.boundingRectForFont.height ?? 18
        scrollView.frame.size.height = lineHeight * 10
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        context.coordinator.parent = self
        let theme = colorScheme == .dark ? "xcode-dark" : "xcode"
        if text != textView.string || context.coordinator.theme != theme {
            context.coordinator.applyHighlighting(to: textView, text: text, theme: theme)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightrTextView
        let highlightr = Highlightr()!
        var theme: String?
        private var isApplyingHighlight = false
        private var pendingHighlight: DispatchWorkItem?

        init(_ parent: HighlightrTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard isApplyingHighlight == false,
                  let textView = notification.object as? NSTextView else { return }

            parent.text = textView.string
            pendingHighlight?.cancel()

            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                let theme = self.parent.colorScheme == .dark ? "xcode-dark" : "xcode"
                self.applyHighlighting(to: textView, text: textView.string, theme: theme)
            }
            pendingHighlight = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        func applyHighlighting(to textView: NSTextView, text: String, theme: String) {
            let selectedRange = textView.selectedRange()
            self.theme = theme
            highlightr.setTheme(to: theme)
            let highlightedCode = highlightr.highlight(text, as: parent.language)
                ?? NSAttributedString(string: text)

            isApplyingHighlight = true
            textView.textStorage?.setAttributedString(highlightedCode)

            let utf16Length = (text as NSString).length
            let location = min(selectedRange.location, utf16Length)
            let length = min(selectedRange.length, utf16Length - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            isApplyingHighlight = false
        }
    }
}
#endif
