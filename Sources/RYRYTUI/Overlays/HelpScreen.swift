// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import TUIKit

/// The list of keys, generated from the `KeyMap`, so it can never be out of date.
@MainActor
public final class HelpScreen: OverlayScreen {
    public let title = "Keys"
    private var scroll = 0
    public init() {}

    public nonisolated static func describe(_ a: Action) -> String {
        switch a {
        case .toggleTx: "switch between transmit and receive"
        case .tune: "send a tuning carrier"
        case .stopRx: "back to receive immediately (also closes a prompt)"
        case .macro(let i): "macro \(i + 1)"
        case .logQSO: "log the QSO"
        case .clearQSO: "clear the QSO fields"
        case .openWindow(let w):
            switch w { case .log: "Log window"; case .spots: "Spots window"; case .bandMap: "Band map"; case .score: "Score window"; case .multipliers: "Multipliers window" }
        case .windowMenu: "step through the windows (for terminals without Alt)"
        case .closeWindow: "close the window / cancel the entry"
        case .focusNext: "next pane: transmit, receive, QSO fields"
        case .focusPrev: "previous pane"
        case .settings: "settings menu"
        case .help: "this list"
        case .quit: "quit"
        case .suspend: "suspend to the shell (fg returns)"
        case .freqEntry: "enter the frequency in kHz"
        case .esmEnter: "Enter Sends Message (contest ESM) / send the transmit text"
        case .rxScrollUp: "scroll the receive window back"
        case .rxScrollDown: "scroll the receive window forward"
        }
    }

    public nonisolated static func lines(keyMap: KeyMap) -> [String] {
        var out = ["Keys", ""]
        func line(_ label: String, _ text: String) { out.append("  " + label.fitted(to: 24) + text) }
        let macros = Action.allCases.filter { if case .macro = $0 { return true }; return false }
        let labels = macros.map { keyMap.label(for: $0) }
        // Wrapped into rows of four so the list fits a narrow terminal.
        for (n, start) in stride(from: 0, to: labels.count, by: 4).enumerated() {
            out.append((n == 0 ? "  Macros: " : "          ") + labels[start..<min(start + 4, labels.count)].joined(separator: "   "))
        }
        for a in Action.allCases where !macros.contains(a) { line(keyMap.label(for: a), describe(a)) }
        out += ["", "Mouse (when the terminal supports it)",
                "  click a word in the receive pane     puts the word into the QSO (call, name, RST, number)",
                "  click on the spectrum / waterfall    tunes the mark tone; right click adds a notch",
                "  click a macro, a top-bar button      does what the key does",
                "  wheel in the receive pane            scrolls back",
                "", "In the transmit pane Enter is a new line; Alt+Enter sends everything, Ctrl+N changes the send mode, Ctrl+U clears.",
                "Everything works without the mouse and without Alt (Ctrl+O steps through the windows, Alt+1…4 = ⇧F1…⇧F4)."]
        return out
    }

    public func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel) {
        buf.fill(rect)
        Chrome.header(&buf, rect, "Keys")
        let all = Self.lines(keyMap: KeyMap())
        let h = max(1, rect.h - 2)
        scroll = max(0, min(scroll, max(0, all.count - h)))
        for (i, l) in all.dropFirst(scroll).prefix(h).enumerated() { buf.put(l, x: rect.x, y: rect.y + 1 + i, style: i == 0 && scroll == 0 ? Style(bold: true) : .plain, clip: rect) }
        Chrome.footer(&buf, rect, "↑↓ PgUp PgDn scroll · Esc close")
    }

    public func handle(_ e: InputEvent, model: AppModel, rect: Rect) async -> OverlayResult {
        if case .key(.escape, _) = e { return .close }
        _ = Chrome.navigate(e, selected: &scroll, count: 1_000, page: max(1, rect.h - 2))
        return .stay
    }
}
