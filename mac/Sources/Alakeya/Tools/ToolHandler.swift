import Foundation

protocol ToolHandler {
    var toolNames: [String] { get }
    var toolSchemas: [[String: Any]] { get }
    func makeAction(toolName: String, args: [String: String]) -> Action?
}
