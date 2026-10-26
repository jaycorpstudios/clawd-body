import Foundation
import HiloContract

/// A project's hue and accessory (`Accessory` cases follow the firmware's `bm_acc_t` order), derived exactly as the buddy does (`bm_project_look`), so both draw the same pet.
public struct PetLook: Equatable, Sendable {
    public static let main = PetLook(hue: 22, accessory: .wizard)

    public var hue: Int
    public var accessory: Accessory

    public init(hue: Int, accessory: Accessory) { self.hue = hue; self.accessory = accessory }

    public static func of(project: String) -> PetLook {
        var h: UInt32 = 2_166_136_261
        for byte in project.utf8 { h = (h ^ UInt32(byte)) &* 16_777_619 }
        return PetLook(hue: Int(h % 360), accessory: Accessory.allCases[Int((h / 360) % UInt32(Accessory.allCases.count))])
    }
}
