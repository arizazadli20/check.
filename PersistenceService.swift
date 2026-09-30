import Foundation

enum PersistenceError: LocalizedError {
    case directoryCreationFailed
    case encodingFailed
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            return "Could not create Application Support directory."
        case .encodingFailed:
            return "Could not encode app data."
        case .decodingFailed(let detail):
            return "Could not read saved data: \(detail)"
        }
    }
}

final class PersistenceService {
    static let shared = PersistenceService()

    private let fileName = "checkpoint-data.json"
    private let backupFileName = "checkpoint-data.backup.json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.checkpoint.persistence", qos: .utility)

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private var dataURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Checkpoint", isDirectory: true).appendingPathComponent(fileName)
    }

    private var backupURL: URL {
        dataURL.deletingLastPathComponent().appendingPathComponent(backupFileName)
    }

    func load() async -> AppData {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.loadSync())
            }
        }
    }

    func save(_ data: AppData) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.saveSync(data)
                continuation.resume()
            }
        }
    }

    private func loadSync() -> AppData {
        let directory = dataURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .empty
        }

        if let data = try? Data(contentsOf: dataURL),
           let decoded = try? decoder.decode(AppData.self, from: data) {
            return decoded
        }

        if let backup = try? Data(contentsOf: backupURL),
           let decoded = try? decoder.decode(AppData.self, from: backup) {
            return decoded
        }

        return .empty
    }

    private func saveSync(_ data: AppData) {
        let directory = dataURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return
        }

        guard let encoded = try? encoder.encode(data) else { return }

        if FileManager.default.fileExists(atPath: dataURL.path) {
            try? FileManager.default.copyItem(at: dataURL, to: backupURL)
        }

        let tempURL = directory.appendingPathComponent("checkpoint-data.tmp.json")
        do {
            try encoded.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: dataURL.path) {
                try FileManager.default.removeItem(at: dataURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: dataURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}
