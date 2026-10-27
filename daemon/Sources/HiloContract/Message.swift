import Foundation

public enum Outbound: Equatable, Sendable {
    case snapshot(Snapshot)
    case sessionStart(SessionStart)
    case sessionEnd(SessionRef)
    case needsPermission(PermissionRequest)
    case question(QuestionRequest)
    case requestResolved(RequestResolved)
    case taskDone(TaskDone)
    case agentError(AgentError)
    case agentStep(AgentStep)
    case usageUpdate(Usage)
    case usageWindowReset
    case hiloTaskChanged(HiloTask)
    case nowPlaying(Media)
    case settingsSet(SettingsChange)
    case face(FaceChunk)
    case pomodoro(PomodoroState)

    public var type: String {
        switch self {
        case .snapshot: "snapshot"
        case .sessionStart: "session.start"
        case .sessionEnd: "session.end"
        case .needsPermission: "agent.needs_permission"
        case .question: "agent.question"
        case .requestResolved: "agent.request_resolved"
        case .taskDone: "agent.task_done"
        case .agentError: "agent.error"
        case .agentStep: "agent.step"
        case .usageUpdate: "usage.update"
        case .usageWindowReset: "usage.window_reset"
        case .hiloTaskChanged: "hilo.task_changed"
        case .nowPlaying: "media.now_playing"
        case .settingsSet: "settings.set"
        case .face: "host.face"
        case .pomodoro: "pomodoro.state"
        }
    }

    var payload: any Encodable & Sendable {
        switch self {
        case .snapshot(let p): p
        case .sessionStart(let p): p
        case .sessionEnd(let p): p
        case .needsPermission(let p): p
        case .question(let p): p
        case .requestResolved(let p): p
        case .taskDone(let p): p
        case .agentError(let p): p
        case .agentStep(let p): p
        case .usageUpdate(let p): p
        case .usageWindowReset: Empty()
        case .hiloTaskChanged(let p): p
        case .nowPlaying(let p): p
        case .settingsSet(let p): p
        case .face(let p): p
        case .pomodoro(let p): p
        }
    }
}

public enum Inbound: Equatable, Sendable {
    case permissionDecision(PermissionDecision)
    case questionAnswer(QuestionAnswer)
    case ack(DeviceAck)
    case snooze(RequestRef)
    case battery(Battery)
    case sleep(SleepWake)
    case wake(SleepWake)
    case petAccessory(PetAccessory)
    case settings(DeviceSettings)
    case faceRequest(FaceRef)
    case pomodoro(PomodoroState)
    case mediaControl(MediaControl)
}

public struct Envelope<Body: Sendable>: Sendable {
    public var id: String
    public var ts: Int
    public var host: String?
    public var body: Body
}

public enum ContractError: Error, Equatable {
    case notJSON
    case badEnvelope(String)
    case unknownType(String)
    case badPayload(String)
}

public enum Wire {
    public static let version = 1

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public static func encode(_ message: Outbound, host: String, id: String = ULID.make(), ts: Int = Int(Date().timeIntervalSince1970)) throws -> Data {
        let data = try JSONSerialization.jsonObject(with: encoder.encode(message.payload))
        let envelope: [String: Any] = ["v": version, "id": id, "ts": ts, "host": host, "type": message.type, "data": data]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    public static func decodeInbound(_ bytes: Data) throws(ContractError) -> Envelope<Inbound> {
        let (header, type, data) = try split(bytes, allowedKeys: ["v", "id", "ts", "type", "data"])
        let body: Inbound
        switch type {
        case "permission.decision":
            let p: PermissionDecision = try payload(data, keys: ["request_id", "decision"])
            body = .permissionDecision(p)
        case "question.answer":
            let p: QuestionAnswer = try payload(data, keys: ["request_id", "choice_index", "choice"])
            guard (0...3).contains(p.choiceIndex), (1...40).contains(p.choice.count) else { throw .badPayload("choice out of range") }
            body = .questionAnswer(p)
        case "device.ack":
            let p: DeviceAck = try payload(data, keys: ["request_id", "seen"])
            guard p.seen else { throw .badPayload("seen must be true") }
            body = .ack(p)
        case "device.snooze":
            body = .snooze(try payload(data, keys: ["request_id"]))
        case "device.battery":
            let p: Battery = try payload(data, keys: ["pct", "charging"])
            guard (0...100).contains(p.pct) else { throw .badPayload("pct out of range") }
            body = .battery(p)
        case "device.sleep":
            body = .sleep(try payload(data, keys: ["by"]))
        case "device.wake":
            body = .wake(try payload(data, keys: ["by"]))
        case "device.pet_accessory":
            body = .petAccessory(try payload(data, keys: ["acc"]))
        case "device.settings":
            let p: DeviceSettings = try payload(data, keys: ["sound", "volume", "brightness"])
            guard DeviceSettings.volumeRange.contains(p.volume), DeviceSettings.brightnessRange.contains(p.brightness) else {
                throw .badPayload("setting out of range")
            }
            body = .settings(p)
        case "device.face_request":
            let p: FaceRef = try payload(data, keys: ["hash"])
            guard p.hash.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil else { throw .badPayload("bad face hash") }
            body = .faceRequest(p)
        case "device.pomodoro":
            let p: PomodoroState = try payload(data, keys: ["state", "phase", "ends_at", "left_s", "work_min", "break_min", "cycle", "updated_at"])
            guard p.isValid else { throw .badPayload("pomodoro out of range") }
            body = .pomodoro(p)
        case "media.control":
            body = .mediaControl(try payload(data, keys: ["action"]))
        default:
            throw .unknownType(type)
        }
        if let requestId = body.requestId, !ULID.isValid(requestId) { throw .badPayload("request_id is not a ULID") }
        return Envelope(id: header.id, ts: header.ts, host: nil, body: body)
    }

    /// Test and tooling support: Mac → buddy messages are only ever produced by the daemon.
    public static func decodeOutbound(_ bytes: Data) throws(ContractError) -> Envelope<Outbound> {
        let (header, type, data) = try split(bytes, allowedKeys: ["v", "id", "ts", "host", "type", "data"])
        guard let host = header.host else { throw .badEnvelope("host is required") }
        let body: Outbound
        switch type {
        case "snapshot": body = .snapshot(try payload(data))
        case "session.start": body = .sessionStart(try payload(data))
        case "session.end": body = .sessionEnd(try payload(data))
        case "agent.needs_permission": body = .needsPermission(try payload(data))
        case "agent.question": body = .question(try payload(data))
        case "agent.request_resolved": body = .requestResolved(try payload(data))
        case "agent.task_done": body = .taskDone(try payload(data))
        case "agent.error": body = .agentError(try payload(data))
        case "agent.step": body = .agentStep(try payload(data))
        case "usage.update": body = .usageUpdate(try payload(data))
        case "usage.window_reset": body = .usageWindowReset
        case "hilo.task_changed": body = .hiloTaskChanged(try payload(data))
        case "media.now_playing": body = .nowPlaying(try payload(data))
        case "settings.set": body = .settingsSet(try payload(data))
        case "host.face": body = .face(try payload(data))
        case "pomodoro.state": body = .pomodoro(try payload(data))
        default: throw .unknownType(type)
        }
        return Envelope(id: header.id, ts: header.ts, host: host, body: body)
    }

    private static func split(_ bytes: Data, allowedKeys: Set<String>) throws(ContractError) -> ((id: String, ts: Int, host: String?), String, [String: Any]) {
        guard let object = try? JSONSerialization.jsonObject(with: bytes), let env = object as? [String: Any] else { throw .notJSON }
        guard Set(env.keys).isSubset(of: allowedKeys) else { throw .badEnvelope("unexpected envelope field") }
        guard let v = integer(env["v"]), v == version else { throw .badEnvelope("unsupported version") }
        guard let id = env["id"] as? String, ULID.isValid(id) else { throw .badEnvelope("id is not a ULID") }
        guard let ts = integer(env["ts"]), ts >= 0 else { throw .badEnvelope("bad ts") }
        guard let type = env["type"] as? String else { throw .badEnvelope("missing type") }
        guard let data = env["data"] as? [String: Any] else { throw .badEnvelope("missing data") }
        let host = env["host"] as? String
        if let host, host.range(of: "^[a-z0-9-]{1,16}$", options: .regularExpression) == nil { throw .badEnvelope("bad host") }
        return ((id, ts, host), type, data)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return value as? Int
    }

    private static func payload<P: Decodable>(_ data: [String: Any], keys: Set<String>? = nil) throws(ContractError) -> P {
        if let keys, !Set(data.keys).isSubset(of: keys) { throw .badPayload("unexpected field") }
        do {
            return try decoder.decode(P.self, from: JSONSerialization.data(withJSONObject: data))
        } catch {
            throw .badPayload(String(describing: error))
        }
    }
}

extension Inbound {
    public var requestId: String? {
        switch self {
        case .permissionDecision(let p): p.requestId
        case .questionAnswer(let p): p.requestId
        case .ack(let p): p.requestId
        case .snooze(let p): p.requestId
        case .battery, .sleep, .wake, .petAccessory, .settings, .faceRequest, .pomodoro, .mediaControl: nil
        }
    }
}

extension Inbound {
    public var type: String {
        switch self {
        case .permissionDecision: "permission.decision"
        case .questionAnswer: "question.answer"
        case .ack: "device.ack"
        case .snooze: "device.snooze"
        case .battery: "device.battery"
        case .sleep: "device.sleep"
        case .wake: "device.wake"
        case .petAccessory: "device.pet_accessory"
        case .settings: "device.settings"
        case .faceRequest: "device.face_request"
        case .pomodoro: "device.pomodoro"
        case .mediaControl: "media.control"
        }
    }

    var payload: any Encodable & Sendable {
        switch self {
        case .permissionDecision(let p): p
        case .questionAnswer(let p): p
        case .ack(let p): p
        case .snooze(let p): p
        case .battery(let p): p
        case .sleep(let p), .wake(let p): p
        case .petAccessory(let p): p
        case .settings(let p): p
        case .faceRequest(let p): p
        case .pomodoro(let p): p
        case .mediaControl(let p): p
        }
    }
}

extension Wire {
    public static func encode(_ message: Inbound, id: String = ULID.make(), ts: Int = Int(Date().timeIntervalSince1970)) throws -> Data {
        let data = try JSONSerialization.jsonObject(with: encoder.encode(message.payload))
        let envelope: [String: Any] = ["v": version, "id": id, "ts": ts, "type": message.type, "data": data]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
