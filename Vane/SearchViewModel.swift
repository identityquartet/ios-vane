import Foundation
import SwiftUI

// MARK: - Models

struct VaneSource: Identifiable {
    let id = UUID()
    let title: String
    let url: String
    let snippet: String
}

struct VaneMessage: Identifiable {
    let id = UUID()
    let query: String
    var response: String = ""
    var sources: [VaneSource] = []
    var isSearching: Bool = true
    var isResearching: Bool = true
}

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let url: String
    let content: String
    let engines: [String]
    let publishedDate: String?
    let imgSrc: String?
    let thumbnailSrc: String?
    var displayHost: String { URL(string: url)?.host ?? url }
}

// MARK: - ViewModel

@Observable
class SearchViewModel {

    // MARK: Persisted settings

    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "vaneServerURL") }
    }
    var searchEngine: SearchEngine {
        didSet { UserDefaults.standard.set(searchEngine.rawValue, forKey: "vaneSearchEngine") }
    }
    var optimizationMode: OptimizationMode = .balanced

    var searxCategory: SearchCategory {
        didSet { UserDefaults.standard.set(searxCategory.rawValue, forKey: "vaneSearxCategory") }
    }
    var searxTimeRange: TimeRange {
        didSet { UserDefaults.standard.set(searxTimeRange.rawValue, forKey: "vaneSearxTimeRange") }
    }

    // MARK: AI state

    var inputText: String = ""
    var isSearching = false
    var messages: [VaneMessage] = []
    var errorMessage: String?

    // MARK: SearXNG state

    var searxResults: [SearchResult] = []
    var searxAnswers: [String] = []
    var searxSuggestions: [String] = []
    var searxTotalResults: Int = 0
    var searxIsSearching = false

    // MARK: AI internals

    private var chatProviderId = "d8822e61-4d9c-4fc4-a81e-5bf35cc68d45"
    private var chatModelKey = "Qwen3-8B"
    private var embeddingProviderId = "8fe18210-2a23-4878-b43e-e7b037019f1c"
    private var embeddingModelKey = "Xenova/all-MiniLM-L6-v2"
    private var sessionChatId = UUID().uuidString
    private var history: [([String])] = []

    // MARK: - Enums

    enum OptimizationMode: String, CaseIterable {
        case speed, balanced, quality
        var label: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .speed:    return "bolt"
            case .balanced: return "scale.3d"
            case .quality:  return "sparkles"
            }
        }
    }

    enum SearchEngine: String, CaseIterable {
        case ai, searchVPN, searchTor
        var label: String {
            switch self {
            case .ai:        return "AI"
            case .searchVPN: return "VPN"
            case .searchTor: return "Tor"
            }
        }
        var icon: String {
            switch self {
            case .ai:        return "sparkles"
            case .searchVPN: return "shield.fill"
            case .searchTor: return "network"
            }
        }
        var searxBaseURL: String? {
            switch self {
            case .ai:        return nil
            case .searchVPN: return "https://search-vpn.stacknest.me"
            case .searchTor: return "https://search.stacknest.me"
            }
        }
        var isSearx: Bool { self != .ai }
        var searxTimeout: TimeInterval { self == .searchTor ? 90 : 30 }
    }

    enum SearchCategory: String, CaseIterable {
        case general, news, images, videos, science, it
        var label: String {
            switch self {
            case .general: return "All"
            case .news:    return "News"
            case .images:  return "Images"
            case .videos:  return "Videos"
            case .science: return "Science"
            case .it:      return "Tech"
            }
        }
        var icon: String {
            switch self {
            case .general: return "magnifyingglass"
            case .news:    return "newspaper"
            case .images:  return "photo"
            case .videos:  return "play.rectangle"
            case .science: return "flask"
            case .it:      return "terminal"
            }
        }
    }

    enum TimeRange: String, CaseIterable {
        case anytime = "", day, week, month, year
        var label: String {
            switch self {
            case .anytime: return "Any time"
            case .day:     return "Past day"
            case .week:    return "Past week"
            case .month:   return "Past month"
            case .year:    return "Past year"
            }
        }
    }

    // MARK: - Init

    init() {
        serverURL = UserDefaults.standard.string(forKey: "vaneServerURL") ?? "http://192.168.8.117:3000"
        let engineRaw = UserDefaults.standard.string(forKey: "vaneSearchEngine") ?? SearchEngine.ai.rawValue
        searchEngine = SearchEngine(rawValue: engineRaw) ?? .ai

        let savedCat = UserDefaults.standard.string(forKey: "vaneSearxCategory") ?? SearchCategory.general.rawValue
        searxCategory = SearchCategory(rawValue: savedCat) ?? .general
        let savedTime = UserDefaults.standard.string(forKey: "vaneSearxTimeRange") ?? TimeRange.anytime.rawValue
        searxTimeRange = TimeRange(rawValue: savedTime) ?? .anytime
    }

    // MARK: - Config

    func loadConfig() async {
        guard let url = URL(string: "\(serverURL)/api/config") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }

        struct ConfigResp: Decodable {
            struct Values: Decodable {
                struct Provider: Decodable {
                    let id: String
                    struct ChatModel: Decodable { let key: String }
                    struct EmbedModel: Decodable { let key: String }
                    let chatModels: [ChatModel]
                    let embeddingModels: [EmbedModel]
                }
                let modelProviders: [Provider]
            }
            let values: Values
        }

        guard let resp = try? JSONDecoder().decode(ConfigResp.self, from: data) else { return }
        let providers = resp.values.modelProviders

        if let p = providers.first(where: { !$0.chatModels.isEmpty }), let m = p.chatModels.first {
            await MainActor.run { chatProviderId = p.id; chatModelKey = m.key }
        }
        if let p = providers.first(where: { !$0.embeddingModels.isEmpty }), let m = p.embeddingModels.first {
            await MainActor.run { embeddingProviderId = p.id; embeddingModelKey = m.key }
        }
    }

    // MARK: - Search dispatch

    func search() async {
        switch searchEngine {
        case .ai:                      await searchAIMode()
        case .searchVPN, .searchTor:   await searchSearxngMode()
        }
    }

    // MARK: - AI search

    private func searchAIMode() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSearching else { return }

        let bgTask = BGTaskHandle()
        bgTask.begin(name: "VaneSearch")
        defer { bgTask.end() }

        await MainActor.run {
            inputText = ""
            isSearching = true
            messages.append(VaneMessage(query: text))
        }
        let msgIndex = await MainActor.run { messages.count - 1 }
        await searchAI(text: text, msgIndex: msgIndex)
    }

    private func searchAI(text: String, msgIndex: Int) async {
        let messageId = UUID().uuidString

        guard let url = URL(string: "\(serverURL)/api/chat") else {
            await MainActor.run { isSearching = false; messages[msgIndex].isSearching = false }
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        let histCopy = history.map { $0 }
        let body: [String: Any] = [
            "message": ["messageId": messageId, "chatId": sessionChatId, "content": text],
            "optimizationMode": optimizationMode.rawValue,
            "sources": ["web"],
            "history": histCopy,
            "files": [] as [String],
            "chatModel": ["providerId": chatProviderId, "key": chatModelKey],
            "embeddingModel": ["providerId": embeddingProviderId, "key": embeddingModelKey],
            "systemInstructions": ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        var textBlockId: String?
        var finalResponse = ""

        do {
            let (stream, _) = try await URLSession.shared.bytes(for: req)
            for try await line in stream.lines {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = obj["type"] as? String
                else { continue }

                switch type {
                case "block":
                    guard let block = obj["block"] as? [String: Any],
                          let bType = block["type"] as? String,
                          let bId   = block["id"]   as? String
                    else { continue }
                    if bType == "text" {
                        textBlockId = bId
                    } else if bType == "source",
                              let sourceData = block["data"] as? [[String: Any]] {
                        let sources = sourceData.compactMap { item -> VaneSource? in
                            guard let meta = item["metadata"] as? [String: Any],
                                  let title = meta["title"] as? String,
                                  let url   = meta["url"]   as? String
                            else { return nil }
                            return VaneSource(title: title, url: url, snippet: item["content"] as? String ?? "")
                        }
                        await MainActor.run { messages[msgIndex].sources = sources }
                    }

                case "updateBlock":
                    guard let bId = obj["blockId"] as? String, bId == textBlockId,
                          let patches = obj["patch"] as? [[String: Any]]
                    else { continue }
                    for patch in patches {
                        if patch["op"]   as? String == "replace",
                           patch["path"] as? String == "/data",
                           let val = patch["value"] as? String {
                            finalResponse = val
                            await MainActor.run { messages[msgIndex].response = val }
                        }
                    }

                case "researchComplete":
                    await MainActor.run { messages[msgIndex].isResearching = false }

                default: break
                }
            }
        } catch {
            await MainActor.run { messages[msgIndex].response = "Error: \(error.localizedDescription)" }
        }

        await MainActor.run {
            messages[msgIndex].isSearching = false
            isSearching = false
        }
        history.append(["human", text])
        history.append(["assistant", finalResponse])
    }

    // MARK: - SearXNG search

    private func searchSearxngMode() async {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !searxIsSearching else { return }

        let bgTask = BGTaskHandle()
        bgTask.begin(name: "SearxSearch")
        defer { bgTask.end() }

        await MainActor.run {
            searxIsSearching = true
            searxResults = []
            searxAnswers = []
            searxSuggestions = []
            searxTotalResults = 0
            errorMessage = nil
        }

        guard let baseURL = searchEngine.searxBaseURL else {
            await MainActor.run { searxIsSearching = false }
            return
        }
        var comps = URLComponents(string: "\(baseURL)/search")!
        var params: [URLQueryItem] = [
            .init(name: "q",          value: q),
            .init(name: "format",     value: "json"),
            .init(name: "categories", value: searxCategory.rawValue),
        ]
        if !searxTimeRange.rawValue.isEmpty {
            params.append(.init(name: "time_range", value: searxTimeRange.rawValue))
        }
        comps.queryItems = params
        guard let url = comps.url else {
            await MainActor.run { searxIsSearching = false }
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = searchEngine.searxTimeout

        do {
            let (data, _) = try await URLSession.shared.data(for: req)

            struct Resp: Decodable {
                struct R: Decodable {
                    let title: String
                    let url: String
                    let content: String?
                    let engines: [String]?
                    let publishedDate: String?
                    let img_src: String?
                    let thumbnail_src: String?
                }
                struct Ans: Decodable {
                    let answer: String?
                }
                let results: [R]
                let answers: [Ans]?
                let suggestions: [String]?
                let number_of_results: Double?
            }

            let resp = try JSONDecoder().decode(Resp.self, from: data)
            let mapped = resp.results.map {
                SearchResult(
                    title: $0.title, url: $0.url, content: $0.content ?? "",
                    engines: $0.engines ?? [], publishedDate: $0.publishedDate,
                    imgSrc: $0.img_src.flatMap { $0.isEmpty ? nil : $0 },
                    thumbnailSrc: $0.thumbnail_src.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
            await MainActor.run {
                searxResults = mapped
                searxAnswers = resp.answers?.compactMap { $0.answer } ?? []
                searxSuggestions = resp.suggestions ?? []
                searxTotalResults = Int(resp.number_of_results ?? 0)
                searxIsSearching = false
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription; searxIsSearching = false }
        }
    }

    func clearSearxSearch() {
        searxResults = []
        searxAnswers = []
        searxSuggestions = []
        inputText = ""
        searxTotalResults = 0
        errorMessage = nil
    }

    // MARK: - AI chat management

    func newChat() {
        messages = []
        history = []
        sessionChatId = UUID().uuidString
    }
}
