import AppKit
import SwiftUI

struct OnboardingView: View {
    private enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case interactions
        case privacy
        case permissions

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome:
                return AppLocalization.localized("欢迎使用 Edge Clip")
            case .interactions:
                return AppLocalization.localized("先认识几种打开方式")
            case .privacy:
                return AppLocalization.localized("数据与隐私")
            case .permissions:
                return AppLocalization.localized("辅助功能权限")
            }
        }
    }

    let onRequestPermission: () -> Void
    let onFinish: () -> Void

    @State private var currentStep: Step = .welcome
    @Environment(\.colorScheme) private var colorScheme

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: 760, height: 560)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: colorScheme == .dark ? .windowBackgroundColor : .controlBackgroundColor),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image("AboutAppIcon")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.1), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 0) {
                    Text(currentStep.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }

                Spacer(minLength: 12)
            }

            HStack(spacing: 10) {
                ForEach(Step.allCases) { step in
                    Capsule(style: .continuous)
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(height: 6)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch currentStep {
            case .welcome:
                welcomeStep
            case .interactions:
                interactionsStep
            case .privacy:
                privacyStep
            case .permissions:
                permissionsStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 28)
    }

    private var footer: some View {
        HStack {
            Button(localized("上一步")) {
                guard let previous = Step(rawValue: currentStep.rawValue - 1) else { return }
                currentStep = previous
            }
            .buttonStyle(.bordered)
            .opacity(currentStep == .welcome ? 0 : 1)
            .disabled(currentStep == .welcome)

            Spacer()

            if currentStep != .permissions {
                Button(localized("继续")) {
                    guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
                    currentStep = next
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 10) {
                    Button(localized("稍后再说")) {
                        onFinish()
                    }
                    .buttonStyle(.bordered)

                    Button(localized("现在去授权")) {
                        onRequestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHeroCard(
                title: "把刚刚复制过的内容，留在手边。",
                description: "Edge Clip 会把你最近复制过的文本、图片和文件整理进一个随手可开的侧边面板里，方便你继续查找、预览、收藏和回贴。"
            )

            HStack(alignment: .top, spacing: 14) {
                onboardingInfoCard(
                    symbol: "sparkles.rectangle.stack",
                    title: "默认保留基础能力",
                    description: "即使还没授予辅助功能权限，你也可以继续记录和查看基础历史。"
                )
                onboardingInfoCard(
                    symbol: "lock.shield",
                    title: "敏感内容优先保护",
                    description: "会为常见密码管理器和敏感应用预置例外规则，你也可以自行调整。"
                )
            }

            onboardingNote(
                "这份引导只会在首次启动时出现一次；后续你仍然可以在设置页查看隐私说明、权限状态和应用例外。"
            )
        }
    }

    private var interactionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                onboardingInfoCard(
                    symbol: "rectangle.righthalf.inset.filled.arrow.right",
                    title: "边缘唤出",
                    description: "鼠标进入设定的屏幕边缘，面板会从左侧或右侧滑出。"
                )
                onboardingInfoCard(
                    symbol: "command.square",
                    title: "快捷键唤出",
                    description: "支持双击修饰键或组合按键，适合键盘优先的工作流。"
                )
                onboardingInfoCard(
                    symbol: "menubar.rectangle",
                    title: "菜单栏入口",
                    description: "你可以从菜单栏图标打开面板、进入设置，或快速查看最近一条内容。"
                )
                onboardingInfoCard(
                    symbol: "cursorarrow.motionlines.click",
                    title: "右键滑出",
                    description: "按住右键向外滑出可进入选择模式，适合不想频繁切手势的场景。"
                )
            }

            onboardingNote(
                "你不需要一次开启所有方式。建议先从自己最顺手的一种开始，再慢慢加。"
            )
        }
    }

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHeroCard(
                title: "默认本地保存，边界明确。",
                description: "历史记录、收藏、资源文件和设置默认都保存在这台 Mac 上。详细声明里也会写清楚：哪些数据会落本地、哪些权限是可选的、什么情况下可能发生网络访问。"
            )

            HStack(alignment: .top, spacing: 14) {
                onboardingInfoCard(
                    symbol: "internaldrive",
                    title: "本地历史与收藏",
                    description: "文本、图片、文件记录与收藏内容默认只保存在本机目录。"
                )
                onboardingInfoCard(
                    symbol: "network",
                    title: "可能的网络访问",
                    description: "仅在剪贴板本身包含远程图片地址，且需要把它落成图片记录时，应用才可能访问该地址。"
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Link(destination: EdgeClipExternalLinks.privacyPolicyURL) {
                    Label(localized("查看详细的数据与隐私声明"), systemImage: "arrow.up.forward.app")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            onboardingHeroCard(
                title: "授权辅助功能可提升使用体验",
                description: "授权后，Edge Clip 可以使用自动粘贴、全局唤出、右键滑出和部分预览快捷操作。如果暂时不授权，你依然可以继续使用基础历史记录与手动回贴。"
            )

            VStack(alignment: .leading, spacing: 10) {
                permissionBullet("会用到权限的能力：全局快捷键、右键滑出、恢复前台应用后自动发送 Cmd+V、部分预览态快捷键。")
                permissionBullet("不会因为你跳过授权而阻止进入应用。")
                permissionBullet("稍后你也可以随时在设置页重新触发授权。")
            }

            onboardingNote(
                "点击“现在去授权”后，我们会发起系统辅助功能授权请求，并同时打开对应的系统设置页面，方便你直接完成。"
            )
        }
    }

    private func onboardingHeroCard(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized(title))
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(localized(description))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(opacity: colorScheme == .dark ? 0.16 : 0.75))
    }

    private func onboardingInfoCard(symbol: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(localized(title))
                .font(.system(size: 16, weight: .semibold))

            Text(localized(description))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground(opacity: colorScheme == .dark ? 0.11 : 0.62))
    }

    private func onboardingNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(localized(text))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(opacity: colorScheme == .dark ? 0.08 : 0.45))
    }

    private func permissionBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            Text(localized(text))
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cardBackground(opacity: Double) -> some View {
        let fillColor: Color
        let strokeColor: Color
        let shadowColor: Color

        if colorScheme == .dark {
            fillColor = Color.primary.opacity(opacity)
            strokeColor = Color.primary.opacity(0.12)
            shadowColor = .clear
        } else {
            fillColor = Color.white.opacity(0.94)
            strokeColor = Color.black.opacity(0.06)
            shadowColor = Color.black.opacity(0.05)
        }

        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 18, y: 8)
    }
}
