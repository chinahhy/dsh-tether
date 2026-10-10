import SwiftUI

enum MobileStyle {
    static let blue = Color(uiColor: .systemBlue)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let muted = Color.secondary
}

private enum WorkMode: String, CaseIterable, Identifiable {
    case standard, ptc, minimal, cordis
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "标准模式"
        case .ptc: "PTC 模式"
        case .minimal: "极简模式"
        case .cordis: "创造模式"
        }
    }
}

struct MobileRootView: View {
    @StateObject private var model = MobileModel()

    var body: some View {
        TabView {
            NavigationStack {
                SessionsScreen(model: model)
            }
            .tabItem { Label("会话", systemImage: "bubble.left") }

            NavigationStack {
                SettingsScreen(model: model)
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(MobileStyle.blue)
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("知道了") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct DeviceHeader: View {
    @ObservedObject var model: MobileModel

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(MobileStyle.muted)
            Text(model.currentHostName)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(MobileStyle.ink)
            Circle()
                .fill(model.connected ? .green : MobileStyle.muted)
                .frame(width: 6, height: 6)
            Spacer(minLength: 8)
            Text(model.status)
                .font(.caption)
                .foregroundStyle(MobileStyle.muted)
                .lineLimit(1)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SessionsScreen: View {
    @ObservedObject var model: MobileModel
    @State private var query = ""
    @State private var selectedMode: WorkMode?
    @State private var showingCreate = false

    private var visible: [RemoteSession] {
        model.sessions.filter { session in
            (selectedMode == nil || session.mode == selectedMode?.rawValue) &&
            (query.isEmpty ||
             session.title.localizedCaseInsensitiveContains(query) ||
             session.cwd.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DeviceHeader(model: model)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("会话")
                            .font(.largeTitle.bold())
                            .foregroundStyle(MobileStyle.ink)
                        Text("家里的进展，随时继续。")
                            .font(.subheadline)
                            .foregroundStyle(MobileStyle.muted)
                    }
                    Spacer()
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(MobileStyle.blue.opacity(0.09),
                                        in: RoundedRectangle(cornerRadius: 13))
                    }
                    .disabled(!model.connected)
                    .accessibilityLabel("新建任务")
                }

                if !model.connected {
                    Label("请先在设置中配对或连接电脑", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(MobileStyle.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(MobileStyle.card, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    approvalCards
                    TextField("搜索会话或工作区", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Menu {
                        Button("全部模式") { selectedMode = nil }
                        ForEach(WorkMode.allCases) { mode in
                            Button(mode.title) { selectedMode = mode }
                        }
                    } label: {
                        Label(selectedMode?.title ?? "全部模式",
                              systemImage: "line.3.horizontal.decrease")
                            .font(.subheadline)
                    }
                    if visible.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "还没有会话" : "没有匹配的会话",
                            systemImage: "bubble.left"
                        )
                    } else {
                        ForEach(visible) { session in
                            NavigationLink {
                                ConversationScreen(model: model, session: session)
                            } label: {
                                SessionCard(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(MobileStyle.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showingCreate) {
            NewTaskSheet(model: model)
        }
    }

    @ViewBuilder
    private var approvalCards: some View {
        ForEach(model.approvals) { approval in
            ApprovalCard(model: model, approval: approval)
        }
    }
}

private struct SessionCard: View {
    let session: RemoteSession

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "bubble.left")
                .font(.title3)
                .foregroundStyle(MobileStyle.blue)
                .frame(width: 42, height: 42)
                .background(MobileStyle.blue.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MobileStyle.ink)
                    Spacer(minLength: 8)
                    if session.running {
                        Text("进行中").foregroundStyle(MobileStyle.blue)
                    } else {
                        Text(session.updatedAt, style: .relative)
                            .foregroundStyle(MobileStyle.muted)
                    }
                }
                .font(.caption2)
                Text(session.cwd.isEmpty ? "默认工作区" : session.cwd)
                    .font(.caption)
                    .foregroundStyle(MobileStyle.muted)
                    .lineLimit(2)
                Text(WorkMode(rawValue: session.mode)?.title ?? session.mode)
                    .font(.caption2)
                    .foregroundStyle(MobileStyle.blue)
            }
        }
        .padding(15)
        .background(MobileStyle.card, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct ApprovalCard: View {
    @ObservedObject var model: MobileModel
    let approval: PendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要批准", systemImage: "checkmark.shield")
                .font(.headline)
            Text(approval.toolName.isEmpty ? "工具调用" : approval.toolName)
                .font(.subheadline.weight(.semibold))
            Text(approval.reason)
                .font(.caption)
                .foregroundStyle(MobileStyle.muted)
            HStack {
                Button("拒绝") {
                    Task { await model.decide(approval, allow: false) }
                }
                .buttonStyle(.bordered)
                Button("仅允许这次") {
                    Task { await model.decide(approval, allow: true) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MobileStyle.card, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MobileModel
    @State private var title = ""
    @State private var cwd = ""
    @State private var mode: WorkMode = .standard

    var body: some View {
        NavigationStack {
            Form {
                Section("任务名称") {
                    TextField("例如：检查今天的构建", text: $title)
                }
                Section("电脑上的工作目录") {
                    TextField("留空使用 DSH 默认目录", text: $cwd)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("工作模式") {
                    Picker("工作模式", selection: $mode) {
                        ForEach(WorkMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
            }
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task {
                            await model.create(title: title, cwd: cwd, mode: mode.rawValue)
                            if model.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || model.busy)
                }
            }
            .onAppear { cwd = model.sessions.first?.cwd ?? "" }
        }
    }
}

private struct ConversationScreen: View {
    @ObservedObject var model: MobileModel
    let session: RemoteSession
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text(session.cwd)
                        .font(.caption)
                        .foregroundStyle(MobileStyle.muted)
                    ForEach(model.messages) { message in
                        HStack {
                            if message.fromUser { Spacer(minLength: 40) }
                            Text(message.text)
                                .font(.subheadline)
                                .foregroundStyle(MobileStyle.ink)
                                .padding(14)
                                .background(
                                    message.fromUser
                                        ? MobileStyle.blue.opacity(0.14) : MobileStyle.card,
                                    in: RoundedRectangle(cornerRadius: 15)
                                )
                            if !message.fromUser { Spacer(minLength: 30) }
                        }
                    }
                    ForEach(model.approvals) { approval in
                        ApprovalCard(model: model, approval: approval)
                    }
                }
                .padding(18)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("输入消息…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(MobileStyle.card,
                                in: RoundedRectangle(cornerRadius: 12))
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    draft = ""
                    Task { await model.send(text) }
                } label: {
                    Image(systemName: "arrow.up")
                        .fontWeight(.bold)
                        .frame(width: 39, height: 39)
                        .background(MobileStyle.blue, in: Circle())
                        .foregroundStyle(.white)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(MobileStyle.card)
        }
        .background(MobileStyle.canvas)
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("停止", systemImage: "stop.fill") {
                    Task { await model.stop() }
                }
                .labelStyle(.iconOnly)
            }
        }
        .onAppear { model.open(session.id) }
        .onDisappear { model.closeSession() }
    }
}

private struct SettingsScreen: View {
    @ObservedObject var model: MobileModel
    @State private var pairing = ""
    @State private var label = "Mac mini M4"
    @State private var showingClearConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DeviceHeader(model: model)
                Text("设置").font(.largeTitle.bold()).foregroundStyle(MobileStyle.ink)
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.currentHostName, systemImage: "desktopcomputer")
                        .font(.headline)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(MobileStyle.muted)
                    if model.connected {
                        Button("断开连接") { Task { await model.disconnect() } }
                    } else if let id = model.currentHostId {
                        Button("重新连接") { Task { await model.connect(id: id) } }
                            .disabled(model.busy)
                    }
                    ForEach(model.hosts) { host in
                        if host.id != model.currentHostId {
                            Button(host.label) { Task { await model.connect(id: host.id) } }
                                .disabled(model.busy)
                        }
                    }
                }
                .settingsCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("配对新电脑").font(.headline)
                    Text("在 Mac 的「iPhone 远程连接」中生成配对串，整串粘贴到下面。自建中继信息会随配对串一起保存；单独 6 位数字无法连接。已配对过的电脑请点上方「重新连接」。")
                        .font(.caption)
                        .foregroundStyle(MobileStyle.muted)
                    TextField("粘贴完整 DSH Mobile 配对串", text: $pairing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("设备名称", text: $label)
                    Button("配对并连接") {
                        Task {
                            await model.pair(pairing, label: label)
                            if model.connected { pairing = "" }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || pairing.isEmpty)
                }
                .settingsCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("中继").font(.headline)
                    Text("电脑当前配置：\(model.relayMode)")
                    Text("可在家里电脑的 DSH 插件中切换公共或自建中继。")
                        .font(.caption)
                        .foregroundStyle(MobileStyle.muted)
                    Button("刷新状态") { Task { await model.refreshRelay() } }
                        .disabled(!model.connected)
                }
                .settingsCard()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Token 活动", systemImage: "chart.bar.xaxis")
                        .font(.headline)
                    TokenHeatmap(days: model.tokenDays)
                    Text(model.tokenState)
                        .font(.caption)
                        .foregroundStyle(MobileStyle.muted)
                }
                .settingsCard()

                NavigationLink {
                    PluginListScreen(model: model)
                } label: {
                    HStack {
                        Label("插件", systemImage: "puzzlepiece.extension")
                            .font(.headline)
                        Spacer()
                        Text(model.pluginState)
                            .font(.caption)
                            .foregroundStyle(MobileStyle.muted)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                }
                .foregroundStyle(MobileStyle.ink)
                .settingsCard()

                Button("刷新插件与 Token 活动") {
                    Task { await model.refreshDetails() }
                }
                .disabled(!model.connected)
                .font(.caption)

                if !model.hosts.isEmpty {
                    Button("清除本机配对与身份", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .font(.caption)
                }
            }
            .padding(20)
        }
        .background(MobileStyle.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.connected) {
            if model.connected { await model.refreshDetails() }
        }
        .confirmationDialog(
            "清除本机配对？Mac 端记录仍需在电脑上单独撤销。",
            isPresented: $showingClearConfirmation
        ) {
            Button("清除本机配对", role: .destructive) {
                Task { await model.clearPairing() }
            }
        }
    }
}

private struct TokenHeatmap: View {
    let days: [TokenDay]
    @State private var selected: TokenDay?

    private var peak: Int { max(1, days.map(\.tokens).max() ?? 0) }

    private func color(for day: TokenDay) -> Color {
        guard day.tokens > 0 else { return MobileStyle.canvas }
        let ratio = Double(day.tokens) / Double(peak)
        if ratio < 0.25 { return Color.green.opacity(0.28) }
        if ratio < 0.5 { return Color.green.opacity(0.48) }
        if ratio < 0.75 { return Color.green.opacity(0.70) }
        return Color.green
    }

    var body: some View {
        if days.isEmpty {
            Text("暂无可显示的活动记录")
                .font(.caption)
                .foregroundStyle(MobileStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 3) {
                    ForEach(0..<Int(ceil(Double(days.count) / 7)), id: \.self) { week in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { weekday in
                                let index = week * 7 + weekday
                                if index < days.count {
                                    let day = days[index]
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(color(for: day))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 16)
                                        .onTapGesture { selected = day }
                                        .accessibilityLabel("\(day.id)，\(day.tokens) Token，\(day.calls) 次调用")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if let selected {
                    Text("\(selected.id) · \(selected.tokens.formatted()) Token · \(selected.calls) 次调用")
                        .font(.caption)
                        .foregroundStyle(MobileStyle.ink)
                } else {
                    Text("近 91 天 · 颜色越深，用量越高 · 点选方格看详情")
                        .font(.caption2)
                        .foregroundStyle(MobileStyle.muted)
                }
            }
        }
    }
}

private struct PluginListScreen: View {
    @ObservedObject var model: MobileModel

    var body: some View {
        List {
            Section {
                ForEach(model.plugins) { plugin in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(plugin.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(plugin.enabled ? plugin.phase : "已停用")
                                .font(.caption)
                                .foregroundStyle(plugin.phase == "active" ? Color.green : MobileStyle.muted)
                        }
                        Text(plugin.moduleName)
                            .font(.caption2)
                            .foregroundStyle(MobileStyle.muted)
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("电脑上的插件")
            } footer: {
                Text("来自 DSH 0.2.0-rc.2 插件清单；当前仅查看运行状态。")
            }
        }
        .navigationTitle("插件")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.plugins.isEmpty {
                ContentUnavailableView(model.pluginState, systemImage: "puzzlepiece.extension")
            }
        }
        .refreshable { await model.refreshDetails() }
    }
}

private extension View {
    func settingsCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(17)
            .background(MobileStyle.card, in: RoundedRectangle(cornerRadius: 15))
    }
}
