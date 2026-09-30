import Foundation

/// Runs on the main thread while security-scoped folder access is active.
@MainActor
enum ProjectScanner {
    static func scan(
        at projectURL: URL,
        referenceManifest: [String: FileFingerprint]?,
        includeDiff: Bool
    ) -> GitSnapshot {
        let canRead = verifyReadAccess(at: projectURL)
        guard canRead else {
            return GitSnapshot(
                gitAvailable: false,
                branch: nil,
                headHash: nil,
                recentCommits: [],
                workingTreeStatus: "Cannot read project folder",
                changedFiles: [],
                diff: "",
                diffTruncated: false,
                errorMessage: "Folder access failed. Use Locate… to reconnect this project.",
                fileStats: [:]
            )
        }

        let native = GitNativeReader.inspect(at: projectURL)
        let scannedChanges = FileChangeScanner.scanModifiedFiles(
            at: projectURL,
            since: nil,
            referenceManifest: referenceManifest
        )

        if native.isRepository {
            if let cliSnapshot = runCLI(at: projectURL, includeDiff: includeDiff, scannedChanges: scannedChanges) {
                return cliSnapshot
            }

            var diff = ""
            var truncated = false
            let files = scannedChanges.isEmpty ? listAllTrackableFiles(at: projectURL) : scannedChanges

            if includeDiff, !files.isEmpty {
                let result = FileChangeScanner.buildReferenceDiff(
                    at: projectURL,
                    changedFiles: files,
                    maxBytes: GitService.maxDiffBytes
                )
                diff = result.diff
                truncated = result.truncated
            }

            let status: String
            if files.isEmpty {
                status = "No changes since last checkpoint"
            } else {
                status = "\(files.count) changed file(s)"
            }

            return GitSnapshot(
                gitAvailable: true,
                branch: native.branch ?? "unknown",
                headHash: native.headHash,
                recentCommits: native.recentCommits,
                workingTreeStatus: status,
                changedFiles: files,
                diff: diff,
                diffTruncated: truncated,
                errorMessage: nil,
                fileStats: [:]
            )
        }

        var diff = ""
        var truncated = false
        if includeDiff, !scannedChanges.isEmpty {
            let result = FileChangeScanner.buildReferenceDiff(
                at: projectURL,
                changedFiles: scannedChanges,
                maxBytes: GitService.maxDiffBytes
            )
            diff = result.diff
            truncated = result.truncated
        }

        let status = scannedChanges.isEmpty
            ? "Not a Git repo · no file changes detected"
            : "Not a Git repo · \(scannedChanges.count) changed file(s)"

        return GitSnapshot(
            gitAvailable: false,
            branch: nil,
            headHash: nil,
            recentCommits: [],
            workingTreeStatus: status,
            changedFiles: scannedChanges,
            diff: diff,
            diffTruncated: truncated,
            errorMessage: nil,
            fileStats: [:]
        )
    }

    private static func verifyReadAccess(at url: URL) -> Bool {
        if FileManager.default.isReadableFile(atPath: url.path) {
            return true
        }
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    private static func listAllTrackableFiles(at projectURL: URL) -> [String] {
        FileChangeScanner.scanModifiedFiles(at: projectURL, since: nil, referenceManifest: nil)
    }

    private static func runCLI(
        at projectURL: URL,
        includeDiff: Bool,
        scannedChanges: [String]
    ) -> GitSnapshot? {
        let gitPath = "/usr/bin/git"
        guard FileManager.default.fileExists(atPath: gitPath) else { return nil }

        do {
            let verify = try runProcess(
                executable: gitPath,
                arguments: gitArguments(for: projectURL, ["rev-parse", "--git-dir"])
            )
            guard verify.exitCode == 0 else { return nil }

            let branchResult = try runProcess(
                executable: gitPath,
                arguments: gitArguments(for: projectURL, ["rev-parse", "--abbrev-ref", "HEAD"])
            )
            let branch = branchResult.exitCode == 0
                ? branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : "HEAD"

            let headResult = try runProcess(
                executable: gitPath,
                arguments: gitArguments(for: projectURL, ["rev-parse", "HEAD"])
            )
            let headHash = headResult.exitCode == 0
                ? headResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            let logResult = try runProcess(
                executable: gitPath,
                arguments: gitArguments(for: projectURL, ["log", "-n", "5", "--format=%h%x00%s"])
            )

            let commits: [GitCommitSnapshot]
            if logResult.exitCode == 0 {
                commits = logResult.stdout
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .compactMap { line -> GitCommitSnapshot? in
                        let parts = line.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false)
                        guard parts.count == 2 else { return nil }
                        return GitCommitSnapshot(shortHash: String(parts[0]), subject: String(parts[1]))
                    }
            } else {
                commits = GitNativeReader.inspect(at: projectURL).recentCommits
            }

            let statusResult = try runProcess(
                executable: gitPath,
                arguments: gitArguments(for: projectURL, ["status", "--porcelain=v1", "-z"])
            )

            var changedFiles = scannedChanges
            var statusSummary = "\(scannedChanges.count) changed file(s)"

            if statusResult.exitCode == 0 {
                let entries = parseStatus(statusResult.stdout)
                if !entries.isEmpty {
                    changedFiles = entries
                    statusSummary = formatStatusSummary(entries)
                }
            }

            var diff = ""
            var truncated = false
            if includeDiff, !changedFiles.isEmpty {
                diff = collectCLIDiff(at: projectURL, gitPath: gitPath, files: changedFiles, truncated: &truncated)
                if diff.isEmpty {
                    let fallback = FileChangeScanner.buildReferenceDiff(
                        at: projectURL,
                        changedFiles: changedFiles,
                        maxBytes: GitService.maxDiffBytes
                    )
                    diff = fallback.diff
                    truncated = fallback.truncated
                }
            }

            var fileStats: [String: String] = [:]
            if let numstatResult = try? runProcess(
                executable: gitPath,
                arguments: gitArguments(for: projectURL, ["diff", "HEAD", "--numstat"])
            ), numstatResult.exitCode == 0 {
                for line in numstatResult.stdout.split(separator: "\n") {
                    let parts = line.split(separator: "\t")
                    if parts.count == 3 {
                        let added = parts[0]
                        let removed = parts[1]
                        let file = String(parts[2])
                        if added == "-" && removed == "-" {
                            fileStats[file] = "(bin)"
                        } else {
                            fileStats[file] = "(+\(added) -\(removed))"
                        }
                    }
                }
            }

            return GitSnapshot(
                gitAvailable: true,
                branch: branch.isEmpty ? "HEAD" : branch,
                headHash: headHash,
                recentCommits: commits,
                workingTreeStatus: statusSummary,
                changedFiles: changedFiles,
                diff: diff,
                diffTruncated: truncated,
                errorMessage: nil,
                fileStats: fileStats
            )
        } catch {
            return nil
        }
    }

    private static func gitArguments(for projectURL: URL, _ args: [String]) -> [String] {
        if let gitDir = GitNativeReader.resolveGitDirectory(for: projectURL) {
            return ["--git-dir", gitDir.path, "--work-tree", projectURL.path] + args
        }
        return ["-C", projectURL.path] + args
    }

    private static func collectCLIDiff(
        at projectURL: URL,
        gitPath: String,
        files: [String],
        truncated: inout Bool
    ) -> String {
        let safeFiles = files.filter { !GitService.isSensitivePath($0) && !GitService.isBinaryPath($0) }
        var combined = ""

        for file in safeFiles {
            if combined.utf8.count >= GitService.maxDiffBytes {
                truncated = true
                break
            }
            guard let unstaged = try? runProcess(
                executable: gitPath,
                arguments: gitArguments(for: projectURL, ["diff", "--no-ext-diff", "--no-textconv", "--", file])
            ), unstaged.exitCode == 0 else { continue }

            guard !unstaged.stdout.isEmpty else { continue }
            let chunk = "diff -- \(file)\n" + unstaged.stdout
            combined = combined.isEmpty ? chunk : combined + "\n\n" + chunk
        }

        if truncated {
            combined += "\n\n[Diff truncated]"
        }
        return combined
    }

    private static func parseStatus(_ output: String) -> [String] {
        let parts = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var index = 0
        var files: [String] = []

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
            if !path.isEmpty { files.append(path) }
        }
        return files
    }

    private static func formatStatusSummary(_ files: [String]) -> String {
        if files.isEmpty { return "Clean working tree" }
        return "\(files.count) changed file(s)"
    }

    private struct ProcessResult {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    private static func runProcess(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
