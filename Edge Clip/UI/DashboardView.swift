import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                permissionCard
                pathCard
                historyCard
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color.blue.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("鼠标贴边唤出剪切板，支持文本、图片、文件与收藏记录的快速回贴。")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(services.isPanelVisible ? "收起边缘面板" : "显示边缘面板") {
                    services.showPanel()
                }
                .buttonStyle(.borderedProminent)

                Button("打开辅助功能") {
                    services.requestAccessibilityPermission()
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var permissionCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: appState.permissionGranted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(appState.permissionGranted ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("辅助功能权限")
                    .font(.headline)
                Text(appState.permissionGranted ? "已授权后，可自动回到原应用并粘贴" : "未授权时，会先复制内容并回到原应用，由你手动粘贴")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(appState.permissionGranted ? "刷新状态" : "立即授权") {
                if appState.permissionGranted {
                    services.refreshPermissionStatus()
                } else {
                    services.requestAccessibilityPermission()
                }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前运行包路径")
                .font(.headline)
            Text(services.runningAppBundlePath())
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("在 Finder 中定位") {
                    services.revealRunningAppInFinder()
                }
                Button("复制路径") {
                    services.copyRunningAppPath()
                }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近记录")
                    .font(.headline)
                Spacer()
                Text("\(appState.history.count) 条")
                    .foregroundStyle(.secondary)
            }

            if appState.history.isEmpty {
                Text("暂无内容，先复制一些文本、图片或文件试试。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(appState.history.prefix(8))) { item in
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.kind.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.preview)
                                .lineLimit(1)

                            Text(item.sourceAppDisplayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(historyTimestamp(for: item.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func historyTimestamp(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        }

        return Self.dayFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
