import Foundation
import Testing
import HiloStore
@testable import HiloRuntime

@Suite struct GitCaptureTests {
    let store: HiloStore

    init() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-git-\(UUID().uuidString)")
        store = try HiloStore(path: dir.appending(path: "hilo.sqlite").path(percentEncoded: false))
    }

    @Test func parsesTheLogFormatAndSkipsJunk() {
        let out = "abcdef1234\u{1f}1792900000\u{1f}Fix: a\u{1f}b\nshort\u{1f}1\u{1f}x\n\nfedcba98765\u{1f}notanumber\u{1f}y\n"
        let commits = GitCapture.parse(out, repo: "/r", branch: "main")
        #expect(commits == [CommitRecord(repo: "/r", hash: "abcdef1234", branch: "main", message: "Fix: a\u{1f}b", ts: 1_792_900_000)])
    }

    @Test func scanAsksGitForThisUsersRecentCommitsInSessionRepos() throws {
        try store.recordSessionStart("s1", project: "api", now: 1_000_000)
        try store.setRepo(session: "s1", repo: "/r/api")
        final class Calls: @unchecked Sendable { var args: [[String]] = [] }
        let calls = Calls()
        let capture = GitCapture(store: store, git: { repo, args in
            #expect(repo == "/r/api")
            calls.args.append(args)
            switch args[0] {
            case "rev-parse": return "feature/x\n"
            case "config": return "dev@example.com\n"
            default: return "1111111aaaa\u{1f}1000100\u{1f}Add thing\n"
            }
        })
        capture.scan(now: 1_000_200)
        capture.scan(now: 1_000_300)
        let log = try #require(calls.args.first { $0[0] == "log" })
        #expect(log.contains("--author=dev@example.com") && log.contains("--max-age=\(1_000_200 - GitCapture.lookbackSeconds)"))
        let commits = try store.commits(since: 0)
        #expect(commits.count == 1 && commits[0].branch == "feature/x" && commits[0].project?.name == "api")
    }

    @Test func theProjectOfADirectoryIsItsRepoName() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hilo-repo-\(UUID().uuidString)/payments-api")
        let nested = root.appending(path: "src/ledger")
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(GitRepo.project(of: nested.path(percentEncoded: false)) == "payments-api")
        #expect(GitRepo.project(of: FileManager.default.temporaryDirectory.path(percentEncoded: false)) == nil)
    }

    @Test func aRepoThatIsNotGitYieldsNothing() {
        let capture = GitCapture(store: store, git: { _, _ in nil })
        #expect(capture.commits(in: "/nowhere", since: 0).isEmpty)
    }
}
