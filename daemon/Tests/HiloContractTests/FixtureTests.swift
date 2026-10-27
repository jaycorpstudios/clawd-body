import Foundation
import Testing
@testable import HiloContract

private let fixtures = URL(filePath: #filePath)
    .deletingLastPathComponent().appending(path: "../../../shared/fixtures").standardized

private func files(_ dir: String) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: fixtures.appending(path: dir), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func json(_ data: Data) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

private let buddyTypes: Set<String> = [
    "permission.decision", "question.answer", "device.ack", "device.snooze",
    "device.battery", "device.sleep", "device.wake", "device.pet_accessory",
    "device.settings", "device.face_request", "device.pomodoro", "media.control", "device.cover_request",
]

@Test(arguments: try files("valid"))
func validFixtureRoundTrips(_ url: URL) throws {
    let original = try Data(contentsOf: url)
    let fixture = try json(original)
    let type = try #require(fixture["type"] as? String)
    let reencoded: Data
    if buddyTypes.contains(type) {
        let env = try Wire.decodeInbound(original)
        reencoded = try Wire.encode(env.body, id: env.id, ts: env.ts)
    } else {
        let env = try Wire.decodeOutbound(original)
        reencoded = try Wire.encode(env.body, host: try #require(env.host), id: env.id, ts: env.ts)
    }
    #expect(try json(reencoded) == fixture)
}

@Test(arguments: try files("invalid"))
func invalidFixtureIsRejected(_ url: URL) throws {
    let wrapper = try json(Data(contentsOf: url))
    let event = try #require(wrapper["event"] as? NSDictionary)
    let bytes = try JSONSerialization.data(withJSONObject: event)
    let name = url.deletingPathExtension().lastPathComponent
    let reason = "\(wrapper["reason"] ?? "")"
    if buddyTypes.contains(event["type"] as? String ?? "") {
        #expect(throws: ContractError.self, "\(reason)") { try Wire.decodeInbound(bytes) }
    } else if envelopeRules.contains(name) {
        #expect(throws: ContractError.self, "\(reason)") { try Wire.decodeOutbound(bytes) }
    }
}

// Payload value rules for Mac → buddy messages are producer-side; shared/ checks them against the schema.
private let envelopeRules: Set<String> = [
    "missing-host", "host-uppercase", "unknown-version", "unknown-type", "bad-ulid", "extra-envelope-field",
]

@Test func rejectsBooleanVersion() throws {
    let bytes = Data(#"{"v":true,"id":"01K8F3Z9QW4Y6R2M7N5P8T0V1X","ts":1,"type":"device.snooze","data":{"request_id":"01K8F3Z9QW4Y6R2M7N5P8T0V1X"}}"#.utf8)
    #expect(throws: ContractError.badEnvelope("unsupported version")) { try Wire.decodeInbound(bytes) }
}

@Test func ulidIsValidAndSortsByTime() {
    let a = ULID.make(now: Date(timeIntervalSince1970: 1))
    let b = ULID.make(now: Date(timeIntervalSince1970: 2))
    #expect(ULID.isValid(a) && ULID.isValid(b))
    #expect(a < b)
}
