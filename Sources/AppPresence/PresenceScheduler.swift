import Foundation

final class PresenceScheduler {
    var onSend: ((AppInfo) -> Void)?
    var onClear: (() -> Void)?

    private let floor: TimeInterval = 0.25
    private let queue = DispatchQueue(label: "apppresence.scheduler", qos: .utility)
    private let timer: DispatchSourceTimer
    private var pending: AppInfo?
    private var lastSentAt = Date.distantPast
    private var lastWasClear = true
    private var enabled = true

    init() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.schedule(deadline: .now() + 3600)
        timer.resume()
    }

    deinit { timer.cancel() }

    func submit(_ app: AppInfo) {
        queue.async { [weak self] in
            guard let self, self.enabled else { return }
            let wait = self.floor - Date().timeIntervalSince(self.lastSentAt)
            if wait <= 0 {
                self.pending = nil
                self.transmit(app)
            } else {
                self.pending = app
                self.timer.schedule(deadline: .now() + wait)
            }
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.enabled = isEnabled
            guard !isEnabled else { return }
            self.pending = nil
            self.clearIfNeeded()
        }
    }

    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.clearIfNeeded()
        }
    }

    private func flush() {
        guard enabled, let app = pending else { return }
        pending = nil
        transmit(app)
    }

    private func transmit(_ app: AppInfo) {
        lastSentAt = Date()
        lastWasClear = false
        log("send \(app.name)")
        onSend?(app)
    }

    private func clearIfNeeded() {
        guard !lastWasClear else { return }
        lastWasClear = true
        lastSentAt = Date()
        log("clear")
        onClear?()
    }
}
