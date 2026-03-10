import Foundation

final class SupabaseClient {
    static let shared = SupabaseClient()

    private let base: String
    private let apiKey: String

    private init() {
        #if SONYA
        let configName = "Config-Sonya"
        #else
        let configName = "Config"
        #endif

        guard let url = Bundle.main.url(forResource: configName, withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String],
              let baseURL = dict["SUPABASE_URL"],
              let key = dict["SUPABASE_ANON_KEY"]
        else {
            // Fallback — copy Config.plist.example to Config.plist and add your keys
            base = ""
            apiKey = ""
            print("⚠️ Config.plist not found. Copy Config.plist.example to Config.plist and add your Supabase credentials.")
            return
        }
        self.base = baseURL
        self.apiKey = key
    }

    // MARK: - Coders
    private static let isoWithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            if let date = SupabaseClient.isoWithFrac.date(from: s) { return date }
            if let date = SupabaseClient.isoPlain.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(s)"
            )
        }
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - Request builder
    private func makeRequest(
        _ resource: String,
        method: String = "GET",
        body: Data? = nil,
        prefer: String? = nil
    ) -> URLRequest {
        let urlString = "\(base)/\(resource)"
        guard let url = URL(string: urlString) else {
            // Return a request to an invalid URL that will fail safely
            var req = URLRequest(url: URL(string: "https://invalid.local")!)
            req.httpMethod = method
            return req
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(apiKey,            forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body
        return req
    }

    // MARK: - Retry with exponential backoff (GET only)
    private func performWithRetry(_ request: URLRequest, maxRetries: Int = 3) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse,
                   (429 == http.statusCode || (500...599).contains(http.statusCode)),
                   attempt < maxRetries - 1 {
                    let delay = Double(1 << attempt) // 1s, 2s, 4s
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = Double(1 << attempt)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
        throw lastError ?? SBError.emptyResponse
    }

    // MARK: - GET
    func get<T: Decodable>(_ resource: String) async throws -> T {
        let req = makeRequest(resource)
        let (data, resp) = try await performWithRetry(req)
        try checkStatus(resp, data)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - POST single — returns the inserted row
    func post<Body: Encodable, T: Decodable>(
        _ resource: String,
        body: Body,
        returning: T.Type = T.self
    ) async throws -> T {
        let data = try encoder.encode(body)
        let req = makeRequest(resource, method: "POST", body: data, prefer: "return=representation")
        let (resp_data, resp) = try await URLSession.shared.data(for: req)
        try checkStatus(resp, resp_data)
        let arr = try decoder.decode([T].self, from: resp_data)
        guard let first = arr.first else { throw SBError.emptyResponse }
        return first
    }

    // MARK: - POST batch (no return)
    func postBatch<T: Encodable>(_ resource: String, body: [T]) async throws {
        let data = try encoder.encode(body)
        let req = makeRequest(resource, method: "POST", body: data, prefer: "return=minimal")
        let (resp_data, resp) = try await URLSession.shared.data(for: req)
        try checkStatus(resp, resp_data)
    }

    // MARK: - PATCH
    func patch<T: Encodable>(_ resource: String, body: T) async throws {
        let data = try encoder.encode(body)
        let req = makeRequest(resource, method: "PATCH", body: data, prefer: "return=minimal")
        let (resp_data, resp) = try await URLSession.shared.data(for: req)
        try checkStatus(resp, resp_data)
    }

    // MARK: - Insert raw JSON — 409 conflict (unique violation) treated as success
    func insertRaw(_ resource: String, payload: [[String: Any]]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let req = makeRequest(resource, method: "POST", body: data, prefer: "return=minimal")
        let (resp_data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 409 { return }
        try checkStatus(resp, resp_data)
    }

    // MARK: - Upsert raw JSON (for mixed-type payloads like schedule)
    func upsertRaw(_ resource: String, payload: [[String: Any]]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let req = makeRequest(resource, method: "POST", body: data,
                              prefer: "resolution=merge-duplicates,return=minimal")
        let (resp_data, resp) = try await URLSession.shared.data(for: req)
        try checkStatus(resp, resp_data)
    }

    // MARK: - DELETE
    func delete(_ resource: String) async throws {
        let req = makeRequest(resource, method: "DELETE")
        let (resp_data, resp) = try await URLSession.shared.data(for: req)
        try checkStatus(resp, resp_data)
    }

    // MARK: - Status check
    private func checkStatus(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SBError.httpError(http.statusCode, msg)
        }
    }
}

extension SupabaseClient {
    /// Convenience: attempt a GET and log errors instead of silently swallowing them.
    func tryGet<T: Decodable>(_ resource: String) async -> T? {
        do {
            return try await get(resource)
        } catch {
            print("[Supabase] GET \(resource.prefix(80)) failed: \(error.localizedDescription)")
            return nil
        }
    }
}

enum SBError: LocalizedError {
    case emptyResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:         return "Supabase returned an empty response"
        case .httpError(let c, let m): return "HTTP \(c): \(m)"
        }
    }
}
