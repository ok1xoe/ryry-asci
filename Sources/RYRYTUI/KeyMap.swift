// Copyright 2026 OK1XOE (RYRY), LGPL v3
import TUIKit

/// Keys → actions. ⌘ of the GUI became Ctrl, and every action also has a key that works without ⇧F-keys (Alt+1…4).
/// Avoided on purpose: Ctrl+M (= Enter), Ctrl+I (= Tab), Ctrl+H (= Backspace), Ctrl+, and Ctrl+digits (terminals do not send them).
public struct KeyMap: Sendable {
    struct Combo: Hashable { var key: Key; var mods: Modifiers }
    private struct Binding { var action: Action; var combos: [Combo]; var label: String }
    private let bindings: [Binding]
    private let lookup: [Combo: Action]
    public let hasDuplicateKeys: Bool

    public init() {
        func c(_ ch: Character, _ m: Modifiers) -> Combo { Combo(key: .char(ch), mods: m) }
        var b: [Binding] = []
        for i in 0..<12 { b.append(Binding(action: .macro(i), combos: [Combo(key: .f(i + 1), mods: [])], label: "F\(i + 1)")) }
        for i in 0..<4 {
            b.append(Binding(action: .macro(12 + i), combos: [Combo(key: .f(i + 1), mods: .shift), c(Character("\(i + 1)"), .alt)],
                             label: "⇧F\(i + 1) / Alt+\(i + 1)"))
        }
        b += [
            Binding(action: .toggleTx, combos: [c("t", .ctrl)], label: "Ctrl+T"),
            Binding(action: .tune, combos: [c("t", .alt)], label: "Alt+T"),
            Binding(action: .stopRx, combos: [Combo(key: .escape, mods: [])], label: "Esc"),
            Binding(action: .logQSO, combos: [c("l", .ctrl)], label: "Ctrl+L"),
            Binding(action: .clearQSO, combos: [c("x", .alt)], label: "Alt+X"),
            Binding(action: .openWindow(.log), combos: [c("l", .alt)], label: "Alt+L"),
            Binding(action: .openWindow(.spots), combos: [c("s", .alt)], label: "Alt+S"),
            Binding(action: .openWindow(.bandMap), combos: [c("b", .alt)], label: "Alt+B"),
            Binding(action: .openWindow(.score), combos: [c("c", .alt)], label: "Alt+C"),
            Binding(action: .openWindow(.multipliers), combos: [c("m", .alt)], label: "Alt+M"),
            Binding(action: .windowMenu, combos: [c("o", .ctrl)], label: "Ctrl+O"),
            Binding(action: .closeWindow, combos: [], label: "Esc (inside a window)"),
            Binding(action: .focusNext, combos: [Combo(key: .tab, mods: [])], label: "Tab"),
            Binding(action: .focusPrev, combos: [Combo(key: .backTab, mods: [])], label: "⇧Tab"),
            Binding(action: .settings, combos: [c("p", .ctrl)], label: "Ctrl+P"),
            Binding(action: .help, combos: [c("g", .ctrl)], label: "Ctrl+G"),
            Binding(action: .quit, combos: [c("q", .ctrl)], label: "Ctrl+Q"),
            Binding(action: .suspend, combos: [c("z", .ctrl)], label: "Ctrl+Z"),
            Binding(action: .freqEntry, combos: [c("f", .alt)], label: "Alt+F"),
            Binding(action: .esmEnter, combos: [Combo(key: .enter, mods: .alt)], label: "Alt+Enter"),
            Binding(action: .rxScrollUp, combos: [Combo(key: .pageUp, mods: [])], label: "PgUp"),
            Binding(action: .rxScrollDown, combos: [Combo(key: .pageDown, mods: [])], label: "PgDn"),
        ]
        bindings = b
        var map: [Combo: Action] = [:]
        var dup = false
        for x in b { for k in x.combos { if map[k] != nil { dup = true }; map[k] = x.action } }
        lookup = map
        hasDuplicateKeys = dup
    }

    public func action(for event: InputEvent) -> Action? {
        guard case .key(let key, let mods) = event else { return nil }
        var k = key, m = mods
        if case .char(let ch) = key, !mods.isDisjoint(with: [.alt, .ctrl]) {
            k = .char(Character(ch.lowercased())); m.remove(.shift)           // Alt+Shift+L / caps lock = Alt+L
        }
        return lookup[Combo(key: k, mods: m)]
    }

    public func label(for action: Action) -> String { bindings.first { $0.action == action }?.label ?? "" }
}
