import Foundation

enum GitNativeReader {
    struct RepositoryInfo {
        var isRepository: Bool
        var gitDirectory: URL?
        var branch: String?
        var headHash: String?
        var recentCommits: [GitCommitSnapshot]
    }

    static func inspect(at projectURL: URL) -> RepositoryInfo {
        guard let gitDir = resolveGitDirectory(for: projectURL) else {
            return RepositoryInfo(isRepository: false, gitDirectory: nil, branch: nil, headHash: nil, recentCommits: [])
        }

        let headHash = readHEADHash(gitDirectory: gitDir, projectURL: projectURL)
        let branch = readBranch(gitDirectory: gitDir, projectURL: projectURL)
        let commits = readRecentCommits(gitDirectory: gitDir, projectURL: projectURL, limit: 5)

        return RepositoryInfo(
            isRepository: true,
            gitDirectory: gitDir,
            branch: branch,
            headHash: headHash,
            recentCommits: commits
        )
    }

    static func resolveGitDirectory(for projectURL: URL) -> URL? {
        let dotGit = projectURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            return dotGit
        }

        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("gitdir: ") else { return nil }
        let path = String(trimmed.dropFirst("gitdir: ".count))
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return projectURL.appendingPathComponent(path)
    }

    private static func readBranch(gitDirectory: URL, projectURL: URL) -> String? {
        guard let head = readHEADContents(gitDirectory: gitDirectory, projectURL: projectURL) else {
            return nil
        }
        if head.hasPrefix("ref: refs/heads/") {
            return String(head.dropFirst("ref: refs/heads/".count))
        }
        if head.count >= 7 {
            return "HEAD detached"
        }
        return nil
    }

    private static func readHEADHash(gitDirectory: URL, projectURL: URL) -> String? {
        guard let head = readHEADContents(gitDirectory: gitDirectory, projectURL: projectURL) else {
            return nil
        }

        if head.hasPrefix("ref: ") {
            let refPath = String(head.dropFirst("ref: ".count))
            let fullRefURL = gitDirectory.appendingPathComponent(refPath)
            if let hash = try? String(contentsOf: fullRefURL, encoding: .utf8) {
                return hash.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readHEADContents(gitDirectory: URL, projectURL: URL) -> String? {
        let headURL = gitDirectory.appendingPathComponent("HEAD")
        return try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readRecentCommits(gitDirectory: URL, projectURL: URL, limit: Int) -> [GitCommitSnapshot] {
        let logURL = gitDirectory.appendingPathComponent("logs/HEAD")
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        var commits: [GitCommitSnapshot] = []

        for line in lines.reversed() {
            // oldHash newHash Name <email> timestamp message
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count >= 5 else { continue }
            let newHash = String(parts[1])
            let message = String(parts[4])
            let shortHash = String(newHash.prefix(7))
            commits.append(GitCommitSnapshot(shortHash: shortHash, subject: message))
            if commits.count >= limit { break }
        }

        return commits
    }
}
