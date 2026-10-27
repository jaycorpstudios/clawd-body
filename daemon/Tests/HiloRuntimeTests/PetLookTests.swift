import Testing
import HiloContract
@testable import HiloRuntime

@Suite struct PetLookTests {
    @Test func matchesTheFirmwareDerivation() {
        #expect(PetLook.of(project: "payments-api") == PetLook(hue: 91, accessory: .shades))
        #expect(PetLook.of(project: "hilo-app") == PetLook(hue: 45, accessory: .heart))
        #expect(PetLook.of(project: "buddy-firmware") == PetLook(hue: 27, accessory: .shades))
        #expect(PetLook.of(project: "x") == PetLook(hue: 135, accessory: .none))
        #expect(PetLook.of(project: "") == PetLook(hue: 61, accessory: .party))
    }
}

@Suite struct SessionLookTests {
    @Test func eachSessionOfAProjectGetsItsOwnAccessoryInsideTheFamily() {
        let first = PetLook.forSession(project: "payments-api", others: [])
        #expect(first == SessionLook(hue: 91, acc: .shades))
        let second = PetLook.forSession(project: "payments-api", others: [first])
        #expect(second == SessionLook(hue: 105, acc: .headphones))
        let third = PetLook.forSession(project: "payments-api", others: [first, second])
        #expect(third == SessionLook(hue: 77, acc: .crown))
        let worn = Accessory.allCases.map { SessionLook(hue: 91, acc: $0) }
        #expect(PetLook.forSession(project: "payments-api", others: worn).acc == .shades)
        #expect(PetLook.forSession(project: "x", others: [SessionLook(hue: 135, acc: .none)] + Array(repeating: first, count: 3)).hue == 107)
    }
}
