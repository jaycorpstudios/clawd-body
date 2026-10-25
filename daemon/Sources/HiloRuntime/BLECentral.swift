import CoreBluetooth
import Foundation
import HiloCore

/// CoreBluetooth central for one buddy. All CoreBluetooth state lives on `queue`.
public final class BLECentral: NSObject, FrameWriter, @unchecked Sendable {
    public static var service: CBUUID { CBUUID(string: "B7369283-8B36-49C1-AAAB-83A726C961EB") }
    static var rx: CBUUID { CBUUID(string: "FF7BD675-3612-48AF-9960-1F7338BF3623") }
    static var tx: CBUUID { CBUUID(string: "2076870D-85DF-42C8-9C4D-21589C44FC9F") }
    static let maxFrameSize = 512

    public let events: AsyncStream<LinkEvent>
    private let continuation: AsyncStream<LinkEvent>.Continuation
    private let queue = DispatchQueue(label: "hilod.ble")
    private let trusted: TrustedBuddies
    private let pairing: Bool
    private let log: @Sendable (String) -> Void
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var pendingWrite: CheckedContinuation<Bool, Never>?

    /// With `pairing`, scans for an untrusted buddy and trusts it once the encrypted link is up.
    public init(trusted: TrustedBuddies, pairing: Bool, log: @escaping @Sendable (String) -> Void) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        self.trusted = trusted
        self.pairing = pairing
        self.log = log
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    public func write(_ frame: Data) async -> Bool {
        await withCheckedContinuation { done in
            queue.async { [self] in
                guard let peripheral, let rx, peripheral.state == .connected, pendingWrite == nil else {
                    done.resume(returning: false)
                    return
                }
                pendingWrite = done
                peripheral.writeValue(frame, for: rx, type: .withResponse)
            }
        }
    }

    private func start() {
        if pairing {
            log("pairing: scanning for a buddy in pairing mode")
            central.scanForPeripherals(withServices: [Self.service])
            return
        }
        let ids = trusted.load()
        guard let known = central.retrievePeripherals(withIdentifiers: ids).first else {
            log(ids.isEmpty ? "no paired buddy; run hilod --pair" : "paired buddy not known to this Mac's Bluetooth")
            return
        }
        connect(known)
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        central.connect(p)
    }

    private func linkDown() {
        rx = nil
        pendingWrite?.resume(returning: false)
        pendingWrite = nil
        continuation.yield(.down)
    }
}

extension BLECentral: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: start()
        case .unauthorized: log("Bluetooth permission denied for hilod")
        default:
            if rx != nil { linkDown() }
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                               advertisementData: [String: Any], rssi: NSNumber) {
        guard pairing, peripheral == nil, !trusted.load().contains(p.identifier) else { return }
        central.stopScan()
        log("pairing: found \(p.name ?? "buddy"); confirm the passkey shown on it")
        connect(p)
    }

    public func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.service])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("connect failed: \(error?.localizedDescription ?? "unknown")")
        central.connect(p)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        let wasUp = rx != nil
        linkDown()
        if wasUp { log("buddy disconnected") }
        if pairing && !trusted.load().contains(p.identifier) {
            log("pairing did not complete")
            return
        }
        central.connect(p)
    }
}

extension BLECentral: CBPeripheralDelegate {
    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = p.services?.first(where: { $0.uuid == Self.service }) else { return drop(p, "no buddy service") }
        p.discoverCharacteristics([Self.rx, Self.tx], for: service)
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let chars = service.characteristics ?? []
        guard let tx = chars.first(where: { $0.uuid == Self.tx }), chars.contains(where: { $0.uuid == Self.rx }) else {
            return drop(p, "buddy characteristics missing")
        }
        p.setNotifyValue(true, for: tx)
    }

    public func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == Self.tx else { return }
        guard error == nil, c.isNotifying else { return drop(p, "encrypted link refused: \(error?.localizedDescription ?? "")") }
        let frameSize = min(p.maximumWriteValueLength(for: .withoutResponse), Self.maxFrameSize)
        guard frameSize >= 36 else { return drop(p, "frame size \(frameSize) too small") }
        if pairing {
            do { try trusted.add(p.identifier) } catch { log("cannot save paired buddy: \(error)") }
            log("paired")
        }
        rx = c.service?.characteristics?.first { $0.uuid == Self.rx }
        continuation.yield(.up(frameSize: frameSize))
    }

    public func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == Self.tx, error == nil, let value = c.value else { return }
        continuation.yield(.frame(value))
    }

    public func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        pendingWrite?.resume(returning: error == nil)
        pendingWrite = nil
    }

    private func drop(_ p: CBPeripheral, _ reason: String) {
        log(reason)
        central.cancelPeripheralConnection(p)
    }
}
