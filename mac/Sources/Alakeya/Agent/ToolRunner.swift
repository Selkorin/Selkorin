import Foundation

// ============================================================
// ToolRunner.swift — permission gate → executor → journal, and the
// task loop that drives the 7 statuses (HANDOFF §4, integration §2/§4).
// ============================================================

@MainActor
final class ToolRunner {
    private let store: AgentStore
    private let policy = PolicyEngine.shared
    private let executors = Executors()
    private let speech = SpeechService()
    private var pendingLocalBusinessQueries: [UUID: LocalBusinessQuery] = [:]

    init(store: AgentStore) { self.store = store }

    // ── public entry points ───────────────────────────────
    func runTask(_ text: String, sessionID: UUID, agentID: String) {
        Task { await runTaskAsync(text, sessionID: sessionID, agentID: agentID) }
    }

    func resolvePending(_ decision: Decision) {
        guard let pending = store.pending else { return }
        store.pending = nil
        pending.resolve(decision)
    }

    // ── the loop ──────────────────────────────────────────
    private func runTaskAsync(_ text: String, sessionID: UUID, agentID: String) async {
        store.setStatus(.thinking)
        store.task = nil
        let sessionHistory = store.messages(for: sessionID)

        // Resume a deterministic local-business request after the explicit
        // city/region follow-up. The original category, count and filters must
        // not be delegated back to the model or inferred a second time.
        if let pendingQuery = pendingLocalBusinessQueries[sessionID] {
            if let city = LocalBusinessQuery.parseCityContinuation(from: text) {
                pendingLocalBusinessQueries[sessionID] = nil
                await appendLocalBusinessResult(
                    pendingQuery.resolvingCity(city),
                    sessionID: sessionID
                )
                return
            }
            // A new command replaces the unfinished request.
            pendingLocalBusinessQueries[sessionID] = nil
        }

        // Handle memory commands locally — no AI call needed.
        if let response = handleMemoryCommand(text) {
            store.appendMessage(
                ChatMessage(role: .assistant, content: response),
                to: sessionID
            )
            store.setStatus(.ready)
            return
        }

        do {
            let history = buildHistory(from: sessionHistory)
            let memCtx  = MemoryStore.shared.composeContext()

            let scope = Self.detectScope(text)
            let tools = ToolRouter.shared.toolSchemas(scope: scope)

            let toolNames = tools.compactMap {
                ($0["function"] as? [String: Any])?["name"] as? String
            }
            print("[AI Tools] scope=\(scope) count=\(tools.count) names=[\(toolNames.joined(separator: ", "))]")

            guard tools.count <= 64 else {
                throw AIClientError.server(
                    status: 400,
                    message: "Tool scope too broad: \(scope). Count: \(tools.count)"
                )
            }

            // ── Deterministic local business pipeline ─────────
            // Bypasses free-form agent for reliable structured extraction.
            if scope == .localBusinessResearch || scope == .localBusinessResearchThenExport {
                let query = LocalBusinessQuery.parse(from: text)
                guard query.city != nil else {
                    pendingLocalBusinessQueries[sessionID] = query
                    store.appendMessage(
                        ChatMessage(
                            role: .assistant,
                            content: "В каком городе искать \(query.category)? Укажите город или регион."
                        ),
                        to: sessionID
                    )
                    store.setStatus(.ready)
                    return
                }
                await appendLocalBusinessResult(query, sessionID: sessionID)
                return
            }

            // ── Standard path (plain gen / export / research / browser) ──
            let client = try AIClient(settings: effectiveSettings(agentID: agentID))

            // Resolve "this" → inject last meaningful content for export.
            let resolvedText = scope == .documentExport
                ? ExportInputResolver.resolve(userText: text, history: sessionHistory)
                : text

            ExportResultStore.shared.clear()

            let reply: String
            if tools.isEmpty {
                reply = try await client.sendMessage(
                    userText: resolvedText, history: history, memoryContext: memCtx
                )
            } else {
                reply = try await runAgenticLoop(
                    client: client, userText: resolvedText, history: history,
                    memoryContext: memCtx, tools: tools
                )
            }

            let fileAttachments = ExportResultStore.shared.drain()

            // Extract sources when the reply came from a browser or research scope.
            let sources: [SourceReference]
            switch scope {
            case .browser, .research, .browserAndConnectors, .all:
                sources = SourceExtractor.extractLinks(from: reply)
            default:
                sources = []
            }

            // Parse structured tables from reply (for "выгрузи это" export later)
            let structuredTables = MarkdownTableParser.parse(from: reply)

            store.appendMessage(
                ChatMessage(
                    role: .assistant, content: reply,
                    sources: sources, fileAttachments: fileAttachments,
                    structuredTables: structuredTables
                ),
                to: sessionID
            )
            store.setStatus(.speaking)
            if store.activeSessionID == sessionID {
                store.transcript = reply
            }

            let voiceMode = store.settings.voice.voiceMode
            if voiceMode != .off, store.activeSessionID == sessionID {
                let speechText = SpeechOutputFormatter.format(reply, mode: voiceMode)
                if !speechText.isEmpty {
                    do {
                        try await speech.speak(speechText, settings: store.settings)
                    } catch {
                        store.showError(
                            "Ответ получен, но озвучивание недоступно: \(humanize(error))",
                            blocked: false
                        )
                    }
                }
            }
            store.setStatus(.ready)
        } catch {
            let message = humanize(error)
            store.appendMessage(
                ChatMessage(
                    role: .assistant,
                    content: "Не удалось получить ответ: \(message)"
                ),
                to: sessionID
            )
            store.setStatus(.error)
            store.showError(message, blocked: isConfigurationError(error))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if store.status == .error { store.setStatus(.ready) }
            }
        }
    }

    private func appendLocalBusinessResult(
        _ query: LocalBusinessQuery,
        sessionID: UUID
    ) async {
        let result = await LocalBusinessSearchCoordinator.run(query: query, store: store)
        let structuredTables: [ParsedMarkdownTable] = result.table.map { [$0] } ?? []

        var seenURLs = Set<String>()
        let sources: [SourceReference] = result.leads.compactMap { lead in
            guard !lead.sourceURL.isEmpty else { return nil }
            guard seenURLs.insert(lead.sourceURL).inserted else { return nil }
            return SourceReference(title: lead.sourceName, url: lead.sourceURL)
        }

        store.appendMessage(
            ChatMessage(
                role: .assistant,
                content: result.formattedText,
                sources: sources,
                fileAttachments: result.fileAttachments,
                structuredTables: structuredTables
            ),
            to: sessionID
        )
        store.setStatus(.ready)
    }

    private func effectiveSettings(agentID: String) -> Settings {
        AgentProfileStore.shared.resolvedSettings(
            base: store.settings,
            activeAgentID: agentID
        )
    }

    private enum ToolResult { case ok, denied, failed }

    // Returns (status, output string) so the agentic loop can feed results back to the model.
    private func runTool(_ action: Action) async -> (ToolResult, String) {
        if !policy.shouldAutoConfirm(action) {
            store.setStatus(.awaiting)
            log(action, action.scope, "awaiting")
            let decision = await requestApproval(action)
            switch decision {
            case .deny:
                log(action, "Отклонено", "denied")
                store.setStatus(.ready)
                return (.denied, "Отклонено пользователем.")
            case .always:
                policy.remember(action)
            case .once:
                break
            }
        }

        store.setStatus(.acting)
        do {
            let result = try await executors.run(action)
            log(action, result.summary, "ok")
            return (.ok, result.summary)
        } catch {
            let message = humanize(error)
            store.setStatus(.error)
            log(action, message, "blocked")
            store.showError(message, blocked: isBlocked(error))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if store.status == .error { store.setStatus(.ready) }
            }
            return (.failed, "Ошибка: \(message)")
        }
    }

    // ── Agentic loop: AI ↔ tools, bounded with repeat protection ──
    private func runAgenticLoop(
        client: AIClient,
        userText: String,
        history: [ChatMessage],
        memoryContext: String,
        tools: [[String: Any]]
    ) async throws -> String {
        var response = try await client.sendWithTools(
            userText: userText, history: history, memoryContext: memoryContext, tools: tools
        )
        var previousSignature = ""
        var repeatedRounds = 0
        for _ in 0..<8 {
            guard case .toolCalls(let calls, let context) = response else { break }
            let signature = calls.map { call in
                let args = call.args.sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "&")
                return "\(call.name):\(args)"
            }.joined(separator: "|")
            if signature == previousSignature {
                repeatedRounds += 1
                if repeatedRounds >= 2 {
                    return "Я остановила повторяющиеся действия в браузере, чтобы не зациклиться."
                }
            } else {
                previousSignature = signature
                repeatedRounds = 0
            }
            var results: [ToolCallResult] = []
            for call in calls {
                guard let action = ToolRouter.shared.makeAction(toolName: call.name, args: call.args)
                else {
                    results.append(ToolCallResult(
                        callID: call.id, toolName: call.name,
                        output: "Инструмент '\(call.name)' не найден."))
                    continue
                }
                let (_, summary) = await runTool(action)
                store.setStatus(.thinking)
                results.append(ToolCallResult(callID: call.id, toolName: call.name, output: summary))
            }
            response = try await client.sendWithToolResults(
                context: context, results: results, tools: tools
            )
        }
        if case .text(let text) = response { return text }
        return "Готово."
    }

    /// Suspend until the PermissionCard resolves a decision, with a 120 s timeout.
    private func requestApproval(_ action: Action) async -> Decision {
        await withCheckedContinuation { cont in
            var resolved = false
            let resolve: (Decision) -> Void = { decision in
                guard !resolved else { return }
                resolved = true
                self.store.pending = nil
                cont.resume(returning: decision)
            }
            store.pending = PendingApproval(id: action.id, action: action) { decision in
                resolve(decision)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                if store.pending?.id == action.id { resolve(.deny) }
            }
        }
    }

    // ── helpers ───────────────────────────────────────────
    private func log(_ action: Action, _ subtitle: String, _ status: String) {
        store.log(ActivityEntry(
            id: "log_\(Date().timeIntervalSince1970)_\(Int.random(in: 0...9999))",
            time: Date(), kind: action.type.rawValue,
            title: action.title, subtitle: subtitle, status: status))
    }

    private func humanize(_ error: Error) -> String {
        let s = error.localizedDescription
        if s.range(of: "(?i)not found|не найден", options: .regularExpression) != nil {
            return "Не нашёл нужный элемент или приложение."
        }
        return s.isEmpty ? "Что-то пошло не так." : s
    }

    private func isBlocked(_ error: Error) -> Bool {
        error.localizedDescription.range(of: "(?i)denied|blocked|permission", options: .regularExpression) != nil
    }

    private func isConfigurationError(_ error: Error) -> Bool {
        guard let error = error as? AIClientError else { return false }
        switch error {
        case .providerNotSelected, .apiKeyMissing, .modelMissing, .invalidBaseURL, .invalidAPIKey:
            return true
        case .rateLimited, .server, .invalidResponse, .network:
            return false
        }
    }

    // ── history ───────────────────────────────────────────
    private static let ChatHistoryLimit = 20

    private func buildHistory(from messages: [ChatMessage]) -> [ChatMessage] {
        let recent = Array(messages.suffix(Self.ChatHistoryLimit))
        let filtered = recent.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // Drop leading assistant messages — providers require history to start with user.
        guard let firstUser = filtered.firstIndex(where: { $0.role == .user }) else { return [] }
        return Array(filtered[firstUser...])
    }

    // ── memory commands ───────────────────────────────────

    private func handleMemoryCommand(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // "Покажи память" / "Что ты обо мне знаешь?"
        if t.range(of: #"^(покажи\s+память|что\s+ты\s+обо\s+мне\s+знаешь|что\s+знаешь\s+обо\s+мне)"#,
                   options: [.regularExpression, .caseInsensitive]) != nil {
            let ctx = MemoryStore.shared.composeContext()
            return ctx.isEmpty
                ? "Я пока ничего о тебе не знаю. Напиши «Запомни: ...» чтобы сохранить факт."
                : "Вот что я о тебе знаю:\n\n" + ctx
        }

        // "Забудь: X"
        if let what = firstGroup(t, #"^[Зз]абудь[,:]?\s+(.+)$"#) {
            let lower = what.lowercased()
            if let entry = MemoryStore.shared.entries.first(where: {
                $0.key.lowercased() == lower || $0.value.lowercased().contains(lower)
            }) {
                MemoryStore.shared.delete(id: entry.id)
                return "Забыла: \(entry.key) — \(entry.value)"
            }
            return "Не нашла такого воспоминания."
        }

        // "Запомни: X" / "Запомни, что X"
        if let fact = firstGroup(t, #"^[Зз]апомни[,:]?\s+(?:[Чч]то\s+)?(.+)$"#) {
            let key = detectMemoryKey(fact)
            MemoryStore.shared.upsert(key: key, value: fact)
            return "Запомнила: \(key) — \(fact)"
        }

        return nil
    }

    private static let memoryKeyRules: [(pattern: String, key: String)] = [
        (#"(меня зовут|моё имя|мое имя|my name|зови меня)"#,               "name"),
        (#"(проект|project|работаю над|создаю|разрабатываю|пишу)"#,         "project"),
        (#"(цель|goal|хочу достичь|планирую запустить|стремлюсь)"#,          "goal"),
        (#"(предпочитаю|предпочтение|нравится когда|prefer|люблю чтобы)"#,   "preference"),
    ]

    private func detectMemoryKey(_ text: String) -> String {
        let lower = text.lowercased()
        for (pattern, key) in Self.memoryKeyRules {
            if lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return key
            }
        }
        return "note"
    }

    private func firstGroup(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return text[r].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ── Tool scope detection ──────────────────────────────

    static func detectScope(_ text: String) -> ToolScope {
        let lower = text.lowercased()

        // ── 1. Export signals (checked first) ────────────────
        let exportPatterns: [String] = [
            #"(выгруз|экспортир|сохрани).{0,25}(pdf|пдф)"#,
            #"(выгруз|экспортир|сохрани).{0,25}(word|docx|ворд|doc\b)"#,
            #"(выгруз|экспортир|сохрани).{0,25}(csv|excel|эксель|xlsx|таблиц)"#,
            #"(выгруз|экспортир|сохрани).{0,25}(markdown|md\b|файл)"#,
            #"(сделай|создай|генерир).{0,20}(pdf|пдф|word|docx|ворд|csv|excel|xlsx)"#,
            #"\b(export|save as|скачать как)\b.{0,20}(pdf|docx|csv|xlsx|word|markdown)"#,
            #"^(pdf|docx|csv|xlsx|word|ворд|эксель|markdown)$"#,
            #"(скачать|download).{0,20}(pdf|word|csv|excel|xlsx)"#,
            #"\b(в excel|в иксель|в эксель|в csv|в word|в pdf)\b"#,
        ]
        let hasExport = exportPatterns.contains {
            lower.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }

        // ── 2. Local business / maps research signals ─────────
        // Requires: search verb AND (map source OR lead criteria).
        // "Сделай таблицу отелей" has no search verb → .none (correct).
        // "Найди отели с источниками" has no map/lead signal → falls to .research.
        // "Найди салоны в Яндекс Картах" has map source → .localBusinessResearch.
        let searchVerbsPattern = #"(найди|поищи|собери|вытащи|спарси|посмотри)\b"#
        let mapSourcesPattern  = #"(яндекс.?карт|yandex.?maps?|яндекс.?бизнес|yandex.?business|2гис|2gis|google.?maps?|гугл.?карт)"#
        let leadCriteriaPattern = #"(без сайта|нет сайта|не было сайта|сайт отсутств|только телефон|без.{0,10}web)"#
        // Contact-focused business search (not generic "найди")
        let contactIntentPattern = #"(найди|собери|вытащи).{0,30}(контакт|телефон|адрес).{0,30}(компани|организаци|салон|клиник|барбершоп|студи|ресторан|кафе)"#
        let businessCategoryPattern = #"(салон|парикмахер|барбершоп|клиник|стоматолог|ресторан|кафе|отел|гостиниц|фитнес|массаж|автосервис|юридическ.{0,10}компани)"#

        let hasSearchVerb    = lower.range(of: searchVerbsPattern,    options: [.regularExpression, .caseInsensitive]) != nil
        let hasMapSource     = lower.range(of: mapSourcesPattern,     options: [.regularExpression, .caseInsensitive]) != nil
        let hasLeadFilter    = lower.range(of: leadCriteriaPattern,   options: [.regularExpression, .caseInsensitive]) != nil
        let hasContactIntent = lower.range(of: contactIntentPattern,  options: [.regularExpression, .caseInsensitive]) != nil
        let hasBusinessCategory = lower.range(
            of: businessCategoryPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        // Business category is enough to enter the deterministic pipeline.
        // Missing city is handled there with a precise follow-up question.
        let isLocalBusiness = hasSearchVerb
            && (hasMapSource || hasLeadFilter || hasContactIntent || hasBusinessCategory)

        if isLocalBusiness && hasExport {
            print("[ToolScope] detected=localBusinessResearchThenExport reason=searchVerb+mapOrLead+export text=\"\(text.prefix(80))\"")
            return .localBusinessResearchThenExport
        }
        if isLocalBusiness {
            let reason = hasMapSource ? "mapSource"
                : hasLeadFilter ? "leadFilter"
                : hasContactIntent ? "contactIntent"
                : "businessCategory"
            print("[ToolScope] detected=localBusinessResearch reason=searchVerb+\(reason) text=\"\(text.prefix(80))\"")
            return .localBusinessResearch
        }

        // ── 3. Pure export (no research needed) ──────────────
        if hasExport {
            print("[ToolScope] detected=documentExport reason=export_only text=\"\(text.prefix(60))\"")
            return .documentExport
        }

        // ── 4. Browser control (navigate, click, scroll, etc.) ──
        let browserControlPatterns: [String] = [
            #"(https?://|www\.|\.(com|ru|org|net|io|app|dev)\b)"#,
            #"(прокрути|scroll|скриншот|screenshot|масштаб|zoom\b)"#,
            #"(очисти.{0,10}(кеш|cache|cookie|куки))"#,
            #"(что.{0,20}открыто|текущ.{0,10}(страниц|сайт))"#,
            #"(опиши.{0,10}(страниц|сайт)|что на (странице|сайте))"#,
            #"(подожди.{0,10}загрузку|дождись загрузки)"#,
            #"\b(browser|браузер)\b"#,
            #"(открой|перейди|зайди).{0,10}(сайт|страниц|ссылк|url|http)"#,
            #"(выдели|подсвети|highlight).{0,20}(элемент|кнопк|блок)"#,
            #"\b(seo|сео|аудит.{0,10}(страниц|сайт))\b"#,
        ]
        for pattern in browserControlPatterns {
            if lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                print("[ToolScope] detected=browser reason=browser_control text=\"\(text.prefix(60))\"")
                return .browser
            }
        }

        // ── 5. General web research with explicit source signal ──
        let webResearchPatterns: [String] = [
            #"(найди|поищи).{0,30}(интернет|онлайн|online|web|браузер)"#,
            #"(с источниками|из открытых источников|актуальные данные|из интернета)"#,
            #"(проверь.{0,15}(интернет|онлайн|online|актуальн))"#,
            #"(проанализируй.{0,10}сайт|извлеки.{0,15}с сайта)"#,
        ]
        for pattern in webResearchPatterns {
            if lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                print("[ToolScope] detected=research reason=web_research text=\"\(text.prefix(60))\"")
                return .research
            }
        }

        // ── 7. Plain generation — no tools ───────────────────
        print("[ToolScope] detected=none reason=plain_generation text=\"\(text.prefix(60))\"")
        return .none
    }

    // ── enrich a tool call into a UI-ready action ─────────
    static func action(from call: ToolCall) -> Action {
        let a = call.args
        switch call.name {
        case .openApp:
            let app = a["app"] ?? ""
            return Action(type: .openApp, title: "Открыть \(app)",
                          description: "Запустить приложение \(app).",
                          target: app, scope: app, reversible: true, args: a)
        case .navigateURL:
            return Action(type: .navigateURL, title: "Открыть ссылку",
                          description: "Перейти на \(a["url"] ?? "").",
                          target: "Safari", scope: "Браузер", reversible: true, args: a)
        case .search:
            return Action(type: .search, title: "Поиск",
                          description: "Найти: «\(a["query"] ?? "")».",
                          target: "Браузер", scope: "Браузер", reversible: true, args: a)
        case .typeText:
            return Action(type: .typeText, title: "Ввести текст",
                          description: "Напечатать: «\(String((a["text"] ?? "").prefix(80)))».",
                          target: a["target"] ?? "активное поле", scope: a["app"] ?? "—",
                          reversible: true, args: a)
        case .clickElement:
            return Action(type: .clickElement, title: "Нажать элемент",
                          description: "Кликнуть «\(a["text"] ?? a["target"] ?? "")».",
                          target: a["target"] ?? a["text"] ?? "", scope: a["app"] ?? "—",
                          reversible: true, args: a)
        case .sendMessage:
            return Action(type: .sendMessage, title: "Отправить сообщение",
                          description: "Отправить «\(String((a["text"] ?? "").prefix(80)))» — \(a["target"] ?? "").",
                          target: a["target"] ?? "", scope: a["app"] ?? "Мессенджер",
                          reversible: false, args: a)
        case .sendEmail:
            return Action(type: .sendEmail, title: "Отправить письмо",
                          description: "Отправить письмо: \(a["target"] ?? "").",
                          target: a["target"] ?? "", scope: "Mail", reversible: false, args: a)
        case .deleteFile:
            return Action(type: .deleteFile, title: "Удалить файл",
                          description: "Удалить \(a["target"] ?? ""). Действие необратимо.",
                          target: a["target"] ?? "", scope: "Finder", reversible: false, args: a)
        case .runShell:
            return Action(type: .runShell, title: "Выполнить shell-команду",
                          description: "Команда показана ниже. Проверь перед запуском.",
                          target: "Terminal", scope: "Система", reversible: false,
                          code: a["command"], args: a)
        case .makePayment:
            return Action(type: .makePayment, title: "Совершить платёж",
                          description: "Оплата: \(a["target"] ?? "").",
                          target: a["target"] ?? "", scope: "Платежи", reversible: false, args: a)
        case .appleScript:
            return Action(type: .appleScript, title: "AppleScript",
                          description: "Выполнить скрипт.", target: a["target"] ?? "—",
                          scope: "Система", reversible: true, code: a["script"], args: a)
        case .readScreen:
            return Action(type: .readScreen, title: "Прочитать экран",
                          description: "Осмотреть активное окно.", target: "Экран",
                          scope: "Только чтение", reversible: true, args: a)
        case .screenshot:
            return Action(type: .screenshot, title: "Снимок экрана",
                          description: "Сделать снимок для верификации.", target: "Экран",
                          scope: "Только чтение", reversible: true, args: a)
        case .listDirectory:
            let path = a["path"] ?? "~"
            return Action(type: .listDirectory, title: "Список файлов",
                          description: "Содержимое папки \(path).",
                          target: path, scope: "Файловая система", reversible: true, args: a)
        case .readTextFile:
            let path = a["path"] ?? ""
            return Action(type: .readTextFile, title: "Прочитать файл",
                          description: "Прочитать \(path).",
                          target: path, scope: "Файловая система", reversible: true, args: a)
        case .openFile:
            let path = a["path"] ?? ""
            return Action(type: .openFile, title: "Открыть файл",
                          description: "Открыть \(path) в стандартной программе.",
                          target: path, scope: "Finder", reversible: true, args: a)
        case .createFolder:
            let path = a["path"] ?? ""
            return Action(type: .createFolder, title: "Создать папку",
                          description: "Создать \(path).",
                          target: path, scope: "Файловая система", reversible: true, args: a)
        case .browserOpen:
            let value = a["url"] ?? a["query"] ?? "https://www.google.com"
            return Action(type: .browserOpen, title: "Открыть браузер",
                          description: "Открыть \(value) во встроенном браузере.",
                          target: value, scope: "Браузер Алакеи", reversible: true, args: a)
        case .browserReadPage:
            return Action(type: .browserReadPage, title: "Прочитать страницу",
                          description: "Получить видимый текст и элементы страницы.",
                          target: "Текущая страница", scope: "Только чтение",
                          reversible: true, args: a)
        case .browserBack:
            return Action(type: .browserBack, title: "Вернуться назад",
                          description: "Открыть предыдущую страницу.",
                          target: "История", scope: "Браузер Алакеи",
                          reversible: true, args: a)
        case .browserReload:
            return Action(type: .browserReload, title: "Обновить страницу",
                          description: "Перезагрузить текущую страницу.",
                          target: "Текущая страница", scope: "Браузер Алакеи",
                          reversible: true, args: a)
        case .browserScroll:
            return Action(type: .browserScroll, title: "Прокрутить страницу",
                          description: "Прокрутить страницу \(a["direction"] ?? "вниз").",
                          target: a["direction"] ?? "down", scope: "Браузер Алакеи",
                          reversible: true, args: a)
        case .browserWait:
            return Action(type: .browserWait, title: "Дождаться страницы",
                          description: "Подождать загрузку или обновление.",
                          target: "Текущая страница", scope: "Только чтение",
                          reversible: true, args: a)
        case .browserScreenshot:
            return Action(type: .browserScreenshot, title: "Снимок страницы",
                          description: "Сделать снимок браузера.",
                          target: "Текущая страница", scope: "Только чтение",
                          reversible: true, args: a)
        case .browserClick:
            let text = a["text"] ?? ""
            return Action(type: .browserClick, title: "Нажать на сайте",
                          description: "Нажать элемент «\(text)».",
                          target: text, scope: "Браузер Алакеи",
                          reversible: true, args: a)
        case .browserType:
            let field = a["field"] ?? ""
            return Action(type: .browserType, title: "Ввести текст на сайте",
                          description: "Ввести текст в поле «\(field)».",
                          target: field, scope: "Браузер Алакеи",
                          reversible: true, args: a)
        case .browserSelect:
            return Action(type: .browserSelect, title: "Выбрать значение",
                          description: "Выбрать «\(a["value"] ?? "")» в списке.",
                          target: a["element_id"] ?? "", scope: "Браузер Алакеи",
                          reversible: true, args: a)
        case .browserSubmit:
            return Action(type: .browserSubmit, title: "Отправить форму",
                          description: "Подтвердить действие на сайте.",
                          target: a["element_id"] ?? a["text"] ?? "",
                          scope: "Браузер Алакеи", reversible: false, args: a)
        case .browserHardReload:
            return Action(type: .browserHardReload, title: "Принудительная перезагрузка",
                          description: "Перезагрузить страницу без кеша.",
                          target: "Текущая страница", scope: "Браузер Алакеи",
                          reversible: true, args: a)
        case .browserZoom:
            let factor = a["factor"] ?? "1.0"
            return Action(type: .browserZoom, title: "Масштаб браузера",
                          description: "Установить масштаб \(factor).",
                          target: factor, scope: "Браузер Алакеи",
                          reversible: true, args: a)
        case .browserClearCookies:
            return Action(type: .browserClearCookies, title: "Очистить cookie",
                          description: "Удалить файлы cookie. Вы можете выйти из всех аккаунтов.",
                          target: "Файлы cookie", scope: "Браузер Алакеи",
                          reversible: false, args: a)
        case .browserClearCache:
            return Action(type: .browserClearCache, title: "Очистить кеш",
                          description: "Удалить кеш браузера. Страницы загрузятся медленнее.",
                          target: "Кеш браузера", scope: "Браузер Алакеи",
                          reversible: false, args: a)
        case .browserHighlightElement:
            let t = a["text"] ?? a["element_id"] ?? ""
            return Action(type: .browserHighlightElement, title: "Подсветить элемент",
                          description: "Выделить «\(t)» рамкой на странице.",
                          target: t, scope: "Браузер Алакеи", reversible: true, args: a)
        case .browserExtractData:
            return Action(type: .browserExtractData, title: "Извлечь данные страницы",
                          description: "Получить структурированные данные: контакты, цены, соцсети.",
                          target: "Текущая страница", scope: "Только чтение",
                          reversible: true, args: a)
        case .browserSeoAudit:
            return Action(type: .browserSeoAudit, title: "SEO-аудит страницы",
                          description: "Проверить метатеги, H1, alt, canonical и структуру.",
                          target: "Текущая страница", scope: "Только чтение",
                          reversible: true, args: a)
        case .connectorRead:
            return Action(type: .connectorRead, title: "Читать данные",
                          description: "Прочитать данные через коннектор.",
                          target: a["tool_name"] ?? "", scope: "Коннекторы",
                          reversible: true, args: a)
        case .connectorWrite:
            return Action(type: .connectorWrite, title: "Записать данные",
                          description: "Записать данные через коннектор. Изменения сохранятся.",
                          target: a["tool_name"] ?? "", scope: "Коннекторы",
                          reversible: false, args: a)
        case .connectorSend:
            return Action(type: .connectorSend, title: "Отправить / опубликовать",
                          description: "Отправить или опубликовать через коннектор. Необратимо.",
                          target: a["tool_name"] ?? "", scope: "Коннекторы",
                          reversible: false, args: a)

        // ── research ──────────────────────────────────────
        case .searchInternet:
            return Action(type: .searchInternet, title: "Поиск в интернете",
                          description: "Найти информацию по запросу без открытия браузера.",
                          target: a["query"] ?? "", scope: "Поиск", reversible: true, args: a)
        case .researchPlan:
            return Action(type: .researchPlan, title: "Составить план исследования",
                          description: "Определить стратегию поиска и необходимые источники.",
                          target: a["query"] ?? "", scope: "Исследование", reversible: true, args: a)
        case .extractSearchResults:
            return Action(type: .extractSearchResults, title: "Извлечь результаты поиска",
                          description: "Спарсить SERP: заголовки, URL, сниппеты.",
                          target: "Поисковая страница", scope: "Только чтение", reversible: true, args: a)
        case .extractBusinessCards:
            return Action(type: .extractBusinessCards, title: "Извлечь карточки компаний",
                          description: "Собрать: название, телефон, адрес, сайт, рейтинг.",
                          target: "Текущая страница", scope: "Только чтение", reversible: true, args: a)
        case .extractHotelCards:
            return Action(type: .extractHotelCards, title: "Извлечь карточки отелей",
                          description: "Собрать: название, звёзды, рейтинг, цена, отзывы.",
                          target: "Текущая страница", scope: "Только чтение", reversible: true, args: a)
        case .extractContactCards:
            return Action(type: .extractContactCards, title: "Извлечь контакты",
                          description: "Собрать телефоны, email, мессенджеры, адреса.",
                          target: "Текущая страница", scope: "Только чтение", reversible: true, args: a)
        case .extractArticle:
            return Action(type: .extractArticle, title: "Прочитать статью",
                          description: "Извлечь чистый текст статьи без рекламы и навигации.",
                          target: "Текущая страница", scope: "Только чтение", reversible: true, args: a)
        case .qualityScoreResults:
            return Action(type: .qualityScoreResults, title: "Оценить качество источников",
                          description: "Ранжировать список источников по авторитетности и актуальности.",
                          target: "Источники", scope: "Только чтение", reversible: true, args: a)

        // ── document export ───────────────────────────────
        case .exportPDF:
            return Action(type: .exportPDF, title: "Создать PDF",
                          description: "Сохранить документ «\(a["title"] ?? "Отчёт")» в ~/Downloads/ как PDF.",
                          target: a["title"] ?? "Отчёт", scope: "Документы", reversible: true, args: a)
        case .exportDocx:
            return Action(type: .exportDocx, title: "Создать Word (DOCX)",
                          description: "Сохранить документ «\(a["title"] ?? "Документ")» как DOCX/RTF.",
                          target: a["title"] ?? "Документ", scope: "Документы", reversible: true, args: a)
        case .exportCSV:
            return Action(type: .exportCSV, title: "Создать CSV",
                          description: "Сохранить таблицу «\(a["title"] ?? "Таблица")» как CSV.",
                          target: a["title"] ?? "Таблица", scope: "Документы", reversible: true, args: a)
        case .exportMarkdown:
            return Action(type: .exportMarkdown, title: "Создать Markdown",
                          description: "Сохранить «\(a["title"] ?? "Файл")» как .md файл.",
                          target: a["title"] ?? "Файл", scope: "Документы", reversible: true, args: a)
        }
    }
}
