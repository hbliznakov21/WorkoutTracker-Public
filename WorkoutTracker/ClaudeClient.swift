import Foundation

final class ClaudeClient {
    static let shared = ClaudeClient()

    private let apiKey: String

    private init() {
        #if SONYA
        let configName = "Config-Sonya"
        #else
        let configName = "Config"
        #endif

        if let url = Bundle.main.url(forResource: configName, withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: String],
           let key = dict["ANTHROPIC_API_KEY"] {
            apiKey = key
        } else {
            apiKey = ""
        }
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct VisionMessage: Encodable {
        let role: String
        let content: [ContentItem]
    }

    enum ContentItem: Encodable {
        case text(String)
        case image(mediaType: String, base64: String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let mediaType, let base64):
                try container.encode("image", forKey: .type)
                var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
                try source.encode("base64", forKey: .type)
                try source.encode(mediaType, forKey: .mediaType)
                try source.encode(base64, forKey: .data)
            }
        }

        enum CodingKeys: String, CodingKey { case type, text, source }
        enum SourceKeys: String, CodingKey { case type, mediaType = "media_type", data }
    }

    struct Request: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [Message]
    }

    struct VisionRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [VisionMessage]
    }

    struct Response: Decodable {
        let content: [ContentBlock]
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
    }

    func send(systemPrompt: String, userMessage: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.missingKey }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = Request(
            model: "claude-sonnet-4-20250514",
            max_tokens: 2048,
            messages: [
                Message(role: "user", content: "\(systemPrompt)\n\n\(userMessage)")
            ]
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ClaudeError.httpError(http.statusCode, msg)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.content.first?.text else { throw ClaudeError.emptyResponse }
        return text
    }
    func sendWithImages(systemPrompt: String, userText: String, images: [(Data, String)]) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.missingKey }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        var contentItems: [ContentItem] = []
        for (imageData, label) in images {
            let base64 = imageData.base64EncodedString()
            contentItems.append(.image(mediaType: "image/jpeg", base64: base64))
            contentItems.append(.text(label))
        }
        contentItems.append(.text(userText))

        let body = VisionRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: 2048,
            system: systemPrompt,
            messages: [VisionMessage(role: "user", content: contentItems)]
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ClaudeError.httpError(http.statusCode, msg)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.content.first?.text else { throw ClaudeError.emptyResponse }
        return text
    }
}

enum ClaudeError: LocalizedError {
    case missingKey
    case badResponse
    case emptyResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey:           return "Anthropic API key not configured"
        case .badResponse:          return "Invalid response from Claude API"
        case .emptyResponse:        return "Claude returned an empty response"
        case .httpError(let c, let m): return "Claude API HTTP \(c): \(m)"
        }
    }
}
