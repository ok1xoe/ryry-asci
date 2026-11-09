// Copyright 2026 OK1XOE (RYRY), LGPL v3
import TUIKit

public enum Focus: Equatable, Sendable { case rx, tx, qso(String) }

/// A one-line input on the status row (Alt+F frequency, …).
public struct Prompt: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case frequency }
    public var kind: Kind
    public var title: String
    public var editor: LineEditor
    public init(kind: Kind, title: String, editor: LineEditor = LineEditor()) { self.kind = kind; self.title = title; self.editor = editor }
}

/// The state of the terminal UI that is not part of the application model.
public struct UIState: Sendable {
    public var focus: Focus = .tx
    public var window: TUIWindow?
    public var rxScroll = 0
    public var help = false
    public var message: String?
    public var prompt: Prompt?
    /// The editor of the focused QSO field.
    public var qsoEditor = LineEditor()
    public init() {}
}
