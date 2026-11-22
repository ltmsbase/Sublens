import Foundation
import Network

/// 主 App 与录屏扩展之间的回环传输。
///
/// 正规做法是 App Group 共享容器，但 App Groups 需要付费开发者账号。
/// 为了免费 Apple ID 也能用，这里加了一条 127.0.0.1 的本地 TCP 通道：
/// 扩展把识别结果发到主 App 监听的端口，主 App 收到后照常翻译。
/// 回环地址不触发"本地网络"权限弹窗，也不需要任何 entitlement。
final class BridgeServer {

    static let port: UInt16 = 47821
    static let host = "127.0.0.1"

    private let queue = DispatchQueue(label: "com.sublens.bridge.server", qos: .userInitiated)
    private var listener: NWListener?
    private(set) var isRunning = false

    var onLines: (([RemoteScreenLine]) -> Void)?

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
        isRunning = false
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
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
                if let lines = try? JSONDecoder().decode([RemoteScreenLine].self, from: chunk) {
                    self.onLines?(lines)
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

/// 扩展侧的发送端：维持一条到主 App 的长连接，掉线自动重连。
final class BridgeClient {

    static let shared = BridgeClient()

    private let queue = DispatchQueue(label: "com.sublens.bridge.client", qos: .utility)
    private var connection: NWConnection?
    private var isReady = false
    private var pending: Data?

    func send(_ lines: [RemoteScreenLine]) {
        guard let payload = try? JSONEncoder().encode(lines) else { return }
        var data = payload
        data.append(0x0A)

        queue.async {
            if let connection = self.connection, self.isReady {
                connection.send(content: data, completion: .contentProcessed { _ in })
                return
            }
            self.pending = data
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
                if let pending = self.pending {
                    self.pending = nil
                    connection.send(content: pending, completion: .contentProcessed { _ in })
                }
            case .failed, .cancelled:
                self.isReady = false
                self.connection = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
}
