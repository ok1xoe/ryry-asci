// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Writes frames to the terminal on its own thread and never blocks the caller: while a write is stuck (a slow SSH link) newer frames
/// replace older ones, so the application keeps handling keys (Esc must stop the transmitter at once).
public final class FrameWriter: @unchecked Sendable {
    private let session: TerminalSession
    private let writer: ANSIWriter
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "tuikit.frames")
    private var pending: (buffer: ScreenBuffer, full: Bool)?
    private var running = false
    private var stopped = false
    private var last: ScreenBuffer?                 // only touched on `queue`

    public init(session: TerminalSession, writer: ANSIWriter) { self.session = session; self.writer = writer }

    /// `full` = the terminal contents are no longer known (after a resize): redraw everything.
    public func submit(_ buffer: ScreenBuffer, full: Bool = false) {
        lock.lock()
        if stopped { lock.unlock(); return }
        pending = (buffer, full || (pending?.full ?? false))
        let start = !running
        running = true
        lock.unlock()
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard !stopped, let p = pending else { running = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            if p.full { last = nil }
            let bytes = writer.render(p.buffer, previous: last)
            last = p.buffer
            if !bytes.isEmpty { session.write(bytes) }
        }
    }

    /// No further frames are written (call before the terminal is restored).
    public func stop() { lock.lock(); stopped = true; pending = nil; lock.unlock() }
}
