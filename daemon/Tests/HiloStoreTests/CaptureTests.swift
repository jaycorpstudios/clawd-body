import Foundation
import Testing
@testable import HiloStore

private func makeStore() throws -> HiloStore {
    let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-capture-\(UUID().uuidString)")
    return try HiloStore(path: dir.appending(path: "hilo.sqlite").path(percentEncoded: false))
}

@Suite struct CaptureTests {
    @Test func sessionTokensAreStoredForKnownSessionsOnly() throws {
        let store = try makeStore()
        try store.recordSessionStart("s1", project: "api", now: 1_000)
        #expect(try store.sessions(since: 0).first?.tokens == nil)
        try store.setTokens(session: "s1", tokens: 41_200)
        try store.setTokens(session: "unknown", tokens: 9)
        #expect(try store.sessions(since: 0).map(\.tokens) == [41_200])
    }

    @Test func activityJoinsEventsAndPausesAfterFiveMinutes() throws {
        let store = try makeStore()
        try store.recordSessionStart("s1", project: "api", now: 1_000)
        for t in [1_000, 1_100, 1_400] { try store.recordActivity(session: "s1", now: t) }
        try store.recordActivity(session: "s1", now: 1_701)
        try store.recordActivity(session: "s1", now: 1_760)
        try store.recordActivity(session: "s1", now: 1_500)
        #expect(try store.activeSeconds(since: 0) == ["api": 400 + 59])
        #expect(try store.activeSeconds(since: 1_300) == ["api": 100 + 59])
        try store.recordActivity(session: "unknown", now: 2_000)
        try store.recordActivity(project: "web", now: 2_000)
        #expect(try store.activeSeconds(since: 0)["web"] == 0)
    }

    @Test func activityPerDaySplitsByStartDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let store = try makeStore()
        let day = 1_792_886_400
        try store.recordActivity(project: "api", now: day + 3_600)
        try store.recordActivity(project: "api", now: day + 3_900)
        try store.recordActivity(project: "api", now: day + 86_400 + 60)
        try store.recordActivity(project: "api", now: day + 86_400 + 120)
        #expect(try store.activeSecondsPerDay(since: day, calendar: calendar) == [day: 300, day + 86_400: 60])
    }

    @Test func commitsAreStoredOnceAndLinkToTheOnlyTaskInProgress() throws {
        let store = try makeStore()
        let task = try store.addTask("Refactor", project: "api", status: .doing, now: 1)
        let c1 = CommitRecord(repo: "/r/api", hash: "aaa", branch: "main", message: "first", ts: 100)
        let c2 = CommitRecord(repo: "/r/api", hash: "bbb", branch: "main", message: "second", ts: 200)
        #expect(try store.addCommits([c1, c2], project: "api") == 2)
        #expect(try store.addCommits([c1], project: "api") == 0)
        #expect(try store.commits(task: task.id).map(\.hash) == ["bbb", "aaa"])
        #expect(try store.commits(since: 150).map(\.message) == ["second"])
        #expect(try store.commits(project: "api", limit: 1).first?.project?.name == "api")
        #expect(try store.activeSeconds(since: 0) == ["api": 100])
    }

    @Test func sessionReposListActiveSessions() throws {
        let store = try makeStore()
        try store.recordSessionStart("s1", project: "api", now: 10)
        try store.setRepo(session: "s1", repo: "/r/api")
        try store.setRepo(session: "s1", repo: "/r/other")
        try store.recordSessionStart("s2", project: "web", now: 10)
        let repos = try store.sessionRepos(since: 0)
        #expect(repos.count == 1 && repos[0].repo == "/r/api" && repos[0].project == "api")
    }

    @Test func migratesAVersionOneStoreKeepingItsSessions() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-v1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appending(path: "hilo.sqlite").path(percentEncoded: false)
        do {
            let db = try Database(path: path)
            try db.execute(Schema.migrations[0])
            try db.execute("PRAGMA user_version = 1")
            try db.run("INSERT INTO session (id, status, started_at, updated_at, last_action) VALUES ('old', 'done', 1, 2, 'x')")
        }
        let store = try HiloStore(path: path)
        #expect(try store.sessions(since: 0).map(\.id) == ["old"])
        try store.setRepo(session: "old", repo: "/r/api")
        #expect(try store.sessionRepos(since: 0).map(\.repo) == ["/r/api"])
    }
}
