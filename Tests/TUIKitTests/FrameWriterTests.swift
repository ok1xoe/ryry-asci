// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Darwin
import Foundation
import Testing
@testable import TUIKit

private let caps = Capabilities(colorDepth: .trueColor, unicode: true, mouse: false)

@Suite(.serialized) struct FrameWriterTests {
    @Test func submitNeverBlocksOnAStalledTerminalAndTheLatestFrameWins() throws {
        var master: Int32 = -1, slave: Int32 = -1
        var w = winsize(ws_row: 32, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
        openpty(&master, &slave, nil, nil, &w)
        defer { close(master); close(slave) }
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
        let session = TerminalSession(inputFD: slave, outputFD: slave, caps: caps)
        try session.start(); defer { session.stop() }
        let fw = FrameWriter(session: session, writer: ANSIWriter(caps: caps))
        defer { fw.stop() }
        // nobody reads the master: after a few KB the writer thread blocks — submit() must still return at once
        let t0 = Date()
        for i in 0..<300 {
            var b = ScreenBuffer(width: 100, height: 32)
            for y in 0..<32 { b.put(String(repeating: Character(UnicodeScalar(UInt8(65 + (i + y) % 26))), count: 100), x: 0, y: y,
                                    style: Style(fg: .rgb(UInt8(i % 256), 1, 2)), clip: nil) }
            if i == 299 { b.put("LASTFRAME", x: 0, y: 0, style: .plain, clip: nil) }
            fw.submit(b, full: i % 7 == 0)
        }
        #expect(Date().timeIntervalSince(t0) < 1.0, "submit blocked on the stalled terminal")
        // now the terminal starts reading: the newest frame must arrive (older ones may be dropped)
        var got = Data(); var buf = [UInt8](repeating: 0, count: 65536)
        let end = Date().addingTimeInterval(10)
        while Date() < end, !String(decoding: got, as: UTF8.self).contains("LASTFRAME") {
            let n = read(master, &buf, buf.count)
            if n > 0 { got.append(contentsOf: buf[0..<n]) } else { usleep(5_000) }
        }
        #expect(String(decoding: got, as: UTF8.self).contains("LASTFRAME"))
        let more = Date().addingTimeInterval(0.5)                                          // let the writer finish before stop()
        while Date() < more { if read(master, &buf, buf.count) <= 0 { usleep(5_000) } }
    }

    @Test func writesAfterStopAreIgnored() throws {
        var master: Int32 = -1, slave: Int32 = -1
        openpty(&master, &slave, nil, nil, nil)
        defer { close(master); close(slave) }
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
        let session = TerminalSession(inputFD: slave, outputFD: slave, caps: caps)
        try session.start()
        session.stop()
        var drain = [UInt8](repeating: 0, count: 65536)
        usleep(100_000); while read(master, &drain, drain.count) > 0 {}                 // the enter/leave sequences
        session.write(Array("AFTERSTOP".utf8))
        usleep(150_000)
        let n = read(master, &drain, drain.count)
        #expect(n <= 0, "the session wrote after stop(): \(n > 0 ? String(decoding: drain[0..<n], as: UTF8.self) : "")")
    }
}
