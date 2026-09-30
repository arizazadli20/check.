import Foundation

enum FileChangeScanner {
    private static let skipDirectoryNames: Set<String> = [
        ".git", "node_modules", "DerivedData", "Pods", ".build", "build",
        "dist", ".next", ".cache", "vendor", "xcuserdata"
    ]

    static func scanModifiedFiles(
        at projectURL: URL,
        since: Date?,
        referenceManifest: [String: FileFingerprint]? = nil
    ) -> [String] {
        var results: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        while let itemURL = enumerator?.nextObject() as? URL {
            let relative = relativePath(for: itemURL, root: projectURL)
            if shouldSkip(relativePath: relative) {
                if (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator?.skipDescendants()
                }
                continue
            }

            guard let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory != true else {
                continue
            }

            if GitService.isSensitivePath(relative) || GitService.isBinaryPath(relative) {
                continue
            }

            let fingerprint = FileFingerprint(
                modificationDate: values.contentModificationDate ?? .distantPast,
                size: (try? itemURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            )

            let changed: Bool
            if let referenceManifest {
                changed = referenceManifest[relative] != fingerprint
            } else if let since {
                changed = (values.contentModificationDate ?? .distantPast) >= since
            } else {
                changed = false
            }

            if changed {
                results.append(relative)
            }
        }

        return results.sorted()
    }

    static func buildManifest(at projectURL: URL) -> [String: FileFingerprint] {
        var manifest: [String: FileFingerprint] = [:]
        let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        while let itemURL = enumerator?.nextObject() as? URL {
            let relative = relativePath(for: itemURL, root: projectURL)
            if shouldSkip(relativePath: relative) {
                if (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator?.skipDescendants()
                }
                continue
            }

            guard let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey, .fileSizeKey]),
                  values.isDirectory != true else { continue }

            if GitService.isSensitivePath(relative) || GitService.isBinaryPath(relative) { continue }

            manifest[relative] = FileFingerprint(
                modificationDate: values.contentModificationDate ?? .distantPast,
                size: values.fileSize ?? 0
            )
        }

        return manifest
    }

    static func buildReferenceDiff(
        at projectURL: URL,
        changedFiles: [String],
        maxBytes: Int
    ) -> (diff: String, truncated: Bool) {
        var combined = ""
        var truncated = false

        for file in changedFiles {
            if combined.utf8.count >= maxBytes {
                truncated = true
                break
            }

            let fileURL = projectURL.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: fileURL),
                  data.count <= 32_768,
                  let text = String(data: data, encoding: .utf8) else {
                let note = "diff -- \(file)\n[Binary or unreadable file omitted]\n"
                combined = appendChunk(combined, note, maxBytes: maxBytes, truncated: &truncated)
                continue
            }

            let snippet = String(text.prefix(4000))
            let chunk = "diff -- \(file)\n--- current file snapshot (not a Git diff)\n+++\n\(snippet)\n"
            combined = appendChunk(combined, chunk, maxBytes: maxBytes, truncated: &truncated)
        }

        if truncated {
            combined += "\n\n[Diff truncated at \(maxBytes / 1024) KB limit]"
        }

        return (combined, truncated)
    }

    private static func appendChunk(_ combined: String, _ chunk: String, maxBytes: Int, truncated: inout Bool) -> String {
        let next = combined.isEmpty ? chunk : combined + "\n\n" + chunk
        if next.utf8.count > maxBytes {
            truncated = true
            let remaining = max(0, maxBytes - combined.utf8.count)
            if remaining > 80 {
                return combined + "\n\n" + String(chunk.prefix(remaining))
            }
            return combined
        }
        return next
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if url.path.hasPrefix(rootPath) {
            return String(url.path.dropFirst(rootPath.count))
        }
        return url.lastPathComponent
    }

    private static func shouldSkip(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        return components.contains { skipDirectoryNames.contains($0) }
    }
}

struct FileFingerprint: Codable, Equatable {
    var modificationDate: Date
    var size: Int
}
