#if os(macOS)
import SwiftUI
import AppKit

// MARK: - AnnotationTool (display metadata)

extension Annotation.AnnotationType {
    var icon: String {
        switch self {
        case .arrow:     return "arrow.up.right"
        case .rect:      return "rectangle"
        case .text:      return "character.cursor.ibeam"
        case .highlight: return "highlighter"
        case .blur:      return "drop.halffull"
        }
    }
    var label: String {
        switch self {
        case .arrow:     return "Arrow"
        case .rect:      return "Rectangle"
        case .text:      return "Text"
        case .highlight: return "Highlight"
        case .blur:      return "Blur"
        }
    }
}

// MARK: - AnnotationToolbar

/// Horizontal toolbar displayed above (or below) the annotation canvas.
/// Provides tool selection, colour picker, stroke width, and undo.
struct AnnotationToolbar: View {

    @Binding var selectedTool: Annotation.AnnotationType
    @Binding var selectedColor: NSColor
    @Binding var strokeWidth: CGFloat

    /// Called when the user taps Undo (removes the last annotation).
    var onUndo: () -> Void
    /// Called when the user taps Done (saves and collapses the toolbar).
    var onDone: () -> Void

    /// Whether any annotations exist (gates undo button).
    var canUndo: Bool

    // SwiftUI Color proxy for the color picker binding
    @State private var pickerColor: Color

    init(
        selectedTool:  Binding<Annotation.AnnotationType>,
        selectedColor: Binding<NSColor>,
        strokeWidth:   Binding<CGFloat>,
        canUndo:       Bool,
        onUndo:        @escaping () -> Void,
        onDone:        @escaping () -> Void
    ) {
        self._selectedTool  = selectedTool
        self._selectedColor = selectedColor
        self._strokeWidth   = strokeWidth
        self.canUndo  = canUndo
        self.onUndo   = onUndo
        self.onDone   = onDone
        self._pickerColor = State(initialValue: Color(selectedColor.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 6) {
            // Tool buttons
            ForEach(Annotation.AnnotationType.allCases, id: \.self) { tool in
                toolButton(tool)
            }

            Divider().frame(height: 20)

            // Colour picker
            ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
                .help("Annotation colour")
                .onChange(of: pickerColor) { newColor in
                    selectedColor = NSColor(newColor)
                }

            // Stroke width stepper (only relevant for arrow + rect)
            if selectedTool == .arrow || selectedTool == .rect {
                Divider().frame(height: 20)
                Stepper(
                    value: $strokeWidth,
                    in: 1...8,
                    step: 0.5
                ) {
                    Text("\(strokeWidth, specifier: "%.1f")pt")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 36)
                }
                .controlSize(.small)
            }

            Spacer()

            // Undo
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .foregroundStyle(canUndo ? .primary : .tertiary)
            .disabled(!canUndo)
            .help("Undo last annotation")
            .keyboardShortcut("z", modifiers: .command)

            // Done
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Finish annotating")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
    }

    // MARK: - Tool button

    private func toolButton(_ tool: Annotation.AnnotationType) -> some View {
        let isSelected = selectedTool == tool
        return Button(action: { selectedTool = tool }) {
            Image(systemName: tool.icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(tool.label)
    }
}

// MARK: - TextLabelInputSheet

/// Small popover that lets the user type a text label for a `.text` annotation
/// before it's committed to the canvas.
struct TextLabelInputSheet: View {

    @Binding var label: String
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Text Label")
                .font(.headline)
            TextField("Label…", text: $label)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { commit() }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Add", action: commit)
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear { focused = true }
    }

    private func commit() {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
    }
}

// MARK: - Preview

#Preview {
    @State var tool = Annotation.AnnotationType.arrow
    @State var color = NSColor.systemRed
    @State var stroke: CGFloat = 2.5
    return AnnotationToolbar(
        selectedTool:  $tool,
        selectedColor: $color,
        strokeWidth:   $stroke,
        canUndo: true,
        onUndo: {},
        onDone: {}
    )
    .frame(width: 480)
}
#endif
