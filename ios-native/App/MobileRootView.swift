import SwiftUI

enum PreviewStyle {
    static let blue = Color(red: 0.20, green: 0.40, blue: 0.98)
    static let canvas = Color(red: 0.97, green: 0.98, blue: 1.00)
    static let ink = Color(red: 0.08, green: 0.13, blue: 0.23)
    static let muted = Color(red: 0.54, green: 0.60, blue: 0.70)
}

enum WorkMode: String, CaseIterable, Identifiable {
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
    var detail: String {
        switch self {
        case .standard: "处理代码、文件和资料，适合大多数任务。"
        case .ptc: "批量调用工具，整理和汇总结果。"
        case .minimal: "仅使用终端工具，适合测试基础能力。"
        case .cordis: "通过对话编写插件，扩展 DSH。"
        }
    }
    var symbol: String {
        switch self {
        case .standard: "doc.text"
        case .ptc: "chart.bar.xaxis"
        case .minimal: "chevron.left.forwardslash.chevron.right"
        case .cordis: "puzzlepiece.extension"
        }
    }
}

struct DemoSession: Identifiable {
    let id: String
    let title: String
    let workspace: String
    let mode: WorkMode
    let preview: String
    let time: String
    let today: Bool

    static let examples: [Self] = [
        .init(id: "ios", title: "规划 iOS 客户端", workspace: "DSH-plugins", mode: .cordis,
              preview: "先把核心操作放进手机，再逐步适配。", time: "刚刚", today: true),
        .init(id: "relay", title: "检查自建中继连接", workspace: "DSH-plugins", mode: .standard,
              preview: "连接成功，接下来验证蜂窝网络切换。", time: "12:08", today: true),
        .init(id: "quota", title: "优化额度显示", workspace: "DSH-plugins", mode: .ptc,
              preview: "让额度信息更清晰，刷新状态更直观。", time: "10:32", today: true),
        .init(id: "network", title: "整理家庭网络", workspace: "家庭网络", mode: .standard,
              preview: "已整理设备清单与下一步检查事项。", time: "昨天", today: false),
        .init(id: "readme", title: "完善插件使用说明", workspace: "DSH-plugins", mode: .minimal,
              preview: "安装、卸载与残留路径已经列清楚。", time: "昨天", today: false),
    ]
}

struct MobileRootView: View {
    @State private var sessions = DemoSession.examples

    var body: some View {
        TabView {
            NavigationStack {
                SessionsView(sessions: $sessions)
            }
            .tabItem { Label("会话", systemImage: "bubble.left") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

private struct DeviceToolbar: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(PreviewStyle.muted)
            Text("Mac mini M4")
                .foregroundStyle(PreviewStyle.ink)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

private struct PreviewNotice: View {
    var body: some View {
        Label("界面试用版 · 演示数据 · 尚未连接电脑", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(PreviewStyle.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(PreviewStyle.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SessionsView: View {
    @Binding var sessions: [DemoSession]
    @State private var query = ""
    @State private var modeFilter: WorkMode?
    @State private var showingNew = false

    private var visible: [DemoSession] {
        sessions.filter { session in
            (modeFilter == nil || session.mode == modeFilter) &&
            (query.isEmpty || session.title.localizedCaseInsensitiveContains(query) ||
             session.workspace.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PreviewNotice()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("会话").font(.largeTitle.bold()).foregroundStyle(PreviewStyle.ink)
                        Text("家里的进展，随时继续。")
                            .font(.subheadline).foregroundStyle(PreviewStyle.muted)
                    }
                    Spacer()
                    Button { showingNew = true } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(PreviewStyle.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                    }
                    .accessibilityLabel("新建任务")
                }
                TextField("搜索会话或工作区", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Menu {
                    Button("全部模式") { modeFilter = nil }
                    ForEach(WorkMode.allCases) { mode in
                        Button(mode.title) { modeFilter = mode }
                    }
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(modeFilter?.title ?? "全部模式")
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                }

                sessionGroup("今天", sessions: visible.filter(\.today))
                sessionGroup("昨天", sessions: visible.filter { !$0.today })
                if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .padding(20)
        }
        .background(PreviewStyle.canvas)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { DeviceToolbar() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNew) {
            NewSessionSheet(sessions: $sessions)
        }
    }

    @ViewBuilder
    private func sessionGroup(_ title: String, sessions: [DemoSession]) -> some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("\(title) · \(sessions.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PreviewStyle.muted)
                    .padding(.bottom, 4)
                ForEach(sessions) { session in
                    NavigationLink {
                        ConversationView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: DemoSession
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "bubble.left")
                .font(.title3)
                .foregroundStyle(PreviewStyle.blue)
                .frame(width: 42, height: 42)
                .background(PreviewStyle.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(PreviewStyle.ink)
                    Spacer(minLength: 8)
                    Text(session.time).font(.caption2).foregroundStyle(PreviewStyle.muted)
                }
                Text(session.preview).font(.caption).foregroundStyle(PreviewStyle.muted)
                    .lineLimit(2)
                HStack(spacing: 7) {
                    Text(session.workspace)
                    Text(session.mode.title)
                        .foregroundStyle(PreviewStyle.blue)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(PreviewStyle.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .font(.caption2)
                .foregroundStyle(PreviewStyle.muted)
            }
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct NewSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sessions: [DemoSession]
    @State private var title = ""
    @State private var mode: WorkMode = .standard

    var body: some View {
        NavigationStack {
            Form {
                Section("任务名称") {
                    TextField("例如：检查今天的构建", text: $title)
                }
                Section {
                    ForEach(WorkMode.allCases) { option in
                        Button { mode = option } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.symbol)
                                    .frame(width: 26).foregroundStyle(PreviewStyle.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(PreviewStyle.ink)
                                    Text(option.detail).font(.caption).foregroundStyle(PreviewStyle.muted)
                                }
                                Spacer()
                                if mode == option { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                    }
                } header: { Text("工作模式") }
                  footer: { Text("这里只创建演示任务，不会发送到家里的 DSH。") }
            }
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        sessions.insert(.init(id: UUID().uuidString, title: name, workspace: "DSH-plugins",
                                              mode: mode, preview: "新建的演示任务", time: "刚刚", today: true), at: 0)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct DemoMessage: Identifiable {
    let id = UUID()
    let fromUser: Bool
    let text: String
}

struct ConversationView: View {
    let session: DemoSession
    @State private var draft = ""
    @State private var approval = "pending"
    @State private var messages: [DemoMessage]

    init(session: DemoSession) {
        self.session = session
        if session.id == "ios" {
            _messages = State(initialValue: [
                .init(fromUser: true, text: "帮我做一个专用的手机客户端，保留现在的配对和自建中继。"),
                .init(fromUser: false, text: "可以。先把核心操作放进手机，再逐步适配其他能力。"),
                .init(fromUser: false, text: "首版先让会话、工作模式和任务内批准在手机上好用。"),
            ])
        } else {
            _messages = State(initialValue: [.init(fromUser: false, text: session.preview)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PreviewNotice()
                    HStack {
                        Image(systemName: session.mode.symbol)
                        Text(session.mode.title)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PreviewStyle.blue)
                    ForEach(messages) { message in
                        HStack {
                            if message.fromUser { Spacer(minLength: 44) }
                            Text(message.text)
                                .font(.subheadline)
                                .foregroundStyle(PreviewStyle.ink)
                                .padding(14)
                                .background(message.fromUser ? PreviewStyle.blue.opacity(0.10) : .white,
                                            in: RoundedRectangle(cornerRadius: 15))
                            if !message.fromUser { Spacer(minLength: 30) }
                        }
                    }
                    if session.id == "ios" {
                        approvalCard
                    }
                }
                .padding(18)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("输入消息…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(PreviewStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    messages.append(.init(fromUser: true, text: text))
                    messages.append(.init(fromUser: false, text: "这是界面演示；消息没有发送到电脑。"))
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up")
                        .fontWeight(.bold)
                        .frame(width: 39, height: 39)
                        .background(PreviewStyle.blue, in: Circle())
                        .foregroundStyle(.white)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(.white)
        }
        .background(PreviewStyle.canvas)
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要批准", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PreviewStyle.ink)
            Text("Shell · 运行前端构建")
                .font(.subheadline).foregroundStyle(PreviewStyle.ink)
            Text("检查页面能否正常打包，不修改电脑上的 DSH。")
                .font(.caption).foregroundStyle(PreviewStyle.muted)
            if approval == "pending" {
                HStack {
                    Button("拒绝") { approval = "denied" }
                        .buttonStyle(.bordered)
                    Button("仅允许这次") { approval = "allowed" }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Text(approval == "allowed" ? "已在演示中允许" : "已在演示中拒绝")
                    .font(.caption).foregroundStyle(PreviewStyle.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
    }
}

struct SettingsView: View {
    @State private var relay = "自建中继"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PreviewNotice()
                VStack(alignment: .leading, spacing: 6) {
                    Text("设置").font(.largeTitle.bold()).foregroundStyle(PreviewStyle.ink)
                    Text("连接、插件和使用偏好。")
                        .font(.subheadline).foregroundStyle(PreviewStyle.muted)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Mac mini M4", systemImage: "desktopcomputer")
                        .font(.headline)
                    Text("尚未连接 · 原生版目前只展示界面")
                        .font(.caption).foregroundStyle(PreviewStyle.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 11) {
                    Text("中继").font(.headline)
                    Picker("中继", selection: $relay) {
                        Text("公共中继").tag("公共中继")
                        Text("自建中继").tag("自建中继")
                    }
                    .pickerStyle(.segmented)
                    Text("仅预览开关样式，不会切换实际网络。")
                        .font(.caption).foregroundStyle(PreviewStyle.muted)
                }
                .padding(17)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 7) {
                    Label("插件功能", systemImage: "puzzlepiece.extension")
                        .font(.headline)
                    Text("目前展示设置入口。插件列表、配置和执行仍需接入真实 DSH 服务。")
                        .font(.caption).foregroundStyle(PreviewStyle.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))

                TokenActivityView()
            }
            .padding(20)
        }
        .background(PreviewStyle.canvas)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { DeviceToolbar() }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
