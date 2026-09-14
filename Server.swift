import Foundation
import Network

struct ServerLine: Identifiable {
    let id: Int
    let text: String
}

private final class Session {
    enum Stage {
        case handshake
        case status
        case login
        case play
    }

    let connection: NWConnection
    var stream = PacketStream()
    var stage: Stage = .handshake
    var protocolVersion: Int32 = 47
    var keepAlive: Task<Void, Never>?
    var playerName = "Player"

    init(connection: NWConnection) {
        self.connection = connection
    }
}

@MainActor
@Observable
final class Server {
    static let port: NWEndpoint.Port = 25565

    private(set) var lines: [ServerLine] = []
    private(set) var isRunning = false

    var playerCount: Int {
        sessions.values.count { $0.stage == .play }
    }

    private var listener: NWListener?
    private var monitor: NWPathMonitor?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private var nextLineID = 0
    private var lastPathStatus: NWPath.Status?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Telemetry.start()

        if let address = lanAddress() {
            log("listening on \(address):\(Server.port.rawValue)")
        } else {
            log("no Wi-Fi connection")
        }
        startPathMonitor()
        startListener()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        for session in sessions.values {
            session.keepAlive?.cancel()
            disconnect(session)
        }
        sessions.removeAll()

        listener?.cancel()
        listener = nil
        monitor?.cancel()
        monitor = nil
        lastPathStatus = nil
        log("server stopped")
    }

    func clear() {
        lines.removeAll()
    }

    private func disconnect(_ session: Session) {
        let connection = session.connection
        guard session.stage == .play else {
            connection.cancel()
            return
        }
        let reason = Packet.json(["text": "§cServer stopped from the phone"])
        connection.send(content: Packet.frame(id: 0x40, body: Packet.string(reason)),
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated {
                guard let self, path.status != self.lastPathStatus else { return }
                let previous = self.lastPathStatus
                self.lastPathStatus = path.status
                if path.status == .satisfied {
                    if previous != nil { self.log("network restored") }
                } else {
                    self.log("network unavailable")
                }
            }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    private func startListener() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: Server.port)
        } catch {
            log("could not open port \(Server.port.rawValue)")
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .ready:
                    self?.log("port \(Server.port.rawValue) open")
                case .failed(let error):
                    self?.log("port \(Server.port.rawValue) failed: \(error.localizedDescription)")
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        sessions[key] = Session(connection: connection)
        log("connection from \(Server.host(of: connection.endpoint))")
        connection.start(queue: .main)
        receive(key)
    }

    private static func host(of endpoint: NWEndpoint) -> String {
        guard case .hostPort(let host, _) = endpoint else { return "\(endpoint)" }
        return "\(host)".components(separatedBy: "%").first ?? "\(host)"
    }

    private func receive(_ key: ObjectIdentifier) {
        guard let session = sessions[key] else { return }
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, let session = self.sessions[key] else { return }
                if let data, !data.isEmpty {
                    session.stream.append(data)
                    while let packet = session.stream.next() {
                        self.handle(packet, in: session)
                    }
                }
                if isComplete || error != nil {
                    self.close(key)
                } else {
                    self.receive(key)
                }
            }
        }
    }

    private func handle(_ packet: Data, in session: Session) {
        var reader = PacketReader(packet)
        guard let id = reader.varInt() else { return }

        switch session.stage {
        case .handshake:
            guard id == 0x00,
                  let version = reader.varInt(),
                  reader.string() != nil,
                  reader.uint16() != nil,
                  let next = reader.varInt() else { return }
            session.protocolVersion = version
            session.stage = next == 1 ? .status : .login

        case .status:
            if id == 0x00 {
                send(Packet.frame(id: 0x00, body: Packet.string(statusJSON(for: session))), to: session)
            } else if id == 0x01, let token = reader.int64() {
                send(Packet.frame(id: 0x01, body: Packet.int64(token)), to: session)
            }

        case .login:
            if id == 0x00 {
                let name = reader.string() ?? "Player"
                session.playerName = name
                let success = Packet.string(UUID().uuidString.lowercased()) + Packet.string(name)
                send(Packet.frame(id: 0x02, body: success), to: session)
                session.stage = .play
                sendWorld(to: session)
                startKeepAlive(for: session)
                log("\(name) joined the game")
                broadcast("§e\(name) joined the game")
            }

        case .play:
            if id == 0x01, let message = reader.string() {
                log("<\(session.playerName)> \(message)")
                broadcast("§7<§f\(session.playerName)§7> §f\(message)")
            }
        }
    }

    private func sendWorld(to session: Session) {
        let join = Packet.int32(1) + Packet.uint8(1) + Packet.uint8(0) + Packet.uint8(0)
            + Packet.uint8(1) + Packet.string("flat") + Packet.bool(false)
        send(Packet.frame(id: 0x01, body: join), to: session)

        send(Packet.frame(id: 0x05, body: Packet.position(8, 4, 8)), to: session)

        let abilities = Packet.uint8(0x0C) + Packet.float(0.05) + Packet.float(0.1)
        send(Packet.frame(id: 0x39, body: abilities), to: session)

        let column = FlatWorld.column()
        let chunkTail = Packet.bool(true) + Packet.uint16(FlatWorld.sectionMask)
            + Packet.varInt(Int32(column.count)) + column
        for x in -FlatWorld.radius ... FlatWorld.radius {
            for z in -FlatWorld.radius ... FlatWorld.radius {
                let chunk = Packet.int32(Int32(x)) + Packet.int32(Int32(z)) + chunkTail
                send(Packet.frame(id: 0x21, body: chunk), to: session)
            }
        }

        let position = Packet.double(FlatWorld.spawn.x) + Packet.double(FlatWorld.spawn.y)
            + Packet.double(FlatWorld.spawn.z) + Packet.float(0) + Packet.float(0) + Packet.uint8(0)
        send(Packet.frame(id: 0x08, body: position), to: session)
    }

    private func startKeepAlive(for session: Session) {
        session.keepAlive = Task { [weak self] in
            var token: Int32 = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                self.send(Packet.frame(id: 0x00, body: Packet.varInt(token)), to: session)
                token &+= 1
            }
        }
    }

    private func statusJSON(for session: Session) -> String {
        let players = sessions.values.filter { $0.stage == .play }
        let sample = players.map { ["name": $0.playerName, "id": UUID().uuidString.lowercased()] }
        return Packet.json([
            "version": ["name": "iPhone", "protocol": session.protocolVersion],
            "players": ["max": 8, "online": players.count, "sample": sample],
            "description": ["text": Telemetry.motd()]
        ])
    }

    func say(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        broadcast("§b[phone] §f\(trimmed)")
        log("[phone] \(trimmed)")
    }

    private func broadcast(_ text: String) {
        let body = Packet.string(Packet.json(["text": text])) + Packet.uint8(0)
        let packet = Packet.frame(id: 0x02, body: body)
        for session in sessions.values where session.stage == .play {
            send(packet, to: session)
        }
    }

    private func send(_ data: Data, to session: Session) {
        session.connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func close(_ key: ObjectIdentifier) {
        guard let session = sessions.removeValue(forKey: key) else { return }
        session.keepAlive?.cancel()
        session.connection.cancel()
        if session.stage == .play {
            log("\(session.playerName) left the game")
        }
    }

    private func log(_ text: String) {
        lines.append(ServerLine(id: nextLineID, text: text))
        nextLineID += 1
    }
}

private func lanAddress() -> String? {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return nil }
    defer { freeifaddrs(head) }

    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let name = String(cString: p.pointee.ifa_name)
        guard name.hasPrefix("en") || name.hasPrefix("bridge"),
              let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0,
              let ip = String(validatingCString: host), ip != "127.0.0.1" else { continue }
        return ip
    }
    return nil
}
