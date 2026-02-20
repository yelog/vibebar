import AppKit
import CoreGraphics
import Foundation

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

let app = NSApplication.shared
let debugDock = ProcessInfo.processInfo.environment["VIBEBAR_DEBUG_DOCK"] == "1"
let policy: NSApplication.ActivationPolicy = debugDock ? .regular : .accessory
_ = app.setActivationPolicy(policy)
let delegate = AppDelegate()
app.delegate = delegate

if let flags = readSessionFlags() {
    if !flags.onConsole {
        fputs("VibeBar error: 当前不是 macOS 图形控制台会话，无法显示右上角菜单栏图标。\n", stderr)
        fputs("请在本机 Terminal.app / iTerm 中直接运行，或打包为 .app 后从 Finder 启动。\n", stderr)
        exit(3)
    }
} else {
    fputs("VibeBar warning: 无法读取会话信息，继续尝试启动。\n", stderr)
}

if debugDock {
    app.activate(ignoringOtherApps: true)
}

app.run()
