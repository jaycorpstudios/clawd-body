import Foundation
import Testing
import HiloContract
@testable import HiloStore

private func makeStore() throws -> HiloStore {
    let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-store-\(UUID().uuidString)")
    return try HiloStore(path: dir.appending(path: "hilo.sqlite").path(percentEncoded: false))
}

@Test func projectsGetStableColorsInCreationOrder() throws {
    let store = try makeStore()
    let a = try store.project(named: "api")
    let b = try store.project(named: "web")
    #expect(a.color == HiloStore.projectPalette[0])
    #expect(b.color == HiloStore.projectPalette[1])
    #expect(try store.project(named: "api") == a)
}

@Test func taskLifecycle() throws {
    let store = try makeStore()
    let t = try store.addTask("Write tests", project: "api", now: 100)
    #expect(t.status == .todo && t.project?.name == "api" && t.startedAt == nil)

    try store.setStatus(task: t.id, .doing, now: 200)
    #expect(try store.currentTask()?.id == t.id)
    try store.setStatus(task: t.id, .done, now: 300)
    #expect(try store.task(t.id)?.doneAt == 300)
    #expect(try store.task(t.id)?.startedAt == 200)

    #expect(try store.tasks(doneSince: 250).map(\.id) == [t.id])
    #expect(try store.tasks(doneSince: 301).isEmpty)
}

@Test func sessionLinksToTheOnlyTaskInProgressForItsProject() throws {
    let store = try makeStore()
    let t = try store.addTask("Refactor", project: "api", status: .doing, now: 1)
    try store.addTask("Other", project: "web", status: .doing, now: 1)
    try store.recordSessionStart("s1", project: "api", now: 10)
    let s = try #require(try store.sessions(since: 0).first)
    #expect(s.taskId == t.id && s.taskTitle == "Refactor" && s.status == .working)
}

@Test func sessionIsNotLinkedWhenTheTaskIsAmbiguous() throws {
    let store = try makeStore()
    try store.addTask("A", project: "api", status: .doing, now: 1)
    try store.addTask("B", project: "api", status: .doing, now: 1)
    try store.recordSessionStart("s1", project: "api", now: 10)
    #expect(try store.sessions(since: 0).first?.taskId == nil)
}

@Test func stepsCreateUnknownSessionsAndTrackWaiting() throws {
    let store = try makeStore()
    try store.recordStep("s1", project: "api", kind: .ask, text: "Bash: npm test", status: .waiting, waitingOn: "Bash: npm test", now: 5)
    var s = try #require(try store.sessions(since: 0).first)
    #expect(s.status == .waiting && s.waitingOn == "Bash: npm test" && s.project?.name == "api")

    try store.recordStep("s1", project: nil, kind: .ok, text: "Approved on the buddy", status: .working, now: 6)
    s = try #require(try store.sessions(since: 0).first)
    #expect(s.status == .working && s.waitingOn == nil && s.lastAction == "Approved on the buddy")
    #expect(try store.steps(session: "s1").map(\.kind) == [.ask, .ok])
}

@Test func endedSessionsDropOutOfTheWindow() throws {
    let store = try makeStore()
    try store.recordSessionStart("s1", project: "api", now: 10)
    try store.finishSession("s1", status: .error, summary: nil, now: 20)
    try store.endSession("s1", now: 30)
    let s = try #require(try store.sessions(since: 0).first)
    #expect(s.status == .error && s.endedAt == 30)
    #expect(try store.sessions(since: 31).isEmpty)
}

@Test func agreementsNeedConfirmation() throws {
    let store = try makeStore()
    let id = try store.addAgreement("JSON events", project: "api", origin: .session, status: .pending, now: 1)
    #expect(try store.agreements().first?.status == .pending)
    try store.confirmAgreement(id)
    #expect(try store.agreements().first?.status == .confirmed)
}

@Test func reopeningRunsNoMigrationTwice() throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "hilo-reopen-\(UUID().uuidString).sqlite").path(percentEncoded: false)
    try HiloStore(path: path).addTask("Kept", project: nil, now: 1)
    #expect(try HiloStore(path: path).tasks(doneSince: 0).map(\.title) == ["Kept"])
}

@Test func buddyLinkState() throws {
    let store = try makeStore()
    #expect(try store.daemonState() == nil)
    try store.setBuddyConnected(true, now: 9)
    #expect(try store.daemonState() == DaemonState(buddyConnected: true, updatedAt: 9))
}
