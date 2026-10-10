import Combine
import Foundation
import DSHMobileProtocol

struct PairedHost: Codable, Identifiable, Equatable {
    let id: String
    var label: String
    var relayURLs: [String]?
}

@MainActor
final class MobileModel: ObservableObject {
    @Published private(set) var hosts: [PairedHost] = []
    @Published private(set) var currentHostId: String?
    @Published private(set) var status = "尚未连接"
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var sessions: [RemoteSession] = []
    @Published private(set) var messages: [RemoteMessage] = []
    @Published private(set) var approvals: [PendingApproval] = []
    @Published private(set) var relayMode = "未知"
    @Published private(set) var localEndpointId: String?
    @Published private(set) var plugins: [RemotePlugin] = []
    @Published private(set) var pluginState = "连接后读取"
    @Published private(set) var tokenDays: [TokenDay] = []
    @Published private(set) var tokenState = "连接后读取"
    @Published var errorMessage: String?
    @Published var selectedSessionId: String?

    private let transport = TetherTransport()
    private lazy var gateway = DSHGateway(transport: transport)
    private var controlTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?
    private static let hostsKey = "dsh.mobile.pairedHosts.v1"
    private static let currentKey = "dsh.mobile.currentHost.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.hostsKey),
           let saved = try? JSONDecoder().decode([PairedHost].self, from: data) {
            hosts = saved
        }
        currentHostId = UserDefaults.standard.string(forKey: Self.currentKey)
        Task { await refreshLocalEndpointId() }
        if let id = currentHostId, hosts.contains(where: { $0.id == id }) {
            Task { await connect(id: id) }
        }
    }

    func refreshLocalEndpointId() async {
        localEndpointId = try? await transport.localEndpointId()
    }

    var currentHostName: String {
        hosts.first(where: { $0.id == currentHostId })?.label ?? "未连接电脑"
    }

    func pair(_ pairing: String, label: String) async {
        guard let ticket = PairingTicket(raw: pairing) else {
            errorMessage = MobileConnectionError.invalidPairing.localizedDescription
            return
        }
        // The host rejects Pair for an identity that is already on its allowlist.
        // A second tap after PairOK must use Hello, even if the user left the code pasted.
        let known = hosts.contains(where: { $0.id == ticket.endpointId })
        await establish(id: ticket.endpointId, code: known ? nil : ticket.code,
                        label: label, relayURLs: ticket.relayURLs)
    }

    func connect(id: String) async {
        await establish(id: id, code: nil, label: nil,
                        relayURLs: hosts.first(where: { $0.id == id })?.relayURLs ?? [])
    }

    private func establish(id: String, code: String?, label: String?, relayURLs: [String]) async {
        guard !busy else { return }
        busy = true
        status = code == nil ? "正在连接…" : "正在配对…"
        errorMessage = nil
        controlTask?.cancel()
        followTask?.cancel()
        connected = false
        approvals = []
        do {
            try await transport.connect(id: id, pairingCode: code, relayURLs: relayURLs)
            if label != nil {
                let name = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let record = PairedHost(id: id, label: name.isEmpty ? "家里的电脑" : name,
                                        relayURLs: relayURLs)
                if let index = hosts.firstIndex(where: { $0.id == id }) {
                    hosts[index] = record
                } else {
                    hosts.append(record)
                }
            }
            currentHostId = id
            persistHosts()
            connected = true
            status = "已连接"
            controlTask = Task { [weak self] in
                guard let self else { return }
                await self.receiveControl()
            }
            await refresh()
            await refreshRelay()
        } catch {
            status = "连接失败"
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    func disconnect() async {
        controlTask?.cancel()
        followTask?.cancel()
        controlTask = nil
        followTask = nil
        await transport.disconnect()
        connected = false
        status = "已断开"
        approvals = []
        sessions = []
        messages = []
        plugins = []
        pluginState = "连接后读取"
        tokenDays = []
        tokenState = "连接后读取"
    }

    func clearPairing() async {
        await disconnect()
        await transport.clearIdentity()
        hosts = []
        currentHostId = nil
        UserDefaults.standard.removeObject(forKey: Self.hostsKey)
        UserDefaults.standard.removeObject(forKey: Self.currentKey)
        await refreshLocalEndpointId()
    }

    func refresh() async {
        guard connected else { return }
        do {
            sessions = try await gateway.sessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshRelay() async {
        guard connected else { return }
        do {
            let value = try await gateway.relayState()
            relayMode = value.fields["mode"]?.text == "private" ? "自建中继" : "公共中继"
        } catch {
            relayMode = "暂时无法读取"
        }
    }

    func refreshDetails() async {
        guard connected else { return }
        pluginState = "正在读取…"
        tokenState = "正在读取…"
        do {
            let result = try await gateway.plugins()
            guard connected else { return }
            plugins = result
            pluginState = result.isEmpty ? "没有已配置的插件" : "已读取 \(result.count) 项"
        } catch {
            guard connected else { return }
            plugins = []
            pluginState = "电脑未提供插件清单"
        }
        do {
            let result = try await gateway.tokenDays()
            guard connected else { return }
            tokenDays = result
            tokenState = result.isEmpty ? "暂无用量记录" : "来自 dsh-cost-meter"
        } catch {
            guard connected else { return }
            tokenDays = []
            tokenState = "电脑未提供 Token 统计"
        }
    }

    func create(title: String, cwd: String, mode: String) async {
        guard connected else { return }
        busy = true
        defer { busy = false }
        do {
            let id = try await gateway.create(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                cwd: cwd.trimmingCharacters(in: .whitespacesAndNewlines),
                mode: mode
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ id: String) {
        selectedSessionId = id
        messages = []
        followTask?.cancel()
        followTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveSession(id)
        }
    }

    func closeSession() {
        followTask?.cancel()
        followTask = nil
        selectedSessionId = nil
        messages = []
        Task { await refresh() }
    }

    func send(_ text: String) async {
        guard let id = selectedSessionId, connected else { return }
        do {
            try await gateway.prompt(sessionId: id, text: text)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard let id = selectedSessionId, connected else { return }
        do { try await gateway.cancel(sessionId: id) }
        catch { errorMessage = error.localizedDescription }
    }

    func decide(_ approval: PendingApproval, allow: Bool) async {
        guard approvals.contains(approval) else { return }
        approvals.removeAll { $0.id == approval.id }
        do {
            try await transport.decide(id: approval.id, allow: allow)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func receiveControl() async {
        do {
            while !Task.isCancelled {
                let message = try await transport.nextControlMessage()
                switch message {
                case .approval(let id, let tool, let reason):
                    if !approvals.contains(where: { $0.id == id }) {
                        approvals.append(.init(id: id, toolName: tool, reason: reason))
                    }
                case .approvalCancel(let id):
                    approvals.removeAll { $0.id == id }
                default: break
                }
            }
        } catch {
            if !Task.isCancelled {
                connected = false
                status = "连接已断开"
                approvals = []
                errorMessage = error.localizedDescription
            }
        }
    }

    private func receiveSession(_ id: String) async {
        do {
            let stream = try await gateway.follow(sessionId: id)
            for try await value in stream {
                guard selectedSessionId == id else { break }
                switch value.fields["type"]?.text {
                case "snapshot":
                    messages = value.fields["records"]?.items
                        .compactMap(RemoteMessage.init).sorted(by: { $0.id < $1.id }) ?? []
                case "event":
                    if let message = RemoteMessage(value) {
                        messages.removeAll { $0.id == message.id }
                        messages.append(message)
                        messages.sort { $0.id < $1.id }
                    }
                default: break
                }
            }
        } catch {
            if !Task.isCancelled, selectedSessionId == id {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func persistHosts() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: Self.hostsKey)
        }
        UserDefaults.standard.set(currentHostId, forKey: Self.currentKey)
    }
}
