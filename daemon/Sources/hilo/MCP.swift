import Foundation
import HiloRuntime
import HiloStore

/// MCP server over stdio (newline-delimited JSON-RPC). Claude can read Hilo and propose agreements; it never confirms them.
struct MCPServer {
    let store: HiloStore
    let onChange: () -> Void
    var defaultProject = GitRepo.project(of: FileManager.default.currentDirectoryPath)

    static var tools: [[String: Any]] { [
        tool("hilo_current_task", "The Hilo task in progress on this Mac, if any.", [:]),
        tool("hilo_resume", "Where the user left off in a project: last session and its steps, open tasks, recent agreements.",
             ["project": ["type": "string", "description": "Project name (the repo directory name); defaults to the repo Claude Code runs in"]]),
        tool("hilo_add_task", "Add a task to the user's Hilo list.",
             ["title": ["type": "string"], "project": ["type": "string"], "start": ["type": "boolean", "description": "Mark it in progress"]],
             required: ["title"]),
        tool("hilo_log_agreement", "Propose an agreement or decision for the user to confirm in Hilo. It stays pending until they confirm it.",
             ["text": ["type": "string"], "project": ["type": "string"], "context": ["type": "string", "description": "Where it came from"]],
             required: ["text"]),
        tool("hilo_week_summary", "This week's sessions, closed tasks and confirmed agreements per project, as Markdown.", [:]),
    ] }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any]]
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = request["method"] as? String else { continue }
            guard let id = request["id"] else { continue }
            let response: [String: Any]
            do {
                response = ["jsonrpc": "2.0", "id": id, "result": try handle(method, request["params"] as? [String: Any] ?? [:])]
            } catch let error as MCPError {
                response = ["jsonrpc": "2.0", "id": id, "error": ["code": error.code, "message": error.message]]
            } catch {
                response = ["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": "\(error)"]]
            }
            if let out = try? JSONSerialization.data(withJSONObject: response) {
                FileHandle.standardOutput.write(out + Data("\n".utf8))
            }
        }
    }

    private func handle(_ method: String, _ params: [String: Any]) throws -> Any {
        switch method {
        case "initialize":
            return ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                    "capabilities": ["tools": [:] as [String: Any]],
                    "serverInfo": ["name": "hilo", "version": "0.1"]]
        case "ping":
            return [:] as [String: Any]
        case "tools/list":
            return ["tools": Self.tools]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                return ["content": [["type": "text", "text": try call(name, args)]]]
            } catch let error as MCPError where error.code == -32602 {
                return ["content": [["type": "text", "text": error.message]], "isError": true]
            }
        default:
            throw MCPError(code: -32601, message: "unknown method \(method)")
        }
    }

    private func call(_ name: String, _ args: [String: Any]) throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        func string(_ key: String) -> String? {
            (args[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        switch name {
        case "hilo_current_task":
            guard let t = try store.currentTask() else { return "No task in progress." }
            return "#\(t.id) \(t.title)" + (t.project.map { " (project \($0.name))" } ?? "") + (t.notes.isEmpty ? "" : "\nNotes: \(t.notes)")
        case "hilo_resume":
            guard let project = string("project") ?? defaultProject else { throw MCPError.invalid("project is required outside a git repo") }
            GitCapture(store: store).scan(now: now, only: project)
            return try store.resumeMarkdown(project: project, now: now)
        case "hilo_add_task":
            guard let title = string("title") else { throw MCPError.invalid("title is required") }
            let t = try store.addTask(title, project: string("project") ?? defaultProject, status: args["start"] as? Bool == true ? .doing : .todo, now: now)
            onChange()
            return "Added task #\(t.id): \(t.title)"
        case "hilo_log_agreement":
            guard let text = string("text") else { throw MCPError.invalid("text is required") }
            try store.addAgreement(text, project: string("project") ?? defaultProject, context: string("context") ?? "", origin: .session, status: .pending, now: now)
            return "Proposed. The user confirms or discards it in Hilo › Agreements."
        case "hilo_week_summary":
            return try store.weekReport(start: HiloStore.startOfWeek(), now: now).markdown
        default:
            throw MCPError.invalid("unknown tool \(name)")
        }
    }
}

struct MCPError: Error {
    var code: Int
    var message: String
    static func invalid(_ message: String) -> MCPError { MCPError(code: -32602, message: message) }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
