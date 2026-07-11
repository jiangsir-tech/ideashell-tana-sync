import AppKit
import Charts
import Darwin
import ServiceManagement
import SwiftUI

private enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: appString("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
    var locale: Locale {
        switch self {
        case .system: .current
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }
}

private func effectiveLanguageCode() -> String {
    let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
    if saved != AppLanguage.system.rawValue { return saved }
    return systemLanguageCode()
}

private func systemLanguageCode() -> String {
    Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
}

private func appString(_ key: String) -> String {
    let language = effectiveLanguageCode()
    guard language != "zh-Hans",
          let path = Bundle.main.path(forResource: language, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

private func appFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: appString(key), locale: AppLanguage(rawValue: effectiveLanguageCode())?.locale ?? .current, arguments: arguments)
}

private func noteCountText(_ count: Int) -> String {
    effectiveLanguageCode() == "en" ? "\(count) notes" : "\(count) 条"
}

private func dayCountText(_ count: Int) -> String {
    effectiveLanguageCode() == "en" ? "\(count) days" : "\(count) 天"
}

private func syncTotalsText(week: Int, total: Int) -> String {
    effectiveLanguageCode() == "en"
        ? "\(week) this week · \(total) all time"
        : "本周已同步 \(week) 条 · 历史同步 \(total) 条"
}

private func syncIntervalTitle(_ minutes: Int) -> String {
    if effectiveLanguageCode() == "en" {
        switch minutes {
        case 60: return "1 hour"
        case 1440: return "Daily"
        default: return "\(minutes) min"
        }
    }
    switch minutes {
    case 60: return appString("每小时")
    case 1440: return appString("每天一次")
    default: return appFormat("每 %d 分钟", minutes)
    }
}

@main
struct IdeaShellTanaApp: App {
    @StateObject private var controller = SyncController()
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue

    init() {
        // LaunchAgent starts this same signed executable in headless mode.  This
        // keeps automatic sync independent of Node.js, zsh, and a mutable script.
        let backgroundSync = CommandLine.arguments.contains("--sync-background")
        let dryRun = CommandLine.arguments.contains("--sync-dry-run")
        guard backgroundSync || dryRun else { return }
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ideashell-tana-sync")
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ideashell-tana-sync")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        do {
            let result = try NativeSync.run(baseDirectory: base, dryRun: dryRun)
            if dryRun {
                print("Dry run: new=\(result.todayNew), posted=\(result.todayPosted), pending=\(result.todayPending), failed=\(result.todayFailed)")
                exit(0)
            }
            let payload: [String: Any] = ["status": "success", "updatedAt": ISO8601DateFormatter().string(from: Date()), "postedNotes": result.postedNotes, "pendingNotes": result.pendingNotes, "todayDate": result.todayDate, "todayNew": result.todayNew, "todayPosted": result.todayPosted, "todayPending": result.todayPending, "todayFailed": result.todayFailed, "warnings": result.warnings]
            try JSONSerialization.data(withJSONObject: payload).write(to: base.appendingPathComponent(".ideashell-tana-status.json"), options: .atomic)
            print("Posted to Tana: \(result.postedNotes)")
            exit(0)
        } catch {
            let message = error.localizedDescription
            let data = try? JSONSerialization.data(withJSONObject: ["status": "error", "updatedAt": ISO8601DateFormatter().string(from: Date()), "error": message])
            try? data?.write(to: base.appendingPathComponent(".ideashell-tana-status.json"), options: .atomic)
            fputs("同步失败：\(message)\n", stderr)
            exit(1)
        }
    }

    private var appLanguage: AppLanguage { AppLanguage(rawValue: appLanguageRaw) ?? .system }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(controller)
                .environment(\.locale, appLanguage.locale)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(controller)
                .environment(\.locale, appLanguage.locale)
        }

        Window(appString("同步历史"), id: "sync-history") {
            SyncHistoryView()
                .environment(\.locale, appLanguage.locale)
        }
        .defaultSize(width: 720, height: 470)
    }

    private static let menuBarIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.scaleBy(x: rect.width / 64, y: rect.height / 64)

            NSColor.black.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 48, height: 48))
            ring.lineWidth = 7
            ring.lineCapStyle = .round
            let dash: [CGFloat] = [123, 28]
            ring.setLineDash(dash, count: dash.count, phase: 0)
            var rotation = AffineTransform()
            rotation.translate(x: 32, y: 32)
            rotation.rotate(byDegrees: 40)
            rotation.translate(x: -32, y: -32)
            ring.transform(using: rotation)
            ring.stroke()

            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 19.5, y: 21.5, width: 25, height: 7.5), xRadius: 2.5, yRadius: 2.5).fill()
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 28, y: 27))
            stem.line(to: NSPoint(x: 36, y: 27))
            stem.line(to: NSPoint(x: 36, y: 44.4))
            stem.curve(to: NSPoint(x: 34.5, y: 47), controlPoint1: NSPoint(x: 36, y: 45.6), controlPoint2: NSPoint(x: 35.5, y: 46.4))
            stem.line(to: NSPoint(x: 32, y: 48.5))
            stem.line(to: NSPoint(x: 29.5, y: 47))
            stem.curve(to: NSPoint(x: 28, y: 44.4), controlPoint1: NSPoint(x: 28.5, y: 46.4), controlPoint2: NSPoint(x: 28, y: 45.6))
            stem.close()
            stem.fill()

            context.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = appString("闪念同步")
        return image
    }()
}

private struct MenuContent: View {
    @EnvironmentObject private var controller: SyncController
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: controller.statusIcon)
                    .foregroundStyle(controller.statusColor)
                    .font(.title3)
                HStack(spacing: 8) {
                    Text("闪念贝壳 → Tana")
                        .fontWeight(.semibold)
                        Text(controller.syncModeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("今日概览")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    TodayMetric(value: controller.todayNew, label: "贝壳新增", color: .primary)
                    TodayMetric(value: controller.todayPosted, label: "Tana 已同步", color: .green)
                    TodayMetric(value: controller.todayPending, label: "处理中", color: .orange)
                    TodayMetric(value: controller.todayFailed, label: "失败", color: .red)
                }
                Button {
                    openSyncHistory()
                } label: {
                    HStack(spacing: 4) {
                        Text(syncTotalsText(week: controller.weekSynced, total: controller.totalSynced))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Text("同步方式")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack {
                SyncModeButton(
                    title: "手动同步",
                    isSelected: !controller.isAutomaticSyncEnabled,
                    isEnabled: controller.isConfigured
                ) {
                    controller.setAutomaticSync(false)
                }
                Spacer()
                Button {
                    controller.syncNow()
                } label: {
                    Label(appString(controller.isSyncing ? "正在同步…" : "立即同步"), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 100)
                .disabled(controller.isAutomaticSyncEnabled || controller.isSyncing || !controller.isConfigured)
            }

            HStack {
                SyncModeButton(
                    title: "自动同步",
                    isSelected: controller.isAutomaticSyncEnabled,
                    isEnabled: controller.isConfigured
                ) {
                    controller.setAutomaticSync(true)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { controller.automaticSyncIntervalMinutes },
                    set: { controller.setAutomaticSyncInterval($0) }
                )) {
                    ForEach(SyncConfiguration.availableSyncIntervals, id: \.self) { minutes in
                        Text(syncIntervalTitle(minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                .disabled(!controller.isAutomaticSyncEnabled || !controller.isConfigured)
            }

            if controller.isAutomaticSyncEnabled && controller.automaticSyncIntervalMinutes == 1440 {
                HStack {
                    Text("执行时间")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { controller.dailySyncTime },
                            set: { controller.setDailySyncTime($0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            Divider()

            HStack(spacing: 8) {
                FooterButton(title: "退出") { NSApp.terminate(nil) }
                FooterButton(title: "日志") { controller.openLogs() }
                FooterButton(title: "设置") {
                    openSettings()
                    bringWindowToFront(identifier: "com_apple_SwiftUI_Settings_window", title: "设置", after: 0)
                    bringWindowToFront(identifier: "com_apple_SwiftUI_Settings_window", title: "设置", after: 0.15)
                }
                FooterButton(title: "关于") { showAboutPanel() }
            }
        }
        .padding(14)
        .frame(width: effectiveLanguageCode() == "en" ? 340 : 290)
        .id(appLanguageRaw)
        .task { controller.refreshStatus() }
    }

    private func bringWindowToFront(identifier: String?, title: String, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.activate(ignoringOtherApps: true)
            guard let window = NSApp.windows.first(where: {
                (identifier != nil && $0.identifier?.rawValue == identifier) || $0.title.contains(title)
            }) else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func showAboutPanel() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: appString("作者：江sir爱数码\n将闪念贝壳笔记同步至 Tana"),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appString("闪念同步"),
            .applicationVersion: "0.1.0 Beta",
            .version: "1",
            .credits: credits,
        ])
    }

    private func openSyncHistory() {
        openWindow(id: "sync-history")
        bringWindowToFront(identifier: nil, title: appString("同步历史"), after: 0)
        bringWindowToFront(identifier: nil, title: appString("同步历史"), after: 0.15)
    }
}

private struct TodayMetric: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(appString(label))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SyncHistoryView: View {
    @State private var snapshot = SyncHistorySnapshot.load()
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("同步历史")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("刷新") { snapshot = SyncHistorySnapshot.load() }
            }

            HStack(spacing: 12) {
                HistoryMetric(title: appString("累计同步"), value: noteCountText(snapshot.totalSynced), color: .green)
                HistoryMetric(title: appString("本月同步"), value: noteCountText(snapshot.monthSynced), color: .green)
                HistoryMetric(title: appString("本月记录"), value: dayCountText(snapshot.monthRecordDays), color: .accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("最近 30 天")
                    .font(.headline)
                Chart {
                    ForEach(snapshot.days) { day in
                        BarMark(
                            x: .value(appString("日期"), day.date, unit: .day),
                            y: .value(appString("数量"), day.discovered)
                        )
                        .foregroundStyle(by: .value(appString("类型"), appString("贝壳新增")))
                        .position(by: .value(appString("类型"), appString("贝壳新增")))

                        BarMark(
                            x: .value(appString("日期"), day.date, unit: .day),
                            y: .value(appString("数量"), day.posted)
                        )
                        .foregroundStyle(by: .value(appString("类型"), appString("Tana 已同步")))
                        .position(by: .value(appString("类型"), appString("Tana 已同步")))
                    }
                }
                .chartForegroundStyleScale([
                    appString("贝壳新增"): Color.secondary.opacity(0.55),
                    appString("Tana 已同步"): Color.green,
                ])
                .chartLegend(position: .top, alignment: .leading)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day().locale(Locale(identifier: effectiveLanguageCode())))
                    }
                }
                .frame(minHeight: 250)
            }

            Text("统计仅保存在这台 Mac，不包含笔记正文。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 430)
        .id(appLanguageRaw)
        .onAppear { snapshot = SyncHistorySnapshot.load() }
    }
}

private struct HistoryMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SyncHistorySnapshot {
    struct Day: Identifiable {
        let date: Date
        let discovered: Int
        let posted: Int
        var id: Date { date }
    }

    private struct StoredState: Decodable {
        let postedIds: [String]?
        let dailyStats: [String: StoredDay]?
    }

    private struct StoredDay: Decodable {
        let discoveredIds: [String]?
        let postedIds: [String]?
    }

    let totalSynced: Int
    let weekSynced: Int
    let monthSynced: Int
    let monthRecordDays: Int
    let days: [Day]

    static func load() -> SyncHistorySnapshot {
        let stateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ideashell-tana-sync/.ideashell-tana-state.json")
        let state = (try? Data(contentsOf: stateURL))
            .flatMap { try? JSONDecoder().decode(StoredState.self, from: $0) }
        let storedDays = state?.dailyStats ?? [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "yyyy-MM"
        let monthPrefix = monthFormatter.string(from: today)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        let days = (0..<30).reversed().compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let stored = storedDays[formatter.string(from: date)]
            return Day(
                date: date,
                discovered: Set(stored?.discoveredIds ?? []).count,
                posted: Set(stored?.postedIds ?? []).count
            )
        }
        let currentMonthDays = storedDays.filter { $0.key.hasPrefix(monthPrefix) }.map(\.value)
        let currentWeekDays = storedDays.compactMap { key, value -> StoredDay? in
            guard let date = formatter.date(from: key), date >= weekStart, date <= today else { return nil }
            return value
        }
        return SyncHistorySnapshot(
            totalSynced: Set(state?.postedIds ?? []).count,
            weekSynced: currentWeekDays.reduce(0) { $0 + Set($1.postedIds ?? []).count },
            monthSynced: currentMonthDays.reduce(0) { $0 + Set($1.postedIds ?? []).count },
            monthRecordDays: currentMonthDays.filter { !Set($0.discoveredIds ?? []).isEmpty }.count,
            days: days
        )
    }
}

private struct SyncModeButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(appString(title))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(appString(title))
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var controller: SyncController
    @State private var configuration = SyncConfiguration.load()
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var discoveredModelIDs: [String] = []
    @State private var isRefreshingModels = false
    @State private var modelRefreshMessage = ""
    @State private var savedPolishPrompt = SyncConfiguration.load().polishPrompt
    @State private var polishPromptSaveError = ""
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    var body: some View {
        Form {
            Section("通用") {
                Picker("界面语言", selection: Binding(
                    get: { appLanguageRaw },
                    set: { newLanguage in
                        // Keep appString-based AppKit and SwiftUI labels in sync before SwiftUI redraws.
                        UserDefaults.standard.set(newLanguage, forKey: "appLanguage")
                        appLanguageRaw = newLanguage
                    }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                Toggle("开机自启", isOn: $configuration.launchAtLogin)
                Text("开启后，登录这台 Mac 时会自动启动菜单栏 App。请将 App 安装在“应用程序”目录后再开启。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("成功后在闪念贝壳标题前加 ～～", isOn: $configuration.markTransferred)
            }

            Section("连接") {
                LabeledContent {
                    SecureField("", text: $configuration.ideaShellToken)
                        .labelsHidden()
                } label: {
                    CredentialLabel(title: "闪念贝壳 API Key") {
                        showCredentialHelp(.ideaShell)
                    }
                }
                LabeledContent {
                    SecureField("", text: $configuration.tanaToken)
                        .labelsHidden()
                } label: {
                    CredentialLabel(title: "Tana Write API Token") {
                        showCredentialHelp(.tanaToken)
                    }
                }
                LabeledContent {
                    TextField("", text: $configuration.tanaTargetNodeID)
                        .labelsHidden()
                } label: {
                    CredentialLabel(title: "Tana 目标节点 ID") {
                        showCredentialHelp(.tanaNodeID)
                    }
                }
                Text("填写 INBOX 会直接写入 Tana 收件箱。")
                    .font(.caption).foregroundStyle(.secondary)
                Label(controller.nodeStatus, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Section("文本处理") {
                Toggle("同步前使用 AI 润色", isOn: $configuration.polishEnabled)
                if configuration.polishEnabled {
                    LabeledContent("AI 服务商") {
                        AIProviderPopUpButton(selection: configuration.aiProvider) { provider in
                            NSApp.keyWindow?.makeFirstResponder(nil)
                            var updatedConfiguration = configuration
                            updatedConfiguration.selectAIProvider(provider)
                            configuration = updatedConfiguration
                        }
                        .frame(width: 180, height: 24)
                    }
                    TextField("API 地址", text: $configuration.openAIBaseURL)
                        .id("api-url-\(configuration.aiProvider.rawValue)")
                    HStack {
                        Text("模型")
                        Spacer()
                        AIModelComboBox(
                            text: $configuration.openAIModel,
                            models: suggestedModels,
                            placeholder: appString("选择或手动填写模型 ID")
                        )
                        .frame(width: modelFieldWidth, height: 24)
                        .id("model-\(configuration.aiProvider.rawValue)")
                    }
                    HStack(spacing: 8) {
                        Button {
                            refreshModels()
                        } label: {
                            Label("刷新模型", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshingModels || !configuration.canRefreshModels)
                        if isRefreshingModels {
                            ProgressView().controlSize(.small)
                            Text("正在读取当前账户可用模型…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !modelRefreshMessage.isEmpty {
                            Text(modelRefreshMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("可直接选择推荐模型，也可手动填写任意模型 ID。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if configuration.aiProvider != .ollama {
                        LabeledContent {
                            SecureField("", text: $configuration.openAIKey)
                                .labelsHidden()
                        } label: {
                            CredentialLabel(title: "API Key") {
                                showAIKeyHelp(configuration.aiProvider)
                            }
                        }
                    }
                    HStack {
                        Text(configuration.aiProvider.helpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("测试 AI 连接") {
                            let result = controller.testAIConnection(configuration)
                            let alert = NSAlert()
                            alert.messageText = appString(result.success ? "AI 连接成功" : "AI 连接失败")
                            alert.informativeText = result.message
                            alert.alertStyle = result.success ? .informational : .warning
                            alert.addButton(withTitle: appString("好"))
                            if let window = NSApp.keyWindow {
                                alert.beginSheetModal(for: window)
                            } else {
                                alert.runModal()
                            }
                        }
                        .disabled(!configuration.isAIValid)
                    }
                    HStack {
                        Text("润色提示词").fontWeight(.medium)
                        Spacer()
                        Text(isPolishPromptSaved ? "已保存" : "未保存")
                            .font(.caption)
                            .foregroundStyle(isPolishPromptSaved ? Color.secondary : Color.orange)
                        Button("保存提示词") {
                            do {
                                try controller.savePolishPrompt(configuration)
                                savedPolishPrompt = configuration.polishPrompt
                                polishPromptSaveError = ""
                            } catch {
                                polishPromptSaveError = appFormat("保存失败：%@", error.localizedDescription)
                            }
                        }
                        Button("恢复默认") {
                            configuration.polishPrompt = SyncConfiguration.defaultPolishPrompt()
                        }
                    }
                    TextEditor(text: $configuration.polishPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 190)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25))
                        }
                    Text("使用 {{text}} 表示闪念原文；没有占位符时，程序会自动把原文附在提示词末尾。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !polishPromptSaveError.isEmpty {
                        Text(polishPromptSaveError)
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 680, height: configuration.polishEnabled ? 700 : 500)
        .padding()
        .onAppear {
            configuration = SyncConfiguration.load()
            discoveredModelIDs = []
            modelRefreshMessage = ""
            savedPolishPrompt = configuration.polishPrompt
            polishPromptSaveError = ""
            refreshLocalizedWindowChrome()
        }
        .onChange(of: configuration) { oldConfiguration, newConfiguration in
            if hasAutomaticSaveChange(from: oldConfiguration, to: newConfiguration) {
                scheduleAutoSave(newConfiguration)
            }
        }
        .onChange(of: configuration.polishPrompt) { _, _ in
            polishPromptSaveError = ""
        }
        .onChange(of: appLanguageRaw) { oldLanguage, newLanguage in
            let oldDefault = SyncConfiguration.defaultPolishPrompt(languageCode: oldLanguage)
            if configuration.polishPrompt.trimmingCharacters(in: .whitespacesAndNewlines) == oldDefault {
                configuration.polishPrompt = SyncConfiguration.defaultPolishPrompt(languageCode: newLanguage)
            }
            refreshLocalizedWindowChrome()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            controller.autoSave(configuration)
        }
    }

    private func scheduleAutoSave(_ configuration: SyncConfiguration) {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            controller.autoSave(configuration)
        }
    }

    private var isPolishPromptSaved: Bool {
        configuration.polishPrompt == savedPolishPrompt
    }

    private func hasAutomaticSaveChange(from oldConfiguration: SyncConfiguration, to newConfiguration: SyncConfiguration) -> Bool {
        var oldConfiguration = oldConfiguration
        var newConfiguration = newConfiguration
        oldConfiguration.polishPrompt = ""
        newConfiguration.polishPrompt = ""
        return oldConfiguration != newConfiguration
    }

    private func refreshLocalizedWindowChrome() {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }) {
                window.title = appString("闪念同步设置")
            }
            guard let mainMenu = NSApp.mainMenu else { return }
            let english = effectiveLanguageCode() == "en"
            let titles = english
                ? ["IdeaSync", "Edit", "View", "Window", "Help"]
                : ["闪念同步", "编辑", "显示", "窗口", "帮助"]
            for (item, title) in zip(mainMenu.items, titles) {
                item.title = title
            }
        }
    }

    private func showCredentialHelp(_ kind: CredentialHelpKind) {
        let alert = NSAlert()
        alert.messageText = appString(kind.title)
        alert.informativeText = appString(kind.instructions)
        alert.alertStyle = .informational
        alert.addButton(withTitle: appString(kind.link == nil ? "取消" : "打开获取页面"))
        if kind.link != nil {
            alert.addButton(withTitle: appString("取消"))
        }
        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn, let link = kind.link else { return }
            NSWorkspace.shared.open(link)
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func showAIKeyHelp(_ provider: AIProvider) {
        let alert = NSAlert()
        alert.messageText = appFormat("如何获取 %@ API Key", provider.label)
        alert.informativeText = provider.apiKeyInstructions
        alert.alertStyle = .informational
        alert.addButton(withTitle: appString(provider.apiKeyURL == nil ? "知道了" : "打开获取页面"))
        if provider.apiKeyURL != nil {
            alert.addButton(withTitle: appString("取消"))
        }
        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn, let url = provider.apiKeyURL else { return }
            NSWorkspace.shared.open(url)
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private var suggestedModels: [String] {
        let models = configuration.aiProvider.recommendedModels + discoveredModelIDs
        let withCurrent = configuration.openAIModel.isEmpty ? models : [configuration.openAIModel] + models
        return Array(NSOrderedSet(array: withCurrent).compactMap { $0 as? String })
    }

    private var modelFieldWidth: CGFloat {
        let minimumWidth: CGFloat = 220
        let maximumWidth: CGFloat = 360
        let estimatedWidth = CGFloat(max(configuration.openAIModel.count, 16)) * 10 + 55
        return min(max(estimatedWidth, minimumWidth), maximumWidth)
    }

    private func refreshModels() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        isRefreshingModels = true
        modelRefreshMessage = ""
        controller.refreshAIModels(configuration) { result in
            isRefreshingModels = false
            switch result {
            case .success(let models):
                discoveredModelIDs = models
                modelRefreshMessage = models.isEmpty
                    ? appString("服务商没有返回可用于文本润色的模型；你仍可手动填写。")
                    : appFormat("已读取 %d 个当前账户可用模型。", models.count)
            case .failure(let error):
                modelRefreshMessage = appFormat("读取模型失败：%@；仍可手动填写。", error.localizedDescription)
            }
        }
    }
}

private struct AIProviderPopUpButton: NSViewRepresentable {
    let selection: AIProvider
    let onSelect: (AIProvider) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: AIProvider.allCases.map(\.label))
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.isBordered = false
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        if let index = AIProvider.allCases.firstIndex(of: selection) {
            button.selectItem(at: index)
        }
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let titles = AIProvider.allCases.map(\.label)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        guard let index = AIProvider.allCases.firstIndex(of: selection), button.indexOfSelectedItem != index else { return }
        button.selectItem(at: index)
    }

    final class Coordinator: NSObject {
        var parent: AIProviderPopUpButton

        init(parent: AIProviderPopUpButton) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard AIProvider.allCases.indices.contains(index) else { return }
            parent.onSelect(AIProvider.allCases[index])
        }
    }
}

private struct AIModelComboBox: NSViewRepresentable {
    @Binding var text: String
    let models: [String]
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox(frame: .zero)
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.placeholderString = placeholder
        comboBox.delegate = context.coordinator
        comboBox.stringValue = text
        comboBox.addItems(withObjectValues: models)
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.parent = self
        comboBox.placeholderString = placeholder
        if comboBox.objectValues.compactMap({ $0 as? String }) != models {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: models)
        }
        if comboBox.stringValue != text { comboBox.stringValue = text }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: AIModelComboBox

        init(parent: AIModelComboBox) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox, parent.text != comboBox.stringValue else { return }
            parent.text = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox, parent.text != comboBox.stringValue else { return }
            parent.text = comboBox.stringValue
        }
    }
}

private struct CredentialLabel: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(appString(title))
            Button("如何获取？", action: action)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
    }
}

private enum CredentialHelpKind {
    case ideaShell
    case tanaToken
    case tanaNodeID

    var title: String {
        switch self {
        case .ideaShell: "如何获取闪念贝壳 API Key"
        case .tanaToken: "如何获取 Tana Write API Token"
        case .tanaNodeID: "如何获取 Tana 目标节点 ID"
        }
    }

    var instructions: String {
        switch self {
        case .ideaShell:
            "1. 登录闪念贝壳网页版。\n2. 打开“设置”。\n3. 点击左侧的“MCP”。\n4. 在页面最下方找到 API Key，点击“复制”。\n5. 返回这里粘贴。"
        case .tanaToken:
            "1. 打开 Tana 设置。\n2. 进入“API Tokens”。\n3. 选择要同步到的工作区。\n4. 点击“Create token”。\n5. 复制生成的 Token 并粘贴到这里。"
        case .tanaNodeID:
            "最简单的方式是填写 INBOX，笔记会进入 Tana 收件箱。\n\n如需指定节点：在 Tana 中对目标节点执行“Copy link”，复制链接里 nodeid= 后面的内容。"
        }
    }

    var link: URL? {
        switch self {
        case .ideaShell: URL(string: "https://ideashell.site")
        case .tanaToken, .tanaNodeID: nil
        }
    }
}

private struct AIConnectionTestResult {
    let success: Bool
    let message: String
}

private struct AIModelListPayload: Decodable {
    let models: [String]
}

@MainActor
final class SyncController: ObservableObject {
    @Published var isSyncing = false
    @Published var isSaving = false
    @Published var isAutomaticSyncEnabled = false
    @Published var automaticSyncIntervalMinutes = 5
    @Published var dailySyncHour = 9
    @Published var dailySyncMinute = 0
    @Published var message = ""
    @Published var hasError = false
    @Published var lastSync: Date?
    @Published var lastPostedCount = 0
    @Published var lastPendingCount = 0
    @Published var lastErrorSummary = ""
    @Published var todayNew = 0
    @Published var todayPosted = 0
    @Published var todayPending = 0
    @Published var todayFailed = 0
    @Published var totalSynced = 0
    @Published var weekSynced = 0

    private let serviceLabel = "com.ideashell-tana-sync"
    private let legacyServiceLabel = "com.coco.ideashell-tana-sync"
    private let baseDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ideashell-tana-sync")
    private let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ideashell-tana-sync")

    var isConfigured: Bool { SyncConfiguration.load().isValid }
    var nodeStatus: String { appString("原生同步引擎已就绪，无需安装 Node.js。") }
    var statusIcon: String { isSyncing ? "arrow.triangle.2.circlepath" : (hasError ? "exclamationmark.triangle.fill" : (lastPendingCount > 0 ? "hourglass" : "checkmark.circle.fill")) }
    var statusColor: Color { isSyncing ? .accentColor : (hasError ? .red : (lastPendingCount > 0 ? .orange : .green)) }
    var syncModeLabel: String { appString(isAutomaticSyncEnabled ? "自动同步" : "手动同步") }
    var dailySyncTime: Date {
        Calendar.current.date(bySettingHour: dailySyncHour, minute: dailySyncMinute, second: 0, of: Date()) ?? Date()
    }

    init() { refreshStatus() }

    func refreshStatus() {
        isAutomaticSyncEnabled = launchAgentExists()
        let configuration = SyncConfiguration.load()
        automaticSyncIntervalMinutes = configuration.automaticSyncIntervalMinutes
        dailySyncHour = configuration.dailySyncHour
        dailySyncMinute = configuration.dailySyncMinute
        let history = SyncHistorySnapshot.load()
        totalSynced = history.totalSynced
        weekSynced = history.weekSynced
        todayNew = 0
        todayPosted = 0
        todayPending = 0
        todayFailed = 0
        if let status = SyncRunStatus.load(from: baseDirectory.appendingPathComponent(".ideashell-tana-status.json")) {
            lastSync = ISO8601DateFormatter().date(from: status.updatedAt)
            lastPostedCount = status.postedNotes ?? 0
            lastPendingCount = status.pendingNotes ?? 0
            hasError = status.status == "error" || !(status.warnings ?? []).isEmpty
            lastErrorSummary = status.error ?? status.warnings?.first ?? ""
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if status.todayDate == formatter.string(from: Date()) {
                todayNew = status.todayNew ?? 0
                todayPosted = status.todayPosted ?? 0
                todayPending = status.todayPending ?? 0
                todayFailed = status.todayFailed ?? 0
            }
            return
        }
        let logURL = logsDirectory.appendingPathComponent("sync.log")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let date = attributes[.modificationDate] as? Date {
            lastSync = date
        }
        let errorURL = logsDirectory.appendingPathComponent("sync.err.log")
        if let errorText = try? String(contentsOf: errorURL, encoding: .utf8), !errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let errorDate = ((try? FileManager.default.attributesOfItem(atPath: errorURL.path))?[.modificationDate] as? Date) ?? .distantPast
            hasError = errorDate > (lastSync ?? .distantPast)
        } else { hasError = false }
    }

    func autoSave(_ configuration: SyncConfiguration) {
        guard configuration.isValid,
              !configuration.polishEnabled || configuration.isAIValid
        else {
            isSaving = false
            message = appString("请补全必要信息，当前可用配置未被覆盖。")
            hasError = false
            return
        }
        save(configuration, syncAfterSave: false, savePolishPrompt: false)
    }

    func savePolishPrompt(_ configuration: SyncConfiguration) throws {
        try Self.installRuntimeFiles(baseDirectory: baseDirectory, logsDirectory: logsDirectory)
        try configuration.writePolishPrompt(to: baseDirectory.appendingPathComponent("polish-prompt.md"))
    }

    fileprivate func testAIConnection(_ configuration: SyncConfiguration) -> AIConnectionTestResult {
        guard configuration.isAIValid else {
            return AIConnectionTestResult(
                success: false,
                message: appString(configuration.aiProvider == .ollama ? "请填写 Ollama 地址和模型名称。" : "请填写 AI 地址、模型名称和 API Key。")
            )
        }
        let startedAt = Date()
        do {
            try Self.installRuntimeFiles(baseDirectory: baseDirectory, logsDirectory: logsDirectory)
            try NativeSync.testAI(configuration: configuration.nativeValues, promptURL: baseDirectory.appendingPathComponent("polish-prompt.md"))
            let elapsedText = String(format: "%.1f", Date().timeIntervalSince(startedAt))
            return AIConnectionTestResult(success: true, message: appFormat("连接成功，用时 %@ 秒。", elapsedText))
        } catch {
            let elapsedText = String(format: "%.1f", Date().timeIntervalSince(startedAt))
            return AIConnectionTestResult(success: false, message: appFormat("连接失败（%@ 秒）：%@", elapsedText, error.localizedDescription))
        }
    }

    func refreshAIModels(_ configuration: SyncConfiguration, completion: @escaping (Result<[String], Error>) -> Void) {
        guard configuration.canRefreshModels else {
            completion(.failure(NSError(domain: "IdeaShellTana", code: 1, userInfo: [NSLocalizedDescriptionKey: appString("请先填写 API 地址和 API Key。")])) )
            return
        }
        let baseDirectory = baseDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<[String], Error>
            do {
                try Self.installRuntimeFiles(baseDirectory: baseDirectory, logsDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ideashell-tana-sync"))
                result = .success(try NativeSync.models(configuration: configuration.nativeValues))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func save(_ configuration: SyncConfiguration, syncAfterSave: Bool, savePolishPrompt: Bool = true) {
        guard configuration.isValid else {
            message = appString("请填写闪念贝壳 API Key 和 Tana Token。")
            hasError = true
            return
        }
        isSaving = true
        do {
            try Self.installRuntimeFiles(baseDirectory: baseDirectory, logsDirectory: logsDirectory)
            try configuration.write(to: baseDirectory.appendingPathComponent(".env"))
            if savePolishPrompt {
                try configuration.writePolishPrompt(to: baseDirectory.appendingPathComponent("polish-prompt.md"))
            }
            try updateAutomaticSync(
                configuration.automaticSync,
                intervalMinutes: configuration.automaticSyncIntervalMinutes,
                dailyHour: configuration.dailySyncHour,
                dailyMinute: configuration.dailySyncMinute
            )
            try updateLaunchAtLogin(configuration.launchAtLogin)
            message = appString("已自动保存")
            hasError = false
            isAutomaticSyncEnabled = configuration.automaticSync
            automaticSyncIntervalMinutes = configuration.automaticSyncIntervalMinutes
            dailySyncHour = configuration.dailySyncHour
            dailySyncMinute = configuration.dailySyncMinute
            isSaving = false
            if syncAfterSave { syncNow() }
            return
        } catch {
            message = appFormat("保存失败：%@", error.localizedDescription)
            hasError = true
        }
        isSaving = false
    }

    func setAutomaticSync(_ enabled: Bool) {
        guard isConfigured else { return }
        do {
            var configuration = SyncConfiguration.load()
            configuration.automaticSync = enabled
            try configuration.write(to: baseDirectory.appendingPathComponent(".env"))
            try updateAutomaticSync(
                enabled,
                intervalMinutes: configuration.automaticSyncIntervalMinutes,
                dailyHour: configuration.dailySyncHour,
                dailyMinute: configuration.dailySyncMinute
            )
            isAutomaticSyncEnabled = enabled
            message = enabled ? appFormat("已开启%@自动同步。", syncIntervalTitle(configuration.automaticSyncIntervalMinutes)) : appString("已切换为手动同步。")
            hasError = false
        } catch {
            message = appFormat("无法更新自动同步：%@", error.localizedDescription)
            hasError = true
        }
    }

    func setAutomaticSyncInterval(_ minutes: Int) {
        guard isConfigured, SyncConfiguration.availableSyncIntervals.contains(minutes) else { return }
        do {
            var configuration = SyncConfiguration.load()
            configuration.automaticSyncIntervalMinutes = minutes
            try configuration.write(to: baseDirectory.appendingPathComponent(".env"))
            automaticSyncIntervalMinutes = minutes
            if isAutomaticSyncEnabled {
                try updateAutomaticSync(
                    true,
                    intervalMinutes: minutes,
                    dailyHour: configuration.dailySyncHour,
                    dailyMinute: configuration.dailySyncMinute
                )
            }
            message = appFormat("自动同步间隔已改为%@。", syncIntervalTitle(minutes))
            hasError = false
        } catch {
            message = appFormat("无法更新自动同步间隔：%@", error.localizedDescription)
            hasError = true
        }
    }

    func setDailySyncTime(_ date: Date) {
        guard isConfigured else { return }
        do {
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            var configuration = SyncConfiguration.load()
            configuration.dailySyncHour = components.hour ?? 9
            configuration.dailySyncMinute = components.minute ?? 0
            try configuration.write(to: baseDirectory.appendingPathComponent(".env"))
            dailySyncHour = configuration.dailySyncHour
            dailySyncMinute = configuration.dailySyncMinute
            if isAutomaticSyncEnabled && configuration.automaticSyncIntervalMinutes == 1440 {
                try updateAutomaticSync(
                    true,
                    intervalMinutes: 1440,
                    dailyHour: configuration.dailySyncHour,
                    dailyMinute: configuration.dailySyncMinute
                )
            }
            message = appFormat("每天执行时间已改为 %02d:%02d。", dailySyncHour, dailySyncMinute)
            hasError = false
        } catch {
            message = appFormat("无法更新每天执行时间：%@", error.localizedDescription)
            hasError = true
        }
    }

    func syncNow() {
        guard isConfigured else { return }
        isSyncing = true
        message = appString("正在同步…")
        hasError = false
        let baseDirectory = baseDirectory
        let logsDirectory = logsDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try Self.installRuntimeFiles(baseDirectory: baseDirectory, logsDirectory: logsDirectory)
                let output = try NativeSync.run(baseDirectory: baseDirectory)
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.lastSync = Date()
                    self.message = output.newNotes == 0 ? appString("同步完成，没有新的闪念。") : appString("同步完成。")
                    self.refreshStatus()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    self.message = appFormat("同步失败：%@", error.localizedDescription)
                    self.hasError = true
                }
            }
        }
    }

    func openLogs() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logsDirectory)
    }

    private func launchAgentExists() -> Bool {
        let launchAgents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        return FileManager.default.fileExists(atPath: launchAgents.appendingPathComponent("\(serviceLabel).plist").path)
            || FileManager.default.fileExists(atPath: launchAgents.appendingPathComponent("\(legacyServiceLabel).plist").path)
    }

    private func updateAutomaticSync(_ enabled: Bool, intervalMinutes: Int, dailyHour: Int, dailyMinute: Int) throws {
        try Self.installRuntimeFiles(baseDirectory: baseDirectory, logsDirectory: logsDirectory)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(serviceLabel).plist")
        let uid = getuid()
        if enabled {
            try writeLaunchAgent(
                to: plist,
                intervalMinutes: intervalMinutes,
                dailyHour: dailyHour,
                dailyMinute: dailyMinute
            )
            _ = try Self.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(serviceLabel)"], allowFailure: true)
            _ = try Self.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(legacyServiceLabel)"], allowFailure: true)
            try Self.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist.path])
        } else {
            _ = try Self.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(serviceLabel)"], allowFailure: true)
            _ = try Self.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(legacyServiceLabel)"], allowFailure: true)
            try? FileManager.default.removeItem(at: plist)
            try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(legacyServiceLabel).plist"))
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled && service.status != .enabled {
            try service.register()
        } else if !enabled && service.status == .enabled {
            try service.unregister()
        }
    }

    nonisolated private static func installRuntimeFiles(baseDirectory: URL, logsDirectory: URL) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let promptDestination = baseDirectory.appendingPathComponent("polish-prompt.md")
        if !FileManager.default.fileExists(atPath: promptDestination.path) {
            guard let promptSource = Bundle.main.url(forResource: "polish-prompt.md", withExtension: nil) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "polish-prompt.md"])
            }
            try FileManager.default.copyItem(at: promptSource, to: promptDestination)
        }
    }

    private func writeLaunchAgent(to url: URL, intervalMinutes: Int, dailyHour: Int, dailyMinute: Int) throws {
        let intervalSeconds = max(5, intervalMinutes) * 60
        let schedule = if intervalMinutes == 1440 {
            """
              <key>StartCalendarInterval</key><dict>
                <key>Hour</key><integer>\(min(max(dailyHour, 0), 23))</integer>
                <key>Minute</key><integer>\(min(max(dailyMinute, 0), 59))</integer>
              </dict>
            """
        } else {
            "<key>StartInterval</key><integer>\(intervalSeconds)</integer>"
        }
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>\(serviceLabel)</string>
          <key>ProgramArguments</key><array><string>\(Bundle.main.executableURL?.path ?? "")</string><string>--sync-background</string></array>
          <key>WorkingDirectory</key><string>\(baseDirectory.path)</string>
        \(schedule)
          <key>RunAtLoad</key><true/>
          <key>StandardOutPath</key><string>\(logsDirectory.appendingPathComponent("sync.log").path)</string>
          <key>StandardErrorPath</key><string>\(logsDirectory.appendingPathComponent("sync.err.log").path)</string>
        </dict></plist>
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    nonisolated private static func run(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        if process.terminationStatus != 0 && !allowFailure {
            throw NSError(domain: "IdeaShellTana", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        return text
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case deepSeek = "deepseek"
    case openRouter = "openrouter"
    case openAICompatible = "openai-compatible"
    case anthropic
    case gemini
    case ollama

    var id: String { rawValue }
    var label: String {
        let key = switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .openRouter: "OpenRouter"
        case .openAICompatible: "其他 OpenAI 兼容接口"
        case .anthropic: "Anthropic Claude"
        case .gemini: "Google Gemini"
        case .ollama: "Ollama 本地模型"
        }
        return appString(key)
    }
    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .openAICompatible: ""
        case .anthropic: "https://api.anthropic.com/v1/messages"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/models"
        case .ollama: "http://localhost:11434/api/chat"
        }
    }
    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5-mini"
        case .deepSeek: "deepseek-v4-flash"
        case .openRouter: "openrouter/free"
        case .openAICompatible: ""
        case .anthropic: "claude-haiku-4-5-20251001"
        case .gemini: "gemini-3.5-flash"
        case .ollama: "qwen2.5:7b"
        }
    }
    var recommendedModels: [String] {
        switch self {
        case .openAI: ["gpt-5-mini", "gpt-5", "gpt-4o-mini", "gpt-4o"]
        case .deepSeek: ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .openRouter: ["openrouter/free", "openai/gpt-5-mini", "anthropic/claude-haiku-4-5"]
        case .openAICompatible: []
        case .anthropic: ["claude-haiku-4-5-20251001", "claude-sonnet-4-5-20250929"]
        case .gemini: ["gemini-3.5-flash", "gemini-3.5-pro"]
        case .ollama: ["qwen2.5:7b", "qwen3:8b", "llama3.2:3b"]
        }
    }
    var helpText: String {
        let key = switch self {
        case .openAI: "使用 OpenAI 官方 API。"
        case .deepSeek: "使用 DeepSeek 官方 OpenAI 兼容 API。"
        case .openRouter: "通过 OpenRouter 使用不同厂商的模型。模型名称可自行修改。"
        case .openAICompatible: "适用于中转服务及其他兼容 OpenAI Chat Completions 的接口。"
        case .anthropic: "使用 Anthropic 原生 Messages API。"
        case .gemini: "使用 Google Gemini 原生 API。"
        case .ollama: "在这台 Mac 上连接本地 Ollama，不需要 API Key。"
        }
        return appString(key)
    }

    var backendValue: String {
        switch self {
        case .openAI, .deepSeek, .openRouter, .openAICompatible: "openai-compatible"
        case .anthropic: "anthropic"
        case .gemini: "gemini"
        case .ollama: "ollama"
        }
    }

    var apiKeyInstructions: String {
        let key = switch self {
        case .openAI: "登录 OpenAI Platform，进入 API Keys 页面创建并复制 Key。"
        case .deepSeek: "登录 DeepSeek 开放平台，进入 API Keys 页面创建并复制 Key。"
        case .openRouter: "登录 OpenRouter，进入 Keys 页面创建并复制 Key。"
        case .openAICompatible: "请从你使用的中转服务或兼容接口提供商处获取 API Key，并按照对方说明填写 API 地址和模型名称。"
        case .anthropic: "登录 Anthropic Console，进入 API Keys 页面创建并复制 Key。"
        case .gemini: "打开 Google AI Studio 的 API Keys 页面创建并复制 Key。"
        case .ollama: "Ollama 在本机运行，不需要 API Key。"
        }
        return appString(key)
    }

    var apiKeyURL: URL? {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .deepSeek: URL(string: "https://platform.deepseek.com/api_keys")
        case .openRouter: URL(string: "https://openrouter.ai/settings/keys")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .openAICompatible, .ollama: nil
        }
    }
}

struct SyncConfiguration: Equatable {
    static let availableSyncIntervals = [5, 10, 15, 30, 60, 1440]

    var ideaShellToken = ""
    var tanaToken = ""
    var tanaTargetNodeID = "INBOX"
    var polishEnabled = false
    var aiProvider = AIProvider.openAI
    var openAIBaseURL = "https://api.openai.com/v1"
    var openAIModel = "gpt-4o-mini"
    var openAIKey = ""
    var polishPrompt = ""
    var markTransferred = true
    var automaticSync = true
    var automaticSyncIntervalMinutes = 5
    var dailySyncHour = 9
    var dailySyncMinute = 0
    var launchAtLogin = false

    var isValid: Bool { !ideaShellToken.isEmpty && !tanaToken.isEmpty }
    var isAIValid: Bool {
        !openAIBaseURL.isEmpty && !openAIModel.isEmpty && (aiProvider == .ollama || !openAIKey.isEmpty)
    }
    var canRefreshModels: Bool {
        !openAIBaseURL.isEmpty && (aiProvider == .ollama || !openAIKey.isEmpty)
    }

    var nativeValues: [String: String] {
        [
            "OPENAI_POLISH_ENABLED": polishEnabled ? "1" : "0",
            "AI_PROVIDER": aiProvider.backendValue,
            "AI_BASE_URL": openAIBaseURL,
            "AI_MODEL": openAIModel,
            "AI_API_KEY": openAIKey,
            "OPENAI_BASE_URL": openAIBaseURL,
            "OPENAI_MODEL": openAIModel,
            "OPENAI_API_KEY": openAIKey,
        ]
    }

    mutating func selectAIProvider(_ newProvider: AIProvider) {
        guard newProvider != aiProvider else { return }
        aiProvider = newProvider
        openAIKey = ""
        if newProvider == .openAICompatible {
            openAIBaseURL = ""
            openAIModel = ""
        } else {
            openAIBaseURL = newProvider.defaultBaseURL
            openAIModel = newProvider.defaultModel
        }
    }

    static func load() -> SyncConfiguration {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ideashell-tana-sync/.env")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let values = Dictionary(uniqueKeysWithValues: text.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].hasPrefix("#") else { return nil }
            return (parts[0], parts[1])
        })
        var value = SyncConfiguration()
        value.ideaShellToken = values["IDEASHELL_TOKEN"] ?? ""
        value.tanaToken = values["TANA_TOKEN"] ?? ""
        value.tanaTargetNodeID = values["TANA_TARGET_NODE_ID"] ?? "INBOX"
        value.polishEnabled = values["OPENAI_POLISH_ENABLED"] == "1"
        if let preset = values["AI_SERVICE_PRESET"], let provider = AIProvider(rawValue: preset) {
            value.aiProvider = provider
        } else if let legacyProvider = AIProvider(rawValue: values["AI_PROVIDER"] ?? "") {
            value.aiProvider = legacyProvider
        } else {
            value.aiProvider = .openAICompatible
        }
        value.openAIBaseURL = values["AI_BASE_URL"] ?? values["OPENAI_BASE_URL"] ?? value.aiProvider.defaultBaseURL
        value.openAIModel = values["AI_MODEL"] ?? values["OPENAI_MODEL"] ?? value.aiProvider.defaultModel
        value.openAIKey = values["AI_API_KEY"] ?? values["OPENAI_API_KEY"] ?? ""
        let promptURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ideashell-tana-sync/polish-prompt.md")
        value.polishPrompt = (try? String(contentsOf: promptURL, encoding: .utf8)) ?? defaultPolishPrompt()
        value.markTransferred = values["IDEASHELL_MARK_TRANSFERRED"] != "0"
        let savedInterval = Int(values["AUTOMATIC_SYNC_INTERVAL_MINUTES"] ?? "5") ?? 5
        value.automaticSyncIntervalMinutes = availableSyncIntervals.contains(savedInterval) ? savedInterval : 5
        value.dailySyncHour = min(max(Int(values["DAILY_SYNC_HOUR"] ?? "9") ?? 9, 0), 23)
        value.dailySyncMinute = min(max(Int(values["DAILY_SYNC_MINUTE"] ?? "0") ?? 0, 0), 59)
        let launchAgents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        value.automaticSync = FileManager.default.fileExists(atPath: launchAgents.appendingPathComponent("com.ideashell-tana-sync.plist").path)
            || FileManager.default.fileExists(atPath: launchAgents.appendingPathComponent("com.coco.ideashell-tana-sync.plist").path)
        value.launchAtLogin = SMAppService.mainApp.status == .enabled
        return value
    }

    func write(to url: URL) throws {
        let escape = { (text: String) in text.replacingOccurrences(of: "\n", with: "") }
        let text = """
        IDEASHELL_TOKEN=\(escape(ideaShellToken))
        IDEASHELL_MCP_ENDPOINT=https://api.ideashell.cn/ideashell/mcp
        TANA_TOKEN=\(escape(tanaToken))
        TANA_TARGET_NODE_ID=\(escape(tanaTargetNodeID.isEmpty ? "INBOX" : tanaTargetNodeID))
        OPENAI_POLISH_ENABLED=\(polishEnabled ? "1" : "0")
        AI_PROVIDER=\(aiProvider.backendValue)
        AI_SERVICE_PRESET=\(aiProvider.rawValue)
        AI_BASE_URL=\(escape(openAIBaseURL))
        AI_MODEL=\(escape(openAIModel))
        AI_API_KEY=\(escape(openAIKey))
        OPENAI_BASE_URL=\(escape(openAIBaseURL))
        OPENAI_MODEL=\(escape(openAIModel))
        OPENAI_API_KEY=\(escape(openAIKey))
        POLISH_PROMPT_FILE=polish-prompt.md
        IDEASHELL_MARK_TRANSFERRED=\(markTransferred ? "1" : "0")
        IDEASHELL_TRANSFERRED_PREFIX=～～
        AUTOMATIC_SYNC_INTERVAL_MINUTES=\(automaticSyncIntervalMinutes)
        DAILY_SYNC_HOUR=\(dailySyncHour)
        DAILY_SYNC_MINUTE=\(dailySyncMinute)
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func writePolishPrompt(to url: URL) throws {
        let prompt = polishPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPrompt = prompt.isEmpty ? Self.defaultPolishPrompt() : prompt
        try (finalPrompt + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func defaultPolishPrompt(languageCode: String? = nil) -> String {
        let requested = languageCode ?? effectiveLanguageCode()
        let resolved = requested == AppLanguage.system.rawValue ? systemLanguageCode() : requested
        let resource = resolved == AppLanguage.english.rawValue ? "polish-prompt.en.md" : "polish-prompt.md"
        guard let url = Bundle.main.url(forResource: resource, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return resolved == AppLanguage.english.rawValue
                ? "Shorten the text without changing its meaning. Return only the result:\n\n{{text}}"
                : "请在不改变原意的前提下精简下面的文本，只输出润色结果：\n\n{{text}}"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SyncRunStatus: Decodable {
    let status: String
    let updatedAt: String
    let postedNotes: Int?
    let pendingNotes: Int?
    let warnings: [String]?
    let error: String?
    let todayDate: String?
    let todayNew: Int?
    let todayPosted: Int?
    let todayPending: Int?
    let todayFailed: Int?

    static func load(from url: URL) -> SyncRunStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SyncRunStatus.self, from: data)
    }
}
