import Foundation

final class PresenceScheduler {
    var onSend: ((Presence) -> Void)?
    var onClear: (() -> Void)?

    private let floor: TimeInterval = 0.25
    private let queue = DispatchQueue(label: "apppresence.scheduler", qos: .utility)
    private let timer: DispatchSourceTimer
    private var pending: Presence?
    private var lastSentAt = Date.distantPast
    private var lastWasClear = true
    private var lastSignature: String?
    private var enabled = true

    init() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.schedule(deadline: .now() + 3600)
        timer.resume()
    }

    deinit { timer.cancel() }

    func submit(_ presence: Presence) {
        queue.async { [weak self] in
            guard let self, self.enabled else { return }
            let wait = self.floor - Date().timeIntervalSince(self.lastSentAt)
            if wait <= 0 {
                self.pending = nil
                self.transmit(presence)
            } else {
                self.pending = presence
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
        guard enabled, let presence = pending else { return }
        pending = nil
        transmit(presence)
    }

    private func transmit(_ presence: Presence) {
        guard presence.signature != lastSignature else { return }
        lastSignature = presence.signature
        lastSentAt = Date()
        lastWasClear = false
        log("send \(presence.details)")
        onSend?(presence)
    }

    private func clearIfNeeded() {
        guard !lastWasClear else { return }
        lastWasClear = true
        lastSignature = nil
        lastSentAt = Date()
        log("clear")
        onClear?()
    }
}
