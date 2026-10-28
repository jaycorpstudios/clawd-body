import Foundation
import Testing
@testable import HiloRuntime

@Suite struct StatusLineSetupTests {
    func state(_ json: String) -> StatusLineSetup.State { StatusLineSetup.detect(Data(json.utf8)) }

    @Test func detectsEachStatusLineShape() {
        #expect(state(#"{"statusLine":{"type":"command","command":"bash ~/.claude/line.sh"}}"#)
            == .notWrapped(command: "bash ~/.claude/line.sh"))
        #expect(state(#"{"statusLine":{"type":"command","command":"/Applications/Hilo.app/Contents/MacOS/hilo statusline -- bash x.sh"}}"#)
            == .wrapped)
        #expect(state(#"{"statusLine":{"command":"'/Users/a b/hilo' statusline"}}"#) == .wrapped)
        #expect(state(#"{"statusLine":{"command":"hilo statusline"}}"#) == .wrapped)
        #expect(state(#"{"statusLine":{"command":"echo hilo statusline"}}"#) == .notWrapped(command: "echo hilo statusline"))
        #expect(state(#"{"statusLine":{"command":"hilostats statusline"}}"#) == .notWrapped(command: "hilostats statusline"))
        #expect(state(#"{"model":"opus"}"#) == .noStatusLine)
        #expect(state(#"{"statusLine":{"type":"command","command":"  "}}"#) == .noStatusLine)
        #expect(state(#"{"statusLine": "#) == .unreadable)
        #expect(state("[]") == .unreadable)
        #expect(StatusLineSetup.detect(path: "/nonexistent/settings.json") == .noStatusLine)
    }

    @Test func promptNamesThisHiloAndEveryStep() {
        let text = StatusLineSetup.prompt(hilo: "/Applications/Hilo.app/Contents/MacOS/hilo")
        #expect(text.contains("`/Applications/Hilo.app/Contents/MacOS/hilo statusline -- <current command>`"))
        #expect(text.contains(#""command": "/Applications/Hilo.app/Contents/MacOS/hilo statusline""#))
        for step in ["settings.json.bak-hilo", "Never wrap it twice", "diff", "wait for my OK", "nothing is saved yet", "usage ring"] {
            #expect(text.contains(step))
        }
        #expect(StatusLineSetup.prompt(hilo: "/Users/a b/hilo").contains("`'/Users/a b/hilo' statusline -- <current command>`"))
    }
}
