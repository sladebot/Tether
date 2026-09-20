import Foundation

@MainActor
final class MiniAppStore {
    private let fileManager: FileManager
    private let root: URL
    private let metadataURL: URL

    init(fileManager: FileManager = .default, root: URL? = nil) {
        self.fileManager = fileManager
        let applicationSupport = root ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = applicationSupport.appending(path: "MiniApps", directoryHint: .isDirectory)
        metadataURL = self.root.appending(path: "apps.json")
    }

    func load() -> [MiniApp] {
        guard let data = try? Data(contentsOf: metadataURL) else { return [] }
        return (try? JSONDecoder().decode([MiniApp].self, from: data))?
            .filter { fileManager.fileExists(atPath: htmlURL(for: $0).path) }
            .sorted { $0.updatedAt > $1.updatedAt } ?? []
    }

    func save(title: String, html: String, id: UUID = UUID()) throws -> MiniApp {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let existing = load().first { $0.id == id }
        let app = MiniApp(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: existing?.createdAt ?? .now)
        let directory = directoryURL(for: app)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = try? Data(contentsOf: htmlURL(for: app))
        if let old, old != Data(html.utf8) {
            try old.write(to: directory.appending(path: "previous.html"), options: [.atomic, .completeFileProtection])
        }
        try Data(html.utf8).write(to: htmlURL(for: app), options: [.atomic, .completeFileProtection])
        var apps = load().filter { $0.id != id }
        apps.insert(app, at: 0)
        try saveMetadata(apps)
        return app
    }

    func delete(_ app: MiniApp, from apps: [MiniApp]) throws {
        let directory = directoryURL(for: app)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try saveMetadata(apps.filter { $0.id != app.id })
    }

    func rollback(_ app: MiniApp) throws {
        let previous = try String(contentsOf: directoryURL(for: app).appending(path: "previous.html"), encoding: .utf8)
        _ = try save(title: app.title, html: previous, id: app.id)
    }

    func chat(for app: MiniApp) -> [ChatMessage] {
        guard let data = try? Data(contentsOf: directoryURL(for: app).appending(path: "chat.json")) else { return [] }
        return (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
    }

    func appendChat(_ message: ChatMessage, for app: MiniApp) throws {
        var messages = chat(for: app)
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        try JSONEncoder().encode(messages).write(to: directoryURL(for: app).appending(path: "chat.json"), options: [.atomic, .completeFileProtection])
    }

    func htmlURL(for app: MiniApp) -> URL {
        directoryURL(for: app).appending(path: "index.html")
    }

    func directoryURL(for app: MiniApp) -> URL {
        root.appending(path: app.id.uuidString, directoryHint: .isDirectory)
    }

    private func saveMetadata(_ apps: [MiniApp]) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(apps)
        try data.write(to: metadataURL, options: [.atomic, .completeFileProtection])
    }
}
