// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import Foundation
import QSOLog
import Settings
import Testing
import TUIKit
@testable import AppUI
@testable import RYRYTUI
@testable import Spots

private let full = Rect(0, 0, 100, 32)
private func rowText(_ b: ScreenBuffer, _ y: Int) -> String { String((0..<b.width).map { b[x: $0, y: y].char }) }
private func allText(_ b: ScreenBuffer) -> String { (0..<b.height).map { rowText(b, $0) }.joined(separator: "\n") }
private func key(_ k: Key, _ m: Modifiers = []) -> InputEvent { .key(k, m) }
private func chars(_ s: String) -> [InputEvent] { s.map { key(.char($0)) } }
@MainActor private func draw(_ o: some OverlayScreen, _ model: AppModel) -> ScreenBuffer {
    var b = ScreenBuffer(width: 100, height: 32); o.draw(into: &b, rect: full, model: model); return b
}
@MainActor private func send(_ o: some OverlayScreen, _ events: [InputEvent], _ model: AppModel) async -> OverlayResult {
    var r = OverlayResult.stay
    for e in events { r = await o.handle(e, model: model, rect: full) }
    return r
}
@MainActor private func logged(_ f: TUIFixture, calls: [String]) async {
    await f.model.start()
    for c in calls { await f.model.setQSOField("call", c); await f.model.logQSO(); await f.settle() }
}

/// `SpotFeed.ingest` only works while the feed runs: start it against a closed local port that is retried only after an hour.
@MainActor private func runningFeed(_ model: AppModel) {
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: 1))
    cfg.clientTuning = (initialDelay: 3600, maxDelay: 3600)
    model.spotFeed.start(cfg)
}

// MARK: path prompt

@Test func pathCompletionListsMatchesAndCompletesUniqueOnes() throws {
    let d = tuiTempDir()
    for n in ["alpha.adi", "alpine.txt", "beta.adi"] { FileManager.default.createFile(atPath: d.appendingPathComponent(n).path, contents: Data()) }
    try FileManager.default.createDirectory(at: d.appendingPathComponent("archive"), withIntermediateDirectories: true)
    let m = PathPrompt.complete(d.path + "/al", fileManager: .default)
    #expect(m.map { ($0 as NSString).lastPathComponent }.sorted() == ["alpha.adi", "alpine.txt"])
    #expect(PathPrompt.complete(d.path + "/be", fileManager: .default).count == 1)
    #expect(PathPrompt.complete(d.path + "/ar", fileManager: .default).first?.hasSuffix("archive/") == true)
    #expect(PathPrompt.complete(d.path + "/zzz", fileManager: .default).isEmpty)
    #expect(PathPrompt.commonPrefix(["alpha.adi", "alpine.txt"]) == "alp")
    var p = PathPrompt(initial: d.path + "/be")
    p.complete()
    #expect(p.editor.text == d.path + "/beta.adi")
    var q = PathPrompt(initial: d.path + "/al")
    q.complete()
    #expect(q.editor.text == d.path + "/alp")                                        // only the common prefix
    #expect(PathPrompt(initial: "~/x").expanded.hasPrefix("/"))
}

// MARK: log

@Test @MainActor func logListsNewestFirstAndSearchFilters() async {
    let f = TUIFixture(); await logged(f, calls: ["DL1ABC", "OK2XYZ"])
    let s = LogScreen()
    let t = allText(draw(s, f.model))
    #expect(t.contains("DL1ABC") && t.contains("OK2XYZ"))
    #expect(t.range(of: "OK2XYZ")!.lowerBound < t.range(of: "DL1ABC")!.lowerBound)  // the newest on top
    _ = await send(s, [key(.char("/"))] + chars("dl1") + [key(.enter)], f.model)
    let t2 = allText(draw(s, f.model))
    #expect(t2.contains("DL1ABC") && !t2.contains("OK2XYZ"))
    _ = await send(s, [key(.char("/")), key(.escape)], f.model)                       // Esc in the search clears the filter
    #expect(allText(draw(s, f.model)).contains("OK2XYZ"))
    await f.model.stop()
}

@Test @MainActor func logDeleteRequiresConfirmation() async {
    let f = TUIFixture(); await logged(f, calls: ["DL1ABC", "OK2XYZ"])
    let s = LogScreen()
    _ = await send(s, [key(.char("d"))], f.model)
    #expect(allText(draw(s, f.model)).contains("Delete"))
    #expect(f.model.logRecords.count == 2)
    _ = await send(s, [key(.char("n"))], f.model)
    #expect(f.model.logRecords.count == 2)
    _ = await send(s, [key(.char("d")), key(.char("y"))], f.model); await f.settle()
    #expect(f.model.logRecords.count == 1 && f.model.logRecords[0].call == "DL1ABC")   // the newest (OK2XYZ) went
    await f.model.stop()
}

@Test @MainActor func logEditAndDeleteFollowTheRecordWhenTheLogChangesUnderneath() async {
    let f = TUIFixture(); await logged(f, calls: ["DL1ABC"])
    let s = LogScreen()
    _ = await send(s, [key(.enter), key(.down), key(.down), key(.down), key(.enter)] + chars("BOB"), f.model)      // editing DL1ABC's name
    await f.model.setQSOField("call", "OK2XYZ"); await f.model.logQSO(); await f.settle()                    // a new QSO lands at the top
    _ = await send(s, [key(.enter)], f.model); await f.settle()
    let byCall = Dictionary(uniqueKeysWithValues: f.model.logRecords.map { ($0.call, $0) })
    #expect(byCall["DL1ABC"]?.name == "BOB" && byCall["OK2XYZ"]?.name == nil, "the edit went to the wrong QSO")
    let t = LogScreen()
    _ = await send(t, [key(.down), key(.char("d"))], f.model)                                                 // delete DL1ABC (second row)
    await f.model.setQSOField("call", "OK3NEW"); await f.model.logQSO(); await f.settle()
    _ = await send(t, [key(.char("y"))], f.model); await f.settle()
    #expect(f.model.logRecords.map(\.call).sorted() == ["OK2XYZ", "OK3NEW"], "the delete hit the wrong QSO: \(f.model.logRecords.map(\.call))")
    await f.model.stop()
}

@Test @MainActor func logEditChangesAFieldAndEscCancels() async {
    let f = TUIFixture(); await logged(f, calls: ["DL1ABC"])
    let s = LogScreen()
    _ = await send(s, [key(.enter), key(.down), key(.down), key(.down), key(.enter)] + chars("BOB") + [key(.enter)], f.model); await f.settle()
    #expect(f.model.logRecords[0].name == "BOB")
    _ = await send(s, [key(.enter), key(.down), key(.down), key(.down), key(.enter)] + chars("ZZZ") + [key(.escape), key(.escape)], f.model)
    #expect(f.model.logRecords[0].name == "BOB")                                     // cancelled
    #expect(await send(s, [key(.escape)], f.model) == .close)
    await f.model.stop()
}

@Test @MainActor func logExportAndImportGoThroughAPathPrompt() async throws {
    let f = TUIFixture(); await logged(f, calls: ["DL1ABC"])
    let s = LogScreen()
    let out = tuiTempDir().appendingPathComponent("out.adi")
    _ = await send(s, [key(.char("a")), key(.char("u"), .ctrl)] + chars(out.path) + [key(.enter)], f.model)
    #expect(FileManager.default.fileExists(atPath: out.path))
    #expect(try String(contentsOf: out, encoding: .utf8).contains("DL1ABC"))
    let cab = tuiTempDir().appendingPathComponent("out.cbr")
    _ = await send(s, [key(.char("e")), key(.char("u"), .ctrl)] + chars(cab.path) + [key(.enter)], f.model)
    #expect(FileManager.default.fileExists(atPath: cab.path))
    _ = await send(s, [key(.char("i")), key(.char("u"), .ctrl)] + chars("/nonexistent/file.adi") + [key(.enter)], f.model)
    #expect(allText(draw(s, f.model)).lowercased().contains("error") || allText(draw(s, f.model)).contains("nonexistent"))
    await f.model.stop()
}

@Test @MainActor func logMouseSelectsRowsAndWheelScrolls() async {
    let f = TUIFixture(); await logged(f, calls: ["DL1ABC", "OK2XYZ"])
    let s = LogScreen()
    _ = await send(s, [.mouse(MouseEvent(kind: .press, button: .left, x: 5, y: 3, mods: []))], f.model)   // the 2nd data row
    #expect(s.selected == 1)
    _ = await send(s, [.mouse(MouseEvent(kind: .wheelUp, button: .none, x: 5, y: 3, mods: []))], f.model)
    #expect(s.selected == 0)
    await f.model.stop()
}

@Test @MainActor func emptyLogSurvivesEveryKey() async {
    let f = TUIFixture(); await f.model.start()
    let s = LogScreen()
    let keys: [InputEvent] = [key(.enter), key(.down), key(.up), key(.pageDown), key(.end), key(.home), key(.char("d")), key(.char("y")), key(.char("n")),
                              key(.escape), key(.char("/")), key(.enter), key(.delete), .mouse(MouseEvent(kind: .press, button: .left, x: 3, y: 9, mods: []))]
    for k in keys { _ = await send(s, [k], f.model); _ = draw(s, f.model) }
    await f.model.stop()
}

@Test @MainActor func logSanitizesRecords() async {
    let f = TUIFixture(); await logged(f, calls: ["DL1ABC"])
    await f.model.setQSOField("name", "A\u{1B}[2JB")
    await f.model.setQSOField("call", "OK1TST"); await f.model.logQSO()
    #expect(!allText(draw(LogScreen(), f.model)).contains("\u{1B}"))
    await f.model.stop()
}

// MARK: spots

@Test @MainActor func spotsListSanitizesTelnetCommentAndEnterUsesSpot() async {
    let f = TUIFixture(); await f.model.start()
    runningFeed(f.model)
    f.model.setSpots { $0.filterModes = SpotFilter.allModes }
    f.model.spotFeed.ingest([Spot(frequencyKHz: 14084.5, call: "DL1ABC", spotter: "OK1XOE", comment: "RTTY\u{1B}[2J 599", time: Date(), mode: "RTTY")])
    let s = SpotsScreen()
    let t = allText(draw(s, f.model))
    #expect(t.contains("DL1ABC") && t.contains("14084.5") && !t.contains("\u{1B}"))
    _ = await send(s, [key(.enter)], f.model)
    #expect(f.model.qso.call == "DL1ABC")
    #expect(await send(s, [key(.escape)], f.model) == .close)
    f.model.spotFeed.stop()
    await f.model.stop()
}

@Test @MainActor func spotsModeFilterToggles() async {
    let f = TUIFixture(); await f.model.start()
    runningFeed(f.model)
    f.model.spotFeed.ingest([Spot(frequencyKHz: 14084.5, call: "DL1ABC", spotter: "X", comment: "", time: Date(), mode: "CW")])
    let s = SpotsScreen()
    _ = await send(s, [key(.char("m"))], f.model)
    let a = f.model.settings.spots.filter.modes
    _ = await send(s, [key(.char("m"))], f.model)
    #expect(a != f.model.settings.spots.filter.modes)
    await f.model.stop()
}

// MARK: band map

@Test @MainActor func bandMapShowsRulerAndMarkers() async {
    let f = TUIFixture(); await f.model.start()
    let s = BandMapScreen()
    let t = allText(draw(s, f.model))
    #expect(t.contains("Band map") && t.contains("0 Hz"))
    #expect(await send(s, [key(.escape)], f.model) == .close)
    await f.model.stop()
}

@Test func bandMapRulerPositionIsProportional() {
    #expect(BandMapScreen.rulerColumn(audioHz: 0, width: 41) == 0)
    #expect(BandMapScreen.rulerColumn(audioHz: 4000, width: 41) == 40)
    #expect(BandMapScreen.rulerColumn(audioHz: 2000, width: 41) == 20)
    #expect(BandMapScreen.rulerColumn(audioHz: 9999, width: 41) == 40)
    #expect(BandMapScreen.rulerColumn(audioHz: -5, width: 41) == 0)
}

// MARK: score and multipliers

@Test @MainActor func scoreAndMultiplierLinesExplainTheStateWithoutAContest() {
    #expect(ScoreScreen.lines(tally: nil).joined().lowercased().contains("contest"))
    #expect(MultipliersScreen.lines(tally: nil).joined().lowercased().contains("contest"))
}

@Test @MainActor func scoreLinesShowBandTableAndTotal() {
    let preset = ContestPreset.allCases.first!
    let mult = MultiplierRule.rule(for: preset)
    let t = ScoreTally(rule: ScoreRule.rule(for: preset), multiplierRule: mult)
    let text = ScoreScreen.lines(tally: t).joined(separator: "\n")
    #expect(text.contains("Band") && text.contains("QSOs") && text.contains("Score"))
    #expect(MultipliersScreen.lines(tally: t.multipliers).joined().contains("0"))
}

// MARK: integration with the main screen

@Test @MainActor func mainScreenOpensClosesAndCyclesWindows() async {
    let f = TUIFixture(); await f.model.start()
    let s = MainScreen(model: f.model, caps: Capabilities(colorDepth: .trueColor, unicode: true, mouse: true), size: (100, 32))
    _ = await s.handle(key(.char("l"), .alt))
    #expect(s.ui.window == .log && allText(s.render(now: Date())).contains("Log"))
    _ = await s.handle(key(.char("o"), .ctrl)); #expect(s.ui.window == .spots)
    _ = await s.handle(key(.char("s"), .alt)); #expect(s.ui.window == .spots)
    _ = await s.handle(key(.char("c"), .alt)); #expect(s.ui.window == .score)
    _ = await s.handle(key(.escape)); #expect(s.ui.window == nil)
    #expect(allText(s.render(now: Date())).contains("[TX]"))
    _ = await s.handle(key(.char("l"), .alt))
    #expect(await s.handle(key(.char("q"), .ctrl)) == false)                         // quit works from a window too
    await f.model.stop()
}
