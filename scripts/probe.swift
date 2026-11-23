import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: probe <client-id> <image-url> [name]")
    exit(1)
}
let clientID = args[1]
let imageURL = args[2]
let appName = args.count > 3 ? args[3] : "Probe"
let startAt = args.count > 4 ? Int(args[4]) : nil

func candidateSockets() -> [String] {
    var out: [String] = []
    let env = ProcessInfo.processInfo.environment
    let tmp = env["TMPDIR"] ?? "/tmp"
    let xdg = env["XDG_RUNTIME_DIR"]
    for n in 0...9 {
        if let xdg { out.append("\(xdg)/discord-ipc-\(n)") }
        out.append("\(tmp)/discord-ipc-\(n)")
        out.append("\(NSHomeDirectory())/Library/Application Support/discord/ipc-\(n)")
        out.append("\(NSHomeDirectory())/Library/Application Support/discordcanary/ipc-\(n)")
        out.append("\(NSHomeDirectory())/Library/Application Support/discordptb/ipc-\(n)")
        out.append("/tmp/discord-ipc-\(n)")
    }
    return out
}

func connect(_ path: String) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < 104 else { close(fd); return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
    }
    if ok != 0 { close(fd); return nil }
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    return fd
}

func readExact(_ fd: Int32, _ count: Int) -> Data? {
    var data = Data(count: count)
    var got = 0
    while got < count {
        let n = data.withUnsafeMutableBytes { read(fd, $0.baseAddress!.advanced(by: got), count - got) }
        if n <= 0 { return nil }
        got += n
    }
    return data
}

func sendFrame(_ fd: Int32, op: UInt32, object: [String: Any]) {
    guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
    var out = Data()
    let len = UInt32(body.count)
    for shift in stride(from: 0, to: 32, by: 8) {
        out.append(UInt8((op >> UInt32(shift)) & 0xff))
    }
    for shift in stride(from: 0, to: 32, by: 8) {
        out.append(UInt8((len >> UInt32(shift)) & 0xff))
    }
    out.append(body)
    _ = out.withUnsafeBytes { write(fd, $0.baseAddress, out.count) }
}

@discardableResult
func readFrame(_ fd: Int32) -> [String: Any]? {
    guard let head = readExact(fd, 8) else { return nil }
    let op = UInt32(head[0]) | UInt32(head[1]) << 8 | UInt32(head[2]) << 16 | UInt32(head[3]) << 24
    let len = UInt32(head[4]) | UInt32(head[5]) << 8 | UInt32(head[6]) << 16 | UInt32(head[7]) << 24
    guard let body = readExact(fd, Int(len)) else { return nil }
    let text = String(data: body, encoding: .utf8) ?? "<binary>"
    print("op=\(op) \(text)")
    return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
}

func isError(_ reply: [String: Any]?) -> Bool {
    (reply?["evt"] as? String) == "ERROR"
}

var fd: Int32?
var used = ""
for path in candidateSockets() where FileManager.default.fileExists(atPath: path) {
    if let handle = connect(path) { fd = handle; used = path; break }
}

guard let socketFD = fd else {
    print("FAIL no Discord IPC socket. Is Discord running?")
    exit(2)
}
print("connected \(used)")

sendFrame(socketFD, op: 0, object: ["v": 1, "client_id": clientID])
guard let ready = readFrame(socketFD) else {
    print("FAIL no handshake reply")
    exit(3)
}
if isError(ready) {
    print("FAIL handshake rejected. The Application ID is wrong or the app was deleted.")
    exit(4)
}

let pid = Int(ProcessInfo.processInfo.processIdentifier)
let nonce = UUID().uuidString

func activity(flat: Bool) -> [String: Any] {
    var fields: [String: Any]
    if flat {
        fields = ["details": appName, "largeImageKey": imageURL, "largeImageText": appName, "instance": true]
    } else {
        fields = ["details": appName, "assets": ["large_image": imageURL, "large_text": appName], "instance": true]
    }
    if let startAt {
        fields["timestamps"] = ["start": startAt]
    }
    return fields
}

print("--- attempt: assets object ---")
sendFrame(socketFD, op: 1, object: [
    "cmd": "SET_ACTIVITY",
    "nonce": nonce,
    "args": ["pid": pid, "activity": activity(flat: false)],
])
let first = readFrame(socketFD)
var ok = !isError(first) && first != nil
print("result: \(ok ? "accepted" : "rejected")")

if !ok {
    let retry = UUID().uuidString
    print("--- attempt: flat keys ---")
    sendFrame(socketFD, op: 1, object: [
        "cmd": "SET_ACTIVITY",
        "nonce": retry,
        "args": ["pid": pid, "activity": activity(flat: true)],
    ])
    let second = readFrame(socketFD)
    ok = !isError(second) && second != nil
    print("result: \(ok ? "accepted" : "rejected")")
}

if ok {
    print("VERDICT external image URL accepted. holding 60s so you can look at Discord.")
    sleep(60)
} else {
    print("VERDICT rejected. Fall back to uploaded Developer Portal assets.")
}

sendFrame(socketFD, op: 1, object: [
    "cmd": "SET_ACTIVITY",
    "nonce": UUID().uuidString,
    "args": ["pid": pid, "activity": NSNull()],
])
sleep(1)
close(socketFD)
