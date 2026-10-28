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
        #expect([api.active, api.sessions, api.commits] as [Int] == [500, 1, 1])
        #expect(api.closed.map(\.title) == ["Webhook retries"])
        #expect(report.commitCount == 1 && report.sessionCount == 2)
        #expect(report.markdown.contains("## api\n8 min active · 1 Claude Code session · 1 commit\n- [x] Webhook retries"))
        #expect(report.markdown.hasSuffix("## Agreements\n- Ship on Friday (api)"))
    }

    @Test func pastWeekLeavesOutWhatCameAfterItsEnd() throws {
        let report = try seeded().weekReport(start: 0, end: 1_400, now: 1_900)
        let api = try #require(report.projects.first { $0.name == "api" })
        #expect(api.commits == 0 && api.closed.isEmpty && api.active == 400)
        #expect(report.agreements.map(\.text) == ["Ship on Friday"])
        #expect(try seeded().weekReport(start: 0, end: 1_250, now: 1_900).agreements.isEmpty)
    }

    @Test func emptyWeekSaysSo() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-reports-\(UUID().uuidString)")
        let empty = try HiloStore(path: dir.appending(path: "hilo.sqlite").path(percentEncoded: false))
        #expect(try empty.weekReport(start: 0, now: 1).markdown.hasSuffix("Nothing recorded this week yet."))
    }

    @Test func resumeDigestsStepsInsteadOfListingCommands() {
        let steps: [(StepKind, String)] = [(.plan, "New prompt"), (.read, "Read a.ts"), (.edit, "Edited a.ts"), (.run, "Ran perl -pi -e x"),
                                           (.edit, "Edited b.ts"), (.edit, "Edited a.ts"), (.run, "Ran git commit"), (.plan, "New prompt"), (.err, "Bash failed")]
        let digest = HiloStore.stepDigest(steps.enumerated().map { StepRecord(ts: $0.offset, kind: $0.element.0, text: $0.element.1) })
        #expect(digest == ["Edited: a.ts, b.ts", "Activity: 2 prompts · 2 commands · 1 read · 3 edits · 1 error"])
        #expect(HiloStore.stepDigest([]).isEmpty)
    }

    @Test func resumeShowsTheLastSessionOpenTasksCommitsAndAgreements() throws {
        let text = try seeded().resumeMarkdown(project: "api", now: 2_000)
        #expect(text.hasPrefix("# api\n## Last session (done)\nTask: Webhook retries\nRetries back off exponentially.\nEdited: src/retry.ts\nActivity: 1 edit\nResume with: claude --resume s1"))
        #expect(text.contains("## Open tasks\n- [ ] #2 Docs pass"))
        #expect(text.contains("## Recent commits\n- 3f2b681 retry with backoff (main)"))
        #expect(text.hasSuffix("## Recent agreements\n- Ship on Friday"))
    }
}

@Suite struct WeekSummaryTests {
    let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()

    @Test func draftsAreValidatedAndAnEditedParagraphIsKept() throws {
        let store = try seeded()
        let now = 1_793_102_400
        let week = HiloStore.weekKey(HiloStore.startOfWeek(Date(timeIntervalSince1970: TimeInterval(now)), calendar: utc), calendar: utc)
        #expect(week == "2026-10-26")
        #expect(throws: SummaryError.self) { try store.saveDraft(week: week, project: "nope", text: "x", now: now, calendar: utc) }
        #expect(throws: SummaryError.self) { try store.saveDraft(week: "2026-10-27", project: "api", text: "x", now: now, calendar: utc) }
        #expect(throws: SummaryError.self) { try store.saveDraft(week: "2026-11-02", project: "api", text: "x", now: now, calendar: utc) }
        #expect(throws: SummaryError.self) {
            try store.saveDraft(week: week, project: "api", text: String(repeating: "a", count: 2001), now: now, calendar: utc)
        }
        #expect(try store.saveDraft(week: week, project: "api", text: "Retries shipped.", now: now, calendar: utc))
        #expect(try store.summaries(week: week)["api"] == WeekSummary(text: "Retries shipped.", edited: false))
        let api = try #require(try store.projects().first { $0.name == "api" })
        try store.editSummary(week: week, projectId: api.id, text: "Retries shipped Friday.", now: now)
        #expect(try store.saveDraft(week: week, project: "api", text: "Overwrite", now: now, calendar: utc) == false)
        #expect(try store.summaries(week: week)["api"] == WeekSummary(text: "Retries shipped Friday.", edited: true))
    }

    @Test func theMarkdownPutsTheParagraphUnderItsProject() throws {
        let report = try seeded().weekReport(start: 0, now: 1_900)
        let with = WeekReport(start: 0, now: 1_900, sessions: [], active: ["api": 500], commits: [], tasks: [], agreements: [],
                              projects: report.projects.compactMap(\.project), summaries: ["api": WeekSummary(text: "Retries shipped.", edited: false)])
        #expect(with.markdown.contains("## api\n8 min active · 0 Claude Code sessions · 0 commits\n\nRetries shipped."))
    }
}
