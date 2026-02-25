import AppKit
import CoreGraphics
import Foundation
import VibeBarCore

private struct SessionFlags {
    let onConsole: Bool
    let loginDone: Bool
}

private func readSessionFlags() -> SessionFlags? {
    if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
        let onConsole = boolValue(in: dict, keys: ["kCGSSessionOnConsoleKey", "kCGSessionOnConsoleKey"]) ?? false
        let loginDone = boolValue(in: dict, keys: ["kCGSessionLoginDoneKey", "kCGSSessionLoginDoneKey"]) ?? false
        return SessionFlags(onConsole: onConsole, loginDone: loginDone)
    } else {
        return nil
    }
}

private func boolValue(in dict: [String: Any], keys: [String]) -> Bool? {
    for key in keys {
        guard let value = dict[key] else { continue }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
    }
    return nil
}

private func localizedString(_ key: L10nKey) -> String {
    let lang = (AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system).resolved
    return L10nStrings.string(key, lang: lang)
}

let app = NSApplication.shared
let debugDock = ProcessInfo.processInfo.environment["VIBEBAR_DEBUG_DOCK"] == "1"
let policy: NSApplication.ActivationPolicy = debugDock ? .regular : .accessory
_ = app.setActivationPolicy(policy)
let delegate = AppDelegate()
app.delegate = delegate

if let flags = readSessionFlags() {
    if !flags.onConsole {
        fputs(localizedString(.consoleNotGuiSession), stderr)
        fputs(localizedString(.consoleRunInTerminal), stderr)
        exit(3)
    }
} else {
    fputs(localizedString(.consoleCannotReadSession), stderr)
}

if debugDock {
    app.activate(ignoringOtherApps: true)
}

app.run()
