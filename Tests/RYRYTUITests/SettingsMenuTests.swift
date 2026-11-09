// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Keying
import RigControl
import Settings
import Testing
import TUIKit
@testable import AppUI
@testable import RYRYTUI

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
private func fileJSON(_ f: TUIFixture) -> [String: Any] {
    let d = (try? Data(contentsOf: f.dir.appendingPathComponent("settings.json"))) ?? Data()
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
}

@Test @MainActor func drawShowsSectionsAndValues() async {
    let f = TUIFixture(); await f.model.start()
    let m = SettingsMenu(model: f.model)
    let t = allText(draw(m, f.model))
    for needle in ["Settings", "Station", "Call", "OK1XOE", "Audio", "Rig", "Contest", "Macros"] { #expect(t.contains(needle), "\(needle)") }
    await f.model.stop()
}

@Test @MainActor func changingCallsignPersists() async {
    let f = TUIFixture(); await f.model.start()
    let m = SettingsMenu(model: f.model)
    #expect(m.select("Call"))
    let r = await send(m, [key(.enter), key(.char("u"), .ctrl)] + chars("OK1ABC") + [key(.enter), key(.char("s"))], f.model)
    await f.settle()
    #expect(r == .close)
    #expect(f.model.settings.station.call == "OK1ABC")
    #expect((fileJSON(f)["station"] as? [String: Any])?["call"] as? String == "OK1ABC")
    await f.model.stop()
}

@Test @MainActor func savingKeepsUnknownFieldsInSettingsJson() async throws {
    let f = TUIFixture(); await f.model.start()
    let url = f.dir.appendingPathComponent("settings.json")
    var j = fileJSON(f)
    j["futureThing"] = 1
    var st = j["station"] as? [String: Any] ?? [:]; st["futureNested"] = "x"; j["station"] = st
    try JSONSerialization.data(withJSONObject: j).write(to: url)
    let m = SettingsMenu(model: f.model)
    _ = m.select("Name")
    _ = await send(m, [key(.enter)] + chars("BOB") + [key(.enter), key(.char("s"))], f.model)
    await f.settle()
    let after = fileJSON(f)
    #expect(after["futureThing"] as? Int == 1)
    #expect((after["station"] as? [String: Any])?["futureNested"] as? String == "x")
    #expect((after["station"] as? [String: Any])?["name"] as? String == "BOB")
    await f.model.stop()
}

@Test @MainActor func selectingContestPresetFillsTheContest() async {
    let f = TUIFixture(); await f.model.start()
    let m = SettingsMenu(model: f.model)
    #expect(m.select("Preset"))
    _ = await send(m, [key(.right)], f.model)                                           // (custom) → the first preset
    _ = await send(m, [key(.char("s"))], f.model); await f.settle()
    let c = f.model.settings.contest
    #expect(c.preset != nil && c.enabled && c.format == c.preset!.format)
    await f.model.stop()
}

@Test @MainActor func macroEditChangesNameAndText() async {
    let f = TUIFixture(); await f.model.start()
    let m = SettingsMenu(model: f.model)
    #expect(m.select("Macro F1"))
    _ = await send(m, [key(.enter), key(.char("u"), .ctrl)] + chars("NEWNAME") + [key(.enter), key(.char("u"), .ctrl)] + chars("NEW TEXT %m") + [key(.enter)], f.model)
    _ = await send(m, [key(.char("s"))], f.model); await f.settle()
    #expect(f.model.settings.macros[0].name == "NEWNAME" && f.model.settings.macros[0].text == "NEW TEXT %m")
    await f.model.stop()
}

@Test @MainActor func escDiscardsChanges() async {
    let f = TUIFixture(); await f.model.start()
    let m = SettingsMenu(model: f.model)
    _ = m.select("Call")
    _ = await send(m, [key(.enter)] + chars("ZZ") + [key(.escape)], f.model)             // cancels the edit only
    #expect(allText(draw(m, f.model)).contains("Settings"))
    _ = m.select("Contest mode")
    _ = await send(m, [key(.enter)], f.model)                                           // toggles in the draft
    let r = await send(m, [key(.escape)], f.model)
    #expect(r == .close)
    await f.settle()
    #expect(f.model.settings.station.call == "OK1XOE" && !f.model.settings.contest.enabled)
    await f.model.stop()
}

@Test @MainActor func choiceRowsCycleBothWays() async {
    let f = TUIFixture(); await f.model.start()
    let m = SettingsMenu(model: f.model)
    #expect(m.select("Rig type"))
    _ = await send(m, [key(.right)], f.model)
    #expect(allText(draw(m, f.model)).contains("hamlib"))
    _ = await send(m, [key(.left), key(.left)], f.model)                                 // wraps around to the last type
    #expect(allText(draw(m, f.model)).contains("cat"))
    await f.model.stop()
}

@Test @MainActor func mouseClickSelectsAndActivatesRows() async {
    let f = TUIFixture(); await f.model.start()
    let m = SettingsMenu(model: f.model)
    _ = draw(m, f.model)
    let y = (0..<32).first { rowText(draw(m, f.model), $0).contains("Contest mode") }!
    _ = await send(m, [.mouse(MouseEvent(kind: .press, button: .left, x: 5, y: y, mods: []))], f.model)
    #expect(allText(draw(m, f.model)).contains("Contest mode") && m.selectedLabel == "Contest mode")
    await f.model.stop()
}

@Test @MainActor func everyKeyOnEveryRowIsSafeAndSmallScreensDraw() async {
    let f = TUIFixture(); await f.model.start()
    let m = SettingsMenu(model: f.model)
    let keys: [InputEvent] = [key(.down), key(.up), key(.pageDown), key(.pageUp), key(.end), key(.home), key(.left), key(.right), key(.enter), key(.escape), key(.tab), key(.char("x"))]
    for _ in 0..<40 { for k in keys { _ = await send(m, [k], f.model) } }
    var tiny = ScreenBuffer(width: 30, height: 6)
    m.draw(into: &tiny, rect: Rect(0, 0, 30, 6), model: f.model)
    await f.model.stop()
}

@Test @MainActor func ctrlPOpensSettingsFromTheMainScreen() async {
    let f = TUIFixture(); await f.model.start()
    let s = MainScreen(model: f.model, caps: Capabilities(colorDepth: .trueColor, unicode: true, mouse: true), size: (100, 32))
    _ = await s.handle(key(.char("p"), .ctrl))
    #expect(allText(s.render(now: Date())).contains("Settings"))
    _ = await s.handle(key(.escape))
    #expect(allText(s.render(now: Date())).contains("[TX]"))
    await f.model.stop()
}
