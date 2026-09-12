import Foundation

struct MiniApp: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date

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

        // Always add the harness policy. Browsers enforce multiple CSPs together, so a
        // document-provided policy cannot weaken this one.
        let meta = #"<meta http-equiv="Content-Security-Policy" content="\#(contentSecurityPolicy)">"#
        if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            html.insert(contentsOf: "\n    \(meta)", at: head.upperBound)
        } else if let opening = html.range(of: "<html[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            html.insert(contentsOf: "\n<head>\(meta)</head>", at: opening.upperBound)
        }
        return html
    }
}
