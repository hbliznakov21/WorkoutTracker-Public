import Testing
import Foundation

@Suite("Models Codable Tests")
struct ModelsTests {

    // MARK: - Round-trip encoding/decoding

    @Test("Routine encodes and decodes")
    func routineCodable() throws {
        struct SimpleRoutine: Codable, Equatable {
            let id: UUID
            let name: String
        }

        let original = SimpleRoutine(id: UUID(), name: "Push A")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SimpleRoutine.self, from: data)
        #expect(original == decoded)
    }

    @Test("ISO8601 date parsing with fractional seconds")
    func isoDateParsing() {
        let isoWithFrac = ISO8601DateFormatter()
        isoWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoWithFrac.date(from: "2026-03-08T10:30:45.123Z")
        #expect(date != nil)
    }

    @Test("ISO8601 date parsing without fractional seconds")
    func isoDateParsingPlain() {
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        let date = isoPlain.date(from: "2026-03-08T10:30:45Z")
        #expect(date != nil)
    }

    @Test("Empty array decodes correctly")
    func emptyArrayDecoding() throws {
        let json = "[]".data(using: .utf8)!
        let decoded = try JSONDecoder().decode([String].self, from: json)
        #expect(decoded.isEmpty)
    }
}
