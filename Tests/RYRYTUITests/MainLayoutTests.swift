// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
import TUIKit
@testable import RYRYTUI

private func all(_ l: MainLayout) -> [Rect] { [l.topBar, l.spectrum, l.waterfall, l.rx] + (l.rx2.map { [$0] } ?? []) + [l.tx, l.macros, l.status, l.qso] }
private func overlap(_ a: Rect, _ b: Rect) -> Bool { a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h }

@Test func layoutNilBelowMinimum() {
    #expect(MainLayout.compute(cols: 99, rows: 32, secondDecoder: false) == nil)
    #expect(MainLayout.compute(cols: 100, rows: 31, secondDecoder: false) == nil)
    #expect(MainLayout.compute(cols: 100, rows: 32, secondDecoder: false) != nil)
}

@Test func layoutFitsEverySizeWithoutOverlap() throws {
    for (c, r, second) in [(100, 32, false), (100, 32, true), (120, 40, true), (140, 50, true), (200, 60, false), (101, 33, true), (100, 37, true), (100, 38, true)] {
        let l = try #require(MainLayout.compute(cols: c, rows: r, secondDecoder: second))
        let rects = all(l)
        for x in rects { #expect(x.w > 0 && x.h > 0 && x.x >= 0 && x.y >= 0 && x.x + x.w <= c && x.y + x.h <= r, "\(c)x\(r) \(x)") }
        for i in 0..<rects.count { for j in (i + 1)..<rects.count { #expect(!overlap(rects[i], rects[j]), "\(c)x\(r) \(rects[i]) vs \(rects[j])") } }
        let mainHeight = (rects.dropLast()).reduce(0) { $0 + $1.h }
        #expect(mainHeight == r, "\(c)x\(r)")
        #expect(l.qso.h == r && l.qso.x + l.qso.w == c)
    }
}

@Test func secondDecoderHiddenAtMinimumHeight() throws {
    #expect(try #require(MainLayout.compute(cols: 100, rows: 32, secondDecoder: true)).rx2 == nil)
    #expect(try #require(MainLayout.compute(cols: 100, rows: 37, secondDecoder: true)).rx2 == nil)
}

@Test func secondDecoderShownAt38Rows() throws {
    #expect(try #require(MainLayout.compute(cols: 100, rows: 38, secondDecoder: true)).rx2?.h == 3)
    #expect(try #require(MainLayout.compute(cols: 100, rows: 40, secondDecoder: false)).rx2 == nil)
}

@Test func qsoPanelWidth() throws {
    #expect(try #require(MainLayout.compute(cols: 100, rows: 32, secondDecoder: false)).qso.w == 34)
    #expect(try #require(MainLayout.compute(cols: 139, rows: 32, secondDecoder: false)).qso.w == 34)
    #expect(try #require(MainLayout.compute(cols: 140, rows: 32, secondDecoder: false)).qso.w == 40)
}

@Test func minimumHeightKeepsFixedBars() throws {
    let l = try #require(MainLayout.compute(cols: 100, rows: 32, secondDecoder: false))
    #expect(l.topBar.h == 2 && l.macros.h == 2 && l.status.h == 1 && l.tx.h == 4 && l.spectrum.h == 4 && l.waterfall.h == 6)
}

@Test func extraHeightGrowsWaterfallAndReceive() throws {
    let a = try #require(MainLayout.compute(cols: 100, rows: 32, secondDecoder: false))
    let b = try #require(MainLayout.compute(cols: 100, rows: 50, secondDecoder: false))
    #expect(b.rx.h > a.rx.h && b.waterfall.h > a.waterfall.h && b.spectrum.h >= a.spectrum.h)
}
