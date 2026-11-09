// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Darwin
import Foundation

public enum TerminalError: Error, Equatable { case notATTY }

/// The escape sequences that put the terminal into the application mode and back.
public enum TerminalModes {
    /// Alternate screen, hidden cursor, bracketed paste and (optionally) SGR mouse reporting.
    public static func enter(mouse: Bool) -> [UInt8] {
        var s = "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h"
        if mouse { s += "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h" }
        return Array(s.utf8)
    }
    public static let leave: [UInt8] = Array("\u{1B}[0m\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?2004l\u{1B}[?25h\u{1B}[?1049l".utf8)
}

// MARK: restoring the terminal when the process dies in a way the session cannot see

private let crashSignals: [Int32] = [SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP]
nonisolated(unsafe) private var crashActive = false
nonisolated(unsafe) private var crashOutFD: Int32 = -1
nonisolated(unsafe) private var crashInFD: Int32 = -1
nonisolated(unsafe) private var crashTermios = termios()
nonisolated(unsafe) private var crashLeave: UnsafeMutablePointer<UInt8>? = nil
nonisolated(unsafe) private var crashLeaveCount = 0
nonisolated(unsafe) private var crashAtexitInstalled = false

/// Async-signal-safe: only write(2) and tcsetattr(3).
private func crashRestore() {
    guard crashActive else { return }
    crashActive = false
    if let p = crashLeave { _ = Darwin.write(crashOutFD, p, crashLeaveCount) }
    var t = crashTermios
    tcsetattr(crashInFD, TCSANOW, &t)
}

private func crashRegister(inFD: Int32, outFD: Int32, termios t: termios) {
    crashInFD = inFD; crashOutFD = outFD; crashTermios = t
    if crashLeave == nil {
        crashLeave = .allocate(capacity: TerminalModes.leave.count)
        crashLeave!.initialize(from: TerminalModes.leave, count: TerminalModes.leave.count)
        crashLeaveCount = TerminalModes.leave.count
    }
    crashActive = true
    if !crashAtexitInstalled { crashAtexitInstalled = true; atexit { crashRestore() } }
    for s in crashSignals { signal(s) { sig in crashRestore(); signal(sig, SIG_DFL); raise(sig) } }
}

private func crashUnregister() {
    crashActive = false
    for s in crashSignals { signal(s, SIG_DFL) }
}

/// Raw mode, the alternate screen, the mouse, resize and termination signals. Everything is undone by `stop()`, by
/// termination signals and at process exit, so the user's terminal is never left broken.
public final class TerminalSession: @unchecked Sendable {
    public let events: AsyncStream<InputEvent>
    /// Called (after the terminal is restored) when SIGTERM/SIGHUP/SIGQUIT/SIGINT arrive. Default: exit(128 + signal).
    public var onTerminate: (@Sendable (Int32) -> Void)?

    private let inputFD: Int32, outputFD: Int32, caps: Capabilities
    private let continuation: AsyncStream<InputEvent>.Continuation
    private let queue = DispatchQueue(label: "tuikit.terminal")
    private let lock = NSLock()
    private let outLock = NSLock()
    private var accepting = false                 // guarded by outLock: only between start() and stop()
    private var saved: termios?
    private var active = false
    private var parser = InputParser()
    private var readSource: DispatchSourceRead?
    private var signalSources: [DispatchSourceSignal] = []
    private var escWork: DispatchWorkItem?
    private static let handledSignals: [Int32] = [SIGTERM, SIGHUP, SIGQUIT, SIGINT, SIGWINCH]

    public init(inputFD: Int32 = 0, outputFD: Int32 = 1, caps: Capabilities) {
        self.inputFD = inputFD; self.outputFD = outputFD; self.caps = caps
        var c: AsyncStream<InputEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
        continuation = c
    }

    public var size: (cols: Int, rows: Int) {
        var w = winsize()
        if ioctl(outputFD, TIOCGWINSZ, &w) == 0, w.ws_col > 0, w.ws_row > 0 { return (Int(w.ws_col), Int(w.ws_row)) }
        let env = ProcessInfo.processInfo.environment
        return (Int(env["COLUMNS"] ?? "") ?? 80, Int(env["LINES"] ?? "") ?? 24)
    }

    public func start() throws {
        guard isatty(inputFD) == 1 else { throw TerminalError.notATTY }
        lock.lock(); defer { lock.unlock() }
        guard !active else { return }
        var t = termios()
        tcgetattr(inputFD, &t)
        saved = t
        var raw = t
        cfmakeraw(&raw)
        raw.c_cc.16 = 1                                       // VMIN
        raw.c_cc.17 = 0                                       // VTIME
        tcsetattr(inputFD, TCSAFLUSH, &raw)
        active = true
        crashRegister(inFD: inputFD, outFD: outputFD, termios: t)
        outLock.lock(); accepting = true; writeLocked(TerminalModes.enter(mouse: caps.mouse)); outLock.unlock()
        installSources()
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        active = false
        escWork?.cancel(); escWork = nil
        readSource?.cancel(); readSource = nil
        signalSources.forEach { $0.cancel() }; signalSources.removeAll()
        for s in Self.handledSignals { signal(s, s == SIGWINCH ? SIG_IGN : SIG_DFL) }
        outLock.lock(); if accepting { writeLocked(TerminalModes.leave); accepting = false }; outLock.unlock()
        if var t = saved { tcsetattr(inputFD, TCSANOW, &t) }      // not DRAIN: the leave bytes contain no newline, and DRAIN would block until the terminal reads
        crashUnregister()
    }

    /// Ctrl+Z: give the terminal back, stop the process, and take the terminal again after `fg`.
    public func suspend() {
        stop()
        raise(SIGSTOP)
        try? start()
        continuation.yield(.resize(cols: size.cols, rows: size.rows))
    }

    /// Ignored when the terminal is not in application mode (before start(), after stop()), so a late frame can never paint over the shell.
    public func write(_ bytes: [UInt8]) {
        outLock.lock(); defer { outLock.unlock() }
        guard accepting else { return }
        writeLocked(bytes)
    }

    private func writeLocked(_ bytes: [UInt8]) {
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBytes { Darwin.write(outputFD, $0.baseAddress, $0.count) }
            if n > 0 { off += n } else if errno == EAGAIN || errno == EINTR { usleep(1000) } else { return }
        }
    }

    // MARK: sources

    private func installSources() {
        let rs = DispatchSource.makeReadSource(fileDescriptor: inputFD, queue: queue)
        rs.setEventHandler { [weak self] in self?.readInput() }
        rs.resume()
        readSource = rs
        for sig in Self.handledSignals {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            s.setEventHandler { [weak self] in
                guard let self else { return }
                if sig == SIGWINCH { self.continuation.yield(.resize(cols: self.size.cols, rows: self.size.rows)); return }
                self.stop()
                if let h = self.onTerminate { h(sig) } else { exit(128 + sig) }
            }
            s.resume()
            signalSources.append(s)
        }
    }

    private func readInput() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(inputFD, &buf, buf.count)
        if n == 0 { continuation.finish(); readSource?.cancel(); return }       // the terminal went away
        guard n > 0 else { return }
        lock.lock()
        let events = parser.feed(Array(buf[0..<n]))
        escWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock(); let ev = self.parser.flushPendingEscape(); self.lock.unlock()
            ev.forEach { self.continuation.yield($0) }
        }
        escWork = work
        lock.unlock()
        events.forEach { continuation.yield($0) }
        queue.asyncAfter(deadline: .now() + 0.04, execute: work)
    }
}
