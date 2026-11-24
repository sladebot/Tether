import Foundation

struct MiniAppBuildJob: Codable {
    var id = UUID()
    let connectionID: UUID
    let title: String
    let prompt: String
    let model: ModelChoice?
    var runID: String?
    var targetAppID: UUID?
    var failureMessage: String? = nil
    var firstSubmissionAt: Date? = nil
    var retentionSeconds: TimeInterval? = nil
}

struct MiniApp: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var connectionID: UUID? = nil
    var model: ModelChoice? = nil

    init(id: UUID = UUID(), title: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum MiniAppDocument {
    enum Error: LocalizedError {
        case missingDocument
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .missingDocument: "Hermes didn’t return a complete HTML document. Try describing the app again."
            case .tooLarge: "The generated mini app is larger than the 2 MB safety limit."
            }
        }
    }

    static let contentSecurityPolicy = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

    static func prepare(_ response: String) throws -> String {
        var html = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if html.hasPrefix("```") {
            let lines = html.components(separatedBy: .newlines)
            html = lines.dropFirst().dropLast(lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard html.range(of: "<html", options: .caseInsensitive) != nil,
              html.range(of: "</html>", options: .caseInsensitive) != nil else {
            throw Error.missingDocument
        }
        guard html.utf8.count <= 2_000_000 else { throw Error.tooLarge }

        // Put the policy in a trusted prefix before parsing any generated markup.
        // Searching untrusted HTML for <head> can match comments or script strings,
        // hiding the policy and permitting requests before it ever takes effect.
        let meta = #"<meta http-equiv="Content-Security-Policy" content="\#(contentSecurityPolicy)">"#
        return "<!DOCTYPE html><html><head>\(meta)</head><body>\(html)</body></html>"
    }
}
