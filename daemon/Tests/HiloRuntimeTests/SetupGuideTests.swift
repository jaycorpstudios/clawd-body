import Testing
@testable import HiloRuntime

@Suite struct SetupGuideTests {
    @Test func launchAgentCommands() {
        let agent = LaunchAgent(logPath: "/logs/hilod.log")
        #expect(agent.submitArguments(hilod: "/apps/hilod") ==
                ["submit", "-l", "dev.hilo.hilod", "-o", "/logs/hilod.log", "-e", "/logs/hilod.log", "--", "/apps/hilod"])
        #expect(agent.removeArguments == ["remove", "dev.hilo.hilod"])
    }

    @Test func pairingStepsReadInOrder() {
        #expect(PairingGuide.describe(BuddyStatus(link: .notPaired)).title == "No buddy paired yet")
        #expect(PairingGuide.describe(BuddyStatus(link: .notPaired, pairing: .scanning)).active)
        let found = PairingGuide.describe(BuddyStatus(link: .notPaired, pairing: .connecting, buddyName: "Hilo Buddy"))
        #expect(found.title == "Found Hilo Buddy" && found.detail.contains("6 digits") && found.active)
        #expect(!PairingGuide.describe(BuddyStatus(link: .connected, pairing: .paired, buddyName: "Hilo Buddy")).active)
        #expect(PairingGuide.describe(BuddyStatus(link: .notPaired, pairing: .timedOut)).detail.contains("5 s"))
        #expect(PairingGuide.describe(BuddyStatus(link: .unauthorized)).detail.contains("Privacy"))
    }
}
