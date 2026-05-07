import Foundation
import SwiftUI

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

@Observable
class SearchViewModel {
    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "vaneServerURL") }
    }
    var searxngURL: String {
        didSet { UserDefaults.standard.set(searxngURL, forKey: "vaneSearxngURL") }
    }
    var searchEngine: SearchEngine {
        didSet { UserDefaults.standard.set(searchEngine.rawValue, forKey: "vaneSearchEngine") }
    }
    var optimizationMode: OptimizationMode = .balanced
    var inputText: String = ""
    var isSearching = false
    var messages: [VaneMessage] = []
    var errorMessage: String?

    private var chatProviderId = "d8822e61-4d9c-4fc4-a81e-5bf35cc68d45"
    private var chatModelKey = "Qwen3-8B"
    private var embeddingProviderId = "8fe18210-2a23-4878-b43e-e7b037019f1c"
    private var embeddingModelKey = "Xenova/all-MiniLM-L6-v2"

    private var sessionChatId = UUID().uuidString
    private var history: [([String])] = []

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
        case ai, searxng
        var label: String {
            switch self {
            case .ai:      return "AI"
            case .searxng: return "SearXNG"
            }
        }
        var icon: String {
            switch self {
            case .ai:      return "sparkles"
            case .searxng: return "magnifyingglass"
            }
        }
    }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "vaneServerURL") ?? "http://192.168.8.117:3000"
        searxngURL = UserDefaults.standard.string(forKey: "vaneSearxngURL") ?? "https://search-vpn.stacknest.me"
        let engineRaw = UserDefaults.standard.string(forKey: "vaneSearchEngine") ?? SearchEngine.ai.rawValue
        searchEngine = SearchEngine(rawValue: engineRaw) ?? .ai
    }

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

    func search() async {
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

        switch searchEngine {
        case .ai:
            await searchAI(text: text, msgIndex: msgIndex)
        case .searxng:
            await searchSearxng(text: text, msgIndex: msgIndex)
        }
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

    private func searchSearxng(text: String, msgIndex: Int) async {
        let base = searxngURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        var components = URLComponents(string: "\(base)/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "safesearch", value: "0")
        ]

        guard let url = components?.url else {
            await MainActor.run {
                messages[msgIndex].response = "Error: invalid SearXNG URL"
                messages[msgIndex].isSearching = false
                messages[msgIndex].isResearching = false
                isSearching = false
            }
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Vane/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 60

        struct SearxngResp: Decodable {
            struct Result: Decodable {
                let title: String?
                let url: String?
                let content: String?
            }
            let results: [Result]
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "SearXNG", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            }
            let decoded = try JSONDecoder().decode(SearxngResp.self, from: data)
            let sources: [VaneSource] = decoded.results.compactMap { r in
                guard let title = r.title, let url = r.url else { return nil }
                return VaneSource(title: title, url: url, snippet: r.content ?? "")
            }
            await MainActor.run {
                messages[msgIndex].sources = sources
                if sources.isEmpty {
                    messages[msgIndex].response = "No results found."
                }
            }
        } catch {
            await MainActor.run {
                messages[msgIndex].response = "Error: \(error.localizedDescription)"
            }
        }

        await MainActor.run {
            messages[msgIndex].isSearching = false
            messages[msgIndex].isResearching = false
            isSearching = false
        }
    }

    func newChat() {
        messages = []
        history = []
        sessionChatId = UUID().uuidString
    }
}
