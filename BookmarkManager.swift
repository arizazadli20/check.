import Foundation

enum BookmarkError: LocalizedError {
    case creationFailed
    case resolutionFailed
    case stale
    case accessDenied
    case unreadable

    var errorDescription: String? {
        switch self {
        case .creationFailed:
            return "Could not save folder access."
        case .resolutionFailed:
            return "Could not open the saved project folder."
        case .stale:
            return "The project folder has moved. Please locate it again."
        case .accessDenied:
            return "Access to the project folder was denied."
        case .unreadable:
            return "The project folder cannot be read. Please locate it again."
        }
    }
}

final class BookmarkManager {
    static let shared = BookmarkManager()

    private var activeAccess: [UUID: URL] = [:]
    private var accessCount: [UUID: Int] = [:]

    private init() {}

    func createBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw BookmarkError.creationFailed
        }
    }

    func createBookmarkFromOpenPanel(_ url: URL) throws -> Data {
        guard canReadProject(at: url) else {
            throw BookmarkError.unreadable
        }
        return try createBookmark(for: url)
    }

    func resolveURL(from bookmarkData: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url.standardizedFileURL, isStale)
        } catch {
            throw BookmarkError.resolutionFailed
        }
    }

    @discardableResult
    func startAccessing(projectID: UUID, bookmarkData: Data) throws -> URL {
        stopAccessing(projectID: projectID)

        let (url, isStale) = try resolveURL(from: bookmarkData)
        if isStale {
            throw BookmarkError.stale
        }

        guard canReadProject(at: url) else {
            throw BookmarkError.unreadable
        }

        activeAccess[projectID] = url
        accessCount[projectID] = 1
        return url
    }

    func stopAccessing(projectID: UUID) {
        guard let url = activeAccess.removeValue(forKey: projectID) else { return }
        accessCount.removeValue(forKey: projectID)
    }

    func stopAllAccess() {
        for projectID in activeAccess.keys {
            stopAccessing(projectID: projectID)
        }
    }

    func folderExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func canReadProject(at url: URL) -> Bool {
        guard folderExists(at: url) else { return false }

        if (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil {
            return true
        }

        let gitHead = url.appendingPathComponent(".git/HEAD")
        if let data = try? Data(contentsOf: gitHead), !data.isEmpty {
            return true
        }

        return false
    }
}
