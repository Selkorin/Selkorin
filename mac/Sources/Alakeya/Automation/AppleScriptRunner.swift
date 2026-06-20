import Foundation

// ============================================================
// AppleScriptRunner.swift — Apple Events / AppleScript path, the
// cleanest channel for scriptable apps and system actions (DOC1 §"Apple
// Events / AppleScript"). Used before falling back to AX / CGEvent.
// ============================================================

enum ScriptError: Error { case failed(String) }

final class AppleScriptRunner {

    @discardableResult
    func run(_ source: String) throws -> String {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw ScriptError.failed("Не удалось скомпилировать AppleScript")
        }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo, let msg = errorInfo[NSAppleScript.errorMessage] as? String {
            throw ScriptError.failed(msg)
        }
        return result.stringValue ?? ""
    }

    /// Activate (launch + front) an application by name.
    func activate(app: String) throws {
        try run("tell application \"\(app)\" to activate")
    }

    /// Point Safari's front document at a URL.
    func openURLInSafari(_ url: String) throws {
        try run("""
        tell application "Safari"
            activate
            if (count of windows) = 0 then make new document
            set URL of front document to "\(url)"
        end tell
        """)
    }
}
