import Foundation
import CoreBluetooth
import CoreLocation
import UserNotifications

enum ConnectionState: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning…"
    case connecting = "Connecting…"
    case discoveringServices = "Discovering Services…"
    case connected = "Connected"
}

@MainActor
final class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()

    // MARK: - Published state

    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastResponse: String = ""
    @Published var log: [String] = []
    @Published var lastVibrationSent: Date?
    @Published var batteryLevel: Int?

    // MARK: - CoreBluetooth

    private var centralManager: CBCentralManager!
    private var ringPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    // MARK: - Protocol

    private let packetFramer = PacketFramer()

    // MARK: - Constants

    private let serviceUUID = CBUUID(string: "FE02")
    private let writeCharUUID = CBUUID(string: "0101")
    private let notifyCharUUID = CBUUID(string: "010A")
    private let ringName = "AIZO RING"
    private let peripheralUUIDKey = "savedRingPeripheralUUID"

    private var shouldReconnect = true
    private var lastReconnectAt: Date?
    private let reconnectMinInterval: TimeInterval = 3
    private let appGroupID = "group.com.tonykim.RingApp"

    // Write queue — ring needs time between commands
    private var writeCompletion: (() -> Void)?

    // Background location to prevent iOS app suspension
    private var locationManager: CLLocationManager?

    // BLE keepalive
    private var keepaliveTimer: Timer?
    private let keepaliveInterval: TimeInterval = 120
    private var batteryTimer: Timer?
    private let batteryInterval: TimeInterval = 600
    private var alarmTimer: Timer?
    private let alarmInterval: TimeInterval = 30

    // Vibration pattern defaults
    var vibrationBuzzes: Int = 3
    var vibrationBuzzMs: Int = 800
    var vibrationPauseMs: Int = 0

    // Alarm support
    var alarmStore: AlarmStore?

    // Leading-edge debounce state, keyed by caller-provided string (e.g. conversation name)
    private var lastBuzzByKey: [String: Date] = [:]

    /// Returns true if this key is outside its debounce window and a buzz should fire.
    /// Updates the stored timestamp for the key only when true is returned.
    func shouldBuzz(key: String, debounceSeconds: Int) -> Bool {
        guard debounceSeconds > 0 else { return true }
        let now = Date()
        if let last = lastBuzzByKey[key],
           now.timeIntervalSince(last) < TimeInterval(debounceSeconds) {
            addLog("debounce skip key=\(key) (\(Int(now.timeIntervalSince(last)))s < \(debounceSeconds)s)")
            return false
        }
        lastBuzzByKey[key] = now
        addLog("debounce pass key=\(key)")
        return true
    }

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "RingAppBLECentral"]
        )
        startBackgroundLocation()
    }

    private func startBackgroundLocation() {
        let lm = CLLocationManager()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        lm.allowsBackgroundLocationUpdates = true
        lm.pausesLocationUpdatesAutomatically = false
        lm.distanceFilter = CLLocationDistanceMax
        lm.requestAlwaysAuthorization()
        lm.startUpdatingLocation()
        locationManager = lm
        addLog("Background location started")
    }

    // MARK: - Public API

    func startScan() {
        guard centralManager.state == .poweredOn else {
            addLog("Bluetooth not ready (state: \(centralManager.state.rawValue))")
            return
        }
        shouldReconnect = true

        // 1. Try reconnecting to a known peripheral first
        if let saved = UserDefaults.standard.string(forKey: peripheralUUIDKey),
           let uuid = UUID(uuidString: saved) {
            let known = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = known.first {
                addLog("Reconnecting to known ring…")
                ringPeripheral = peripheral
                peripheral.delegate = self
                connectionState = .connecting
                centralManager.connect(peripheral, options: nil)
                return
            }
        }

        // 2. Check if already connected at system level
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let peripheral = connected.first {
            addLog("Found already-connected ring")
            ringPeripheral = peripheral
            peripheral.delegate = self
            savePeripheralUUID(peripheral)
            connectionState = .connecting
            centralManager.connect(peripheral, options: nil)
            return
        }

        // 3. Fall back to scanning
        connectionState = .scanning
        addLog("Scanning for \(ringName)…")
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func disconnect() {
        shouldReconnect = false
        stopKeepalive()
        if let peripheral = ringPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectionState = .disconnected
        addLog("Disconnected by user")
    }

    func sendVibratePhone(type: UInt8 = 1) {
        let payload: [UInt8] = [0x10, 0x08, type]
        sendCommand(payload: payload, label: "vibratePhone(type=\(type))")
        lastVibrationSent = Date()
    }

    func sendExperience(type: UInt8 = 4, intensity: UInt8 = 0xFF) {
        let payload: [UInt8] = [0x16, 0x10, type, intensity]
        sendCommand(payload: payload, label: "sendExperience(type=\(type), intensity=0x\(String(format: "%02X", intensity)))")
        lastVibrationSent = Date()
    }

    func startVibration() {
        let payload: [UInt8] = [0x10, 0x08, 0x01] // RINGING — start vibrating
        sendCommand(payload: payload, label: "startVibration")
    }

    func stopVibration() {
        let payload: [UInt8] = [0x10, 0x08, 0x02] // OFFHOOK — stop vibrating
        sendCommand(payload: payload, label: "stopVibration")
    }

    func vibrateForDuration(ms: Int) {
        guard connectionState == .connected else {
            addLog("Cannot send — not connected")
            return
        }
        addLog("Vibrating for \(ms)ms")
        startVibration()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(ms))
            stopVibration()
            lastVibrationSent = Date()
        }
    }

    func sendRepeatedVibration(buzzes: Int, buzzMs: Int, pauseMs: Int) {
        guard connectionState == .connected else {
            addLog("Cannot send — not connected")
            return
        }
        addLog("Sending \(buzzes)x buzzes (\(buzzMs)ms on, \(pauseMs)ms off)")
        Task { @MainActor in
            for i in 0..<buzzes {
                await sendCommandAndWait(payload: [0x10, 0x08, 0x01], label: "start[\(i+1)/\(buzzes)]")
                try? await Task.sleep(for: .milliseconds(buzzMs))
                await sendCommandAndWait(payload: [0x10, 0x08, 0x02], label: "stop[\(i+1)/\(buzzes)]")
                if i < buzzes - 1 {
                    try? await Task.sleep(for: .milliseconds(pauseMs))
                }
            }
            lastVibrationSent = Date()
        }
    }

    func getVibrate(type: UInt8) {
        let payload: [UInt8] = [0x16, 0x14, type]
        sendCommand(payload: payload, label: "getVibrate(type=\(type))")
    }

    func setVibrate(type: UInt8, highEnabled: Bool, highVal: UInt16, lowEnabled: Bool, lowVal: UInt16) {
        let hFlag: UInt8 = highEnabled ? 1 : 0
        let hBytes: [UInt8] = highEnabled
            ? [UInt8(highVal & 0xFF), UInt8(highVal >> 8)]
            : [0xFF, 0xFF]
        let lFlag: UInt8 = lowEnabled ? 1 : 0
        let lBytes: [UInt8] = lowEnabled
            ? [UInt8(lowVal & 0xFF), UInt8(lowVal >> 8)]
            : [0xFF, 0xFF]
        let payload: [UInt8] = [0x16, 0x13, type, hFlag, hBytes[0], hBytes[1], lFlag, lBytes[0], lBytes[1], 0xFF]
        sendCommand(payload: payload, label: "setVibrate(type=\(type), h=\(highEnabled):\(highVal), l=\(lowEnabled):\(lowVal))")
    }

    func requestBattery() {
        let payload: [UInt8] = [0x38, 0x38, 0x02]
        sendCommand(payload: payload, label: "getBattery")
    }

    private func timeBytes() -> [UInt8] {
        let cal = Calendar.current
        let now = Date()
        return [
            UInt8(cal.component(.year, from: now) % 100),
            UInt8(cal.component(.month, from: now)),
            UInt8(cal.component(.day, from: now)),
            UInt8(cal.component(.hour, from: now)),
            UInt8(cal.component(.minute, from: now)),
            UInt8(cal.component(.second, from: now))
        ]
    }

    func getSitRemind() {
        let payload: [UInt8] = [0x10, 0x16] + timeBytes()
        sendCommand(payload: payload, label: "getSitRemind")
    }

    func setSitRemind(startHour: UInt8, startMin: UInt8, endHour: UInt8, endMin: UInt8, notDisturb: Bool, isOpen: Bool) {
        let payload: [UInt8] = [0x10, 0x06, startHour, startMin, endHour, endMin, notDisturb ? 1 : 0, isOpen ? 1 : 0]
        sendCommand(payload: payload, label: "setSitRemind(open=\(isOpen))")
    }

    func disableSitRemind() {
        setSitRemind(startHour: 0, startMin: 0, endHour: 0, endMin: 0, notDisturb: false, isOpen: false)
    }

    /// Disable all vibration types except phone calls via setStatus
    func disableAllReminders() {
        setStatus(pairs: [
            (type: 1, enabled: false),  // app
            (type: 2, enabled: false),  // health
            (type: 3, enabled: false),  // alarm
            (type: 4, enabled: true),   // call — keep enabled
            (type: 5, enabled: false),  // notification
            (type: 6, enabled: false),  // care/sedentary
        ])
    }

    /// Sedentary reminder config via [0x15, 0x1B] command (from BeDeviceConfigUtil)
    func setSedentaryConfig(remindTimes: UInt8, eachDuration: UInt8, interval: UInt8, frequency: UInt16, intensity: UInt8) {
        let payload: [UInt8] = [
            0x15, 0x1B,                             // command prefix
            0x00,                                    // unknown field
            0xFF, 0xFF,                              // padding
            0x02,                                    // unknown field
            0xFF, 0xFF, 0xFF, 0xFF,                  // padding
            0xFF, 0xFF, 0xFF, 0xFF,                  // padding
            remindTimes,                             // number of reminder vibrations
            eachDuration,                            // duration of each vibration
            interval,                                // interval between reminders
            UInt8(frequency >> 8), UInt8(frequency & 0xFF), // frequency (big-endian)
            intensity,                               // vibration intensity
            0xFF, 0xFF,                              // padding
            0xFF, 0xFF, 0xFF, 0xFF,                  // padding
            0xFF, 0xFF, 0xFF, 0xFF,                  // padding
        ]
        sendCommand(payload: payload, label: "setSedentaryConfig(times=\(remindTimes), dur=\(eachDuration), int=\(interval))")
    }

    func disableSedentaryConfig() {
        setSedentaryConfig(remindTimes: 0, eachDuration: 0, interval: 0, frequency: 0, intensity: 0)
    }

    /// Query ring switch config [0x38, 0x38, 0x01]
    func getSwitchConfig() {
        sendCommand(payload: [0x38, 0x38, 0x01], label: "getSwitchConfig")
    }

    /// Query ring device config [0x38, 0x38, 0x04]
    func getDeviceConfig() {
        sendCommand(payload: [0x38, 0x38, 0x04], label: "getDeviceConfig")
    }

    /// Query heart rate monitoring interval [0x22, 0x10]
    func getHeartRateInterval() {
        sendCommand(payload: [0x22, 0x10], label: "getHRInterval")
    }

    /// Set heart rate monitoring interval [0x22, 0x11, value] — 0 to disable
    func setHeartRateInterval(_ value: UInt8) {
        sendCommand(payload: [0x22, 0x11, value], label: "setHRInterval(\(value))")
    }

    func setStatus(pairs: [(type: UInt8, enabled: Bool)]) {
        var payload: [UInt8] = [0x16, 0x11, UInt8(pairs.count)]
        for pair in pairs {
            payload.append(pair.type)
            payload.append(pair.enabled ? 1 : 0)
        }
        let desc = pairs.map { "\($0.type):\($0.enabled ? "on" : "off")" }.joined(separator: " ")
        sendCommand(payload: payload, label: "setStatus(\(desc))")
    }

    // MARK: - Private

    private func sendCommand(payload: [UInt8], label: String) {
        guard let characteristic = writeCharacteristic,
              let peripheral = ringPeripheral else {
            addLog("Cannot send \(label) — not connected")
            return
        }
        let packet = packetFramer.frame(payload: payload)
        let hex = packet.map { String(format: "%02X", $0) }.joined()
        addLog("TX \(label) → \(hex)")
        peripheral.writeValue(Data(packet), for: characteristic, type: .withResponse)
    }

    private func sendCommandAndWait(payload: [UInt8], label: String) async {
        guard let characteristic = writeCharacteristic,
              let peripheral = ringPeripheral else {
            addLog("Cannot send \(label) — not connected")
            return
        }
        let packet = packetFramer.frame(payload: payload)
        let hex = packet.map { String(format: "%02X", $0) }.joined()
        addLog("TX \(label) → \(hex)")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeCompletion = {
                continuation.resume()
            }
            peripheral.writeValue(Data(packet), for: characteristic, type: .withResponse)
        }
    }

    private func savePeripheralUUID(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: peripheralUUIDKey)
    }

    // Keep the last ~500 lines on screen and on disk; trim to 400 when we hit the cap.
    nonisolated private static let logMaxLines = 500
    nonisolated private static let logTrimTo = 400

    private func addLog(_ message: String) {
        let ts = Self.logDateFormatter.string(from: Date())
        let line = "[\(ts)] \(message)"
        log.append(line)
        if log.count > Self.logMaxLines {
            log.removeFirst(log.count - Self.logTrimTo)
        }
        persistLogLine(line)
    }

    nonisolated static let persistentLogURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ringapp.log")
    }()

    private func persistLogLine(_ line: String) {
        let url = Self.persistentLogURL
        let newLine = line + "\n"

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var combined = existing + newLine

        // Trim by line count, not byte count, so on-disk window matches what's on screen.
        var lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > Self.logMaxLines {
            lines = Array(lines.suffix(Self.logTrimTo))
            combined = lines.joined(separator: "\n")
        }

        try? combined.write(to: url, atomically: true, encoding: .utf8)
    }

    func clearPersistentLog() {
        try? FileManager.default.removeItem(at: Self.persistentLogURL)
        log.removeAll()
    }

    private func logDeliveredNotifications() {
        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] notes in
            Task { @MainActor in
                guard let self = self else { return }
                self.addLog("UN delivered count (own app only): \(notes.count)")
                for n in notes.prefix(5) {
                    let id = n.request.identifier
                    let title = n.request.content.title
                    self.addLog("  UN: \(id) — \(title)")
                }
            }
        }
    }

    private func decodeRX(_ bytes: [UInt8]) -> String {
        guard bytes.count >= 8 else { return "short(\(bytes.count))" }
        let length = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        let header = (UInt16(bytes[2]) << 8) | UInt16(bytes[3])
        let sn = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
        let payloadEnd = bytes.count - 2
        guard payloadEnd > 6 else { return "len=\(length) hdr=\(String(format:"%04X",header)) sn=\(sn) empty" }
        let payload = Array(bytes[6..<payloadEnd])
        let cmd = payload.count >= 2 ? String(format: "%02X%02X", payload[0], payload[1]) : "?"
        let label: String
        switch cmd {
        case "7878": label = "batteryResp"
        case "1108": label = "vibratePhoneAck"
        case "1620": label = "sendExperienceAck"
        case "1621": label = "setStatusAck"
        case "2006": label = "setSitRemindAck"
        case "2026": label = "getSitRemindResp"
        case "152B": label = "setSedentaryConfigAck"
        default: label = "cmd=\(cmd)"
        }
        let payHex = payload.map { String(format: "%02X", $0) }.joined()
        return "len=\(length) sn=\(sn) \(label) payload=\(payHex)"
    }

    private func attemptReconnect() {
        guard shouldReconnect else { return }

        let now = Date()
        let delay: TimeInterval
        if let last = lastReconnectAt {
            let elapsed = now.timeIntervalSince(last)
            delay = elapsed < reconnectMinInterval ? (reconnectMinInterval - elapsed) : 0
        } else {
            delay = 0
        }
        lastReconnectAt = now.addingTimeInterval(delay)

        // If we have a known peripheral, reconnect directly (no scan needed)
        if let peripheral = ringPeripheral {
            addLog("Reconnecting to ring…")
            connectionState = .connecting
            Task { @MainActor in
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                }
                guard self.shouldReconnect else { return }
                self.centralManager.connect(peripheral, options: nil)
            }
            return
        }

        addLog("Reconnecting in 2s…")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard self.shouldReconnect,
                  self.connectionState == .disconnected else { return }
            self.startScan()
        }
    }

    private func startKeepalive() {
        alarmTimer?.invalidate()
        alarmTimer = Timer.scheduledTimer(withTimeInterval: alarmInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.checkAlarms()
            }
        }
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: keepaliveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.connectionState == .connected else { return }
                self.addLog("keepalive: getVibrate")
                self.getVibrate(type: 1)
            }
        }
        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: batteryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.connectionState == .connected else { return }
                self.addLog("periodic: getBattery")
                self.requestBattery()
            }
        }
    }

    private func checkAlarms() {
        guard let store = alarmStore,
              let alarm = store.checkAlarms() else { return }
        addLog("Alarm: \(alarm.label.isEmpty ? alarm.timeString : alarm.label) → \(alarm.buzzes) buzzes")
        sendRepeatedVibration(buzzes: alarm.buzzes, buzzMs: 800, pauseMs: 0)
    }

    private func stopKeepalive() {
        alarmTimer?.invalidate()
        alarmTimer = nil
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                addLog("Bluetooth powered on")
                if shouldReconnect { startScan() }
            case .poweredOff:
                addLog("Bluetooth powered off")
                connectionState = .disconnected
            default:
                addLog("Bluetooth state: \(central.state.rawValue)")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        Task { @MainActor in
            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
               let ring = peripherals.first {
                addLog("Restored peripheral: \(ring.name ?? "unknown")")
                ringPeripheral = ring
                ring.delegate = self
                if ring.state == .connected {
                    connectionState = .discoveringServices
                    ring.discoverServices([serviceUUID])
                } else {
                    // Was connected before app was killed, reconnect
                    connectionState = .connecting
                    centralManager.connect(ring, options: nil)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard peripheral.name == ringName else { return }
            addLog("Found \(ringName) (RSSI: \(RSSI))")
            centralManager.stopScan()
            ringPeripheral = peripheral
            peripheral.delegate = self
            savePeripheralUUID(peripheral)
            connectionState = .connecting
            centralManager.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            addLog("Connected to \(peripheral.name ?? "ring")")
            connectionState = .discoveringServices
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor in
            addLog("Failed to connect: \(error?.localizedDescription ?? "unknown")")
            connectionState = .disconnected
            attemptReconnect()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor in
            let nsErr = error as NSError?
            let detail = nsErr.map { "\($0.domain) code=\($0.code) — \($0.localizedDescription)" } ?? "user initiated"
            addLog("Disconnected: \(detail)")
            stopKeepalive()
            writeCharacteristic = nil
            notifyCharacteristic = nil
            connectionState = .disconnected
            attemptReconnect()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else {
                addLog("No services found")
                return
            }
            for service in services {
                addLog("Service: \(service.uuid)")
                if service.uuid == serviceUUID {
                    peripheral.discoverCharacteristics([writeCharUUID, notifyCharUUID], for: service)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let chars = service.characteristics else { return }
            for char in chars {
                if char.uuid == writeCharUUID {
                    writeCharacteristic = char
                    addLog("Write characteristic ready")
                }
                if char.uuid == notifyCharUUID {
                    notifyCharacteristic = char
                    peripheral.setNotifyValue(true, for: char)
                    addLog("Subscribed to notify characteristic")
                }
            }
            if writeCharacteristic != nil {
                connectionState = .connected
                addLog("Ring ready!")
                stopVibration()
                setHeartRateInterval(0)   // disable HR monitoring buzz (~30 min interval)
                requestBattery()
                logDeliveredNotifications()
                startKeepalive()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value, !data.isEmpty else { return }
            let bytes = [UInt8](data)
            let hex = bytes.map { String(format: "%02X", $0) }.joined()
            addLog("RX: \(hex)  [\(decodeRX(bytes))]")
            lastResponse = hex

            // Parse battery response: payload starts at byte 6 (after 2B len + 2B header + 2B SN)
            // Response command: [0x78, 0x78, 0x02, battery%, ...]
            if bytes.count >= 10, bytes[6] == 0x78, bytes[7] == 0x78, bytes[8] == 0x02 {
                let battery = Int(bytes[9])
                batteryLevel = battery
                addLog("Battery: \(battery)%")
            }

            // Parse getSitRemind response: [0x20, 0x26, startHour, startMin, endHour, endMin, notDisturb, isOpen]
            if bytes.count >= 14, bytes[6] == 0x20, bytes[7] == 0x26 {
                let startH = bytes[8], startM = bytes[9]
                let endH = bytes[10], endM = bytes[11]
                let notDisturb = bytes[12] == 1
                let isOpen = bytes[13] == 1
                addLog("SitRemind: open=\(isOpen), \(startH):\(String(format:"%02d",startM))–\(endH):\(String(format:"%02d",endM)), notDisturb=\(notDisturb)")
            }

            // Parse setSitRemind ack: [0x20, 0x06, result]
            if bytes.count >= 9, bytes[6] == 0x20, bytes[7] == 0x06 {
                let ok = bytes.count > 8 && bytes[8] == 1
                addLog("setSitRemind result: \(ok ? "success" : "failed")")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                addLog("Write error: \(error.localizedDescription)")
            } else {
                addLog("Write OK")
            }
            // Signal any waiting sendCommandAndWait
            writeCompletion?()
            writeCompletion = nil
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension BLEManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // No-op — we only need the background session active
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            addLog("Location error: \(error.localizedDescription)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            addLog("Location auth: \(status.rawValue)")
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                manager.startUpdatingLocation()
            }
        }
    }
}
