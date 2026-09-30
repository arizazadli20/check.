import Foundation

enum GitServiceError: LocalizedError {
    case gitNotInstalled
    case notARepository
    case commandFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .gitNotInstalled:
            return "Git is not installed or not available in PATH."
        case .notARepository:
            return "This folder is not a Git repository."
        case .commandFailed(let message):
            return message
        case .timeout:
            return "Git command timed out."
        }
    }
}

actor GitService {
    static let shared = GitService()

    static let maxDiffBytes = 80 * 1024

    private static let sensitivePathPatterns: [String] = [
        ".env", ".env.local", ".env.production", ".env.development",
        "id_rsa", "id_ed25519", "credentials", "secrets",
        "node_modules/", ".build/", "DerivedData/", "Pods/",
        ".git/", "vendor/", "dist/", "build/", ".next/", ".cache/"
    ]

    private static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "pdf", "zip", "gz",
        "tar", "dmg", "app", "exe", "dll", "so", "dylib", "bin", "woff",
        "woff2", "ttf", "otf", "mp3", "mp4", "mov", "avi", "sqlite",
        "db", "xcworkspace", "xcodeproj", "framework", "a", "o"
    ]

    private let gitPath: String

    private init() {
        gitPath = Self.locateGit()
    }

    private static func locateGit() -> String {
        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }

    func getSessionStats(at url: URL, sinceCommit: String?) async -> [String: String]? {
        guard let commit = sinceCommit, !commit.isEmpty else { return nil }
        let args = gitArguments(for: url, ["diff", commit, "--numstat"])
        do {
            let result = try await runGit(arguments: args)
            guard result.exitCode == 0 else { return nil }
            var stats: [String: String] = [:]
            for line in result.stdout.split(separator: "\n") {
                let parts = line.split(separator: "\t")
                if parts.count == 3 {
                    let added = parts[0]
                    let removed = parts[1]
                    let file = String(parts[2])
                    if added == "-" && removed == "-" {
                        stats[file] = "(bin)"
                    } else {
                        stats[file] = "(+\(added) -\(removed))"
                    }
                }
            }
            return stats
        } catch {
            return nil
        }
    }

    func createWorkingTreeSnapshot(at url: URL) async -> String? {
        // `git stash create` creates a dangling commit of the working tree if there are changes.
        let args = gitArguments(for: url, ["stash", "create"])
        do {
            let result = try await runGit(arguments: args)
            let hash = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hash.isEmpty {
                return hash
            } else {
                // If there are no uncommitted changes, `stash create` returns empty. Just use HEAD.
                let headArgs = gitArguments(for: url, ["rev-parse", "HEAD"])
                let headResult = try await runGit(arguments: headArgs)
                return headResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return nil
        }
    }

    func collectSnapshot(
        at projectURL: URL,
        includeDiff: Bool = true,
        referenceManifest: [String: FileFingerprint]? = nil
    ) async -> GitSnapshot {
        let native = GitNativeReader.inspect(at: projectURL)
        let scannedChanges = FileChangeScanner.scanModifiedFiles(
            at: projectURL,
            since: nil,
            referenceManifest: referenceManifest
        )

        if native.isRepository {
            if let cliSnapshot = await tryCLISnapshot(
                at: projectURL,
                native: native,
                includeDiff: includeDiff
            ) {
                return cliSnapshot
            }

            return nativeFallbackSnapshot(
                at: projectURL,
                native: native,
                scannedChanges: scannedChanges,
                includeDiff: includeDiff
            )
        }

        return nonGitSnapshot(
            at: projectURL,
            scannedChanges: scannedChanges,
            includeDiff: includeDiff
        )
    }

    func refreshMetadata(
        at projectURL: URL,
        referenceManifest: [String: FileFingerprint]? = nil
    ) async -> GitSnapshot {
        await collectSnapshot(at: projectURL, includeDiff: false, referenceManifest: referenceManifest)
    }

    // MARK: - Snapshot builders

    private func tryCLISnapshot(
        at projectURL: URL,
        native: GitNativeReader.RepositoryInfo,
        includeDiff: Bool
    ) async -> GitSnapshot? {
        do {
            try await verifyRepository(at: projectURL)

            let branch = try await currentBranch(at: projectURL)
            let headHash = try await headCommit(at: projectURL)
            let commits = try await recentCommits(at: projectURL, count: 5)
            let statusEntries = try await statusEntries(at: projectURL)
            let changedFiles = statusEntries.map(\.path)
            let statusSummary = formatStatusSummary(statusEntries)

            var diff = ""
            var truncated = false
            if includeDiff {
                let result = try await collectBoundedDiff(at: projectURL, changedFiles: changedFiles)
                diff = result.diff
                truncated = result.truncated
            }

            return GitSnapshot(
                gitAvailable: true,
                branch: branch,
                headHash: headHash,
                recentCommits: commits,
                workingTreeStatus: statusSummary,
                changedFiles: changedFiles,
                diff: diff,
                diffTruncated: truncated,
                errorMessage: nil,
                fileStats: nil
            )
        } catch {
            return nil
        }
    }

    private func nativeFallbackSnapshot(
        at projectURL: URL,
        native: GitNativeReader.RepositoryInfo,
        scannedChanges: [String],
        includeDiff: Bool
    ) -> GitSnapshot {
        let changedFiles = scannedChanges
        let status: String
        if changedFiles.isEmpty {
            status = "No local changes detected (native scan)"
        } else {
            status = "\(changedFiles.count) changed file(s) detected (native scan)"
        }

        var diff = ""
        var truncated = false
        if includeDiff, !changedFiles.isEmpty {
            let result = FileChangeScanner.buildReferenceDiff(
                at: projectURL,
                changedFiles: changedFiles,
                maxBytes: Self.maxDiffBytes
            )
            diff = result.diff
            truncated = result.truncated
        }

        return GitSnapshot(
            gitAvailable: true,
            branch: native.branch,
            headHash: native.headHash,
            recentCommits: native.recentCommits,
            workingTreeStatus: status,
            changedFiles: changedFiles,
            diff: diff,
            diffTruncated: truncated,
            errorMessage: "Git CLI unavailable in sandbox; using automatic file scan.",
            fileStats: nil
        )
    }

    private func nonGitSnapshot(
        at projectURL: URL,
        scannedChanges: [String],
        includeDiff: Bool
    ) -> GitSnapshot {
        var diff = ""
        var truncated = false
        if includeDiff, !scannedChanges.isEmpty {
            let result = FileChangeScanner.buildReferenceDiff(
                at: projectURL,
                changedFiles: scannedChanges,
                maxBytes: Self.maxDiffBytes
            )
            diff = result.diff
            truncated = result.truncated
        }

        let status: String
        if scannedChanges.isEmpty {
            status = "Not a Git repo · no recent file changes"
        } else {
            status = "Not a Git repo · \(scannedChanges.count) changed file(s)"
        }

        return GitSnapshot(
            gitAvailable: false,
            branch: nil,
            headHash: nil,
            recentCommits: [],
            workingTreeStatus: status,
            changedFiles: scannedChanges,
            diff: diff,
            diffTruncated: truncated,
            errorMessage: "Not a Git repository. File changes are still tracked automatically.",
            fileStats: nil
        )
    }

    // MARK: - Git Commands

    private struct StatusEntry {
        var indexStatus: Character
        var workTreeStatus: Character
        var path: String
    }

    private func gitArguments(for projectURL: URL, _ args: [String]) -> [String] {
        if let gitDir = GitNativeReader.resolveGitDirectory(for: projectURL) {
            return ["--git-dir", gitDir.path, "--work-tree", projectURL.path] + args
        }
        return ["-C", projectURL.path] + args
    }

    private func verifyRepository(at url: URL) async throws {
        let result = try await runGit(arguments: gitArguments(for: url, ["rev-parse", "--git-dir"]))
        if result.exitCode != 0 {
            throw GitServiceError.notARepository
        }
    }

    private func currentBranch(at url: URL) async throws -> String {
        let result = try await runGit(arguments: gitArguments(for: url, ["rev-parse", "--abbrev-ref", "HEAD"]))
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? "HEAD" : branch
    }

    private func headCommit(at url: URL) async throws -> String {
        let result = try await runGit(arguments: gitArguments(for: url, ["rev-parse", "HEAD"]))
        guard result.exitCode == 0 else { return "" }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recentCommits(at url: URL, count: Int) async throws -> [GitCommitSnapshot] {
        let result = try await runGit(
            arguments: gitArguments(for: url, ["log", "-n", String(count), "--format=%h%x00%s"])
        )
        guard result.exitCode == 0 else { return [] }

        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> GitCommitSnapshot? in
                let parts = line.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                return GitCommitSnapshot(shortHash: String(parts[0]), subject: String(parts[1]))
            }
    }

    private func statusEntries(at url: URL) async throws -> [StatusEntry] {
        let result = try await runGit(
            arguments: gitArguments(for: url, ["status", "--porcelain=v1", "-z"])
        )
        guard result.exitCode == 0 else { return [] }

        var entries: [StatusEntry] = []
        let parts = result.stdout.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var index = 0

        while index < parts.count {
            let record = parts[index]
            index += 1
            guard record.count >= 4 else { continue }

            let indexStatus = record[record.startIndex]
            let workTreeStatus = record[record.index(record.startIndex, offsetBy: 1)]
            let firstPath = String(record[record.index(record.startIndex, offsetBy: 3)...])

            let path: String
            if indexStatus == "R" || workTreeStatus == "R", index < parts.count {
                path = parts[index]
                index += 1
            } else {
                path = firstPath
            }

            if !path.isEmpty {
                entries.append(StatusEntry(indexStatus: indexStatus, workTreeStatus: workTreeStatus, path: path))
            }
        }

        return entries
    }

    private func formatStatusSummary(_ entries: [StatusEntry]) -> String {
        if entries.isEmpty { return "Clean working tree" }

        var modified = 0
        var added = 0
        var deleted = 0
        var untracked = 0
        var renamed = 0

        for entry in entries {
            if entry.indexStatus == "?" && entry.workTreeStatus == "?" {
                untracked += 1
            } else if entry.indexStatus == "R" || entry.workTreeStatus == "R" {
                renamed += 1
            } else if entry.indexStatus == "A" || entry.workTreeStatus == "A" {
                added += 1
            } else if entry.indexStatus == "D" || entry.workTreeStatus == "D" {
                deleted += 1
            } else {
                modified += 1
            }
        }

        var parts: [String] = []
        if modified > 0 { parts.append("\(modified) modified") }
        if added > 0 { parts.append("\(added) added") }
        if deleted > 0 { parts.append("\(deleted) deleted") }
        if renamed > 0 { parts.append("\(renamed) renamed") }
        if untracked > 0 { parts.append("\(untracked) untracked") }
        return parts.joined(separator: ", ")
    }

    private func collectBoundedDiff(
        at url: URL,
        changedFiles: [String]
    ) async throws -> (diff: String, truncated: Bool) {
        let safeFiles = changedFiles.filter { !Self.isSensitivePath($0) && !Self.isBinaryPath($0) }
        guard !safeFiles.isEmpty else {
            return ("", false)
        }

        var combined = ""
        var truncated = false

        for file in safeFiles {
            if combined.utf8.count >= Self.maxDiffBytes {
                truncated = true
                break
            }

            let unstaged = try await diffFile(at: url, file: file, staged: false)
            let staged = try await diffFile(at: url, file: file, staged: true)
            let chunk = [unstaged, staged].filter { !$0.isEmpty }.joined(separator: "\n")
            guard !chunk.isEmpty else { continue }

            let header = "diff -- \(file)\n"
            let next = combined.isEmpty ? header + chunk : combined + "\n\n" + header + chunk
            if next.utf8.count > Self.maxDiffBytes {
                truncated = true
                break
            }
            combined = next
        }

        if truncated {
            combined += "\n\n[Diff truncated at \(Self.maxDiffBytes / 1024) KB limit]"
        }

        return (combined, truncated)
    }

    private func diffFile(at url: URL, file: String, staged: Bool) async throws -> String {
        var args = gitArguments(for: url, ["diff", "--no-ext-diff", "--no-textconv"])
        if staged {
            args.insert("--cached", at: args.count - 1)
        }
        args.append("--")
        args.append(file)

        let result = try await runGit(arguments: args)
        guard result.exitCode == 0 else { return "" }
        return result.stdout
    }

    static func isSensitivePath(_ path: String) -> Bool {
        let lowered = path.lowercased()
        if lowered.hasSuffix(".env") || lowered.contains("/.env") { return true }
        if lowered.contains("private key") || lowered.contains("id_rsa") || lowered.contains("id_ed25519") {
            return true
        }
        for pattern in sensitivePathPatterns {
            if lowered.contains(pattern.lowercased()) { return true }
        }
        if lowered.hasSuffix(".pem") || lowered.hasSuffix(".p12") || lowered.hasSuffix(".key") {
            return true
        }
        return false
    }

    static func isBinaryPath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return binaryExtensions.contains(ext)
    }

    private struct ProcessResult {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    private func runGit(arguments: [String], timeout: TimeInterval = 30) async throws -> ProcessResult {
        try await MainActor.run {
            try Self.runProcess(executable: gitPath, arguments: arguments, timeout: timeout)
        }
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let outHandle = stdoutPipe.fileHandleForReading
        let errHandle = stderrPipe.fileHandleForReading

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            throw GitServiceError.timeout
        }

        let stdout = String(data: outHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return ProcessResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
