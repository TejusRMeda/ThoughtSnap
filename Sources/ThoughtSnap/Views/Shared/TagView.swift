#if os(macOS)
import SwiftUI

// MARK: - TagView

struct TagView: View {
    let tag: String
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Text("#\(tag)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
            .onTapGesture { onTap?() }
    }
}

#Preview {
    HStack {
        TagView(tag: "questflow")
        TagView(tag: "auth", isSelected: true)
    }
    .padding()
}
#endif
