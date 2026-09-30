import SwiftUI

struct ExportPreviewView: View {
    @Bindable var store: AppStore
    let onClose: () -> Void

    private var markdown: String {
        store.exportMarkdown(includeDiff: store.exportIncludeDiff)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Include checkpoint diff", isOn: $store.exportIncludeDiff)

            SelectableTextView(text: markdown)
                .frame(minHeight: 220)
                .border(Color.secondary.opacity(0.2))

            HStack {
                Button("Close", action: onClose)
                Spacer()
                Button(store.copiedFeedback ? "Copied" : "Copy to clipboard") {
                    store.copyExportToPasteboard(includeDiff: store.exportIncludeDiff)
                }
            }
        }
    }
}

struct SelectableTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.backgroundColor = .textBackgroundColor

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView, textView.string != text {
            textView.string = text
        }
    }
}
