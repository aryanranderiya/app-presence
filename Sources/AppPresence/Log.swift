import Foundation

private let logFileURL: URL? = {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
    let directory = base.appendingPathComponent("AppPresence", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("app.log")
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    return url
}()

private let logTime: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

private let logLock = NSLock()

func log(_ message: String) {
    logLock.lock()
    defer { logLock.unlock() }
    guard let data = "\(logTime.string(from: Date())) \(message)\n".data(using: .utf8) else { return }
    try? FileHandle.standardError.write(contentsOf: data)
    guard let logFileURL, let handle = try? FileHandle(forWritingTo: logFileURL) else { return }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: data)
    try? handle.close()
}
