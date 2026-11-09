// Copyright 2026 OK1XOE (RYRY), LGPL v3
import TUIKit

/// Where the parts of the main screen go (same arrangement as the GUI: the main column on the left, the QSO panel on the right).
public struct MainLayout: Equatable, Sendable {
    public var topBar, spectrum, waterfall, rx: Rect
    public var rx2: Rect?
    public var tx, macros, status, qso: Rect

    public static let minCols = 100
    public static let minRows = 32

    /// nil below the minimum size. The fixed bars keep their height; extra rows go to the spectrum, waterfall and receive pane.
    public static func compute(cols: Int, rows: Int, secondDecoder: Bool) -> MainLayout? {
        guard cols >= minCols, rows >= minRows else { return nil }
        let qsoW = cols >= 140 ? 40 : 34
        let mw = cols - qsoW
        let rx2H = secondDecoder && rows >= 38 ? 3 : 0
        let r = rows - (2 + 2 + 1 + 4) - rx2H                       // topBar + macros + status + tx are fixed
        let extra = max(0, r - (4 + 6 + 13))
        let extraSW = extra / 3
        let sp = 4 + extraSW / 3
        let wf = 6 + extraSW - extraSW / 3
        let rxH = r - sp - wf
        var y = 0
        func take(_ h: Int) -> Rect { defer { y += h }; return Rect(0, y, mw, h) }
        let top = take(2), spect = take(sp), wat = take(wf), rxR = take(rxH)
        let rx2R: Rect? = rx2H > 0 ? take(rx2H) : nil
        let txR = take(4), mac = take(2), st = take(1)
        return MainLayout(topBar: top, spectrum: spect, waterfall: wat, rx: rxR, rx2: rx2R, tx: txR, macros: mac, status: st,
                          qso: Rect(mw, 0, qsoW, rows))
    }
}
