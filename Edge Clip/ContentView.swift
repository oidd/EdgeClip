import SwiftUI
import AppKit

struct ContentView: View {
    private let layoutMinWidth: CGFloat = 610
    private let userResizeMinWidth: CGFloat = 860
    private let windowMinHeight: CGFloat = 620
    private let sidebarWidth: CGFloat = 186

    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    @State private var selectedSection: SettingsSection = .interaction
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsOnboarding = false
    @Namespace private var sidebarIndicatorNamespace

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: layoutMinWidth, minHeight: windowMinHeight)
        .preferredColorScheme(services.preferredColorScheme)
        .background(
            WindowChromeConfigurator(
                appearanceMode: appState.settings.appearanceMode,
                minContentSize: NSSize(width: layoutMinWidth, height: windowMinHeight),
                userResizeMinWidth: userResizeMinWidth,
                onWindowVisibilityChanged: { isVisible in
                    services.setSettingsWindowVisible(isVisible)
                }
            )
            .frame(width: 0, height: 0)
        )
        .task {
            // AppDelegate 已经在 applicationDidFinishLaunching 阶段调用过
            // services.start() 并装好了 AppKit 兜底的"打开设置窗口"动作。
            // 这里再用 SwiftUI 的 openWindow 覆盖一次，让窗口被完全关闭后
            // 仍能由菜单栏 / Reopen 重新创建出来。
            services.configureOpenSettingsWindowAction {
                openWindow(id: AppWindowID.settings)
            }
            services.refreshPermissionStatus()
            syncOnboardingPresentation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appState.synchronizeLocalization()
                services.refreshPermissionStatus()
                services.refreshPreferredColorSchemeFromSystemIfNeeded()
            }
        }
        .onChange(of: appState.settings.hasCompletedOnboarding) { _, _ in
            syncOnboardingPresentation()
        }
        .onChange(of: appState.onboardingPresentationRequestToken) { _, _ in
            showsOnboarding = true
        }
        .overlay(alignment: .bottom) {
            if !services.isPanelVisible,
               appState.transientNotice != nil || appState.lastErrorMessage != nil {
                NoticeOverlayView(
                    transientNotice: appState.transientNotice,
                    persistentMessage: appState.lastErrorMessage,
                    onDismissPersistent: {
                        appState.lastErrorMessage = nil
                    }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showsOnboarding) {
            OnboardingView(
                onRequestPermission: {
                    services.requestAccessibilityPermission()
                    finishOnboarding()
                },
                onFinish: finishOnboarding
            )
            .interactiveDismissDisabled()
        }
        .environment(\.locale, appState.appLocale)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarRow(
                    section: section,
                    isSelected: selectedSection == section,
                    indicatorNamespace: sidebarIndicatorNamespace,
                    onSelect: {
                        // 关键：不要用 `withAnimation(...)` 包裹这次赋值。
                        // withAnimation 会创建一个事务并沿整个视图树向下
                        // 传播——传到 detail pane 时，SwiftUI 会给"完全不同
                        // switch case 之间的切换"自动套一层 opacity 交叉淡
                        // 入淡出。由于 NSWindow 本身是透明的
                        // (`WindowChromeConfigurator` 把 isOpaque/backgroundColor
                        // 设为透明，方便侧边栏走 material 半透明)，任何一帧
                        // 的 opacity < 1.0 都会直接露出桌面，视觉上就是
                        // "整个 detail pane 闪一下"。
                        //
                        // 改用 `.animation(.spring, value: selectedSection)`
                        // 加在下面侧边栏 VStack 上：动画环境只对侧边栏子树
                        // 内由 selectedSection 触发的变化生效，detail 子树
                        // 完全不在动画事务里，不会被叠 opacity 过渡。
                        guard selectedSection != section else { return }
                        selectedSection = section
                    }
                )
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .frame(minWidth: sidebarWidth, idealWidth: sidebarWidth, maxWidth: sidebarWidth)
        .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth)
        // 把 spring 动画严格圈在侧边栏子树内：matchedGeometryEffect 的
        // 竖线滑动 + 选中行的颜色过渡都在这里获得动画环境，detail pane
        // 收不到事务，从而不会被裹进 opacity cross-fade。
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selectedSection)
    }

    @ViewBuilder
    private var detailView: some View {
        SettingsView(section: selectedSection)
            .environmentObject(services)
            .environmentObject(appState)
    }

    private func syncOnboardingPresentation() {
        showsOnboarding = !appState.settings.hasCompletedOnboarding
    }

    private func finishOnboarding() {
        appState.updateSettings { settings in
            settings.hasCompletedOnboarding = true
        }
        showsOnboarding = false
    }
}

/// 设置面板侧边栏的单行视图。
///
/// 选中态包含三层视觉反馈：
/// 1. 左侧 accent 蓝色竖线，通过 `matchedGeometryEffect` 在父 `@Namespace`
///    中共享，切换选项时在各行之间沿左侧边缘平滑滑动。竖线高度与行高
///    一致，因此视觉上与背景同高。
/// 2. 淡蓝色 accent 背景，使用 `GeometryReader` 驱动宽度从 0 动画到满，
///    形成"从竖线位置向右展开"的扫描效果（避免 scaleEffect 拉伸圆角）。
/// 3. 图标 + 文本变为 accent 色。字重保持 regular 不变，避免 spring 动画
///    期间在 regular / semibold 之间切换字宽导致的微弱位移闪动。
private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let indicatorNamespace: Namespace.ID
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    /// 0 → 1，控制选中背景的"从左向右扫开"动画进度。
    @State private var selectedBackgroundProgress: CGFloat = 0

    private static let rowHeight: CGFloat = 36
    private static let indicatorWidth: CGFloat = 3
    private static let backgroundLeadingInset: CGFloat = 8
    private static let contentLeadingInset: CGFloat = 18
    private static let cornerRadius: CGFloat = 8

    private var selectedBackgroundFill: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14)
    }

    private var hoverBackgroundFill: Color {
        (isHovered && !isSelected) ? Color.primary.opacity(0.05) : Color.clear
    }

    private var foreground: Color {
        isSelected ? Color.accentColor : Color.primary
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .leading) {
                // Layer 1：hover 背景（无动画、铺满可用宽度）。仅对未选中行
                // 起效，避免 hover 在选中行上叠加视觉噪声。
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(hoverBackgroundFill)
                    .padding(.leading, Self.backgroundLeadingInset)

                // Layer 2：选中背景扫开层。使用 GeometryReader 测量可用宽度，
                // 再用 `frame(width:)` 动画从 0 增长到满；锚点 alignment 为
                // leading，因此扫开方向是从左到右（即从竖线位置向右展开）。
                GeometryReader { geo in
                    let sweepableWidth = max(0, geo.size.width - Self.backgroundLeadingInset)
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(selectedBackgroundFill)
                        .frame(
                            width: sweepableWidth * selectedBackgroundProgress,
                            height: geo.size.height,
                            alignment: .leading
                        )
                        .offset(x: Self.backgroundLeadingInset)
                }

                // Layer 3：左侧 accent 竖线。仅在选中行渲染，通过
                // matchedGeometryEffect 在不同行之间共享同一身份；高度等于
                // 整行高度，确保竖线与背景同高。父视图触发的 spring 动画
                // 会让它沿左侧边缘平滑上下滑动到新选中行。
                HStack(spacing: 0) {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: Self.indicatorWidth, height: Self.rowHeight)
                            .matchedGeometryEffect(
                                id: "sidebar.indicator",
                                in: indicatorNamespace
                            )
                    } else {
                        Color.clear.frame(width: Self.indicatorWidth, height: Self.rowHeight)
                    }
                    Spacer(minLength: 0)
                }

                // Layer 4：图标 + 标题。字重恒定 regular，避免选中时切换
                // semibold 导致文字宽度突变带来的"闪动"。
                HStack(spacing: 10) {
                    Image(section.icon)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                    Text(section.title)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(foreground)
                .padding(.leading, Self.contentLeadingInset)
                .padding(.trailing, 12)
            }
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                // 重置到 0 后再 easeOut 到 1，形成"从竖线开始向右扫开"的视觉。
                selectedBackgroundProgress = 0
                withAnimation(.easeOut(duration: 0.30)) {
                    selectedBackgroundProgress = 1
                }
            } else {
                withAnimation(.easeIn(duration: 0.14)) {
                    selectedBackgroundProgress = 0
                }
            }
        }
        .onAppear {
            selectedBackgroundProgress = isSelected ? 1 : 0
        }
    }
}
