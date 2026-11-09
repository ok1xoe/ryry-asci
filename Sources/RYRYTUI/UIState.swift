// Copyright 2026 OK1XOE (RYRY), LGPL v3
import TUIKit

public enum Focus: Equatable, Sendable { case rx, tx, qso(String) }

/// The state of the terminal UI that is not part of the application model.
public struct UIState: Sendable {
    public var focus: Focus = .tx
    public var window: TUIWindow?
    public var rxScroll = 0
    public var help = false
    public var message: String?
    /// The editor of the focused QSO field.
    public var qsoEditor = LineEditor()
    public init() {}
}
