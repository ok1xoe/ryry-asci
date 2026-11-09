// Copyright 2026 OK1XOE (RYRY), LGPL v3

public enum TUIWindow: CaseIterable, Hashable, Sendable { case log, spots, bandMap, score, multipliers }

public enum Action: Hashable, Sendable {
    case toggleTx, tune, stopRx
    case macro(Int)                          // 0…15 = F1…F12, ⇧F1…⇧F4
    case logQSO, clearQSO
    case openWindow(TUIWindow), windowMenu, closeWindow
    case focusNext, focusPrev
    case settings, help, quit, suspend
    case freqEntry, esmEnter
    case rxScrollUp, rxScrollDown
    case textBigger, textSmaller

    public static var allCases: [Action] {
        [.toggleTx, .tune, .stopRx] + (0..<16).map { .macro($0) } + [.logQSO, .clearQSO]
            + TUIWindow.allCases.map { .openWindow($0) }
            + [.windowMenu, .closeWindow, .focusNext, .focusPrev, .settings, .help, .quit, .suspend, .freqEntry, .esmEnter,
               .rxScrollUp, .rxScrollDown, .textBigger, .textSmaller]
    }
}
