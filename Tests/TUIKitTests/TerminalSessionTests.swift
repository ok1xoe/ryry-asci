// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Darwin
import Foundation
import Testing
@testable import TUIKit

private let caps = Capabilities(colorDepth: .trueColor, unicode: true, mouse: true)

/// A pseudo terminal: the session works on the slave side, the test plays the terminal on the master side.
private struct PTY {
    var master: Int32 = -1, slave: Int32 = -1
    init(cols: Int = 100, rows: Int = 32) {
        var w = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        openpty(&master, &slave, nil, nil, &w)
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
    }
    func close() { Darwin.close(master); Darwin.close(slave) }
    /// Everything the session wrote so far (waits briefly for it).
    func output(wait: Double = 0.3) -> String {
        var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        let end = Date().addingTimeInterval(wait)
        while Date() < end {
            let n = read(master, &buf, buf.count)
            if n > 0 { data.append(contentsOf: buf[0..<n]) } else { usleep(10_000) }
        }
        return String(decoding: data, as: UTF8.self)
    }
    func type(_ s: String) { let b = Array(s.utf8); _ = write(master, b, b.count) }
    func attrs() -> termios { var t = termios(); tcgetattr(slave, &t); return t }
}

/// PENDIN (0x20000000) is a state flag the kernel sets itself when the mode changes; it is not a setting.
private func same(_ a: termios, _ b: termios) -> Bool {
    let pendin = tcflag_t(0x2000_0000)
    return a.c_iflag == b.c_iflag && a.c_oflag == b.c_oflag && a.c_cflag == b.c_cflag && a.c_lflag & ~pendin == b.c_lflag & ~pendin
}

@Suite(.serialized) struct TerminalSessionTests {
    @Test func leaveSequenceUndoesEverythingEnableDid() {
        let enter = String(decoding: TerminalModes.enter(mouse: true), as: UTF8.self)
        let leave = String(decoding: TerminalModes.leave, as: UTF8.self)
        let modes = enter.components(separatedBy: "\u{1B}[?").dropFirst().filter { $0.hasSuffix("h") }.map { String($0.dropLast()) }
        #expect(modes.count >= 4)
        for m in modes { #expect(leave.contains("\u{1B}[?\(m)l"), "mode \(m) is not turned off") }
        #expect(leave.contains("\u{1B}[?25h"))                            // the cursor is shown again
        #expect(!String(decoding: TerminalModes.enter(mouse: false), as: UTF8.self).contains("?1006h"))
    }

    @Test func startFailsOnNonTTY() {
        let fd = open("/dev/null", O_RDWR); defer { close(fd) }
        let s = TerminalSession(inputFD: fd, outputFD: fd, caps: caps)
        #expect(throws: TerminalError.notATTY) { try s.start() }
    }

    @Test func ptyRoundTripRestoresTermios() throws {
        let pty = PTY(); defer { pty.close() }
        let before = pty.attrs()
        let s = TerminalSession(inputFD: pty.slave, outputFD: pty.slave, caps: caps)
        try s.start()
        #expect(!same(pty.attrs(), before))                               // raw mode is on
        #expect(pty.output().contains("\u{1B}[?1049h"))
        s.stop()
        let after = pty.attrs()
        #expect(same(after, before))
        #expect(pty.output().contains("\u{1B}[?1049l"))
        s.stop()                                                          // a second stop is harmless
    }

    @Test func sizeComesFromThePty() throws {
        let pty = PTY(cols: 120, rows: 40); defer { pty.close() }
        let s = TerminalSession(inputFD: pty.slave, outputFD: pty.slave, caps: caps)
        #expect(s.size.cols == 120 && s.size.rows == 40)
    }

    @Test(.timeLimit(.minutes(1))) func ptyDeliversInputEventsAndLoneEscape() async throws {
        let pty = PTY(); defer { pty.close() }
        let s = TerminalSession(inputFD: pty.slave, outputFD: pty.slave, caps: caps)
        try s.start(); defer { s.stop() }
        var it = s.events.makeAsyncIterator()
        pty.type("\u{1B}[1;2P")
        #expect(await it.next() == .key(.f(1), .shift))
        pty.type("\u{1B}")
        #expect(await it.next() == .key(.escape, []))                     // flushed after the pause
    }

    @Test(.timeLimit(.minutes(1))) func winchSignalEmitsResizeEvent() async throws {
        let pty = PTY(cols: 100, rows: 32); defer { pty.close() }
        let s = TerminalSession(inputFD: pty.slave, outputFD: pty.slave, caps: caps)
        try s.start(); defer { s.stop() }
        var w = winsize(ws_row: 50, ws_col: 150, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(pty.master, TIOCSWINSZ, &w)
        kill(getpid(), SIGWINCH)
        var it = s.events.makeAsyncIterator()
        #expect(await it.next() == .resize(cols: 150, rows: 50))
    }

    @Test(.timeLimit(.minutes(1))) func terminationSignalRestoresTerminalFirst() async throws {
        let pty = PTY(); defer { pty.close() }
        let before = pty.attrs()
        let s = TerminalSession(inputFD: pty.slave, outputFD: pty.slave, caps: caps)
        let got = Locked<Int32?>(nil)
        s.onTerminate = { sig in got.set(sig) }                           // the default would exit the process
        try s.start()
        _ = pty.output(wait: 0.1)
        kill(getpid(), SIGTERM)
        for _ in 0..<100 where got.get() == nil { usleep(20_000) }
        #expect(got.get() == SIGTERM)
        #expect(same(pty.attrs(), before))
        #expect(pty.output().contains("\u{1B}[?1049l"))
    }
}

final class Locked<T>: @unchecked Sendable {
    private var v: T; private let l = NSLock()
    init(_ v: T) { self.v = v }
    func get() -> T { l.lock(); defer { l.unlock() }; return v }
    func set(_ n: T) { l.lock(); v = n; l.unlock() }
}
