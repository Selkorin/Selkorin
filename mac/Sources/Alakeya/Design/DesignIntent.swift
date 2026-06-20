import Foundation

enum DesignIntent {
    static func requestsVectorization(_ text: String) -> Bool {
        let value = text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let directPhrases = [
            "векториз",
            "vectorize",
            "convert to vector",
            "convert to svg"
        ]
        if directPhrases.contains(where: value.contains) {
            return true
        }

        let targets = ["svg", "вектор"]
        let actions = [
            "сделай", "создай", "переведи", "преобразуй",
            "конвертируй", "сконвертируй", "сконвектируй"
        ]
        return targets.contains(where: value.contains)
            && actions.contains(where: value.contains)
    }
}
