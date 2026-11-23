import CoreBluetooth
import CryptoKit
import Foundation

/// Friends a few steps away, heard over Bluetooth: it works where there is no signal, which is
/// where the positions shared through the server (see `Nearby`) do not arrive.
///
/// While a day is recorded, and only if turned on, the iPhone says a short code over Bluetooth
/// and listens for the codes of the phones around. The code is made from the account's id and
/// the day, so it changes every day: your friends, who know your id, can tell it is you; to
/// anyone else it is a number that says nothing. No position is sent this way.
final class Proximity: NSObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {
    static let shared = Proximity()

    /// What the phones with Ski Apex say and look for.
    static let service = CBUUID(string: "6F3A1C52-8B7D-4E0A-9C41-5D2E7A90B1F3")
    /// The code of who is carrying the phone.
    static let whoIs = CBUUID(string: "6F3A1C53-8B7D-4E0A-9C41-5D2E7A90B1F3")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var running = false
    private var me = ""
    private var friends: [Friend] = []
    /// The phones being asked who they are: kept, or iOS drops the connection.
    private var asking: [UUID: CBPeripheral] = [:]
    /// When each phone around was last asked.
    private var asked: [UUID: Date] = [:]
    private var lastScan = Date.distantPast

    static var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.bluetooth) }

    // MARK: The code

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The code of an account on a day: the first eight bytes of the SHA-256 of its id and the date.
    static func code(id: String, day: Date = Date()) -> Data {
        Data(SHA256.hash(data: Data("skiapex|\(id)|\(dayFormat.string(from: day))".utf8)).prefix(8))
    }

    /// Whose code it is, among the friends: today's, or the day before's or after's for the
    /// phones whose clocks are across midnight.
    static func friend(for code: Data, among friends: [Friend], day: Date = Date()) -> Friend? {
        for shift in [0.0, -86_400.0, 86_400.0] {
            let date = day.addingTimeInterval(shift)
            if let found = friends.first(where: { Self.code(id: $0.id, day: date) == code }) { return found }
        }
        return nil
    }

    // MARK: On and off

    /// From the recorder, every few seconds: on while a day is recorded, if you turned it on.
    func update(recording: Bool) {
        let social = Shared.social
        let on = recording && Self.enabled && !Demo.isOn && social.account != nil
        if on, let account = social.account {
            me = account.id
            friends = social.friends.isEmpty ? Social.keptFriends() : social.friends
            if !running {
                running = true
                central = CBCentralManager(delegate: self, queue: nil)
                peripheral = CBPeripheralManager(delegate: self, queue: nil)
            } else if Date().timeIntervalSince(lastScan) > 120 {
                // A phone is told of once for each search: started again, to hear the same ones later.
                scan()
            }
        } else if running {
            stop()
        }
    }

    func stop() {
        running = false
        if let central {
            if central.state == .poweredOn { central.stopScan() }
            for phone in asking.values { central.cancelPeripheralConnection(phone) }
        }
        if let peripheral, peripheral.state == .poweredOn {
            peripheral.stopAdvertising()
            peripheral.removeAllServices()
        }
        central = nil
        peripheral = nil
        asking = [:]
        asked = [:]
    }

    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        lastScan = Date()
        central.stopScan()
        central.scanForPeripherals(withServices: [Self.service], options: nil)
    }

    // MARK: Listening

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, running { scan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Asked a moment ago: no need to ask again so soon.
        if let last = asked[peripheral.identifier], Date().timeIntervalSince(last) < 300 { return }
        guard asking[peripheral.identifier] == nil, asking.count < 6 else { return }
        asked[peripheral.identifier] = Date()
        asking[peripheral.identifier] = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        asking[peripheral.identifier] = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        asking[peripheral.identifier] = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.whoIs], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.whoIs }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let code = characteristic.value, let friend = Self.friend(for: code, among: friends) {
            Nearby.heard(friend)
        }
        central?.cancelPeripheralConnection(peripheral)
    }

    // MARK: Saying

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn, running else { return }
        // The value is given when asked for, so that it is always the code of the day.
        let who = CBMutableCharacteristic(type: Self.whoIs, properties: [.read], value: nil, permissions: [.readable])
        let service = CBMutableService(type: Self.service, primary: true)
        service.characteristics = [who]
        peripheral.removeAllServices()
        peripheral.add(service)
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.service]])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let code = Self.code(id: me)
        guard request.characteristic.uuid == Self.whoIs, request.offset <= code.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = code.subdata(in: request.offset..<code.count)
        peripheral.respond(to: request, withResult: .success)
    }
}
