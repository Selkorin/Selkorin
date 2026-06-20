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

        // Clean phone
        if !isValidPhone(out.phone) {
            let wasPhone = out.phone
            out.phone = ""
            if !wasPhone.isEmpty {
                out.notes += out.notes.isEmpty ? "Телефон скрыт в источнике" : "; Телефон скрыт"
                out.confidence = max(0, out.confidence - 0.2)
            }
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

    // MARK: - Deduplication key

    static func deduplicateKey(_ lead: LocalBusinessLead) -> String {
        let name = lead.name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = lead.phone.filter { $0.isNumber }
        return "\(name)|\(phone)"
    }
}
