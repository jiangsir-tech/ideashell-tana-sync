import Foundation

/// Native replacement for the former Node.js sync runtime.  It deliberately keeps
/// state writes separate from source marking: a note is persisted as posted only
/// after Tana accepts it, and source titles are marked in a later operation.
enum NativeSync {
    static let tanaEndpoint = "https://europe-west1-tagr-prod.cloudfunctions.net/addToNodeV2"
    static let ideaShellEndpoint = "https://api.ideashell.cn/ideashell/mcp"

    struct Result: Codable {
        var inputNotes = 0
        var newNotes = 0
        var readyNotes = 0
        var pendingNotes = 0
        var postedNotes = 0
        var markedNotes = 0
        var warnings: [String] = []
        var todayDate = NativeSync.dayKey(Date())
        var todayNew = 0
        var todayPosted = 0
        var todayPending = 0
        var todayFailed = 0
    }

    private struct Pending: Codable { var fingerprint: String; var stableScans: Int; var firstStableAt: String; var title: String; var createdAt: String }
    private struct DayStats: Codable { var discoveredIds: [String] = []; var postedIds: [String] = []; var failedIds: [String] = [] }
    private struct State: Codable {
        var version = 4
        var postedIds: [String] = []
        var markedIds: [String] = []
        var syncedIds: [String] = []
        var pendingNotes: [String: Pending] = [:]
        var dailyStats: [String: DayStats] = [:]
        var backfillComplete = false
        var lastScanAt: String?
        // Kept optional so states written before local-date statistics remain
        // decodable. The first native run after this upgrade re-scans today.
        var localDateStatisticsMigrated: Bool?
        var localDateStatisticsMigrationVersion: Int?
    }
    private struct Note { var id: String; var title: String; var createdAt: String; var summary: String; var content: String }

    static func run(baseDirectory: URL, dryRun: Bool = false) throws -> Result {
        let lock = baseDirectory.appendingPathComponent(".sync.lock", isDirectory: true)
        do { try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false) }
        catch { throw SyncError("已有同步正在进行，请稍后查看状态。") }
        defer { try? FileManager.default.removeItem(at: lock) }
        let config = try configuration(at: baseDirectory.appendingPathComponent(".env"))
        guard let ideaToken = config["IDEASHELL_TOKEN"], !ideaToken.isEmpty,
              let tanaToken = config["TANA_TOKEN"], !tanaToken.isEmpty else {
            throw SyncError("请填写闪念贝壳 API Key 和 Tana Token。")
        }
        let stateURL = baseDirectory.appendingPathComponent(".ideashell-tana-state.json")
        var state = loadState(stateURL)
        let runStartedAt = ISO8601DateFormatter().string(from: Date())
        let today = dayKey(Date())
        var day = state.dailyStats[today] ?? DayStats()
        let fetched = try fetchNotes(token: ideaToken, state: state, config: config)
        var result = Result(inputNotes: fetched.notes.count, warnings: fetched.warnings, todayDate: today)
        var posted = Set(state.postedIds + state.syncedIds)
        var marked = Set(state.markedIds + state.syncedIds)

        // Posted IDs are authoritative. Clear any stale failure entries left
        // by an older run before rebuilding today's summary.
        for id in posted { removeFailure(id, state: &state) }
        day.failedIds.removeAll { posted.contains($0) }

        for note in fetched.notes where !note.id.isEmpty {
            let statisticsDay = statisticsDayKey(note, fallback: today)
            removeStatistic(note.id, fromOtherDaysThan: statisticsDay, state: &state, list: \.discoveredIds)
            if statisticsDay == today {
                append(note.id, to: &day.discoveredIds)
            } else {
                var sourceDay = state.dailyStats[statisticsDay] ?? DayStats()
                append(note.id, to: &sourceDay.discoveredIds)
                state.dailyStats[statisticsDay] = sourceDay
            }
            if isMarked(note.title, prefix: config["IDEASHELL_TRANSFERRED_PREFIX"] ?? "～～") {
                posted.insert(note.id); marked.insert(note.id)
            }
            // A source-title mark can fail or be disabled after Tana accepted
            // the note. The persisted posted ID is the authoritative record
            // for statistics in that case.
            if posted.contains(note.id) {
                removeStatistic(note.id, fromOtherDaysThan: statisticsDay, state: &state, list: \.postedIds)
                if statisticsDay == today {
                    append(note.id, to: &day.postedIds)
                } else {
                    var sourceDay = state.dailyStats[statisticsDay] ?? DayStats()
                    append(note.id, to: &sourceDay.postedIds)
                    state.dailyStats[statisticsDay] = sourceDay
                }
                if statisticsDay == today { day.failedIds.removeAll { $0 == note.id } }
                state.pendingNotes.removeValue(forKey: note.id); removeFailure(note.id, state: &state)
            }
        }
        let fresh = fetched.notes.filter { !posted.contains($0.id) && !isMarked($0.title, prefix: config["IDEASHELL_TRANSFERRED_PREFIX"] ?? "～～") }
        result.newNotes = fresh.count
        var ready: [(Note, String)] = []
        for note in fresh {
            let fingerprint = stableFingerprint(note)
            let readable = noteReadiness(note)
            let old = state.pendingNotes[note.id]
            let scans = readable ? ((old?.fingerprint == fingerprint) ? old!.stableScans + 1 : 1) : 0
            let first = readable && old?.fingerprint == fingerprint ? old!.firstStableAt : ISO8601DateFormatter().string(from: Date())
            state.pendingNotes[note.id] = Pending(fingerprint: fingerprint, stableScans: scans, firstStableAt: first, title: note.title, createdAt: note.createdAt)
            let elapsed = ISO8601DateFormatter().date(from: first).map { Date().timeIntervalSince($0) } ?? 0
            if readable && scans >= 2 && elapsed >= 240 {
                let text = try polishedText(noteText(note), config: config, baseDirectory: baseDirectory)
                if !text.isEmpty { ready.append((note, String(text.prefix(1800)))) }
            }
        }
        result.readyNotes = ready.count
        result.pendingNotes = state.pendingNotes.count
        if dryRun {
            result.todayNew = Set(day.discoveredIds).count; result.todayPosted = Set(day.postedIds).count
            result.todayPending = state.pendingNotes.keys.filter { day.discoveredIds.contains($0) }.count
            return result
        }
        // All four daily metrics describe the same cohort: the calendar day on
        // which a note was created in ideaShell. A note that finishes
        // transcription tomorrow therefore moves from pending to posted in
        // yesterday's bucket instead of inflating tomorrow's posted count.
        state.dailyStats[today] = day
        persist(state, to: stateURL)
        for (note, text) in ready {
            let sourceDayKey = statisticsDayKey(note, fallback: today)
            var sourceDay = state.dailyStats[sourceDayKey] ?? DayStats()
            do { try postToTana(text: text, token: tanaToken, target: config["TANA_TARGET_NODE_ID"] ?? "INBOX") }
            catch { append(note.id, to: &sourceDay.failedIds); state.dailyStats[sourceDayKey] = sourceDay; persist(state, to: stateURL); throw error }
            posted.insert(note.id); append(note.id, to: &sourceDay.postedIds); sourceDay.failedIds.removeAll { $0 == note.id }
            state.pendingNotes.removeValue(forKey: note.id); state.dailyStats[sourceDayKey] = sourceDay; removeFailure(note.id, state: &state)
            state.postedIds = posted.sorted(); state.syncedIds = state.postedIds; persist(state, to: stateURL); result.postedNotes += 1
        }
        let needsMark = config["IDEASHELL_MARK_TRANSFERRED"] == "0" ? [] : fetched.notes.filter { posted.contains($0.id) && !marked.contains($0.id) && !isMarked($0.title, prefix: config["IDEASHELL_TRANSFERRED_PREFIX"] ?? "～～") }
        for note in needsMark {
            do { try markNote(note, token: ideaToken, prefix: config["IDEASHELL_TRANSFERRED_PREFIX"] ?? "～～"); marked.insert(note.id); result.markedNotes += 1 }
            catch { result.warnings.append("\(note.id): \(error.localizedDescription)") }
        }
        state.postedIds = posted.sorted(); state.syncedIds = state.postedIds; state.markedIds = marked.sorted()
        state.backfillComplete = true; state.lastScanAt = runStartedAt; state.localDateStatisticsMigrated = true; state.localDateStatisticsMigrationVersion = 3; persist(state, to: stateURL)
        let finalDay = state.dailyStats[today] ?? DayStats()
        result.pendingNotes = state.pendingNotes.count; result.todayNew = Set(finalDay.discoveredIds).count; result.todayPosted = Set(finalDay.postedIds).count
        result.todayPending = state.pendingNotes.keys.filter { finalDay.discoveredIds.contains($0) }.count; result.todayFailed = Set(finalDay.failedIds).count
        return result
    }

    static func testAI(configuration: [String: String], promptURL: URL) throws { _ = try aiRequest(text: "ping", config: configuration, promptURL: promptURL, test: true) }
    static func models(configuration: [String: String]) throws -> [String] {
        let provider = configuration["AI_PROVIDER"] ?? "openai-compatible"; let key = configuration["AI_API_KEY"] ?? configuration["OPENAI_API_KEY"] ?? ""
        let base = (configuration["AI_BASE_URL"] ?? configuration["OPENAI_BASE_URL"] ?? defaultBase(provider)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = base; var headers: [String: String] = [:]
        switch provider {
        case "ollama": url = URL(string: base)?.deletingLastPathComponent().appendingPathComponent("tags").absoluteString ?? base
        case "gemini": url += "?key=\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)"
        case "anthropic": url = base.replacingOccurrences(of: "/messages", with: "") + "/models"; headers = ["x-api-key": key, "anthropic-version": "2023-06-01"]
        default: url = base.replacingOccurrences(of: "/chat/completions", with: "") + "/models"; headers = ["Authorization": "Bearer \(key)"]
        }
        let json = try requestJSON(url, method: "GET", headers: headers, body: nil)
        let values: [Any]
        if provider == "gemini" { values = json["models"] as? [Any] ?? [] } else if provider == "ollama" { values = json["models"] as? [Any] ?? [] } else { values = json["data"] as? [Any] ?? [] }
        return values.compactMap { item in let d = item as? [String: Any]; return (d?["id"] ?? d?["model"] ?? d?["name"]) as? String }.map { $0.replacingOccurrences(of: "models/", with: "") }.sorted()
    }

    private static func fetchNotes(token: String, state: State, config: [String: String]) throws -> (notes: [Note], warnings: [String]) {
        let session = try mcpSession(token); let limit = 20; var all: [Note] = []; var seen = Set<String>(); var end: String?
        let start: String?
        if state.localDateStatisticsMigrationVersion != 3 {
            // One safe, read-only migration pass: revisit today's source notes
            // so notes recorded after local midnight are moved into today's
            // local-date statistics bucket without reposting to Tana.
            start = ISO8601DateFormatter().string(from: Calendar.autoupdatingCurrent.startOfDay(for: Date()))
        } else {
            start = state.backfillComplete ? state.lastScanAt.flatMap { ISO8601DateFormatter().date(from: $0) }.map { ISO8601DateFormatter().string(from: $0.addingTimeInterval(-600)) } : nil
        }
        repeat {
            var args: [String: Any] = ["limit": limit]; if let start { args["start_time"] = start }; if let end { args["end_time"] = end }
            let text = try tool(session, token, "recent_notes", args); let page = parseRecent(text)
            for item in page where seen.insert(item.id).inserted { all.append(item) }
            guard start != nil, page.count == limit, let date = ISO8601DateFormatter().date(from: page.last?.createdAt ?? "") else { break }
            end = ISO8601DateFormatter().string(from: date.addingTimeInterval(-1))
        } while all.count < 10_000
        var detailed: [Note] = []
        let old = Set(state.postedIds + state.syncedIds)
        for note in all {
            if old.contains(note.id) || isMarked(note.title, prefix: config["IDEASHELL_TRANSFERRED_PREFIX"] ?? "～～") { detailed.append(note) }
            else { detailed.append(try detail(session, token, note)) }
        }
        for (id, pending) in state.pendingNotes where !seen.contains(id) {
            let fallback = Note(id: id, title: pending.title, createdAt: pending.createdAt, summary: "", content: "")
            if let note = try? detail(session, token, fallback) { detailed.append(note) }
        }
        return (detailed, [])
    }

    private static func mcpSession(_ token: String) throws -> String {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "ideashell-tana-sync", "version": "0.1.0"]]]
        let (_, response) = try requestData(ideaShellEndpoint, method: "POST", headers: mcpHeaders(token), body: body)
        guard (200..<300).contains(response.statusCode) else { throw SyncError("ideaShell 初始化失败：HTTP \(response.statusCode)") }
        guard let id = response.value(forHTTPHeaderField: "mcp-session-id"), !id.isEmpty else { throw SyncError("ideaShell MCP 未返回会话 ID") }
        let (_, initialized) = try requestData(ideaShellEndpoint, method: "POST", headers: mcpHeaders(token, id), body: ["jsonrpc": "2.0", "method": "notifications/initialized", "params": [:]])
        guard (200..<300).contains(initialized.statusCode) else { throw SyncError("ideaShell 初始化通知失败：HTTP \(initialized.statusCode)") }
        return id
    }
    private static func tool(_ session: String, _ token: String, _ name: String, _ args: [String: Any]) throws -> String {
        let json = try requestJSON(ideaShellEndpoint, method: "POST", headers: mcpHeaders(token, session), body: ["jsonrpc": "2.0", "id": Int(Date().timeIntervalSince1970 * 1000), "method": "tools/call", "params": ["name": name, "arguments": args]])
        if let error = json["error"] { throw SyncError("ideaShell \(name) failed: \(error)") }
        let result = json["result"] as? [String: Any]; let contents = result?["content"] as? [[String: Any]] ?? []
        return contents.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
    private static func detail(_ session: String, _ token: String, _ fallback: Note) throws -> Note {
        let text = try tool(session, token, "note_detail", ["note_id": fallback.id, "scope": "full"]); return parseDetail(text, fallback)
    }
    private static func markNote(_ note: Note, token: String, prefix: String) throws {
        let session = try mcpSession(token); let title = (prefix + note.title.replacingOccurrences(of: prefix, with: "")).prefix(30)
        _ = try tool(session, token, "note_update", ["note_id": note.id, "title": String(title)])
        for _ in 0..<3 { if isMarked(try detail(session, token, note).title, prefix: prefix) { return }; Thread.sleep(forTimeInterval: 0.5) }
        throw SyncError("源笔记标题未确认出现转移标记")
    }

    private static func postToTana(text: String, token: String, target: String) throws {
        let name = tanaNodeName(text)
        guard !name.isEmpty else { throw SyncError("笔记正文为空，无法写入 Tana。") }
        _ = try requestJSON(tanaEndpoint, method: "POST", headers: ["Authorization": "Bearer \(token)"], body: ["targetNodeId": target, "nodes": [["name": name]]])
    }
    private static func tanaNodeName(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    private static func polishedText(_ text: String, config: [String: String], baseDirectory: URL) throws -> String {
        guard config["OPENAI_POLISH_ENABLED"] != "0" else { return text }
        guard !(config["AI_API_KEY"] ?? config["OPENAI_API_KEY"] ?? "").isEmpty || config["AI_PROVIDER"] == "ollama" else { return text }
        do { return try aiRequest(text: text, config: config, promptURL: baseDirectory.appendingPathComponent("polish-prompt.md"), test: false) } catch { return text }
    }
    private static func aiRequest(text: String, config: [String: String], promptURL: URL, test: Bool) throws -> String {
        let provider = config["AI_PROVIDER"] ?? "openai-compatible"; let key = config["AI_API_KEY"] ?? config["OPENAI_API_KEY"] ?? ""; let model = config["AI_MODEL"] ?? config["OPENAI_MODEL"] ?? defaultModel(provider)
        if provider != "ollama" && key.isEmpty { throw SyncError("请填写 AI API Key。") }; if model.isEmpty { throw SyncError("请填写 AI 模型名称。") }
        let base = (config["AI_BASE_URL"] ?? config["OPENAI_BASE_URL"] ?? defaultBase(provider)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let system = test ? "Reply with OK only." : "你是语音转文字内容的润色助手。严格按用户提供的规则处理文本，只输出最终润色结果。"
        let prompt = test ? "ping" : ((try? String(contentsOf: promptURL)) ?? "{{text}}").replacingOccurrences(of: "{{text}}", with: text)
        var url = base; var headers = ["Content-Type": "application/json"]; var body: [String: Any]
        switch provider {
        case "anthropic": headers["x-api-key"] = key; headers["anthropic-version"] = "2023-06-01"; body = ["model": model, "system": system, "messages": [["role":"user", "content":prompt]], "max_tokens": test ? 16 : 2048]
        case "gemini": url += "/\(model):generateContent?key=\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)"; body = ["contents": [["parts": [["text": "\(system)\n\n\(prompt)"]]]], "generationConfig": ["temperature": 0.2, "maxOutputTokens": test ? 16 : 2048]]
        case "ollama": body = ["model": model, "stream": false, "messages": [["role":"system", "content":system], ["role":"user", "content":prompt]], "options": ["temperature": 0.2]]
        default: if !url.hasSuffix("/chat/completions") { url += "/chat/completions" }; headers["Authorization"] = "Bearer \(key)"; body = ["model": model, "messages": [["role":"system", "content":system], ["role":"user", "content":prompt]], "max_tokens": test ? 16 : 2048]
        }
        let json = try requestJSON(url, method: "POST", headers: headers, body: body)
        let output: String?
        if provider == "anthropic" { output = (((json["content"] as? [[String: Any]])?.first?["text"]) as? String) }
        else if provider == "gemini" { output = ((((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"]) as? String }
        else if provider == "ollama" { output = (json["message"] as? [String: Any])?["content"] as? String }
        else { output = ((((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"]) as? String) }
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SyncError("AI 服务返回成功，但没有可用文本。") }; return stripTags(output)
    }

    private static func requestJSON(_ url: String, method: String, headers: [String: String], body: [String: Any]?) throws -> [String: Any] { let (data, response) = try requestData(url, method: method, headers: headers, body: body); guard (200..<300).contains(response.statusCode) else { throw SyncError("HTTP \(response.statusCode): \(String(decoding: data, as: UTF8.self))") }; return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
    private static func requestData(_ value: String, method: String, headers: [String: String], body: [String: Any]?) throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: value) else { throw SyncError("无效地址：\(value)") }; var request = URLRequest(url: url, timeoutInterval: 30); request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept"); headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }; if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let semaphore = DispatchSemaphore(value: 0); var answer: (Data?, URLResponse?, Error?); answer = (nil, nil, nil)
        URLSession.shared.dataTask(with: request) { data, response, error in answer = (data, response, error); semaphore.signal() }.resume(); _ = semaphore.wait(timeout: .now() + 35)
        if let error = answer.2 { throw error }; guard let response = answer.1 as? HTTPURLResponse else { throw SyncError("网络请求超时或没有响应") }; return (answer.0 ?? Data(), response)
    }
    private static func mcpHeaders(_ token: String, _ session: String? = nil) -> [String: String] { var value = ["Authorization": "Bearer \(token)"]; if let session { value["Mcp-Session-Id"] = session }; return value }

    private static func parseRecent(_ text: String) -> [Note] { let p = "(?m)^# (.+?) @ ([^\\n]+)\\nnote_id:\\s*([^\\s]+)"; guard let regex = try? NSRegularExpression(pattern: p) else { return [] }; let ns = text as NSString; return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { Note(id: ns.substring(with: $0.range(at: 3)), title: ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces), createdAt: ns.substring(with: $0.range(at: 2)).trimmingCharacters(in: .whitespaces), summary: "", content: "") } }
    private static func parseDetail(_ text: String, _ fallback: Note) -> Note { func field(_ pattern: String) -> String? { guard let r = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]), let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(m.range(at: 1), in: text) else { return nil }; return String(text[range]).trimmingCharacters(in: .whitespaces) }; return Note(id: fallback.id, title: field("^#\\s+(.+)$") ?? fallback.title, createdAt: field("^time:\\s*(.+)$") ?? fallback.createdAt, summary: field("^summary:\\s*(.+)$") ?? "", content: text) }
    private static func noteText(_ note: Note) -> String { stripTags(extractText(note).isEmpty ? (note.summary.isEmpty ? note.title : note.summary) : extractText(note)) }
    private static func extractText(_ note: Note) -> String { extractOriginalText(note.content) }
    static func extractOriginalText(_ raw: String) -> String {
        guard let range = raw.range(of: "## Memos") else { return cleanMetadata(raw) }
        let memoSection = String(raw[range.upperBound...])
        let headerPattern = #"^\*\*Memo\s+\d+:[^\n]*\*\*\s*$"#
        let headerRegex = try? NSRegularExpression(pattern: headerPattern)
        var bodies: [String] = []
        var currentLines: [String] = []

        func isMemoHeader(_ line: String) -> Bool {
            let range = NSRange(line.startIndex..., in: line)
            return headerRegex?.firstMatch(in: line, range: range) != nil
        }

        func appendCurrentBody() {
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { bodies.append(body) }
            currentLines.removeAll(keepingCapacity: true)
        }

        for rawLine in memoSection.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if isMemoHeader(line) {
                appendCurrentBody()
            } else if !line.hasPrefix("summary:") {
                currentLines.append(line)
            }
        }
        appendCurrentBody()
        return bodies.isEmpty ? cleanMetadata(raw) : bodies.joined(separator: "\n\n")
    }
    private static func cleanMetadata(_ text: String) -> String { text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("# ") && !$0.hasPrefix("note_id:") && !$0.hasPrefix("time:") && !$0.hasPrefix("summary:") && $0 != "转写中..." && $0 != "## Memos" }.joined(separator: "\n") }
    private static func stripTags(_ text: String) -> String { guard let regex = try? NSRegularExpression(pattern: "(?:\\s|^)(?:#[\\p{Han}\\p{L}\\p{N}_-]+)(?:\\s+#[\\p{Han}\\p{L}\\p{N}_-]+)*\\s*$") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }; return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func noteReadiness(_ note: Note) -> Bool { let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); let body = extractText(note).trimmingCharacters(in: .whitespacesAndNewlines); return !["", "(untitled)", "untitled", "无标题", "转写中...", "转写中…"].contains(title) && !body.isEmpty && body != "转写中..." && body != "转写中…" }
    private static func stableFingerprint(_ note: Note) -> String { Data("\(note.title)\u{1f}\(extractText(note))\u{1f}\(note.summary)".utf8).base64EncodedString() }
    private static func isMarked(_ title: String, prefix: String) -> Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix) }
    private static func dayKey(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .autoupdatingCurrent; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    private static func noteDayKey(_ note: Note) -> String {
        // ideaShell returns timestamps such as 2026-07-11T19:52:42.721Z.
        // The calendar date in that UTC string may be yesterday on the user's
        // Mac, so parse the instant before deriving its local statistics day.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: note.createdAt) { return dayKey(date) }
        return String(note.createdAt.prefix(10))
    }
    private static func statisticsDayKey(_ note: Note, fallback: String) -> String {
        let key = noteDayKey(note)
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return fallback }
        return key
    }
    private static func append(_ id: String, to array: inout [String]) { if !array.contains(id) { array.append(id) } }
    private static func removeStatistic(_ id: String, fromOtherDaysThan day: String, state: inout State, list: WritableKeyPath<DayStats, [String]>) {
        for key in state.dailyStats.keys where key != day {
            var stats = state.dailyStats[key] ?? DayStats()
            stats[keyPath: list].removeAll { $0 == id }
            state.dailyStats[key] = stats
        }
    }
    private static func removeFailure(_ id: String, state: inout State) { for key in state.dailyStats.keys { state.dailyStats[key]?.failedIds.removeAll { $0 == id } } }
    private static func loadState(_ url: URL) -> State { guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(State.self, from: data) else { return State() }; return value }
    private static func persist(_ state: State, to url: URL) { var state = state; state.dailyStats = Dictionary(uniqueKeysWithValues: state.dailyStats.sorted { $0.key > $1.key }.prefix(365).map { ($0.key, $0.value) }); let temp = url.appendingPathExtension("tmp"); if let data = try? JSONEncoder().encode(state) { try? data.write(to: temp, options: .atomic); try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path); try? FileManager.default.removeItem(at: url); try? FileManager.default.moveItem(at: temp, to: url) } }
    private static func configuration(at url: URL) throws -> [String: String] { let text = try String(contentsOf: url); return Dictionary(uniqueKeysWithValues: text.split(separator: "\n").compactMap { line in let p = line.split(separator: "=", maxSplits: 1).map(String.init); return p.count == 2 && !p[0].hasPrefix("#") ? (p[0], p[1]) : nil }) }
    private static func defaultBase(_ provider: String) -> String { ["anthropic":"https://api.anthropic.com/v1/messages", "gemini":"https://generativelanguage.googleapis.com/v1beta/models", "ollama":"http://localhost:11434/api/chat"][provider] ?? "https://api.openai.com/v1" }
    private static func defaultModel(_ provider: String) -> String { ["anthropic":"claude-haiku-4-5-20251001", "gemini":"gemini-3.5-flash", "ollama":"qwen2.5:7b"][provider] ?? "gpt-5-mini" }
}

private struct SyncError: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
