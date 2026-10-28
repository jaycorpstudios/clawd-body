import Foundation
import Testing
@testable import HiloRuntime

@Suite struct HooksSetupTests {
    func state(_ json: String) -> HooksSetup.State { HooksSetup.detect(Data(json.utf8)) }

    func settings(_ command: String, askMatcher: String = "AskUserQuestion", skip: String? = nil) -> String {
        let groups = HooksSetup.events.filter { $0.name != skip }.map { event in
            let matcher = event.matcher == nil ? "" : #""matcher":"\#(askMatcher)","#
            return #""\#(event.name)":[{\#(matcher)"hooks":[{"type":"command","command":"\#(command)"}]}]"#
        }
        return #"{"hooks":{\#(groups.joined(separator: ","))}}"#
    }

    @Test func detectsInstalledAndMissingHooks() {
        let all = HooksSetup.events.map(\.name)
        #expect(state(settings("/Applications/Hilo.app/Contents/MacOS/hilo hook")) == .installed)
        #expect(state(settings(#"'/Users/a b/hilo' hook"#)) == .installed)
        #expect(state(settings("hilo hook", askMatcher: "Bash|AskUserQuestion")) == .installed)
        #expect(state(settings("hilo hook", askMatcher: "Bash")) == .missing(["PreToolUse"]))
        #expect(state(settings("hilo hook", skip: "Stop")) == .missing(["Stop"]))
        #expect(state(settings("hilo hook --verbose")) == .missing(all))
        #expect(state(settings("echo hilo hook")) == .missing(all))
        #expect(state(#"{"model":"opus"}"#) == .missing(all))
        #expect(state(#"{"hooks": "#) == .unreadable)
        #expect(HooksSetup.detect(path: "/nonexistent/settings.json") == .missing(all))
    }

    @Test func promptNamesThisHiloEveryEventAndStep() {
        let text = HooksSetup.prompt(hilo: "/Applications/Hilo.app/Contents/MacOS/hilo")
        #expect(text.contains(#""command": "/Applications/Hilo.app/Contents/MacOS/hilo hook""#))
        for event in HooksSetup.events { #expect(text.contains("- \(event.name)")) }
        for step in ["settings.json.bak-hilo", "timeout 660", #"matcher "AskUserQuestion""#, "Never add it twice",
                     "diff", "wait for my OK", "nothing is saved yet", "new session"] {
            #expect(text.contains(step))
        }
        #expect(HooksSetup.prompt(hilo: "/Users/a b/hilo").contains("`'/Users/a b/hilo' hook`"))
    }
}
