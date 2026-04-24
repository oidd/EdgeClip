import AppKit
import SwiftUI

struct StackGlyphIcon: View {
    static let toolbarSize: CGFloat = 14
    static let sourceSize: CGFloat = 11.5
    static let emptyStateSize: CGFloat = 24

    var isSelected: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Image(systemName: StackGlyphSymbolResolver.symbolName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: StackGlyphMetrics.fontSize(for: side), weight: .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private enum StackGlyphMetrics {
    static func fontSize(for side: CGFloat) -> CGFloat {
        max(side * 0.88, 10)
    }
}

private enum StackGlyphSymbolResolver {
    static let symbolName: String = {
        let candidates = [
            "square.3.layers.3d.down.forward",
            "square.stack.3d.down.forward",
            "square.3.layers.3d",
            "square.stack.3d.up"
        ]

        for candidate in candidates {
            if NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil {
                return candidate
            }
        }

        return "square.stack.3d.up"
    }()
}
