// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import TUIKit

/// A one-line file path entry with Tab completion (the terminal has no file dialog).
public struct PathPrompt: Equatable, Sendable {
    public var editor: LineEditor
    public var candidates: [String] = []

    public init(initial: String = "") { editor = LineEditor(text: initial) }

    /// The path with `~` expanded.
    public var expanded: String { (editor.text as NSString).expandingTildeInPath }

    /// Splits at the last "/": the directory part as typed (with the slash) and the name prefix.
    static func split(_ partial: String) -> (dir: String, prefix: String) {
        guard let i = partial.lastIndex(of: "/") else { return ("", partial) }
        return (String(partial[...i]), String(partial[partial.index(after: i)...]))
    }

    /// The entries whose names start with what has been typed (directories with a trailing "/"), as typed paths.
    public static func complete(_ partial: String, fileManager: FileManager) -> [String] {
        let (dir, prefix) = split(partial)
        let listDir = ((dir.isEmpty ? "./" : dir) as NSString).expandingTildeInPath
        guard let names = try? fileManager.contentsOfDirectory(atPath: listDir) else { return [] }
        return names.filter { $0.hasPrefix(prefix) && (prefix.hasPrefix(".") || !$0.hasPrefix(".")) }.sorted().map { name in
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: (listDir as NSString).appendingPathComponent(name), isDirectory: &isDir)
            return dir + name + (isDir.boolValue ? "/" : "")
        }
    }

    public static func commonPrefix(_ names: [String]) -> String {
        guard var p = names.first else { return "" }
        for n in names.dropFirst() { while !n.hasPrefix(p) { p.removeLast() } }
        return p
    }

    /// Tab: completes a unique match fully, several matches up to their common prefix (the matches stay in `candidates`).
    public mutating func complete(fileManager: FileManager = .default) {
        let matches = Self.complete(editor.text, fileManager: fileManager)
        candidates = matches
        guard !matches.isEmpty else { return }
        let dir = Self.split(editor.text).dir
        let names = matches.map { String($0.dropFirst(dir.count)) }
        editor = LineEditor(text: dir + (matches.count == 1 ? names[0] : Self.commonPrefix(names)))
    }
}
