//
//  RealtimeClient.swift
//  MilkTeaRadar
//
//  SSE（Server-Sent Events）长连接客户端。
//
//  为什么选 SSE 而不是 WebSocket / 轮询（详见方案文档）：
//    - 本业务数据流是「服务端 -> 客户端」单向的，不需要客户端向服务端推送；
//    - SSE 走普通 HTTP/HTTPS，复用现有网关、鉴权与负载均衡，无需协议升级，
//      对代理 / 企业网络更友好；
//    - EventSource 语义自带事件边界（空行分隔），解析简单可靠；
//    - 浏览器端与移动端可以复用同一套协议，降低服务端维护成本。
//  兜底：SSE 连续失败后自动降级为轮询，避免长连接不可用时完全失去实时性。
//

import Foundation

// MARK: - 连接状态

enum RealtimePhase: Equatable {
    case idle
    case connecting
    case open
    case polling(reason: String)          // 降级轮询
    case reconnecting(attempt: Int, delay: TimeInterval)
    case closed(reason: String)
}

// MARK: - 事件

struct RealtimeEvent: Decodable {
    let type: String
    let version: Int
    let ts: String?
    let payload: RealtimePayload?

    struct RealtimePayload: Decodable {
        let deals: [Deal]?
        let changed: [String]?
        let removed: [String]?
    }
}

// MARK: - 客户端

@MainActor
final class RealtimeClient: ObservableObject {

    // 回调
    var onDeals: (([Deal], Int) -> Void)?     // 全量/增量合并后的结果 + 版本号
    var onPhaseChange: ((RealtimePhase) -> Void)?

    @Published private(set) var phase: RealtimePhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    @Published private(set) var lastMessageAt: Date?

    // MARK: 可调参数（与 Android 端保持一致）
    private let connectTimeout: TimeInterval = Config.requestTimeout   // 8s
    private let maxRetries = Config.maxRetries                          // 3
    private let backoffBase: TimeInterval = Config.backoffBase           // 0.4
    private let backoffMax: TimeInterval = Config.backoffMax            // 6
    private let heartbeatTimeout: TimeInterval = Config.heartbeatTimeout // 60
    private let pollInterval: TimeInterval = Config.pollInterval         // 30

    private var listenTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var retryCount = 0
    private var stopped = false
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = connectTimeout
        cfg.timeoutIntervalForResource = .greatestFiniteMagnitude  // 长连接不设资源超时
        cfg.waitsForConnectivity = false
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    // MARK: 生命周期

    func start() {
        // 未配置 SSE 端点（如静态托管场景）时直接走轮询，避免无谓的失败重连
        guard !Config.realtimeURL.isEmpty else {
            phase = .polling(reason: "未配置实时端点，已启用轮询")
            startPolling()
            return
        }
        stopped = false
        openStream()
    }

    func stop() {
        stopped = true
        listenTask?.cancel(); listenTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        pollTask?.cancel(); pollTask = nil
        phase = .closed(reason: "已停止")
    }

    /// 应用回到前台 / 网络恢复时调用：若数据已陈旧则立即补偿刷新
    func resumeIfNeeded(isStale: Bool) {
        guard !stopped else { return }
        if isStale {
            retryCount = 0
            openStream()
        }
    }

    // MARK: SSE 主循环

    private func openStream() {
        guard !stopped else { return }
        listenTask?.cancel()
        phase = .connecting

        guard let url = URL(string: Config.realtimeURL) else {
            phase = .closed(reason: "长连接地址无效")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.timeoutInterval = connectTimeout

        listenTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (bytes, response) = try await self.session.bytes(for: req)

                // 非 2xx 不视为长连接建立成功
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw NetworkError.http(status: http.statusCode)
                }

                await MainActor.run {
                    self.retryCount = 0
                    self.phase = .open
                    self.lastMessageAt = Date()
                }
                self.startHeartbeatMonitor()

                // 逐行读取：SSE 以空行分隔事件，data: 行可出现多次
                var dataLines: [String] = []
                for try await rawLine in bytes.lines {
                    await MainActor.run { self.lastMessageAt = Date() }

                    let line = rawLine.trimmingCharacters(in: .newlines)

                    if line.isEmpty {
                        // 事件结束
                        if !dataLines.isEmpty {
                            let payload = dataLines.joined(separator: "\n")
                            dataLines.removeAll()
                            self.handle(payload: payload)
                        }
                        continue
                    }
                    if line.hasPrefix(":") { continue }          // 心跳注释行
                    if line.hasPrefix("data:") {
                        dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                    }
                }

                // 正常读到流末尾（服务端关闭）→ 视为断开，进入重连
                throw NetworkError.offline

            } catch is CancellationError {
                return
            } catch let e as NetworkError {
                self.handleFailure(e)
            } catch {
                self.handleFailure(NetworkError.map(error))
            }
        }
    }

    // MARK: 事件处理

    private func handle(payload: String) {
        guard let data = payload.data(using: .utf8) else { return }
        do {
            let event = try JSONDecoder().decode(RealtimeEvent.self, from: data)
            switch event.type {
            case "deals.snapshot":
                // 全量快照：直接替换
                if let deals = event.payload?.deals {
                    onDeals?(deals, event.version)
                }
            case "deals.updated":
                // 增量：交给 Repository 按 version 与 updated_at 合并
                if let payload = event.payload {
                    NotificationCenter.default.post(
                        name: .dealsIncrementalUpdate,
                        object: nil,
                        userInfo: [
                            "deals": payload.deals ?? [],
                            "changed": payload.changed ?? [],
                            "removed": payload.removed ?? [],
                            "version": event.version
                        ]
                    )
                }
            case "heartbeat":
                lastMessageAt = Date()
            default:
                break
            }
        } catch {
            // 单条事件解析失败不应影响整体连接
            print("[realtime] 事件解析失败: \(error)")
        }
    }

    // MARK: 心跳监控

    private func startHeartbeatMonitor() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !self.stopped else { return }
                if let last = await MainActor.run(body: { self.lastMessageAt }),
                   Date().timeIntervalSince(last) > self.heartbeatTimeout {
                    // 长时间静默：连接大概率已死，主动重连
                    print("[realtime] 心跳超时，重连")
                    await MainActor.run { self.phase = .reconnecting(attempt: 1, delay: self.backoffBase) }
                    self.openStream()
                    return
                }
            }
        }
    }

    // MARK: 失败与重连

    private func handleFailure(_ error: NetworkError) {
        guard !stopped else { return }

        if error.isRetryable && retryCount < maxRetries {
            retryCount += 1
            let delay = backoff(retryCount - 1)
            phase = .reconnecting(attempt: retryCount, delay: delay)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !self.stopped else { return }
                self.openStream()
            }
        } else {
            // 长连接连续失败 -> 降级为轮询，保证弱网/受限网络下仍可用
            phase = .polling(reason: "长连接不可用，已切换为每 \(Int(pollInterval)) 秒轮询")
            startPolling()
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.stopped else { return }
                do {
                    let doc = try await APIClient.shared.fetchDeals()
                    await MainActor.run { self.onDeals?(doc.deals, doc.version) }
                } catch {
                    // 轮询失败保持现有缓存，等待下一轮
                }
                try? await Task.sleep(nanoseconds: UInt64(Config.pollInterval * 1_000_000_000))
            }
        }
    }

    private func backoff(_ attempt: Int) -> TimeInterval {
        min(backoffBase * pow(2.0, Double(attempt)), backoffMax)
    }
}

extension Notification.Name {
    static let dealsIncrementalUpdate = Notification.Name("dealsIncrementalUpdate")
}
