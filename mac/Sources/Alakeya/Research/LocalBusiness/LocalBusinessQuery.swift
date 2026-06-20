import Foundation

// ============================================================
// LocalBusinessQuery.swift — parsed representation of a local
// business research request with all intent fields extracted.
// ============================================================

struct LocalBusinessQuery {
    let rawText: String
    let category: String           // "салоны красоты", "клиники" etc.
    let city: String?              // nil = city not specified, must ask
    let region: String?
    let targetCount: Int           // default 10
    let requireNoWebsite: Bool     // "без сайта"
    let requirePhone: Bool         // "с телефоном" or contact intent
    let requestedSources: [LocalBusinessSearchSource]
    let exportFormat: String?      // "csv", "pdf", "docx", nil
    let shouldExport: Bool

    // MARK: - Parser

    static func parse(from text: String) -> LocalBusinessQuery {
        let lower = text.lowercased()

        // ── Target count ──────────────────────────────────────
        let countPattern = try! NSRegularExpression(pattern: #"\b(\d+)\b"#)
        let countMatches = countPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let targetCount = countMatches.compactMap { m -> Int? in
            guard let r = Range(m.range(at: 1), in: text) else { return nil }
            let n = Int(text[r])
            return (n != nil && n! >= 2 && n! <= 500) ? n : nil
        }.first ?? 10

        // ── City extraction ───────────────────────────────────
        let cityPatterns: [(pattern: String, group: Int)] = [
            (#"(?:в|из|по|для)\s+([А-ЯЁ][а-яёА-ЯЁ]+(?:\s+[А-ЯЁ][а-яёА-ЯЁ]+)?)\b"#, 1),
            (#"(Севастопол[еьи]|Ялт[еаи]|Москв[еаи]|Санкт-Петербург[еа]?|Симферопол[еьи]|Евпатори[иея]|Феодоси[иея]|Керч[иьею]|Алушт[еаи]|Судак[еа]?)"#, 0),
        ]
        var city: String? = nil
        for (pattern, group) in cityPatterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(m.range(at: group), in: text) {
                let raw = String(text[r])
                // Normalise inflections → nominative
                city = normalizeCityName(raw)
                break
            }
        }

        // ── Category extraction ───────────────────────────────
        let categoryMap: [(pattern: String, label: String)] = [
            (#"салон[ыа]?\s+красот[ыа]"#,  "салоны красоты"),
            (#"парикмахерск"#,              "парикмахерские"),
            (#"барбершоп"#,                 "барбершопы"),
            (#"клиник[аи]?"#,               "клиники"),
            (#"стоматолог"#,                "стоматологии"),
            (#"ресторан[ыа]?"#,             "рестораны"),
            (#"кафе"#,                      "кафе"),
            (#"отел(?:ь|я|и|ей|ям|ями|ях)?"#, "отели"),
            (#"гостиниц[аы]?"#,             "гостиницы"),
            (#"студи[яи]"#,                 "студии"),
            (#"фитнес"#,                    "фитнес-клубы"),
            (#"массаж"#,                    "массажные салоны"),
            (#"автосерви[с]"#,              "автосервисы"),
            (#"юрид"#,                      "юридические компании"),
        ]
        var category = "организации"
        for (pattern, label) in categoryMap {
            if lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                category = label; break
            }
        }

        // ── Filters ───────────────────────────────────────────
        let noWebsite = lower.range(of: #"(без сайта|нет сайта|не было сайта|сайт отсутств|без web)"#,
                                    options: [.regularExpression, .caseInsensitive]) != nil
        let requirePhone = lower.range(of: #"(контакт|телефон|звонок|номер|позвонить)"#,
                                       options: [.regularExpression, .caseInsensitive]) != nil

        // ── Requested sources ─────────────────────────────────
        var sources: [LocalBusinessSearchSource] = []
        if lower.range(of: #"яндекс.?карт|yandex.?maps?"#, options: [.regularExpression, .caseInsensitive]) != nil {
            sources.append(.yandexMaps)
        }
        if lower.range(of: #"2гис|2gis"#, options: [.regularExpression, .caseInsensitive]) != nil {
            sources.append(.twoGis)
        }
        if lower.range(of: #"google|гугл"#, options: [.regularExpression, .caseInsensitive]) != nil {
            sources.append(.googleSearch)
        }
        if lower.range(of: #"яндекс.?бизнес|yandex.?business"#, options: [.regularExpression, .caseInsensitive]) != nil {
            if !sources.contains(.yandexMaps) { sources.append(.yandexMaps) }
        }
        if sources.isEmpty {
            sources = [.yandexMaps, .twoGis, .yandexSearch, .googleSearch]
        }

        // ── Export format ─────────────────────────────────────
        var exportFormat: String? = nil
        var shouldExport = false
        if lower.range(of: #"(excel|xlsx|иксель|эксель)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            exportFormat = "csv"; shouldExport = true
        } else if lower.range(of: #"\bcsv\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            exportFormat = "csv"; shouldExport = true
        } else if lower.range(of: #"\bpdf\b|\bпдф\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            exportFormat = "pdf"; shouldExport = true
        } else if lower.range(of: #"(word|docx|ворд)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            exportFormat = "docx"; shouldExport = true
        } else if lower.range(of: #"(выгруз|экспорт|скачать|файл)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            exportFormat = "csv"; shouldExport = true
        }

        return LocalBusinessQuery(
            rawText: text,
            category: category,
            city: city,
            region: city,
            targetCount: targetCount,
            requireNoWebsite: noWebsite,
            requirePhone: requirePhone,
            requestedSources: sources,
            exportFormat: exportFormat,
            shouldExport: shouldExport
        )
    }

    func resolvingCity(_ city: String) -> LocalBusinessQuery {
        LocalBusinessQuery(
            rawText: rawText,
            category: category,
            city: city,
            region: city,
            targetCount: targetCount,
            requireNoWebsite: requireNoWebsite,
            requirePhone: requirePhone,
            requestedSources: requestedSources,
            exportFormat: exportFormat,
            shouldExport: shouldExport
        )
    }

    /// Parses a reply to the explicit city/region follow-up.
    /// This is intentionally strict so an unrelated new command does not
    /// accidentally become a location.
    static func parseCityContinuation(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }

        let lower = trimmed.lowercased()
        if lower.range(
            of: #"\b(отмена|отмени|стоп|найди|поищи|собери|создай|сделай|открой|покажи|экспорт)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return nil
        }

        let candidate = trimmed.replacingOccurrences(
            of: #"^(?:в|по|город|регион)\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: CharacterSet(charactersIn: " .,!?:;"))

        guard candidate.range(
            of: #"^[\p{L}][\p{L}\-]*(?:[\s\-][\p{L}][\p{L}\-]*){0,3}$"#,
            options: .regularExpression
        ) != nil else { return nil }

        return normalizeCityName(
            candidate.prefix(1).uppercased() + candidate.dropFirst().lowercased()
        )
    }

    private static func normalizeCityName(_ raw: String) -> String {
        let map: [String: String] = [
            "Севастополе": "Севастополь", "Севастополя": "Севастополь",
            "Ялте": "Ялта", "Ялты": "Ялта",
            "Москве": "Москва", "Москвы": "Москва",
            "Санкт-Петербурге": "Санкт-Петербург", "Санкт-Петербурга": "Санкт-Петербург",
            "Симферополе": "Симферополь", "Симферополя": "Симферополь",
            "Евпатории": "Евпатория", "Феодосии": "Феодосия",
            "Керчи": "Керчь", "Алуште": "Алушта", "Судаке": "Судак",
        ]
        return map[raw] ?? raw
    }
}
