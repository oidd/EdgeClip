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
            services.configureOpenSettingsWindowAction {
                openWindow(id: AppWindowID.settings)
            }
            services.start()
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
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .frame(width: 18)
                        Text(section.title)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(selectedSection == section ? Color.white : Color.primary)
                    .background(selectionBackground(for: section), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(minWidth: sidebarWidth, idealWidth: sidebarWidth, maxWidth: sidebarWidth)
        .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth)
    }

    @ViewBuilder
    private var detailView: some View {
        SettingsView(section: selectedSection)
            .environmentObject(services)
            .environmentObject(appState)
    }

    private func selectionBackground(for section: SettingsSection) -> AnyShapeStyle {
        if selectedSection == section {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color.clear)
        }
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
