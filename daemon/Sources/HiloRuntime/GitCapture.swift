import Foundation
import HiloStore

/// Polls `git log` in the repos of recent Claude Code sessions and stores this user's commits.
public struct GitCapture: Sendable {
    public typealias Git = @Sendable (_ repo: String, _ arguments: [String]) -> String?

    public static let lookbackSeconds = 7 * 86_400
    private static let separator = "\u{1f}"

    private let store: HiloStore
    private let git: Git
    private let log: @Sendable (String) -> Void

    public init(store: HiloStore, git: @escaping Git = GitCapture.run, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.store = store; self.git = git; self.log = log
    }

    public func scan(now: Int) {
        do {
            for (repo, project) in try store.sessionRepos(since: now - Self.lookbackSeconds) {
                let commits = commits(in: repo, since: now - Self.lookbackSeconds)
                let added = try store.addCommits(commits, project: project)
                if added > 0 { log("git: \(added) new commit\(added == 1 ? "" : "s") in \(project ?? repo)") }
            }
        } catch {
            log("git: \(error)")
        }
    }

    func commits(in repo: String, since: Int) -> [CommitRecord] {
        guard let branch = git(repo, ["rev-parse", "--abbrev-ref", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !branch.isEmpty else { return [] }
        let email = git(repo, ["config", "user.email"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var arguments = ["log", "--max-age=\(since)", "--format=%H\(Self.separator)%ct\(Self.separator)%s"]
        if !email.isEmpty { arguments.append("--author=\(email)") }
        guard let output = git(repo, arguments) else { return [] }
        return Self.parse(output, repo: repo, branch: branch)
    }

    static func parse(_ output: String, repo: String, branch: String) -> [CommitRecord] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: Character(separator), maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, fields[0].count >= 7, let ts = Int(fields[1]) else { return nil }
            return CommitRecord(repo: repo, hash: String(fields[0]), branch: branch, message: String(fields[2].prefix(200)), ts: ts)
        }
    }

    public static let run: Git = { repo, arguments in
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", repo] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
