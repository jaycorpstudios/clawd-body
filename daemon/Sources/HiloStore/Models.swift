import Foundation
import HiloContract

public enum TaskStatus: String, Codable, Sendable, CaseIterable { case todo, doing, done }
public enum AgreementOrigin: String, Codable, Sendable { case meeting, session, manual }
public enum AgreementStatus: String, Codable, Sendable { case confirmed, pending }

public struct Project: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var color: String
    public var jiraKey: String?
}

public struct HiloTaskRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var project: Project?
    public var title: String
    public var notes: String
    public var status: TaskStatus
    public var jiraRef: String?
    public var createdAt: Int
    public var startedAt: Int?
    public var doneAt: Int?
}

public struct SessionRecord: Equatable, Sendable, Identifiable {
    public var id: String
    public var project: Project?
    public var taskId: Int?
    public var taskTitle: String?
    public var status: SessionStatus
    public var startedAt: Int
    public var updatedAt: Int
    public var endedAt: Int?
    public var lastAction: String
    public var waitingOn: String?
    public var summary: String?
    public var tokens: Int?
}

public struct StepRecord: Equatable, Sendable {
    public var ts: Int
    public var kind: StepKind
    public var text: String
}

public struct Agreement: Equatable, Sendable, Identifiable {
    public var id: Int
    public var project: Project?
    public var taskId: Int?
    public var text: String
    public var context: String
    public var origin: AgreementOrigin
    public var status: AgreementStatus
    public var ts: Int
}

public struct DaemonState: Equatable, Sendable {
    public var buddyConnected: Bool
    public var updatedAt: Int
}

public struct CommitRecord: Equatable, Sendable, Identifiable {
    public var id: String { repo + "@" + hash }
    public var repo: String
    public var hash: String
    public var branch: String
    public var message: String
    public var ts: Int
    public var project: Project?
    public var taskId: Int?

    public init(repo: String, hash: String, branch: String, message: String, ts: Int, project: Project? = nil, taskId: Int? = nil) {
        self.repo = repo; self.hash = hash; self.branch = branch; self.message = message; self.ts = ts
        self.project = project; self.taskId = taskId
    }
}
