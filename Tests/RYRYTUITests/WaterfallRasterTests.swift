// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
import TUIKit
@testable import RYRYTUI

private let uni = Capabilities(colorDepth: .trueColor, unicode: true, mouse: true)
private let mono = Capabilities(colorDepth: .mono, unicode: false, mouse: false)
private let asciiColor = Capabilities(colorDepth: .ansi256, unicode: false, mouse: false)
private let black = RGB(0, 0, 0), white = RGB(255, 255, 255)

@Test func halfBlockUsesTopAsForegroundBottomAsBackground() {
    let c = WaterfallRaster.cells(rows: [[RGB(255, 0, 0)], [RGB(0, 0, 255)]], cols: 1, cellRows: 1, caps: uni)
    #expect(c.count == 1 && c[0].count == 1)
    #expect(c[0][0].char == "▀")
    #expect(c[0][0].style.fg == .rgb(255, 0, 0) && c[0][0].style.bg == .rgb(0, 0, 255))
}

@Test func asciiRampMapsBlackToSpaceAndWhiteToAt() {
    let c = WaterfallRaster.cells(rows: [[black, white]], cols: 2, cellRows: 1, caps: mono)
    #expect(c[0][0].char == " " && c[0][1].char == "@")
    #expect(c[0][1].style == .plain)                                         // mono: no colors
}

@Test func asciiWithColorKeepsPixelColorAsForeground() {
    let c = WaterfallRaster.cells(rows: [[RGB(255, 0, 0)]], cols: 1, cellRows: 1, caps: asciiColor)
    #expect(c[0][0].style.fg == .rgb(255, 0, 0) && c[0][0].char != " ")
}

@Test func monoWithUnicodeStillUsesRamp() {
    let m = Capabilities(colorDepth: .mono, unicode: true, mouse: false)
    #expect(WaterfallRaster.cells(rows: [[white]], cols: 1, cellRows: 1, caps: m)[0][0].char == "@")
}

@Test func downsamplesWideRowsKeepingTheBrightestPixel() {
    var row = [RGB](repeating: black, count: 600); row[300] = white
    let c = WaterfallRaster.cells(rows: [row, row], cols: 40, cellRows: 1, caps: uni)
    #expect(c[0][20].style.fg == .rgb(255, 255, 255))
    #expect(c[0][0].style.fg == .rgb(0, 0, 0) && c[0][39].style.fg == .rgb(0, 0, 0))
}

@Test func sourceRowsAreResampledToTheCellRows() {
    let rows = (0..<100).map { _ in [black] }
    let c = WaterfallRaster.cells(rows: rows, cols: 1, cellRows: 6, caps: uni)
    #expect(c.count == 6)
    #expect(WaterfallRaster.cells(rows: [], cols: 3, cellRows: 2, caps: uni).count == 2)     // no data: blank, no crash
}

@Test func hzColumnRoundTrip() {
    let from = 300.0, to = 3300.0, cols = 60
    var hz = from
    while hz < to {
        let col = WaterfallRaster.hzToColumn(hz, fromHz: from, toHz: to, cols: cols)
        #expect((0..<cols).contains(col))
        #expect(abs(WaterfallRaster.columnToHz(col, fromHz: from, toHz: to, cols: cols) - hz) <= (to - from) / Double(cols) / 2 + 1e-9)
        hz += 37
    }
    #expect(WaterfallRaster.hzToColumn(-100, fromHz: from, toHz: to, cols: cols) == 0)
    #expect(WaterfallRaster.hzToColumn(9999, fromHz: from, toHz: to, cols: cols) == cols - 1)
}

@Test func spectrumHeightIsProportional() {
    let s = WaterfallRaster.spectrum([0.5, 0.5], cols: 2, cellRows: 4, caps: uni, markCol: nil, spaceCol: nil)
    #expect(s.count == 4)
    #expect(s[3][0].char == "█" && s[2][0].char == "█" && s[1][0].char == " " && s[0][0].char == " ")
    let zero = WaterfallRaster.spectrum([0], cols: 1, cellRows: 4, caps: uni, markCol: nil, spaceCol: nil)
    #expect(zero.allSatisfy { $0[0].char == " " })
    let full = WaterfallRaster.spectrum([1], cols: 1, cellRows: 2, caps: uni, markCol: nil, spaceCol: nil)
    #expect(full[0][0].char == "█" && full[1][0].char == "█")
}

@Test func spectrumPartialCellUsesEighths() {
    let s = WaterfallRaster.spectrum([3.0 / 8.0], cols: 1, cellRows: 1, caps: uni, markCol: nil, spaceCol: nil)
    #expect(s[0][0].char == "▃")
}

@Test func spectrumAsciiUsesPlainCharacters() {
    let s = WaterfallRaster.spectrum([1, 0.5], cols: 2, cellRows: 2, caps: mono, markCol: nil, spaceCol: nil)
    #expect(s[1][0].char == "#" && s[0][0].char == "#")
    #expect(s.joined().allSatisfy { $0.char.isASCII })
}

@Test func markAndSpaceColumnsAreMarked() {
    let s = WaterfallRaster.spectrum([0, 0, 0, 0], cols: 4, cellRows: 2, caps: uni, markCol: 1, spaceCol: 3)
    #expect(s[0][1].char == "▼" && s[0][3].char == "▽" && s[0][0].char == " ")
    let a = WaterfallRaster.spectrum([0, 0, 0, 0], cols: 4, cellRows: 2, caps: mono, markCol: 1, spaceCol: 3)
    #expect(a[0][1].char == "M" && a[0][3].char == "S")
}
