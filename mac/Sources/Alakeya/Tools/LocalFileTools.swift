import Foundation

struct LocalFileTools: ToolHandler {

    var toolNames: [String] {
        ["list_directory", "read_text_file", "open_file", "create_folder"]
    }

    var toolSchemas: [[String: Any]] { Self.schemas }

    func makeAction(toolName: String, args: [String: String]) -> Action? {
        switch toolName {
        case "list_directory":
            let path = args["path"] ?? "~"
            return Action(
                type: .listDirectory,
                title: "Показать содержимое папки",
                description: "Просмотреть файлы в: \(path)",
                target: path, scope: "Файловая система",
                reversible: true, args: args
            )
        case "read_text_file":
            let path = args["path"] ?? ""
            return Action(
                type: .readTextFile,
                title: "Прочитать файл",
                description: "Прочитать содержимое: \(path)",
                target: path, scope: "Файловая система",
                reversible: true, args: args
            )
        case "open_file":
            let path = args["path"] ?? ""
            return Action(
                type: .openFile,
                title: "Открыть файл",
                description: "Открыть в стандартном приложении: \(path)",
                target: path, scope: "Файловая система",
                reversible: true, args: args
            )
        case "create_folder":
            let path = args["path"] ?? ""
            return Action(
                type: .createFolder,
                title: "Создать папку",
                description: "Создать директорию: \(path)",
                target: path, scope: "Файловая система",
                reversible: false, args: args
            )
        default:
            return nil
        }
    }

    // ── JSON schemas for OpenAI function calling ──────────

    private static let schemas: [[String: Any]] = [
        fn("list_directory",
           "Показать список файлов и папок по указанному пути на компьютере пользователя",
           ["path": ["type": "string",
                     "description": "Путь к папке, например ~/Desktop или ~/Documents"]],
           ["path"]),
        fn("read_text_file",
           "Прочитать содержимое текстового файла",
           ["path": ["type": "string",
                     "description": "Полный путь к текстовому файлу"]],
           ["path"]),
        fn("open_file",
           "Открыть файл или папку в стандартном приложении macOS",
           ["path": ["type": "string",
                     "description": "Полный путь к файлу или папке"]],
           ["path"]),
        fn("create_folder",
           "Создать новую папку. В path ОБЯЗАТЕЛЬНО укажи полный путь вместе с именем новой папки. Если пользователь говорит «на рабочем столе» или «Desktop» — используй ~/Desktop/ИмяПапки. Если место не уточнено — создавай на ~/Desktop.",
           ["path": ["type": "string",
                     "description": "Полный путь к новой папке, включая её имя. Примеры: ~/Desktop/AlakeyaTest, ~/Documents/Проект, ~/Desktop/СписокДел. Нельзя передавать просто ~/Desktop — нужно имя папки после /"]],
           ["path"]),
    ]

    private static func fn(_ name: String, _ desc: String,
                           _ props: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "function", "function": [
            "name": name, "description": desc,
            "parameters": ["type": "object", "properties": props,
                           "required": required, "additionalProperties": false],
        ]]
    }
}
