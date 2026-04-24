import SwiftUI

struct NoticeOverlayView: View {
    let transientNotice: TransientNotice?
    let persistentMessage: String?
    let onDismissPersistent: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            if let transientNotice {
                noticeCard(
                    message: transientNotice.message,
                    tone: transientNotice.tone
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let persistentMessage, !persistentMessage.isEmpty {
                noticeCard(
                    message: persistentMessage,
                    tone: .warning,
                    dismissAction: onDismissPersistent
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.18), value: transientNotice?.id)
        .animation(.easeInOut(duration: 0.18), value: persistentMessage)
    }

    private func noticeCard(
        message: String,
        tone: TransientNotice.Tone,
        dismissAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: tone.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone.tintColor)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let dismissAction {
                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 440, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tone.borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
    }
}

private extension TransientNotice.Tone {
    var tintColor: Color {
        switch self {
        case .info:
            return .blue
        case .warning:
            return .orange
        }
    }

    var borderColor: Color {
        tintColor.opacity(0.28)
    }

    var symbolName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }
}
