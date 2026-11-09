// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// `settings.json` is rewritten from `AppSettings`, which drops keys this version does not know (e.g. written by a newer
/// RYRY). The console menu puts them back so that the GUI and the console version can take turns safely.
public enum SettingsPreserver {
    /// Copies the keys of `old` that are missing in `new` into `new`, recursively through objects.
    static func merge(old: [String: Any], into new: inout [String: Any]) {
        for (k, v) in old {
            if var n = new[k] as? [String: Any], let o = v as? [String: Any] { merge(old: o, into: &n); new[k] = n }
            else if new[k] == nil { new[k] = v }
        }
    }

    /// `before` = the file contents from before the save; the file at `url` (freshly written) gets the unknown keys back.
    public static func reinjectUnknown(before: Data?, url: URL) {
        guard let before, let old = (try? JSONSerialization.jsonObject(with: before)) as? [String: Any],
              let data = try? Data(contentsOf: url), var new = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let sizeBefore = new.count
        merge(old: old, into: &new)
        // only rewrite when something was actually missing (nested additions are also detected by comparing the encodings)
        guard let out = try? JSONSerialization.data(withJSONObject: new, options: [.prettyPrinted, .sortedKeys]) else { return }
        if new.count != sizeBefore || out != data { try? out.write(to: url, options: .atomic) }
    }
}
