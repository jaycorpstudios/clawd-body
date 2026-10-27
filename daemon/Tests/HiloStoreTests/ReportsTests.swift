import Foundation
import Testing
import HiloContract
@testable import HiloStore

private func seeded() throws -> HiloStore {
    let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-reports-\(UUID().uuidString)")
    let store = try HiloStore(path: dir.appending(path: "hilo.sqlite").path(percentEncoded: false))
    let task = try store.addTask("Webhook retries", project: "api", status: .doing, now: 1_000)
    try store.addTask("Docs pass", project: "api", now: 1_000)
    try store.recordSessionStart("s1", project: "api", now: 1_000)
    try store.recordStep("s1", project: "api", kind: .edit, text: "Edited src/retry.ts", status: .working, now: 1_200)
    try store.recordActivity(session: "s1", now: 1_000)
    try store.recordActivity(session: "s1", now: 1_240)
    try store.finishSession("s1", status: .done, summary: "Retries back off exponentially.", now: 1_600)
    try store.addCommits([CommitRecord(repo: "/r/api", hash: "3f2b6810c4", branch: "main", message: "retry with backoff", ts: 1_500)],
                         project: "api")
    try store.setStatus(task: task.id, .done, now: 1_700)
    try store.recordSessionStart("s2", project: "web", now: 1_100)
    try store.addAgreement("Ship on Friday", project: "api", now: 1_300)
    return store
}

@Suite struct ReportsTests {
    @Test func weekGroupsByProjectWithActiveTimeAndCommits() throws {
        let report = try seeded().weekReport(start: 0, now: 1_900)
        #expect(report.projects.map(\.name) == ["api", "web"])
        let api = try #require(report.projects.first)
        #expect([api.active, api.sessions, api.sessionSeconds, api.commits] as [Int] == [500, 1, 600, 1])
        #expect(api.closed.map(\.title) == ["Webhook retries"])
        #expect(report.commitCount == 1 && report.sessionCount == 2)
        #expect(report.markdown.contains("## api\n8 min active · 10 min in 1 Claude Code session · 1 commit\n- [x] Webhook retries"))
        #expect(report.markdown.hasSuffix("## Agreements\n- Ship on Friday (api)"))
    }

    @Test func pastWeekLeavesOutWhatCameAfterItsEnd() throws {
        let report = try seeded().weekReport(start: 0, end: 1_400, now: 1_900)
        let api = try #require(report.projects.first { $0.name == "api" })
        #expect(api.commits == 0 && api.closed.isEmpty && api.active == 400)
        #expect(report.agreements.map(\.text) == ["Ship on Friday"])
        #expect(try seeded().weekReport(start: 0, end: 1_250, now: 1_900).agreements.isEmpty)
    }

    @Test func parallelSessionsCountOnceAndTimeStaysInsideTheWeek() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-reports-\(UUID().uuidString)")
        let store = try HiloStore(path: dir.appending(path: "hilo.sqlite").path(percentEncoded: false))
        try store.recordSessionStart("old", project: "api", now: 500)
        try store.endSession("old", now: 1_300)
        try store.recordSessionStart("a", project: "api", now: 1_100)
        try store.endSession("a", now: 1_500)
        try store.recordSessionStart("b", project: "api", now: 1_200)
        try store.endSession("b", now: 1_400)
        try store.recordSessionStart("w", project: "web", now: 1_450)
        try store.endSession("w", now: 1_700)
        let report = try store.weekReport(start: 1_000, now: 2_000)
        let api = try #require(report.projects.first { $0.name == "api" })
        #expect(api.sessions == 3 && api.sessionSeconds == 500)
        #expect(report.sessionSeconds == 700)
    }

    @Test func emptyWeekSaysSo() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-reports-\(UUID().uuidString)")
        let empty = try HiloStore(path: dir.appending(path: "hilo.sqlite").path(percentEncoded: false))
        #expect(try empty.weekReport(start: 0, now: 1).markdown.hasSuffix("Nothing recorded this week yet."))
    }

    @Test func resumeShowsTheLastSessionOpenTasksCommitsAndAgreements() throws {
        let text = try seeded().resumeMarkdown(project: "api", now: 2_000)
        #expect(text.hasPrefix("# api\n## Last session (done)\nRetries back off exponentially.\n- edit: Edited src/retry.ts\nResume with: claude --resume s1"))
        #expect(text.contains("## Open tasks\n- [ ] #2 Docs pass"))
        #expect(text.contains("## Recent commits\n- 3f2b681 retry with backoff (main)"))
        #expect(text.hasSuffix("## Recent agreements\n- Ship on Friday"))
    }
}
