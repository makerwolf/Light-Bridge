import Foundation
@preconcurrency import CoreBluetooth

// MARK: - Opple Light Master BLE Constants
/// Opple Light Master protocol identifiers (LM3/LM4).
struct OppleProtocol {
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    /// RX on device side: app writes measurement/calibration commands here.
    static let writeCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    /// TX on device side: device notifies measurement payloads here.
    static let notifyCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    /// Optional standard Battery Service (if exposed by firmware).
    static let batteryServiceUUID = CBUUID(string: "180F")
    static let batteryLevelCharacteristicUUID = CBUUID(string: "2A19")
}

struct OppleMeterReading {
    let cctKelvin: Double
    let lux: Double
    let duv: Double
    let chromaticityX: Double
    let chromaticityY: Double
    let ev100: Double
    let batteryPercent: Int?
    let temperature: Int?
    let metricsProfileId: String
    let metricsProfileName: String
    let metricsProfileIsProvisional: Bool
    let updatedAt: Date
}

@MainActor
final class OppleGATTController {
    private let logMessage: (String) -> Void
    private let onMeasurement: (UUID, OppleMeterReading) -> Void
    private let onBatteryLevel: (UUID, Int) -> Void

    private struct DeviceRuntime {
        var seqNo: UInt8 = 0
        var inflight = false
        var rxBuffer: [UInt8] = []
        var notificationsEnabled = false
        var sessionStarted = false
        var metricsProfileId: String = "lm3"
        var calibrationFactors: [Double] = Array(repeating: 1.0, count: 8)
        var calPower: Double = 3305.0
        var cctHistory: [(time: Date, cct: Double)] = []
        var lastBatteryPercent: Int?
        var hasBatteryServiceLevel = false
        var loggedBatteryCandidates = false
        var loggedUnknownOpcodes: Set<Int> = []
        var measureTask: Task<Void, Never>?
    }

    private var writeCharacteristics: [UUID: CBCharacteristic] = [:]
    private var notifyCharacteristics: [UUID: CBCharacteristic] = [:]
    private var batteryCharacteristics: [UUID: CBCharacteristic] = [:]
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var managedDeviceIds: Set<UUID> = []
    private var runtimes: [UUID: DeviceRuntime] = [:]

    private let oppleNameHints = [
        "OPPLE",
        "SIGMESH",
        "LIGHT MASTER",
        "LIGHTMASTER",
        "LM3",
        "LM4",
    ]

    private let protoReqReadM3 = 0x0A04 // 2564
    private let protoResReadM3 = 0x0A05 // 2565
    private let protoReqMeas = 0x0A00   // 2560
    private let protoResMeas = 0x0A01   // 2561

    private let protoMsgSingle: UInt8 = 0x00
    private let protoMsgFFRAG: UInt8 = 0x80
    private let protoMsgMFRAG: UInt8 = 0xA0
    private let protoMsgLFRAG: UInt8 = 0xC0

    private let measureIntervalNanoseconds: UInt64 = 500_000_000

    private struct MetricsProfile {
        let id: String
        let displayName: String
        let isProvisional: Bool
    }

    private lazy var metricsProfiles: [String: MetricsProfile] = [
        "lm3": MetricsProfile(
            id: "lm3",
            displayName: "LM3",
            isProvisional: false
        ),
        // AS7341 V2 colorimetric profile from LM4 reverse engineering.
        "lm4_as7341_v2": MetricsProfile(
            id: "lm4_as7341_v2",
            displayName: "LM4",
            isProvisional: false
        ),
        "generic_provisional": MetricsProfile(
            id: "generic_provisional",
            displayName: "LM",
            isProvisional: true
        ),
    ]

    private let batteryVoltages = [4080, 3985, 3894, 3838, 3773, 3725, 3710, 3688, 3656, 3594, 3455]
    private let batteryPercents = [100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 1]

    init(
        logMessage: @escaping (String) -> Void,
        onMeasurement: @escaping (UUID, OppleMeterReading) -> Void,
        onBatteryLevel: @escaping (UUID, Int) -> Void
    ) {
        self.logMessage = logMessage
        self.onMeasurement = onMeasurement
        self.onBatteryLevel = onBatteryLevel
    }

    func canHandle(peripheral: CBPeripheral, advertisementData: [String: Any]? = nil) -> Bool {
        if managedDeviceIds.contains(peripheral.identifier) {
            return true
        }

        if let advertisementData, isOppleServiceAdvertised(advertisementData) {
            return true
        }

        if let advertisementData,
           let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           isSupportedOppleDevice(advertisedName) {
            return true
        }

        if let name = peripheral.name {
            return isSupportedOppleDevice(name)
        }

        return false
    }

    func modelInfo(from name: String?) -> (code: String, name: String) {
        guard let name else {
            return ("LM4", "Opple Light Master IV")
        }

        let upper = name.uppercased()
        if upper.contains("LM4") || upper.contains("IV") {
            return ("LM4", "Opple Light Master IV")
        }
        if upper.contains("LM3") || upper.contains("III") {
            return ("LM3", "Opple Light Master III")
        }
        // Most unnamed/aliased Opple BLE meters (e.g. "SigMesh") observed in this app are LM4.
        return ("LM4", "Opple Light Master IV")
    }

    func handleConnectedPeripheral(_ peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier
        managedDeviceIds.insert(deviceId)
        peripherals[deviceId] = peripheral
        let model = modelInfo(from: peripheral.name)
        var runtime = runtimes[deviceId] ?? DeviceRuntime()
        let profile = metricsProfile(forModelCode: model.code)
        runtime.metricsProfileId = profile.id
        runtimes[deviceId] = runtime

        if profile.isProvisional {
            logMessage("[\(peripheral.name ?? "?")] Opple \(profile.displayName) uses provisional metric profile (\(profile.id))")
        } else {
            logMessage("[\(peripheral.name ?? "?")] Opple metric profile: \(profile.id)")
        }

        // Discover all services so we can also pick up Battery Service (180F) when available.
        peripheral.discoverServices(nil)
    }

    func handleDisconnectedPeripheral(_ peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier
        managedDeviceIds.remove(deviceId)
        writeCharacteristics.removeValue(forKey: deviceId)
        notifyCharacteristics.removeValue(forKey: deviceId)
        batteryCharacteristics.removeValue(forKey: deviceId)
        peripherals.removeValue(forKey: deviceId)

        if let runtime = runtimes[deviceId] {
            runtime.measureTask?.cancel()
        }
        runtimes.removeValue(forKey: deviceId)
    }

    func handleDidDiscoverServices(peripheral: CBPeripheral, error: Error?) -> Bool {
        guard managedDeviceIds.contains(peripheral.identifier) else { return false }

        if let error {
            logMessage("[\(peripheral.name ?? "?")] Opple service discovery error: \(error.localizedDescription)")
            return true
        }

        guard let services = peripheral.services else {
            logMessage("[\(peripheral.name ?? "?")] Opple: no services found")
            return true
        }

        for service in services {
            if service.uuid == OppleProtocol.serviceUUID {
                logMessage("[\(peripheral.name ?? "?")] Opple service found")
                peripheral.discoverCharacteristics(
                    [OppleProtocol.writeCharacteristicUUID, OppleProtocol.notifyCharacteristicUUID],
                    for: service
                )
            } else if service.uuid == OppleProtocol.batteryServiceUUID {
                logMessage("[\(peripheral.name ?? "?")] Battery service found")
                peripheral.discoverCharacteristics([OppleProtocol.batteryLevelCharacteristicUUID], for: service)
            }
        }

        return true
    }

    func handleDidDiscoverCharacteristics(peripheral: CBPeripheral, service: CBService, error: Error?) -> Bool {
        guard managedDeviceIds.contains(peripheral.identifier) else { return false }

        if let error {
            logMessage("[\(peripheral.name ?? "?")] Opple characteristic discovery error: \(error.localizedDescription)")
            return true
        }

        guard let characteristics = service.characteristics else {
            logMessage("[\(peripheral.name ?? "?")] Opple: no characteristics found")
            return true
        }

        let deviceId = peripheral.identifier

        if service.uuid == OppleProtocol.serviceUUID {
            for characteristic in characteristics {
                // In practice with LM3/LM4, TX(003) is used for notifications and writes.
                if characteristic.uuid == OppleProtocol.notifyCharacteristicUUID,
                   characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                    writeCharacteristics[deviceId] = characteristic
                    logMessage("[\(peripheral.name ?? "?")] Opple TX characteristic supports write, using it for commands")
                }

                if characteristic.uuid == OppleProtocol.writeCharacteristicUUID {
                    // Keep RX(002) as a fallback only if TX(003) write is unavailable.
                    if writeCharacteristics[deviceId] == nil {
                        writeCharacteristics[deviceId] = characteristic
                    }
                    logMessage("[\(peripheral.name ?? "?")] Opple RX characteristic found")
                }

                if characteristic.uuid == OppleProtocol.notifyCharacteristicUUID {
                    notifyCharacteristics[deviceId] = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    logMessage("[\(peripheral.name ?? "?")] Opple notify characteristic found, subscribing...")
                }
            }
        } else if service.uuid == OppleProtocol.batteryServiceUUID {
            for characteristic in characteristics where characteristic.uuid == OppleProtocol.batteryLevelCharacteristicUUID {
                batteryCharacteristics[deviceId] = characteristic
                logMessage("[\(peripheral.name ?? "?")] Battery level characteristic found")

                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
            }
        }

        if writeCharacteristics[deviceId] != nil && notifyCharacteristics[deviceId] != nil {
            startSessionIfReady(for: peripheral)
        }

        return true
    }

    func handleDidUpdateValue(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) -> Bool {
        let deviceId = peripheral.identifier
        guard managedDeviceIds.contains(deviceId) else { return false }

        if let error {
            logMessage("[\(peripheral.name ?? "?")] Opple receive error: \(error.localizedDescription)")
            markInflight(deviceId, inflight: false)
            return true
        }

        guard let data = characteristic.value else {
            return true
        }

        if characteristic.uuid == OppleProtocol.batteryLevelCharacteristicUUID {
            if let value = data.first {
                let batteryPercent = min(100, max(0, Int(value)))
                if var runtime = runtimes[deviceId] {
                    runtime.lastBatteryPercent = batteryPercent
                    runtime.hasBatteryServiceLevel = true
                    runtimes[deviceId] = runtime
                }
                onBatteryLevel(deviceId, batteryPercent)
                logMessage("[\(peripheral.name ?? "?")] Battery service level: \(batteryPercent)%")
            }
            return true
        }

        guard characteristic.uuid == OppleProtocol.notifyCharacteristicUUID else {
            return true
        }

        parseNotification(data: [UInt8](data), from: peripheral)
        markInflight(deviceId, inflight: false)
        return true
    }

    func handleDidWriteValue(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) -> Bool {
        guard managedDeviceIds.contains(peripheral.identifier) else { return false }

        if let error {
            logMessage("[\(peripheral.name ?? "?")] Opple write error: \(error.localizedDescription)")
        }

        return true
    }

    func handleDidUpdateNotificationState(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) -> Bool {
        guard managedDeviceIds.contains(peripheral.identifier) else { return false }

        if let error {
            logMessage("[\(peripheral.name ?? "?")] Opple notification error: \(error.localizedDescription)")
        } else if characteristic.uuid == OppleProtocol.notifyCharacteristicUUID {
            if var runtime = runtimes[peripheral.identifier] {
                runtime.notificationsEnabled = characteristic.isNotifying
                runtimes[peripheral.identifier] = runtime
            }
            logMessage("[\(peripheral.name ?? "?")] Opple notifications \(characteristic.isNotifying ? "enabled" : "disabled")")
            startSessionIfReady(for: peripheral)
        } else if characteristic.uuid == OppleProtocol.batteryLevelCharacteristicUUID {
            logMessage("[\(peripheral.name ?? "?")] Battery notifications \(characteristic.isNotifying ? "enabled" : "disabled")")
            if characteristic.isNotifying || characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }

        return true
    }

    private func startSessionIfReady(for peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier
        guard writeCharacteristics[deviceId] != nil,
              notifyCharacteristics[deviceId] != nil,
              var runtime = runtimes[deviceId],
              runtime.notificationsEnabled,
              !runtime.sessionStarted else {
            return
        }

        runtime.sessionStarted = true
        runtimes[deviceId] = runtime

        logMessage("[\(peripheral.name ?? "?")] Opple meter paired and ready")
        sendCommand(to: peripheral, opCode: protoReqReadM3)
        startMeasuringLoop(for: deviceId)
    }

    private func startMeasuringLoop(for deviceId: UUID) {
        guard var runtime = runtimes[deviceId] else { return }

        runtime.measureTask?.cancel()
        runtime.measureTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: measureIntervalNanoseconds)
                guard !Task.isCancelled else { return }

                guard let peripheral = self.peripherals[deviceId],
                      self.writeCharacteristics[deviceId] != nil else {
                    continue
                }

                if self.runtimes[deviceId]?.inflight == true {
                    continue
                }

                self.sendCommand(to: peripheral, opCode: self.protoReqMeas)
            }
        }

        runtimes[deviceId] = runtime
    }

    private func parseNotification(data: [UInt8], from peripheral: CBPeripheral) {
        guard data.count >= 3 else { return }

        let deviceId = peripheral.identifier
        let msgType = data[0] & 0xE0

        switch msgType {
        case protoMsgSingle:
            parseMessage(Array(data.dropFirst(3)), for: deviceId, deviceName: peripheral.name)

        case protoMsgFFRAG:
            let payload = Array(data.dropFirst(3))
            var runtime = runtimes[deviceId] ?? DeviceRuntime()
            runtime.rxBuffer = payload
            runtimes[deviceId] = runtime

        case protoMsgMFRAG:
            appendFragment(Array(data.dropFirst(1)), for: deviceId)

        case protoMsgLFRAG:
            appendFragment(Array(data.dropFirst(1)), for: deviceId)
            if let payload = runtimes[deviceId]?.rxBuffer {
                parseMessage(payload, for: deviceId, deviceName: peripheral.name)
            }
            runtimes[deviceId]?.rxBuffer = []

        default:
            logMessage("[\(peripheral.name ?? "?")] Opple unknown message type: \(msgType)")
        }
    }

    private func appendFragment(_ fragment: [UInt8], for deviceId: UUID) {
        guard var runtime = runtimes[deviceId] else { return }
        runtime.rxBuffer.append(contentsOf: fragment)
        runtimes[deviceId] = runtime
    }

    private func parseMessage(_ data: [UInt8], for deviceId: UUID, deviceName: String?) {
        guard data.count > 11 else { return }

        let code = (Int(data[9]) << 8) + Int(data[10])

        switch code {
        case protoResReadM3:
            parseCalibrationResponse(data, for: deviceId, deviceName: deviceName)

        case protoResMeas:
            let measureBytes = Array(data.dropFirst(11))
            parseMeasurementResponse(measureBytes, for: deviceId, deviceName: deviceName)

        default:
            if var runtime = runtimes[deviceId], !runtime.loggedUnknownOpcodes.contains(code) {
                runtime.loggedUnknownOpcodes.insert(code)
                runtimes[deviceId] = runtime

                let payloadHex = Data(data).hexString
                logMessage("[\(deviceName ?? "?")] Opple unhandled opcode 0x\(String(format: "%04X", code)) payload: \(payloadHex)")
            }
        }
    }

    private func parseCalibrationResponse(_ data: [UInt8], for deviceId: UUID, deviceName: String?) {
        guard data.count >= 44, var runtime = runtimes[deviceId] else { return }

        var factors: [Double] = []
        for i in 0..<8 {
            let base = 12 + (i * 4)
            guard base + 3 < data.count else { break }
            let bits = UInt32(data[base]) |
                (UInt32(data[base + 1]) << 8) |
                (UInt32(data[base + 2]) << 16) |
                (UInt32(data[base + 3]) << 24)
            let value = Double(Float(bitPattern: bits))
            factors.append(value.isFinite ? value : 1.0)
        }

        if factors.count == 8 {
            runtime.calibrationFactors = factors.map { ($0 >= 0.5 && $0 <= 1.5) ? $0 : 1.0 }
        }

        if let calPower = uint16BE(data, at: 56) {
            runtime.calPower = Double(calPower)
            logMessage("[\(deviceName ?? "?")] Opple calPower: \(calPower)")
        }

        runtimes[deviceId] = runtime

        logMessage("[\(deviceName ?? "?")] Opple calibration loaded")
    }

    private func parseMeasurementResponse(_ data: [UInt8], for deviceId: UUID, deviceName: String?) {
        guard data.count >= 23, var runtime = runtimes[deviceId] else { return }
        let profile = metricsProfile(forId: runtime.metricsProfileId)

        // LM4 response payload stores 11 x UInt16 values at byte offsets 1...22 (big-endian words).
        let rawWords = parseUInt16BEWords(data, start: 1, count: 11)
        guard rawWords.count >= 8 else { return }

        let result = As7341ColorCalculatorV2.computeLuxCctFromRaw(
            rawData: Array(rawWords.prefix(8)),
            calPower: runtime.calPower,
            calibrationFactors: runtime.calibrationFactors,
            cctHistory: &runtime.cctHistory
        )
        let ev100 = calcEV100(lux: result.lux)

        let trailingWords = Array(rawWords.dropFirst(8))
        var batteryPercent = runtime.lastBatteryPercent
        if !runtime.hasBatteryServiceLevel {
            if !runtime.loggedBatteryCandidates, !trailingWords.isEmpty {
                runtime.loggedBatteryCandidates = true
                let wordsText = trailingWords.map { String($0) }.joined(separator: ", ")
                let inferred = inferBatteryPercent(
                    fromTrailingWords: trailingWords,
                    calPower: runtime.calPower
                )
                let inferredText = inferred.map { String($0) } ?? "n/a"
                logMessage("[\(deviceName ?? "?")] Opple trailing words (8...10): [\(wordsText)], inferred battery: \(inferredText)")
            }

            if let inferredBattery = inferBatteryPercent(
                fromTrailingWords: trailingWords,
                calPower: runtime.calPower
            ) {
                let smoothedBattery = smoothBatteryLevel(previous: runtime.lastBatteryPercent, next: inferredBattery)
                runtime.lastBatteryPercent = smoothedBattery
                batteryPercent = smoothedBattery
                onBatteryLevel(deviceId, smoothedBattery)
            }
        }

        let temperature = inferTemperature(fromTrailingWords: trailingWords)
        runtimes[deviceId] = runtime

        let reading = OppleMeterReading(
            cctKelvin: result.cctKelvin,
            lux: result.lux,
            duv: result.duv,
            chromaticityX: result.chromaticityX,
            chromaticityY: result.chromaticityY,
            ev100: ev100,
            batteryPercent: batteryPercent,
            temperature: temperature,
            metricsProfileId: profile.id,
            metricsProfileName: profile.displayName,
            metricsProfileIsProvisional: profile.isProvisional,
            updatedAt: Date()
        )

        onMeasurement(deviceId, reading)

        logMessage(
            "[\(deviceName ?? "?")] Opple measurement (\(profile.id)): " +
            "CCT \(Int(result.cctKelvin.rounded()))K, " +
            "Lux \(Int(result.lux.rounded())), " +
            "Duv \(String(format: "%.4f", result.duv)), " +
            "EV100 \(String(format: "%.2f", ev100))"
        )
    }

    private func calcEV100(lux: Double) -> Double {
        guard lux > 0 else { return 0 }
        return log2((lux * 100.0) / 250.0)
    }

    private func parseUInt16BEWords(_ data: [UInt8], start: Int, count: Int) -> [UInt16] {
        guard start >= 0, count > 0 else { return [] }

        var words: [UInt16] = []
        words.reserveCapacity(count)

        for index in 0..<count {
            let offset = start + (index * 2)
            guard let word = uint16BE(data, at: offset) else { break }
            words.append(word)
        }

        return words
    }

    private func uint16BE(_ data: [UInt8], at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 1 < data.count else { return nil }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private func inferBatteryPercent(fromTrailingWords words: [UInt16], calPower: Double) -> Int? {
        guard !words.isEmpty else { return nil }

        // Only trust realistic Li-ion ranges and ignore values that look like calPower.
        for word in words where word >= 3455 && word <= 4300 {
            if abs(Double(word) - calPower) <= 80.0 {
                continue
            }
            return batteryLevel(voltage: Int(word))
        }

        return nil
    }

    private func smoothBatteryLevel(previous: Int?, next: Int) -> Int {
        guard let previous else { return next }
        let blended = (0.85 * Double(previous)) + (0.15 * Double(next))
        return min(100, max(0, Int(blended.rounded())))
    }

    private func inferTemperature(fromTrailingWords words: [UInt16]) -> Int? {
        guard !words.isEmpty else { return nil }

        for word in words {
            let signed = Int(Int16(bitPattern: word))
            if (-20...120).contains(signed) {
                return signed
            }

            let deci = Double(signed) / 10.0
            if (-20.0...120.0).contains(deci) {
                return Int(deci.rounded())
            }
        }

        return nil
    }

    private func batteryLevel(voltage: Int) -> Int {
        var level = 1.0

        for i in 0..<9 {
            if voltage > batteryVoltages[i + 1] {
                let highV = Double(batteryVoltages[i])
                let lowV = Double(batteryVoltages[i + 1])
                let highP = Double(batteryPercents[i])
                let lowP = Double(batteryPercents[i + 1])
                level = ((Double(voltage) - lowV) / (highV - lowV)) * (highP - lowP) + lowP
                break
            }
        }

        return min(100, max(1, Int(level.rounded())))
    }

    private enum As7341ColorCalculatorV2 {
        static let cctLuxMin = 5.0
        static let cctMin = 0.0
        static let cctMax = 15000.0
        static let fixedCctOffset = -76.0
        static let useCustomCctCorrection = true
        static let useCctBounds = true
        static let useStableCctLimit = false
        static let cctStableMax = 10000.0
        static let useCctSmoothing = true
        static let cctSmoothingCount = 4
        static let cctSmoothingMaxAge: TimeInterval = 10.0
        static let luxGain = 0.094
        static let cctGain = 0.703

        static let regressionMatrix: [[Double]] = [
            [1.0941533, -0.846312, 7.3111637],
            [3.9575146, 0.1573942, 31.208729],
            [1.0834547, 0.7809895, 10.766341],
            [-0.038636, 5.9429088, -1.077367],
            [3.031054, 7.4237086, 0.501092],
            [3.563769, 3.9823614, -1.293768],
            [3.551561, 1.4783982, 0.4297808],
            [-1.045693, -0.883656, -1.763941],
        ]

        struct Result {
            let lux: Double
            let cctKelvin: Double
            let chromaticityX: Double
            let chromaticityY: Double
            let uPrime: Double
            let vPrime: Double
            let duv: Double
        }

        static func computeLuxCctFromRaw(
            rawData: [UInt16],
            calPower: Double,
            calibrationFactors: [Double],
            cctHistory: inout [(time: Date, cct: Double)]
        ) -> Result {
            _ = calPower

            guard rawData.count >= 8 else {
                return Result(lux: 0, cctKelvin: 0, chromaticityX: 0, chromaticityY: 0, uPrime: 0, vPrime: 0, duv: 0)
            }

            let factors = normalizeCalibrationFactors(calibrationFactors)

            var x = 0.0
            var y = 0.0
            var z = 0.0

            for channel in 0..<8 {
                let sample = Double(rawData[channel]) * factors[channel]
                x += sample * regressionMatrix[channel][0]
                y += sample * regressionMatrix[channel][1]
                z += sample * regressionMatrix[channel][2]
            }

            let sumXYZ = x + y + z
            guard sumXYZ > 1e-9 else {
                return Result(lux: 0, cctKelvin: 0, chromaticityX: 0, chromaticityY: 0, uPrime: 0, vPrime: 0, duv: 0)
            }

            let chromaticityX = x / sumXYZ
            let chromaticityY = y / sumXYZ
            var cct = computeCct(x: chromaticityX, y: chromaticityY)
            let lux = y * luxGain

            if useCctBounds {
                if lux <= cctLuxMin {
                    cct = 0
                }
                cct = min(max(cct, cctMin), cctMax)
            }

            if useStableCctLimit, cct > cctStableMax {
                cct = cctStableMax
            }

            if useCctSmoothing {
                cct = smoothCct(cct, history: &cctHistory, now: Date())
            }

            let uvDen = x + (15.0 * y) + (3.0 * z)
            let uPrime = uvDen > 1e-9 ? (4.0 * x / uvDen) : 0
            let vPrime = uvDen > 1e-9 ? (9.0 * y / uvDen) : 0
            let duv = computeDuv(cct: cct, uPrime: uPrime, vPrime: vPrime)

            return Result(
                lux: lux,
                cctKelvin: cct,
                chromaticityX: chromaticityX,
                chromaticityY: chromaticityY,
                uPrime: uPrime,
                vPrime: vPrime,
                duv: duv
            )
        }

        private static func normalizeCalibrationFactors(_ factors: [Double]) -> [Double] {
            guard factors.count >= 8 else {
                return Array(repeating: 1.0, count: 8)
            }

            return Array(factors.prefix(8)).map { value in
                guard value.isFinite else { return 1.0 }
                return (value >= 0.5 && value <= 1.5) ? value : 1.0
            }
        }

        private static func computeCct(x: Double, y: Double) -> Double {
            let denom = 0.1858 - y
            guard abs(denom) > 1e-6 else { return 0 }

            let n = (x - 0.3320) / denom
            var cct = 449.0 * pow(n, 3) +
                3525.0 * pow(n, 2) +
                6823.3 * n +
                5520.33

            cct = cct * cctGain - fixedCctOffset

            if useCustomCctCorrection {
                cct = correctCct(cct)
            }

            return cct
        }

        private static func correctCct(_ shownCct: Double) -> Double {
            let a = 4.52e-5
            let b = 0.6910
            let c = 171.3
            return (a * shownCct * shownCct) + (b * shownCct) + c
        }

        private static func smoothCct(
            _ cct: Double,
            history: inout [(time: Date, cct: Double)],
            now: Date
        ) -> Double {
            history.append((time: now, cct: cct))
            history.removeAll { now.timeIntervalSince($0.time) > cctSmoothingMaxAge }

            if history.count > cctSmoothingCount {
                history = Array(history.suffix(cctSmoothingCount))
            }

            guard !history.isEmpty else { return cct }
            let sum = history.reduce(0.0) { $0 + $1.cct }
            return sum / Double(history.count)
        }

        private static func computeDuv(cct: Double, uPrime: Double, vPrime: Double) -> Double {
            guard cct > 0 else { return 0 }

            let temperature = max(cct, 1667.0)
            let xBlackbody: Double
            if temperature <= 4000.0 {
                xBlackbody = -0.2661239e9 / pow(temperature, 3) -
                    0.2343580e6 / pow(temperature, 2) +
                    0.8776956e3 / temperature +
                    0.179910
            } else {
                xBlackbody = -3.0258469e9 / pow(temperature, 3) +
                    2.1070379e6 / pow(temperature, 2) +
                    0.2226347e3 / temperature +
                    0.240390
            }

            let yBlackbody: Double
            if temperature <= 2222.0 {
                yBlackbody = -1.1063814 * pow(xBlackbody, 3) -
                    1.34811020 * pow(xBlackbody, 2) +
                    2.18555832 * xBlackbody -
                    0.20219683
            } else if temperature <= 4000.0 {
                yBlackbody = -0.9549476 * pow(xBlackbody, 3) -
                    1.37418593 * pow(xBlackbody, 2) +
                    2.09137015 * xBlackbody -
                    0.16748867
            } else {
                yBlackbody = 3.0817580 * pow(xBlackbody, 3) -
                    5.87338670 * pow(xBlackbody, 2) +
                    3.75112997 * xBlackbody -
                    0.37001483
            }

            let denominator = (-2.0 * xBlackbody) + (12.0 * yBlackbody) + 3.0
            guard abs(denominator) > 1e-9 else { return 0 }

            let uBlackbody = 4.0 * xBlackbody / denominator
            let vBlackbody = 9.0 * yBlackbody / denominator

            let du = uPrime - uBlackbody
            let dv = vPrime - vBlackbody
            let magnitude = sqrt((du * du) + (dv * dv))

            return vPrime < vBlackbody ? -magnitude : magnitude
        }
    }

    private func sendCommand(to peripheral: CBPeripheral, opCode: Int, payload: [UInt8] = []) {
        let deviceId = peripheral.identifier
        guard let characteristic = writeCharacteristics[deviceId],
              var runtime = runtimes[deviceId] else {
            return
        }

        runtime.seqNo = runtime.seqNo &+ 1
        runtime.inflight = true
        runtimes[deviceId] = runtime

        let header: [UInt8] = [
            0x00,
            0x13,
            0x00,
            0x00,
            runtime.seqNo,
            0x00,
            UInt8(payload.count & 0xFF),
            0x00,
            0x00,
            UInt8((opCode >> 8) & 0xFF),
            UInt8(opCode & 0xFF),
        ]

        let body = header + payload
        let frames = encapsulateData(body)

        for frame in frames {
            let data = Data(frame)
            let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(data, for: characteristic, type: writeType)
        }
    }

    private func encapsulateData(_ data: [UInt8]) -> [[UInt8]] {
        let nFragments: Int
        if data.count < 17 {
            nFragments = 1
        } else {
            nFragments = Int(ceil((Double(data.count - 17) / 19.0) + 1.0))
        }

        var fragments: [[UInt8]] = []

        for index in 0..<nFragments {
            var head: [UInt8] = []
            var chunk: [UInt8] = []

            if index == 0 {
                let totalLen = data.count + nFragments + 2
                head = [nFragments > 1 ? protoMsgFFRAG : protoMsgSingle, UInt8((totalLen >> 8) & 0xFF), UInt8(totalLen & 0xFF)]
                chunk = nFragments > 1 ? Array(data.prefix(17)) : data
            } else if index != (nFragments - 1) {
                head = [protoMsgMFRAG | UInt8(index & 0x1F)]
                let start = 17 + (19 * (index - 1))
                let end = min(start + 19, data.count)
                chunk = Array(data[start..<end])
            } else {
                head = [protoMsgLFRAG | UInt8(index & 0x1F)]
                let start = 17 + (19 * (index - 1))
                if start < data.count {
                    chunk = Array(data[start...])
                }
            }

            fragments.append(head + chunk)
        }

        return fragments
    }

    private func markInflight(_ deviceId: UUID, inflight: Bool) {
        guard var runtime = runtimes[deviceId] else { return }
        runtime.inflight = inflight
        runtimes[deviceId] = runtime
    }

    private func metricsProfile(forModelCode code: String) -> MetricsProfile {
        switch code.uppercased() {
        case "LM3":
            return metricsProfile(forId: "lm3")
        case "LM4":
            return metricsProfile(forId: "lm4_as7341_v2")
        default:
            return metricsProfile(forId: "lm4_as7341_v2")
        }
    }

    private func metricsProfile(forId id: String) -> MetricsProfile {
        if let profile = metricsProfiles[id] {
            return profile
        }
        if let fallback = metricsProfiles["generic_provisional"] {
            return fallback
        }
        return MetricsProfile(
            id: "generic_provisional",
            displayName: "LM",
            isProvisional: true
        )
    }

    private func isSupportedOppleDevice(_ name: String) -> Bool {
        let upper = name.uppercased()
        return oppleNameHints.contains { upper.contains($0) }
    }

    private func advertisedServiceUUIDs(from advertisementData: [String: Any]) -> [CBUUID] {
        var uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        if let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            uuids.append(contentsOf: overflow)
        }
        return uuids
    }

    private func isOppleServiceAdvertised(_ advertisementData: [String: Any]) -> Bool {
        advertisedServiceUUIDs(from: advertisementData).contains(OppleProtocol.serviceUUID)
    }
}
