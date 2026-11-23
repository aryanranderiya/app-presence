import Foundation

final class DiscordRPC {
    private let clientID: String
    private let queue = DispatchQueue(label: "apppresence.rpc", qos: .utility)
    private var fd: Int32 = -1
    private var rxBuffer = Data()
    private var loggedReady = false
    private var retrying = false
    private var lastActivity: Presence?

    init(clientID: String) {
        self.clientID = clientID
    }

    func connect() { queue.async { self.connectOnQueue() } }
    func setActivity(_ presence: Presence) { queue.async { self.sendActivity(presence) } }
    func clearActivity() { queue.async { self.sendActivity(nil) } }

    func shutdown(completion: (() -> Void)? = nil) {
        queue.sync {
            if self.fd >= 0 {
                self.sendActivity(nil)
                _ = self.writeFrame(opcode: 2, body: Data("{}".utf8))
                self.closeSocket()
            }
        }
        completion?()
    }

    private func connectOnQueue() {
        guard fd < 0 else { return }
        guard let (socketFD, path) = Self.openSocket() else {
            if !retrying { log("no discord ipc socket found, retrying every 3s") }
            retrying = true
            retryLater()
            return
        }
        retrying = false
        fd = socketFD
        rxBuffer.removeAll()
        loggedReady = false
        guard writeFrame(opcode: 0, body: Data("{\"v\":1,\"client_id\":\"\(clientID)\"}".utf8)) else {
            closeSocket()
            retryLater()
            return
        }
        log("connected to discord via \(path)")
        DispatchQueue.global(qos: .utility).async { self.readLoop(socketFD) }
    }
    private func retryLater() {
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.connectOnQueue() }
    }
    private func sendActivity(_ presence: Presence?) {
        lastActivity = presence
        guard fd >= 0 else {
            log("discord not connected, holding \(presence?.details ?? "clear")")
            return
        }
        var activity: Any = NSNull()
        if let presence {
            var fields: [String: Any] = [
                "name": presence.name,
                "details": presence.details,
                "assets": ["large_image": presence.iconURL, "large_text": presence.iconText],
                "instance": true,
                "type": presence.type,
            ]
            if let state = presence.state { fields["state"] = state }
            if let startedAt = presence.startedAt {
                fields["timestamps"] = ["start": Int(startedAt.timeIntervalSince1970 * 1000)]
            }
            if !presence.buttons.isEmpty {
                fields["buttons"] = presence.buttons.map { ["label": $0.label, "url": $0.url] }
            }
            activity = fields
        }
        let args: [String: Any] = ["pid": Int(ProcessInfo.processInfo.processIdentifier), "activity": activity]
        let payload: [String: Any] = ["cmd": "SET_ACTIVITY", "nonce": UUID().uuidString, "args": args]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            log("could not encode activity json")
            return
        }
        if !writeFrame(opcode: 1, body: body) { handleDisconnect(fd) }
        log("presence \(presence?.name ?? "clear") / \(presence?.details ?? "") / \(presence?.state ?? "")")
    }
    private func readLoop(_ socketFD: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { recv(socketFD, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                queue.async { self.consume(Data(buffer[0..<count]), socketFD) }
                continue
            }
            if count < 0 && errno == EINTR { continue }
            break
        }
        queue.async { self.handleDisconnect(socketFD) }
    }
    private func consume(_ chunk: Data, _ socketFD: Int32) {
        guard socketFD == fd else { return }
        rxBuffer.append(chunk)
        while rxBuffer.count >= 8 {
            let opcode = rxBuffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }.littleEndian
            let length = Int(rxBuffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }.littleEndian)
            guard length <= 1 << 20 else {
                handleDisconnect(socketFD)
                return
            }
            guard rxBuffer.count >= 8 + length else { return }
            let payload = rxBuffer.subdata(in: 8..<(8 + length))
            rxBuffer.removeSubrange(0..<(8 + length))
            handleFrame(opcode: opcode, payload: payload)
            guard socketFD == fd else { return }
        }
    }
    private func handleFrame(opcode: UInt32, payload: Data) {
        switch opcode {
        case 1:
            guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return }
            if (object["evt"] as? String) == "ERROR" {
                log("discord rejected activity \(object["data"] ?? "?")")
                return
            }
            guard !loggedReady else { return }
            loggedReady = true
            log("discord ready")
            if let last = lastActivity { sendActivity(last) }
        case 2:
            let object = ((try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]) ?? [:]
            log("discord error code=\(object["code"] ?? "?") message=\(object["message"] ?? "?")")
            closeSocket()
            retryLater()
        case 3:
            _ = writeFrame(opcode: 4, body: payload)
        default:
            break
        }
    }
    private func handleDisconnect(_ socketFD: Int32) {
        guard socketFD == fd else { return }
        log("discord connection lost")
        closeSocket()
        retryLater()
    }
    private func closeSocket() {
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR) // wakes the blocked reader
            close(fd)
        }
        fd = -1
        rxBuffer.removeAll()
    }
    private func writeFrame(opcode: UInt32, body: Data) -> Bool {
        guard fd >= 0 else { return false }
        var frame = Data()
        var littleOpcode = opcode.littleEndian
        var littleLength = UInt32(body.count).littleEndian
        withUnsafeBytes(of: &littleOpcode) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: &littleLength) { frame.append(contentsOf: $0) }
        frame.append(body)
        var sent = 0
        return frame.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            while sent < raw.count {
                let count = send(fd, base + sent, raw.count - sent, 0)
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                sent += count
            }
            return true
        }
    }

    private static func openSocket() -> (Int32, String)? {
        for path in candidatePaths() {
            guard path.utf8.count < 104 else { continue }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let fits = path.withCString { pointer -> Bool in
                let size = strlen(pointer) + 1
                guard size <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
                withUnsafeMutableBytes(of: &address.sun_path) {
                    $0.copyBytes(from: UnsafeRawBufferPointer(start: pointer, count: size))
                }
                return true
            }
            guard fits else { continue }
            let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
            guard socketFD >= 0 else { continue }
            var noSigPipe: Int32 = 1
            // Without SO_NOSIGPIPE a send to a dead Discord raises SIGPIPE and kills us.
            setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result == 0 { return (socketFD, path) }
            close(socketFD)
        }
        return nil
    }

    private static func candidatePaths() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        var roots = [environment["TMPDIR"] ?? "/tmp"]
        for app in ["discord", "discordcanary", "discordptb"] { roots.append("\(home)/Library/Application Support/\(app)") }
        roots.append("/tmp")
        if let runtime = environment["XDG_RUNTIME_DIR"], !runtime.isEmpty { roots.append(runtime) }
        var paths: [String] = []
        for index in 0...9 {
            for root in roots {
                paths.append("\(root)/\(root.contains("Application Support") ? "ipc" : "discord-ipc")-\(index)")
            }
        }
        return paths
    }
}
