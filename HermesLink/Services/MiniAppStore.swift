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

    func save(title: String, html: String) throws -> MiniApp {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let app = MiniApp(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        let directory = directoryURL(for: app)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data(html.utf8).write(to: htmlURL(for: app), options: [.atomic, .completeFileProtection])
        var apps = load()
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
