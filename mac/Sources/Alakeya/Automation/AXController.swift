import Foundation
import AXSwift
import ApplicationServices

// ============================================================
// AXController.swift — Accessibility control plane (DOC2 examples).
// Read the focused UI element, find an editable field, set its value;
// this is the *primary* actuator, ahead of paste/CGEvent fallbacks.
// ============================================================

struct AXNode: Codable {
    let role: String?
    let subrole: String?
    let title: String?
    let value: String?
    let children: [AXNode]
}

enum AXError: Error { case notTrusted, noFocusedElement, setFailed }

final class AXController {

    private var systemWide: UIElement { UIElement(AXUIElementCreateSystemWide()) }

    /// Whether this process is trusted for Accessibility (TCC).
    var isTrusted: Bool { UIElement.isProcessTrusted(withPrompt: false) }

    // ── Read a bounded snapshot of an element's subtree ────
    func snapshot(_ element: UIElement, depth: Int = 0, maxDepth: Int = 5) -> AXNode {
        let role: String? = try? element.attribute(.role)
        let subrole: String? = try? element.attribute(.subrole)
        let title: String? = try? element.attribute(.title)
        let value: String? = try? element.attribute(.value)

        guard depth < maxDepth else {
            return AXNode(role: role, subrole: subrole, title: title, value: value, children: [])
        }
        let kids: [UIElement] = (try? element.attribute(.children)) ?? []
        let children = kids.map { snapshot($0, depth: depth + 1, maxDepth: maxDepth) }
        return AXNode(role: role, subrole: subrole, title: title, value: value, children: children)
    }

    /// The element owning keyboard focus, system-wide.
    func focusedElement() throws -> UIElement {
        guard let focused: UIElement = try systemWide.attribute(.focusedUIElement) else {
            throw AXError.noFocusedElement
        }
        return focused
    }

    /// Depth-first search for the first editable text field/area.
    func findFirstEditable(_ node: UIElement) -> UIElement? {
        let role: String = (try? node.attribute(.role)) ?? ""
        let subrole: String = (try? node.attribute(.subrole)) ?? ""
        let enabled: Bool = (try? node.attribute(.enabled)) ?? true

        if enabled && (role == Role.textField.rawValue ||
                       role == Role.textArea.rawValue ||
                       subrole.lowercased().contains("search")) {
            return node
        }
        let kids: [UIElement] = (try? node.attribute(.children)) ?? []
        for child in kids {
            if let found = findFirstEditable(child) { return found }
        }
        return nil
    }

    /// Semantic-first text entry: AXSetAttributeValue on the focused field.
    /// Returns false if the field isn't settable (caller falls back to paste).
    @discardableResult
    func setFocusedValue(_ text: String) -> Bool {
        guard let focused = try? focusedElement() else { return false }
        do {
            try focused.setAttribute(.value, value: text)
            return true
        } catch {
            return false
        }
    }

    /// Invoke the standard AXPress action on an element (buttons, menu items).
    @discardableResult
    func press(_ element: UIElement) -> Bool {
        (try? element.performAction(.press)) != nil
    }
}
