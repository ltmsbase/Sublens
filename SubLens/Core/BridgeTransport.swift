import Foundation
import Network

/// 主 App 与录屏扩展之间的一条消息。
/// - lines：扩展 → 主 App，本轮识别到的文字
/// - audio：扩展 → 主 App，媒体音频片段（16kHz 单声道 Int16，base64）
/// - config：主 App → 扩展，识别区域 / 自动语种 / 是否 OCR / 是否转录媒体声音
struct BridgeEnvelope: Codable {
    var type: String
    var lines: [RemoteScreenLine]?
    var config: ScreenConfigPayload?
    var audio: String?

    static func makeLines(_ lines: [RemoteScreenLine]) -> BridgeEnvelope {
        BridgeEnvelope(type: "lines", lines: lines, config: nil, audio: nil)
    }

    static func makeConfig(_ payload: ScreenConfigPayload) -> BridgeEnvelope {
        BridgeEnvelope(type: "config", lines: nil, config: payload, audio: nil)
    }

    static func makeAudio(_ pcm: Data) -> BridgeEnvelope {
        BridgeEnvelope(type: "audio", lines: nil, config: nil, audio: pcm.base64EncodedString())
    }
}

enum BridgeCodec {
    static func encode(_ envelope: BridgeEnvelope) -> Data? {
        guard var data = try? JSONEncoder().encode(envelope) else { return nil }
        data.append(0x0A)
        return data
    }

    static func decode(_ data: Data) -> BridgeEnvelope? {
        try? JSONDecoder().decode(BridgeEnvelope.self, from: data)
    }
}

/// 主 App 与录屏扩展之间的回环传输。
///
/// 正规做法是 App Group 共享容器，但 App Groups 需要付费开发者账号。
/// 为了免费 Apple ID 也能用，这里加了一条 127.0.0.1 的本地 TCP 通道：
/// 扩展把识别结果发到主 App 监听的端口，主 App 收到后照常翻译；
/// 同一条连接是双向的，主 App 顺带把「识别区域」推回扩展。
/// 回环地址不触发"本地网络"权限弹窗，也不需要任何 entitlement。
final class BridgeServer {

    static let port: UInt16 = 47821
    static let host = "127.0.0.1"

    private let queue = DispatchQueue(label: "com.sublens.bridge.server", qos: .userInitiated)
    private var listener: NWListener?
    private(set) var isRunning = false

    private var connections: [NWConnection] = []
    private var lastConfig: ScreenConfigPayload?

    var onLines: (([RemoteScreenLine]) -> Void)?
    /// 媒体音频片段（16kHz 单声道 Int16）
    var onAudio: ((Data) -> Void)?

    func start() {
        guard !isRunning else { return }
        guard let port = NWEndpoint.Port(rawValue: Self.port) else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.isRunning = true
                }
                if case .failed = state {
                    self?.isRunning = false
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
    }

    /// 把识别区域推给扩展；同时记住它，扩展重连或后启动时自动补发
    func sendConfig(_ payload: ScreenConfigPayload) {
        guard let data = BridgeCodec.encode(.makeConfig(payload)) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.lastConfig = payload
            for connection in self.connections {
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connections.append(connection)

        // 新连上的扩展立即拿到当前的识别区域，避免"用户已经选好了却还在整屏识别"
        if let config = lastConfig,
           let data = BridgeCodec.encode(.makeConfig(config)) {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            let newline = Data([0x0A])
            while let range = accumulated.range(of: newline) {
                let chunk = accumulated.subdata(in: accumulated.startIndex..<range.lowerBound)
                accumulated.removeSubrange(accumulated.startIndex...range.lowerBound)
                if chunk.isEmpty { continue }
                guard let envelope = BridgeCodec.decode(chunk) else { continue }
                if let lines = envelope.lines {
                    self.onLines?(lines)
                } else if let base64 = envelope.audio, let pcm = Data(base64Encoded: base64) {
                    self.onAudio?(pcm)
                }
            }

            if error != nil || isComplete {
                self.drop(connection)
                return
            }
            self.receive(on: connection, buffer: accumulated)
        }
    }

    private func drop(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }
}

/// 扩展侧的发送端：维持一条到主 App 的长连接，掉线自动重连，
/// 同时在这条连接上接收主 App 下发的识别区域。
final class BridgeClient {

    static let shared = BridgeClient()

    private let queue = DispatchQueue(label: "com.sublens.bridge.client", qos: .utility)
    private var connection: NWConnection?
    private var isReady = false
    private var pending: [Data] = []

    /// 收到主 App 下发的识别配置
    var onConfig: ((ScreenConfigPayload) -> Void)?

    /// 发一段媒体音频（16kHz 单声道 Int16）
    func sendAudio(_ pcm: Data) {
        send(.makeAudio(pcm))
    }

    func send(_ envelope: BridgeEnvelope) {
        guard let data = BridgeCodec.encode(envelope) else { return }

        queue.async {
            if let connection = self.connection, self.isReady {
                connection.send(content: data, completion: .contentProcessed { _ in })
                return
            }
            // 没连上就先攒着，但别无限攒（画面文字是快照，攒太多没意义）
            self.pending.append(data)
            if self.pending.count > 4 {
                self.pending.removeFirst(self.pending.count - 4)
            }
            if self.connection == nil {
                self.connect()
            }
        }
    }

    private func connect() {
        connection?.cancel()
        isReady = false
        guard let port = NWEndpoint.Port(rawValue: BridgeServer.port) else { return }

        let connection = NWConnection(host: NWEndpoint.Host(BridgeServer.host), port: port, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isReady = true
                let queued = self.pending
                self.pending.removeAll()
                for data in queued {
                    connection.send(content: data, completion: .contentProcessed { _ in })
                }
                self.receive(on: connection)
            case .failed, .cancelled:
                self.isReady = false
                self.connection = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            let newline = Data([0x0A])
            while let range = accumulated.range(of: newline) {
                let chunk = accumulated.subdata(in: accumulated.startIndex..<range.lowerBound)
                accumulated.removeSubrange(accumulated.startIndex...range.lowerBound)
                if chunk.isEmpty { continue }
                if let envelope = BridgeCodec.decode(chunk),
                   envelope.type == "config",
                   let config = envelope.config {
                    self.onConfig?(config)
                }
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: accumulated)
        }
    }
}
