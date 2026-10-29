import Foundation
import Testing
@testable import HiloRuntime

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [[String]] = []
    private let failing: Set<String>
    init(failing: Set<String> = []) { self.failing = failing }
    var all: [[String]] { lock.withLock { calls } }
    var launchctl: LaunchAgent.Launchctl {
        { args in
            self.lock.withLock { self.calls.append(args) }
            return self.failing.contains(args[0]) ? (5, "Input/output error\n") : (0, "")
        }
    }
}

@Suite struct LaunchAgentTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "hilo-launchagent-\(UUID().uuidString)")
    var agent: LaunchAgent {
        LaunchAgent(logPath: dir.appending(path: "Logs/Hilo/hilod.log").path(percentEncoded: false),
                    plistPath: dir.appending(path: "LaunchAgents/dev.hilo.hilod.plist").path(percentEncoded: false),
                    domain: "gui/501")
    }

    @Test func plistRunsTheBundledHilodAtLoadAndKeepsItAlive() throws {
        let data = try agent.plist(hilod: "/Applications/Hilo.app/Contents/Helpers/hilod")
        let job = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(job["Label"] as? String == "dev.hilo.hilod")
        #expect(job["ProgramArguments"] as? [String] == ["/Applications/Hilo.app/Contents/Helpers/hilod"])
        #expect(job["RunAtLoad"] as? Bool == true)
        #expect(job["KeepAlive"] as? Bool == true)
        #expect(job["StandardOutPath"] as? String == agent.logPath)
        #expect(job["StandardErrorPath"] as? String == agent.logPath)
        #expect(Set(job.keys) == ["Label", "ProgramArguments", "RunAtLoad", "KeepAlive", "StandardOutPath", "StandardErrorPath"])
        #expect(String(decoding: data, as: UTF8.self).hasPrefix("<?xml"))
    }

    @Test func installWritesThePlistReplacesASubmittedJobAndBootstraps() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let calls = Calls()
        try agent.install(hilod: "/apps/hilod", launchctl: calls.launchctl)
        #expect(agent.isInstalled)
        #expect(FileManager.default.fileExists(atPath: URL(filePath: agent.logPath).deletingLastPathComponent().path(percentEncoded: false)))
        #expect(calls.all == [["remove", "dev.hilo.hilod"], ["bootout", "gui/501/dev.hilo.hilod"],
                              ["bootstrap", "gui/501", agent.plistPath]])
        let job = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(filePath: agent.plistPath)), format: nil) as? [String: Any]
        #expect(job?["ProgramArguments"] as? [String] == ["/apps/hilod"])
    }

    @Test func aBootstrapThatKeepsFailingIsReported() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let calls = Calls(failing: ["bootstrap"])
        #expect(throws: LaunchAgent.Failure.self) { try agent.install(hilod: "/apps/hilod", launchctl: calls.launchctl) }
        #expect(calls.all.filter { $0[0] == "bootstrap" }.count == 6)
    }

    @Test func uninstallStopsTheJobAndRemovesThePlist() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try agent.install(hilod: "/apps/hilod", launchctl: Calls().launchctl)
        let calls = Calls(failing: ["remove"])
        try agent.uninstall(launchctl: calls.launchctl)
        #expect(!agent.isInstalled)
        #expect(calls.all == [["bootout", "gui/501/dev.hilo.hilod"], ["remove", "dev.hilo.hilod"]])
        try agent.uninstall(launchctl: calls.launchctl)
    }

    @Test func aJobStoppedByPrivacyChecksSaysSo() {
        let print = "gui/501/dev.hilo.hilod = {\n\tstate = spawn scheduled\n\truns = 5\n\tlast exit reason = OS_REASON_TCC\n}"
        #expect(agent.whyNotRunning(print: print)?.contains("Bluetooth") == true)
        #expect(agent.whyNotRunning(print: "\tstate = running\n\tlast exit code = (never exited)\n") == nil)
        #expect(agent.whyNotRunning(print: "\tlast exit code = 1\n") == "hilod exited with 1. Log in ~/Library/Logs/Hilo.")
    }

    @Test func restartKicksTheJob() throws {
        let calls = Calls()
        try agent.restart(launchctl: calls.launchctl)
        #expect(calls.all == [["kickstart", "-k", "gui/501/dev.hilo.hilod"]])
    }
}
