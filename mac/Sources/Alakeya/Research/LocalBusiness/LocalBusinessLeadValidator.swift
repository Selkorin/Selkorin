import Foundation

// ============================================================
// LocalBusinessLeadValidator.swift — validates phone numbers,
// website URLs, and addresses. Rejects masked/fake contacts.
// ============================================================

enum LocalBusinessLeadValidator {

    // MARK: - Phone

    /// Returns true only if the phone looks like a real, unmasked number.
    static func isValidPhone(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }

        // Reject masked numbers: X, *, •, "показать", "скрыт", "hidden"
        let maskedChars: Set<Character> = ["X", "x", "Х", "х", "*", "•", "…"]
        if s.unicodeScalars.contains(where: { maskedChars.contains(Character($0)) }) { return false }
        let lower = s.lowercased()
        if lower.contains("показать") || lower.contains("скрыт") ||
           lower.contains("hidden") || lower.contains("contact") { return false }

        // Must have at least 10 digits
        let digits = s.filter { $0.isNumber }
        return digits.count >= 10
    }

    static func normalizePhone(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPhone(s) else { return "" }
        var digits = String(s.filter { $0.isNumber })
        if digits.count == 11, digits.hasPrefix("8") {
            digits.removeFirst()
            digits = "7" + digits
        } else if digits.count == 10 {
            digits = "7" + digits
        }
        guard digits.count == 11, digits.hasPrefix("7") else { return s }
        let start = digits.index(after: digits.startIndex)
        let a = digits[start..<digits.index(start, offsetBy: 3)]
        let bStart = digits.index(start, offsetBy: 3)
        let b = digits[bStart..<digits.index(bStart, offsetBy: 3)]
        let cStart = digits.index(bStart, offsetBy: 3)
        let c = digits[cStart..<digits.index(cStart, offsetBy: 2)]
        let dStart = digits.index(cStart, offsetBy: 2)
        let d = digits[dStart..<digits.index(dStart, offsetBy: 2)]
        return "+7 (\(a)) \(b)-\(c)-\(d)"
    }

    // MARK: - Website

    /// Classify a website URL/string into WebsiteStatus.
    static func classifyWebsite(_ raw: String) -> WebsiteStatus {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty, s != "-", s != "—", s != "н/д", s != "нет" else {
            return .noWebsite
        }
        // Social networks
        let socials = ["vk.com", "vkontakte.ru", "instagram.com", "facebook.com",
                       "t.me", "telegram.me", "ok.ru", "odnoklassniki.ru",
                       "youtube.com", "tiktok.com", "whatsapp.com"]
        if socials.contains(where: { s.contains($0) }) { return .socialOnly }

        // Directory listing pages (not a real website)
        let directories = ["yandex.ru/maps", "2gis.ru", "avito.ru", "zoon.ru",
                           "tripadvisor.com", "flamp.ru", "otzovik.com"]
        if directories.contains(where: { s.contains($0) }) { return .noWebsite }

        // Looks like a real domain
        if s.contains(".") && !s.hasPrefix("yandex") {
            return .hasWebsite
        }
        return .unknown
    }

    // MARK: - Address

    static func isValidAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > 5 else { return false }
        let lower = s.lowercased()
        let streetWords = ["ул.", "улица", "проспект", "пр.", "пер.", "шоссе",
                           "наб.", "площадь", "бульвар", "набережная", "переулок"]
        return streetWords.contains(where: { lower.contains($0) }) ||
               s.range(of: #"\d"#, options: .regularExpression) != nil
    }

    // MARK: - Lead

    static func validate(_ lead: LocalBusinessLead) -> LocalBusinessLead {
        var out = lead

        // Clean email
        if !out.email.isEmpty && !isValidEmail(out.email) {
            out.email = ""
        }

        // Clean phone
        if !isValidPhone(out.phone) {
            let wasPhone = out.phone
            out.phone = ""
            if !wasPhone.isEmpty {
                out.notes += out.notes.isEmpty ? "Телефон скрыт в источнике" : "; Телефон скрыт"
                out.confidence = max(0, out.confidence - 0.2)
            }
        } else {
            out.phone = normalizePhone(out.phone)
        }

        // Classify website
        out.websiteStatus = classifyWebsite(out.website)
        if out.websiteStatus == .noWebsite || out.websiteStatus == .socialOnly {
            // Don't store directory/social as a "website"
            if out.websiteStatus == .socialOnly {
                // keep social URL for reference but lower confidence
            } else {
                out.website = ""
            }
        }

        return out
    }

    static func hasUsableName(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2 else { return false }
        let lower = name.lowercased()
        let junkPatterns = [
            #"^[-—]+$"#,
            #"^https?://"#,
            #"\.ru$|\.com$|\.рф$"#,
            #"яндекс|google|2гис|duckduckgo|поиск|карты|captcha|капч[аиу]"#,
            #"подтвердите[, ]+что|не робот|запросы отправляли вы|robot check|verify you are human|unusual traffic|access denied|доступ ограничен"#,
            #"открыть|показать|подробнее|перейти|маршрут"#,
            #"%[0-9a-f]{2}"#,
        ]
        return !junkPatterns.contains {
            lower.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    // MARK: - Email

    static func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 254 else { return false }
        return s.range(of: #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#,
                       options: .regularExpression) != nil
    }

    static func isActionable(_ lead: LocalBusinessLead, requirePhone: Bool) -> Bool {
        guard hasUsableName(lead.name) else { return false }
        if requirePhone {
            return isValidPhone(lead.phone)
        }
        return !lead.phone.isEmpty || !lead.email.isEmpty || !lead.address.isEmpty || !lead.website.isEmpty
    }

    // MARK: - Deduplication key

    static func deduplicateKey(_ lead: LocalBusinessLead) -> String {
        let name = lead.name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = lead.phone.filter { $0.isNumber }
        return "\(name)|\(phone)"
    }
}
