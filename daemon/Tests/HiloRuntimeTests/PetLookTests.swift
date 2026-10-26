import Testing
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
