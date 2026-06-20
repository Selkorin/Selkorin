import Foundation

// ============================================================
// LocalBusinessExtractionNormalizer.swift
// Converts raw browser/extractor output (JSON strings from
// AlakeyaBrowser) into validated LocalBusinessLead structs.
// Never invents contact data — only uses what's explicitly
// present in the source text.
// ============================================================

enum LocalBusinessExtractionNormalizer {

    // MARK: - Business Cards JSON

    /// Parse JSON string from extract_business_cards into leads.
    static func parseBusinessCards(_ json: String, source: String, sourceURL: String, city: String) -> [LocalBusinessLead] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return parsePageText(json, source: source, sourceURL: sourceURL, city: city)
        }
        let arr: [[String: Any]]
        if let direct = root as? [[String: Any]] {
            arr = direct
        } else if let object = root as? [String: Any],
                  let cards = object["cards"] as? [[String: Any]] {
            arr = cards
        } else {
            return []
        }

        return arr.compactMap { card -> LocalBusinessLead? in
            let name    = (card["name"]    as? String ?? card["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let address = (card["address"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let phone   = firstString(card["phone"]) ?? firstString(card["phones"]) ?? ""
            let website = (card["website"] as? String ?? card["url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let rating  = firstString(card["rating"]) ?? firstString(card["ratings"]) ?? ""

            guard !name.isEmpty else { return nil }

            let lead = LocalBusinessLead(
                name: name,
                city: city,
                address: address,
                phone: phone,
                website: website,
                sourceName: source,
                sourceURL: sourceURL,
                notes: rating.isEmpty ? "" : "Рейтинг: \(rating)",
                confidence: address.isEmpty && phone.isEmpty ? 0.3 : 0.7
            )
            return LocalBusinessLeadValidator.validate(lead)
        }
    }

    // MARK: - Contact Cards JSON

    static func parseContactCards(_ json: String, source: String, sourceURL: String, city: String) -> [LocalBusinessLead] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let arr: [[String: Any]]
        if let direct = root as? [[String: Any]] {
            arr = direct
        } else if let object = root as? [String: Any] {
            arr = [object]
        } else {
            return []
        }

        return arr.compactMap { card -> LocalBusinessLead? in
            let name  = (card["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let phone = firstString(card["phone"])
                ?? firstString(card["phones"])
                ?? firstString(card["tel"])
                ?? ""
            let addr  = (card["address"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty || !phone.isEmpty else { return nil }
            let lead = LocalBusinessLead(
                name: name,
                city: city,
                address: addr,
                phone: phone,
                sourceName: source,
                sourceURL: sourceURL,
                notes: "Контактная карточка",
                confidence: 0.5
            )
            return LocalBusinessLeadValidator.validate(lead)
        }
    }

    // MARK: - Page text fallback

    /// Heuristic extraction from raw page text when structured JSON fails.
    /// Only extracts visible text — never invents data.
    static func parsePageText(_ text: String, source: String, sourceURL: String, city: String) -> [LocalBusinessLead] {
        var leads: [LocalBusinessLead] = []
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let phoneRE = try! NSRegularExpression(pattern: #"[\+7|8][\s\-\(]?\d{3}[\s\-\)]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}"#)

        var currentName = ""
        var currentPhone = ""
        var currentAddr = ""

        for line in lines {
            guard !line.isEmpty else {
                // Empty line may mark end of card block
                if !currentName.isEmpty {
                    var lead = LocalBusinessLead(
                        name: currentName,
                        city: city,
                        address: currentAddr,
                        phone: currentPhone,
                        sourceName: source,
                        sourceURL: sourceURL,
                        notes: "Данные из текста страницы",
                        confidence: 0.3
                    )
                    lead = LocalBusinessLeadValidator.validate(lead)
                    if lead.isUsable { leads.append(lead) }
                }
                currentName = ""; currentPhone = ""; currentAddr = ""
                continue
            }

            // Phone detection
            let phoneMatches = phoneRE.matches(in: line, range: NSRange(line.startIndex..., in: line))
            if let m = phoneMatches.first, let r = Range(m.range, in: line) {
                currentPhone = String(line[r])
                continue
            }

            // Address detection
            let addrWords = ["ул.", "улица", "проспект", "пр.", "пер.", "шоссе", "наб."]
            if addrWords.contains(where: { line.contains($0) }) && line.count < 120 {
                currentAddr = line
                continue
            }

            // Name heuristic: looks like a business name (2-6 words, starts with capital, not too long)
            if currentName.isEmpty && line.count < 80 && line.count > 3 {
                let words = line.components(separatedBy: " ")
                if words.count >= 1 && words.count <= 6 {
                    if let first = words.first?.first, first.isUppercase {
                        currentName = line
                    }
                }
            }
        }
        // Flush last block
        if !currentName.isEmpty {
            var lead = LocalBusinessLead(
                name: currentName, city: city,
                address: currentAddr, phone: currentPhone,
                sourceName: source, sourceURL: sourceURL,
                notes: "Данные из текста страницы", confidence: 0.3
            )
            lead = LocalBusinessLeadValidator.validate(lead)
            if lead.isUsable { leads.append(lead) }
        }

        return leads
    }

    // MARK: - Deduplication

    static func deduplicate(_ leads: [LocalBusinessLead]) -> [LocalBusinessLead] {
        var seen = Set<String>()
        return leads.filter { lead in
            let key = LocalBusinessLeadValidator.deduplicateKey(lead)
            return seen.insert(key).inserted
        }
    }

    private static func firstString(_ value: Any?) -> String? {
        if let string = value as? String {
            let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
        if let strings = value as? [String] {
            return strings.first {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
