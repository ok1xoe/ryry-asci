// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Testing
@testable import TUIKit

private let esc = "\u{1B}"
private func text(_ b: [UInt8]) -> String { String(decoding: b, as: UTF8.self) }
private func writer(_ d: ColorDepth = .ansi256) -> ANSIWriter { ANSIWriter(caps: Capabilities(colorDepth: d, unicode: true, mouse: true)) }
private func blank(_ w: Int = 5, _ h: Int = 2) -> ScreenBuffer { ScreenBuffer(width: w, height: h) }

@Test func identicalBuffersProduceNoBytes() { #expect(writer().render(blank(), previous: blank()).isEmpty) }

@Test func singleChangedCellEmitsCursorMoveAndChar() {
    var b = blank(); b[x: 3, y: 1] = Cell(char: "X")
    #expect(text(writer().render(b, previous: blank())) == "\(esc)[2;4HX")
}

@Test func sameStyleRunsShareOneSGR() {
    var b = blank(); let red = Style(fg: .indexed(1))
    b.put("ab", x: 0, y: 0, style: red, clip: nil)
    let out = text(writer().render(b, previous: blank()))
    #expect(out.components(separatedBy: "38;5;1").count - 1 == 1)
    #expect(out.contains("ab"))
    #expect(out.hasSuffix("\(esc)[0m"))
}

@Test func rgbQuantizesTo256Cube() {
    #expect(ANSIWriter.quantize(.rgb(255, 0, 0), to: .ansi256) == .indexed(196))
    #expect(ANSIWriter.quantize(.rgb(255, 255, 255), to: .ansi256) == .indexed(231))
    #expect(ANSIWriter.quantize(.rgb(128, 128, 128), to: .ansi256) == .indexed(244))
    #expect(ANSIWriter.quantize(.rgb(1, 2, 3), to: .trueColor) == .rgb(1, 2, 3))
}

@Test func rgbQuantizesTo16() {
    #expect(ANSIWriter.quantize(.rgb(255, 0, 0), to: .ansi16) == .indexed(9))
    #expect(ANSIWriter.quantize(.indexed(196), to: .ansi16) == .indexed(9))
    #expect(ANSIWriter.quantize(.indexed(4), to: .ansi16) == .indexed(4))
}

@Test func monoDropsColorKeepsBoldInverse() {
    var b = blank(); b.put("a", x: 0, y: 0, style: Style(fg: .rgb(255, 0, 0), bold: true, inverse: true), clip: nil)
    let out = text(writer(.mono).render(b, previous: blank()))
    #expect(!out.contains("38;") && !out.contains("48;"))
    #expect(out.contains(";1") && out.contains(";7"))
}

@Test func trueColorEmitsRGB() {
    var b = blank(); b.put("a", x: 0, y: 0, style: Style(fg: .rgb(1, 2, 3), bg: .rgb(4, 5, 6)), clip: nil)
    let out = text(writer(.trueColor).render(b, previous: blank()))
    #expect(out.contains("38;2;1;2;3") && out.contains("48;2;4;5;6"))
}

@Test func fullRedrawWhenPreviousIsNilOrSizeDiffers() {
    var b = blank(); b.put("hi", x: 0, y: 0, style: .plain, clip: nil)
    for prev in [nil, blank(3, 3)] {
        let out = text(writer().render(b, previous: prev))
        #expect(out.contains("\(esc)[2J") && out.contains("hi"))
    }
}

@Test func wideCharIsWrittenOnceAndContinuationSkipped() {
    var b = blank(); b.put("漢", x: 0, y: 0, style: .plain, clip: nil)
    let out = text(writer().render(b, previous: blank()))
    #expect(out.components(separatedBy: "漢").count - 1 == 1)
}
