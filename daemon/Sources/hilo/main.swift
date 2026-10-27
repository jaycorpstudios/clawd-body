import Foundation
import HiloCore
import HiloRuntime
import HiloStore

let arguments = Array(CommandLine.arguments.dropFirst())
let socketPath = LocalSocket.defaultPath
let now = Int(Date().timeIntervalSince1970)
let cwd = FileManager.default.currentDirectoryPath

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("hilo: \(message)\n".utf8))
    exit(code)
}

func option(_ name: String, in args: [String]) -> (value: String?, rest: [String]) {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return (nil, args) }
    var rest = args
    rest.removeSubrange(i...i + 1)
    return (args[i + 1], rest)
}

func openStore() -> HiloStore {
    do { return try HiloStore() } catch { fail("cannot open the Hilo store: \(error)") }
}

/// `-p ""` keeps the task or agreement out of any project.
func projectOption(_ given: String?) -> String? {
    given.map { $0.isEmpty ? nil : $0 } ?? GitRepo.project(of: cwd)
}

/// Lets the buddy show the change right away; quietly skipped when hilod is not running.
func notifyDaemon() {
    _ = LocalSocket.request(path: socketPath, op: "hilo", body: Data(), timeoutSeconds: 2)
}

func taskId(_ args: [String]) -> Int {
    guard args.count == 2, let id = Int(args[1].trimmingCharacters(in: CharacterSet(charactersIn: "#"))) else {
        fail("expected a task id, see `hilo today`", code: 2)
    }
    return id
}

func line(_ t: HiloTaskRecord) -> String {
    let box = switch t.status { case .todo: "[ ]"; case .doing: "[>]"; case .done: "[x]" }
    let project = t.project.map { "  · \($0.name)" } ?? ""
    return "\(box) #\(t.id) \(t.title)\(project)"
}

var startOfToday: Int { Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) }

switch arguments.first {
case "hook":
    // Must never block or break Claude Code: any failure prints nothing and exits 0.
    let input = FileHandle.standardInput.readDataToEndOfFile()
    if let reply = LocalSocket.request(path: socketPath, op: "hook", body: input, timeoutSeconds: 650) {
        FileHandle.standardOutput.write(reply)
    }
    exit(0)
case "statusline":
    // Forwards only `rate_limits` to hilod, then hands the same input to the wrapped status line command, if any.
    let input = FileHandle.standardInput.readDataToEndOfFile()
    if let limits = RateLimits.fromStatusLine(input), let body = try? JSONEncoder().encode(limits) {
        _ = LocalSocket.request(path: socketPath, op: "usage", body: body, timeoutSeconds: 1)
    }
    let wrapped = Array(arguments.dropFirst().drop { $0 == "--" })
    guard !wrapped.isEmpty else { exit(0) }
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = wrapped
    let pipe = Pipe()
    process.standardInput = pipe
    do { try process.run() } catch { exit(0) }
    pipe.fileHandleForWriting.write(input)
    try? pipe.fileHandleForWriting.close()
    process.waitUntilExit()
    exit(process.terminationStatus)
case "buddy" where arguments.count == 2:
    var body = Data(arguments[1].utf8)
    if var json = try? JSONSerialization.jsonObject(with: body) as? [String: Any], (json["ts"] as? Int ?? 0) == 0 {
        json["ts"] = Int(Date().timeIntervalSince1970)
        body = (try? JSONSerialization.data(withJSONObject: json)) ?? body
    }
    guard let reply = LocalSocket.request(path: socketPath, op: "buddy", body: body, timeoutSeconds: 5) else {
        fail("hilod is not running")
    }
    FileHandle.standardOutput.write(reply)
case "add":
    let (project, rest) = option("-p", in: Array(arguments.dropFirst()))
    let title = rest.filter { $0 != "--start" }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty else { fail("usage: hilo add \"title\" [-p project] [--start]", code: 2) }
    let task = try openStore().addTask(title, project: projectOption(project), status: rest.contains("--start") ? .doing : .todo, now: now)
    print(line(task))
    notifyDaemon()
case "start", "done", "todo":
    let status: TaskStatus = arguments[0] == "start" ? .doing : arguments[0] == "done" ? .done : .todo
    let store = openStore()
    let id = taskId(arguments)
    guard try store.task(id) != nil else { fail("no task #\(id)") }
    try store.setStatus(task: id, status, now: now)
    print(line(try store.task(id)!))
    notifyDaemon()
case "today", nil:
    let tasks = try openStore().tasks(doneSince: startOfToday)
    for status in [TaskStatus.doing, .todo, .done] {
        for t in tasks where t.status == status { print(line(t)) }
    }
    if tasks.isEmpty { print("No tasks. Add one with: hilo add \"…\"") }
case "agree":
    let (project, rest) = option("-p", in: Array(arguments.dropFirst()))
    let text = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { fail("usage: hilo agree \"text\" [-p project]", code: 2) }
    try openStore().addAgreement(text, project: projectOption(project), now: now)
    print("agreement logged")
    notifyDaemon()
case "sessions":
    let store = openStore()
    for s in try store.sessions(since: startOfToday) {
        let task = s.taskTitle.map { " → \($0)" } ?? ""
        print("\(s.id.prefix(8))  \(s.status.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0))  \(s.project?.name ?? "-")\(task)  \(s.lastAction)")
    }
case "resume":
    let project = arguments.count > 1 ? arguments[1] : URL(filePath: GitRepo.root(of: cwd) ?? cwd).lastPathComponent
    let store = openStore()
    GitCapture(store: store).scan(now: now, only: project)
    print(try store.resumeMarkdown(project: project, now: now))
case "week":
    let markdown = try openStore().weekReport(start: HiloStore.startOfWeek(), now: now).markdown
    print(arguments.contains("--md") ? markdown : markdown.split(separator: "\n", omittingEmptySubsequences: false).map { $0.drop { $0 == "#" }.drop { $0 == " " } }.joined(separator: "\n"))
case "install":
    let (explicit, _) = option("--hilod", in: Array(arguments.dropFirst()))
    guard let hilod = explicit ?? LaunchAgent.bundledHilod() else {
        fail("no hilod found in Hilo.app or next to hilo; pass --hilod <path>", code: 2)
    }
    let agent = LaunchAgent()
    do { try agent.install(hilod: hilod) } catch { fail("\(error)") }
    print("installed \(agent.plistPath) → \(hilod); log in \(agent.logPath)")
case "uninstall":
    let agent = LaunchAgent()
    do { try agent.uninstall() } catch { fail("\(error)") }
    print("hilod stopped; removed \(agent.plistPath)")
case "mcp":
    MCPServer(store: openStore(), onChange: notifyDaemon).run()
case "link" where arguments.count == 3:
    guard let id = Int(arguments[2].trimmingCharacters(in: CharacterSet(charactersIn: "#"))) else { fail("bad task id", code: 2) }
    let store = openStore()
    guard let session = try store.sessions(since: 0).first(where: { $0.id.hasPrefix(arguments[1]) }) else {
        fail("no session starting with \(arguments[1])")
    }
    try store.link(session: session.id, task: id)
    print("linked \(session.id.prefix(8)) to #\(id)")
default:
    FileHandle.standardError.write(Data("""
    usage:
      hilo today                       tasks in progress, next, and done today
      hilo add "title" [-p project] [--start]   project defaults to this directory's repo; -p "" for none
      hilo start|done|todo <id>        change a task's status
      hilo agree "text" [-p project]   log an agreement (same project default)
      hilo sessions                    today's Claude Code sessions
      hilo link <session> <task id>    attach a session to a task
      hilo resume [project]            where you left off (default: this directory's repo)
      hilo week [--md]                 this week per project; --md keeps the Markdown headings
      hilo mcp                         MCP server on stdio, for Claude Code
      hilo install [--hilod path]      run hilod at login as a LaunchAgent (default: the hilod in Hilo.app)
      hilo uninstall                   stop hilod and remove the LaunchAgent
      hilo hook                        read a Claude Code hook payload on stdin (configured in settings.json)
      hilo statusline [-- command…]    status line command: sends rate_limits to hilod, then runs the wrapped command
      hilo buddy '<json>'              send a buddy -> Mac message to hilod (development); ts 0 or absent becomes now

    """.utf8))
    exit(2)
}
