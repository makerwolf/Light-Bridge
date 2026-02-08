import Foundation
@preconcurrency import CoreBluetooth
import Combine

// MARK: - Zhiyun GATT Protocol Constants
/// Proprietary GATT protocol for Zhiyun PL105 mesh lights
/// Decoded from Bluetooth sniff of official Zyvega iOS app
struct ZhiyunProtocol {
    // MARK: - Service & Characteristic UUIDs
    /// Custom Zhiyun service UUID (0xFEE9 - registered BLE service)
    static let serviceUUID = CBUUID(string: "FEE9")
    /// Write characteristic for sending commands
    static let writeCharacteristicUUID = CBUUID(string: "D44BC439-ABFD-45A2-B575-925416129600")
    /// Notify characteristic for receiving responses
    static let notifyCharacteristicUUID = CBUUID(string: "D44BC439-ABFD-45A2-B575-925416129601")
    
    // MARK: - Packet Structure Constants
    /// Magic header bytes for all packets
    static let magicHeader: [UInt8] = [0x24, 0x3C]
    /// Direction byte for requests (app → device)
    static let directionRequest: [UInt8] = [0x00, 0x01]
    /// Direction byte for responses (device → app)
    static let directionResponse: [UInt8] = [0x01, 0x00]
    
    // MARK: - Command IDs (little-endian)
    enum Command: UInt16 {
        case setBrightness = 0x1001      // 01 10
        case setColorTemperature = 0x1002 // 02 10
        case getPowerState = 0x1008       // 08 10
        case queryBrightness = 0x1009     // 09 10 - REQUIRED before setting brightness
        case queryDevice = 0x1201         // 01 12
        case getDeviceInfo = 0x2005       // 05 20
        case getDeviceName = 0x2003       // 03 20
        case getDeviceStatus = 0x2001     // 01 20
        case readDeviceState = 0x0006     // 06 00 - REQUIRED initialization
        case getFirmwareVersion = 0x8001  // 01 80
        
        var bytes: [UInt8] {
            [UInt8(self.rawValue & 0xFF), UInt8((self.rawValue >> 8) & 0xFF)]
        }
    }
    
    // MARK: - Sub-commands
    static let subCommandControl: [UInt8] = [0x03, 0x80]
    
    // MARK: - Color Temperature Limits (Kelvin)
    static let colorTempMin: UInt16 = 2700
    static let colorTempMax: UInt16 = 6500
    
    // MARK: - Brightness Limits
    static let brightnessMin: Float = 0.0
    static let brightnessMax: Float = 100.0
}

// MARK: - Device State
struct ZhiyunDeviceState {
    var isOn: Bool = false
    var brightness: Float = 0.0  // 0-100
    var colorTemperature: UInt16 = 5600  // Kelvin
    var firmwareVersion: String = ""
    var deviceName: String = ""
    var modelCode: String = ""  // e.g., "PL105"
    var modelName: String = ""  // e.g., "MOLUS X100"
}

// MARK: - ZhiyunGATTController
@MainActor
class ZhiyunGATTController: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isScanning = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDevices: [CBPeripheral] = []  // Multiple connected devices
    @Published var deviceStates: [UUID: ZhiyunDeviceState] = [:]  // State per device
    @Published var selectedDeviceId: UUID?  // Currently selected device for control
    @Published var lastError: String?
    @Published var logMessages: [String] = []
    
    // Computed property for backwards compatibility
    var isConnected: Bool { !connectedDevices.isEmpty }
    var connectedDevice: CBPeripheral? { connectedDevices.first }
    var deviceState: ZhiyunDeviceState {
        get { selectedDeviceId.flatMap { deviceStates[$0] } ?? ZhiyunDeviceState() }
    }
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var writeCharacteristics: [UUID: CBCharacteristic] = [:]  // Per device
    private var notifyCharacteristics: [UUID: CBCharacteristic] = [:]  // Per device
    private var sequenceNumbers: [UUID: UInt16] = [:]  // Per device
    private var pendingCommands: [UInt16: (Data) -> Void] = [:]
    
    // Debounce timers per device
    private var brightnessDebounceTask: [UUID: Task<Void, Never>] = [:]
    private var colorTempDebounceTask: [UUID: Task<Void, Never>] = [:]
    private var pendingBrightness: [UUID: Float] = [:]
    private var pendingColorTemp: [UUID: UInt16] = [:]
    private var needsWakeUp: [UUID: Bool] = [:]  // Track if device needs to be woken up
    
    // Remember last brightness per device
    private var lastBrightness: [UUID: Float] = [:]
    
    // Supported device name prefixes (from Zhiyun device models)
    // Molus Series: PL103, PL105, PL107, PL109, PLG105, PLG106, PLB101-108, PL0102-0108, PLX104-114
    // FIVERAY Series: PLM103, PLM110
    // CINEPEER Series: PL113, PLX108, PLX109
    private let supportedPrefixes = [
        // Molus COB Series
        "PL103",   // MOLUS G60
        "PL105",   // MOLUS X100
        "PL107",   // MOLUS G100
        "PL109",   // MOLUS G200
        "PLG105",  // MOLUS G300
        "PLG106",  // MOLUS G200D
        // Molus B Series (Daylight)
        "PLB101",  // MOLUS B100D
        "PLB102",  // MOLUS Z1
        "PLB103",  // MOLUS B200D
        "PLB104",  // MOLUS Z2
        "PLB105",  // MOLUS B300D
        "PLB106",  // MOLUS Z3
        "PLB107",  // MOLUS B500D
        "PLB108",  // MOLUS Z5
        // Molus B Series (Bi-color)
        "PL0102",  // MOLUS B100
        "PL0104",  // MOLUS B200
        "PL0106",  // MOLUS B300
        "PL0108",  // MOLUS B500
        // Molus X/RGB Series
        "PLX104",  // MOLUS X60RGB
        "PLX105",  // MOLUS X60
        "PLX110",  // MOLUS X100RGB
        "PLX113",  // MOLUS X200RGB
        "PLX114",  // MOLUS X200
        // FIVERAY Series
        "PLM103",  // FIVERAY M20C
        "PLM110",  // FIVERAY M60 Ultra
        // CINEPEER Series
        "PL113",   // CINEPEER C100
        "PLX108",  // CINEPEER CX50
        "PLX109",  // CINEPEER CX50RGB
    ]
    
    // Model code to friendly name mapping
    private let modelNames: [String: String] = [
        "PL103": "MOLUS G60",
        "PL105": "MOLUS X100",
        "PL107": "MOLUS G100",
        "PL109": "MOLUS G200",
        "PLG105": "MOLUS G300",
        "PLG106": "MOLUS G200D",
        "PLB101": "MOLUS B100D",
        "PLB102": "MOLUS Z1",
        "PLB103": "MOLUS B200D",
        "PLB104": "MOLUS Z2",
        "PLB105": "MOLUS B300D",
        "PLB106": "MOLUS Z3",
        "PLB107": "MOLUS B500D",
        "PLB108": "MOLUS Z5",
        "PL0102": "MOLUS B100",
        "PL0104": "MOLUS B200",
        "PL0106": "MOLUS B300",
        "PL0108": "MOLUS B500",
        "PLX104": "MOLUS X60RGB",
        "PLX105": "MOLUS X60",
        "PLX110": "MOLUS X100RGB",
        "PLX113": "MOLUS X200RGB",
        "PLX114": "MOLUS X200",
        "PLM103": "FIVERAY M20C",
        "PLM110": "FIVERAY M60 Ultra",
        "PL113": "CINEPEER C100",
        "PLX108": "CINEPEER CX50",
        "PLX109": "CINEPEER CX50RGB",
    ]
    
    // Auto-connect to known devices
    private let knownDevicesKey = "knownZhiyunDevices"
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        log("ZhiyunGATTController initialized")
    }
    
    // MARK: - Known Devices Storage
    private var knownDeviceUUIDs: [UUID] {
        get {
            let strings = UserDefaults.standard.stringArray(forKey: knownDevicesKey) ?? []
            return strings.compactMap { UUID(uuidString: $0) }
        }
        set {
            let strings = newValue.map { $0.uuidString }
            UserDefaults.standard.set(strings, forKey: knownDevicesKey)
        }
    }
    
    private func saveKnownDevice(_ peripheral: CBPeripheral) {
        var uuids = knownDeviceUUIDs
        if !uuids.contains(peripheral.identifier) {
            uuids.append(peripheral.identifier)
            knownDeviceUUIDs = uuids
            log("Saved device to known devices: \(peripheral.name ?? peripheral.identifier.uuidString)")
        }
    }
    
    private func isKnownDevice(_ peripheral: CBPeripheral) -> Bool {
        return knownDeviceUUIDs.contains(peripheral.identifier)
    }
    
    /// Forget all known devices
    func forgetAllDevices() {
        knownDeviceUUIDs = []
        log("Cleared all known devices")
    }
    
    // MARK: - Logging
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)"
        print(logMessage)
        Task { @MainActor in
            self.logMessages.append(logMessage)
            if self.logMessages.count > 100 {
                self.logMessages.removeFirst()
            }
        }
    }
    
    // MARK: - Scanning
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            lastError = "Bluetooth is not powered on"
            return
        }
        
        log("Starting scan for Zhiyun devices...")
        isScanning = true
        discoveredDevices.removeAll()
        
        // Scan for devices with the Zhiyun service UUID or by name
        centralManager.scanForPeripherals(
            withServices: nil,  // Scan all devices to find by name
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    func stopScanning() {
        log("Stopping scan")
        centralManager.stopScan()
        isScanning = false
    }
    
    // MARK: - Connection
    func connect(to peripheral: CBPeripheral) {
        // Don't stop scanning - allow multiple connections
        if connectedDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            log("Already connected to \(peripheral.name ?? "Unknown")")
            return
        }
        log("Connecting to \(peripheral.name ?? "Unknown")...")
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect(from peripheral: CBPeripheral) {
        log("Disconnecting from \(peripheral.name ?? "Unknown")...")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func disconnectAll() {
        for peripheral in connectedDevices {
            log("Disconnecting from \(peripheral.name ?? "Unknown")...")
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    /// Select a device for control
    func selectDevice(_ peripheral: CBPeripheral) {
        selectedDeviceId = peripheral.identifier
        log("Selected device: \(peripheral.name ?? "Unknown")")
    }
    
    /// Get state for a specific device
    func state(for peripheral: CBPeripheral) -> ZhiyunDeviceState {
        return deviceStates[peripheral.identifier] ?? ZhiyunDeviceState()
    }
    
    // MARK: - Command Building
    private func buildPacket(command: ZhiyunProtocol.Command, payload: [UInt8], for deviceId: UUID) -> Data {
        var packet: [UInt8] = []
        
        // Magic header
        packet.append(contentsOf: ZhiyunProtocol.magicHeader)
        
        // Calculate length (everything after length field, EXCLUDING CRC: direction + seq + command + payload)
        let contentLength = 2 + 2 + 2 + payload.count
        packet.append(UInt8(contentLength & 0xFF))
        packet.append(UInt8((contentLength >> 8) & 0xFF))
        
        // Direction (request)
        packet.append(contentsOf: ZhiyunProtocol.directionRequest)
        
        // Sequence number per device
        let seq = sequenceNumbers[deviceId] ?? 0
        sequenceNumbers[deviceId] = (seq + 1) & 0xFFFF
        packet.append(UInt8(seq & 0xFF))
        packet.append(UInt8((seq >> 8) & 0xFF))
        
        // Command ID
        packet.append(contentsOf: command.bytes)
        
        // Payload
        packet.append(contentsOf: payload)
        
        // CRC-16-XMODEM calculated on data AFTER header+length (starting from byte 4)
        // CRC is stored little-endian (low byte first)
        let crcData = Array(packet[4...])  // Skip header (2) + length (2)
        let crc = calculateCRC16(crcData)
        packet.append(UInt8(crc & 0xFF))          // Low byte first (little-endian)
        packet.append(UInt8((crc >> 8) & 0xFF))  // High byte second
        
        return Data(packet)
    }
    
    // MARK: - CRC Calculation
    /// CRC-16-XMODEM: poly=0x1021, init=0x0000
    private func calculateCRC16(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0x0000
        
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        
        return crc
    }
    
    // MARK: - Light Control Commands
    
    /// Set brightness (0-100) with debouncing - applies to all connected devices or selected device
    /// - Parameters:
    ///   - value: Brightness value 0-100
    ///   - deviceId: Specific device, or nil for selected/all
    ///   - allDevices: If true and deviceId is nil, controls ALL devices (not just selected)
    func setBrightness(_ value: Float, for deviceId: UUID? = nil, allDevices: Bool = false) {
        let clampedValue = max(ZhiyunProtocol.brightnessMin, min(ZhiyunProtocol.brightnessMax, value))
        let targetDevices = getTargetDevices(for: deviceId, allDevices: allDevices)
        
        for peripheral in targetDevices {
            let id = peripheral.identifier
            
            // Remember last non-zero brightness for turn on
            if clampedValue > 0 {
                lastBrightness[id] = clampedValue
            }
            
            // Capture if device is currently off BEFORE updating UI
            // Only set needsWakeUp if going from off to non-zero brightness
            let currentlyOff = deviceStates[id]?.isOn == false
            if clampedValue > 0 && currentlyOff {
                needsWakeUp[id] = true
            } else if clampedValue == 0 {
                needsWakeUp[id] = false
            }
            
            // Update UI immediately
            deviceStates[id]?.brightness = clampedValue
            deviceStates[id]?.isOn = clampedValue > 0
            
            // Store pending value and debounce
            pendingBrightness[id] = clampedValue
            brightnessDebounceTask[id]?.cancel()
            brightnessDebounceTask[id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms debounce
                guard !Task.isCancelled else { return }
                self.sendBrightnessCommand(for: id)
            }
        }
    }
    
    /// Actually send the brightness command to a specific device
    private func sendBrightnessCommand(for deviceId: UUID) {
        guard let characteristic = writeCharacteristics[deviceId],
              let peripheral = connectedDevices.first(where: { $0.identifier == deviceId }) else {
            return
        }
        
        guard let value = pendingBrightness[deviceId] else { return }
        pendingBrightness[deviceId] = nil
        
        // If brightness is 0, send power off command instead
        if value == 0.0 {
            var payload: [UInt8] = []
            payload.append(contentsOf: ZhiyunProtocol.subCommandControl)
            payload.append(0x01)  // sub-sub command
            payload.append(0x00)  // power OFF
            
            let packet = buildPacket(command: .getPowerState, payload: payload, for: deviceId)
            log("[\(peripheral.name ?? "?")] Brightness 0% - turning OFF")
            sendCommand(packet, to: characteristic, from: peripheral)
            needsWakeUp[deviceId] = false
            return
        }
        
        // Check if device needs to be woken up (was off when slider started moving)
        let shouldWakeUp = needsWakeUp[deviceId] == true
        needsWakeUp[deviceId] = false
        
        if shouldWakeUp {
            // Send power ON command first
            var powerPayload: [UInt8] = []
            powerPayload.append(contentsOf: ZhiyunProtocol.subCommandControl)
            powerPayload.append(0x01)  // sub-sub command
            powerPayload.append(0x01)  // power ON
            
            let powerPacket = buildPacket(command: .getPowerState, payload: powerPayload, for: deviceId)
            log("[\(peripheral.name ?? "?")] Waking device from sleep...")
            sendCommand(powerPacket, to: characteristic, from: peripheral)
            
            // Then set brightness after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.sendActualBrightnessCommand(value: value, deviceId: deviceId, characteristic: characteristic, peripheral: peripheral)
            }
        } else {
            // Device is already on, just set brightness
            sendActualBrightnessCommand(value: value, deviceId: deviceId, characteristic: characteristic, peripheral: peripheral)
        }
    }
    
    /// Helper to send the actual brightness command
    private func sendActualBrightnessCommand(value: Float, deviceId: UUID, characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        // Build payload: sub-command (2) + flag (1) + float32 LE (4) = 7 bytes
        var payload: [UInt8] = []
        payload.append(contentsOf: ZhiyunProtocol.subCommandControl)
        payload.append(0x01)  // flag indicating brightness is set
        let floatBytes = withUnsafeBytes(of: value) { Array($0) }
        payload.append(contentsOf: floatBytes)
        
        let packet = buildPacket(command: .setBrightness, payload: payload, for: deviceId)
        log("[\(peripheral.name ?? "?")] Setting brightness to \(value)%")
        sendCommand(packet, to: characteristic, from: peripheral)
        
        // Mark device as on
        deviceStates[deviceId]?.isOn = true
    }
    
    /// Set color temperature (2700K - 6500K) with debouncing
    /// - Parameters:
    ///   - kelvin: Color temperature in Kelvin
    ///   - deviceId: Specific device, or nil for selected/all
    ///   - allDevices: If true and deviceId is nil, controls ALL devices (not just selected)
    func setColorTemperature(_ kelvin: UInt16, for deviceId: UUID? = nil, allDevices: Bool = false) {
        let clampedValue = max(ZhiyunProtocol.colorTempMin, min(ZhiyunProtocol.colorTempMax, kelvin))
        let targetDevices = getTargetDevices(for: deviceId, allDevices: allDevices)
        
        for peripheral in targetDevices {
            let id = peripheral.identifier
            
            // Update UI immediately
            deviceStates[id]?.colorTemperature = clampedValue
            
            // Store pending value and debounce
            pendingColorTemp[id] = clampedValue
            colorTempDebounceTask[id]?.cancel()
            colorTempDebounceTask[id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms debounce
                guard !Task.isCancelled else { return }
                self.sendColorTempCommand(for: id)
            }
        }
    }
    
    /// Actually send the color temperature command
    private func sendColorTempCommand(for deviceId: UUID) {
        guard let characteristic = writeCharacteristics[deviceId],
              let peripheral = connectedDevices.first(where: { $0.identifier == deviceId }) else {
            return
        }
        
        guard let value = pendingColorTemp[deviceId] else { return }
        pendingColorTemp[deviceId] = nil
        
        var payload: [UInt8] = []
        payload.append(contentsOf: ZhiyunProtocol.subCommandControl)
        payload.append(0x01)
        payload.append(UInt8(value & 0xFF))
        payload.append(UInt8((value >> 8) & 0xFF))
        
        let packet = buildPacket(command: .setColorTemperature, payload: payload, for: deviceId)
        log("[\(peripheral.name ?? "?")] Setting color temperature to \(value)K")
        sendCommand(packet, to: characteristic, from: peripheral)
    }
    
    /// Turn light(s) on
    /// - Parameters:
    ///   - brightness: Optional brightness to set after turning on
    ///   - deviceId: Specific device, or nil for selected/all
    ///   - allDevices: If true and deviceId is nil, controls ALL devices (not just selected)
    func turnOn(brightness: Float? = nil, for deviceId: UUID? = nil, allDevices: Bool = false) {
        let targetDevices = getTargetDevices(for: deviceId, allDevices: allDevices)
        
        for peripheral in targetDevices {
            let id = peripheral.identifier
            guard let characteristic = writeCharacteristics[id] else { continue }
            
            let targetBrightness = brightness ?? lastBrightness[id] ?? 50.0
            
            var payload: [UInt8] = []
            payload.append(contentsOf: ZhiyunProtocol.subCommandControl)
            payload.append(0x01)
            payload.append(0x01)
            
            let packet = buildPacket(command: .getPowerState, payload: payload, for: id)
            log("[\(peripheral.name ?? "?")] Turning light ON")
            sendCommand(packet, to: characteristic, from: peripheral)
            
            // Set brightness after delay
            let capturedId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setBrightness(targetBrightness, for: capturedId)
            }
        }
    }
    
    /// Turn light(s) off
    /// - Parameters:
    ///   - deviceId: Specific device, or nil for selected/all
    ///   - allDevices: If true and deviceId is nil, controls ALL devices (not just selected)
    func turnOff(for deviceId: UUID? = nil, allDevices: Bool = false) {
        let targetDevices = getTargetDevices(for: deviceId, allDevices: allDevices)
        
        for peripheral in targetDevices {
            let id = peripheral.identifier
            guard let characteristic = writeCharacteristics[id] else { continue }
            
            var payload: [UInt8] = []
            payload.append(contentsOf: ZhiyunProtocol.subCommandControl)
            payload.append(0x01)
            payload.append(0x00)
            
            let packet = buildPacket(command: .getPowerState, payload: payload, for: id)
            log("[\(peripheral.name ?? "?")] Turning light OFF")
            sendCommand(packet, to: characteristic, from: peripheral)
            
            deviceStates[id]?.isOn = false
        }
    }
    
    /// Get target devices based on deviceId
    /// - Parameters:
    ///   - deviceId: Specific device UUID, or nil
    ///   - allDevices: If true and deviceId is nil, returns ALL connected devices (ignores selectedDeviceId)
    private func getTargetDevices(for deviceId: UUID?, allDevices: Bool = false) -> [CBPeripheral] {
        if let specificId = deviceId {
            return connectedDevices.filter { $0.identifier == specificId }
        } else if allDevices {
            return connectedDevices  // All connected devices explicitly requested
        } else if let selectedId = selectedDeviceId {
            return connectedDevices.filter { $0.identifier == selectedId }
        } else {
            return connectedDevices  // No selection, default to all
        }
    }
    
    /// Get firmware version for a device
    func getFirmwareVersion(for deviceId: UUID? = nil, allDevices: Bool = false) {
        let targetDevices = getTargetDevices(for: deviceId, allDevices: allDevices)
        
        for peripheral in targetDevices {
            let id = peripheral.identifier
            guard let characteristic = writeCharacteristics[id] else { continue }
            
            let packet = buildPacket(command: .getFirmwareVersion, payload: [], for: id)
            log("[\(peripheral.name ?? "?")] Querying firmware version")
            sendCommand(packet, to: characteristic, from: peripheral)
        }
    }
    
    // MARK: - Command Sending
    private func sendCommand(_ data: Data, to characteristic: CBCharacteristic, from peripheral: CBPeripheral) {
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }
    
    // MARK: - Response Parsing
    private func parseResponse(_ data: Data, from deviceId: UUID) {
        guard data.count >= 10 else {
            log("Response too short: \(data.count) bytes")
            return
        }
        
        let bytes = [UInt8](data)
        
        // Verify magic header
        guard bytes[0] == 0x24 && bytes[1] == 0x3C else {
            log("Invalid magic header")
            return
        }
        
        // Parse command ID (bytes 8-9, little-endian)
        let commandId = UInt16(bytes[8]) | (UInt16(bytes[9]) << 8)
        
        let deviceName = connectedDevices.first(where: { $0.identifier == deviceId })?.name ?? "?"
        log("[\(deviceName)] Response: cmd=0x\(String(format: "%04X", commandId))")
        
        // Parse payload based on command
        if data.count > 10 {
            let payload = Array(bytes[10..<bytes.count-2])
            parsePayload(commandId: commandId, payload: payload, for: deviceId)
        }
    }
    
    private func parsePayload(commandId: UInt16, payload: [UInt8], for deviceId: UUID) {
        switch commandId {
        case ZhiyunProtocol.Command.setBrightness.rawValue:
            if payload.count >= 7 {
                let floatBytes = Array(payload[3..<7])
                let brightness = floatBytes.withUnsafeBufferPointer {
                    $0.baseAddress!.withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee }
                }
                log("Brightness response: \(brightness)%")
                deviceStates[deviceId]?.brightness = brightness
                deviceStates[deviceId]?.isOn = brightness > 0
            }
            
        case ZhiyunProtocol.Command.setColorTemperature.rawValue:
            if payload.count >= 5 {
                let colorTemp = UInt16(payload[3]) | (UInt16(payload[4]) << 8)
                log("Color temperature response: \(colorTemp)K")
                deviceStates[deviceId]?.colorTemperature = colorTemp
            }
            
        case ZhiyunProtocol.Command.getPowerState.rawValue:
            if payload.count >= 3 {
                let isOn = payload[2] == 0x01
                log("Power state response: \(isOn ? "ON" : "OFF")")
                deviceStates[deviceId]?.isOn = isOn
            }
            
        case ZhiyunProtocol.Command.getFirmwareVersion.rawValue:
            if let versionStr = String(bytes: payload, encoding: .utf8) {
                log("Firmware version: \(versionStr)")
                deviceStates[deviceId]?.firmwareVersion = versionStr
            }
            
        case ZhiyunProtocol.Command.queryDevice.rawValue:
            if payload.count >= 4 {
                let subCmd = payload[0...1]
                log("Query device response: subcmd=\(subCmd.map { String(format: "%02X", $0) }.joined())")
            }
            
        case ZhiyunProtocol.Command.getDeviceStatus.rawValue:
            log("Device status (0x2001) payload: \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
            
        default:
            log("Unknown command response: 0x\(String(format: "%04X", commandId))")
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension ZhiyunGATTController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.log("Bluetooth is powered on")
                // Auto-start scanning when Bluetooth is ready
                self.startScanning()
            case .poweredOff:
                self.log("Bluetooth is powered off")
                self.lastError = "Bluetooth is powered off"
            case .unauthorized:
                self.log("Bluetooth is unauthorized")
                self.lastError = "Bluetooth access not authorized"
            case .unsupported:
                self.log("Bluetooth is not supported")
                self.lastError = "Bluetooth not supported on this device"
            case .resetting:
                self.log("Bluetooth is resetting")
            case .unknown:
                self.log("Bluetooth state is unknown")
            @unknown default:
                self.log("Unknown Bluetooth state")
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            // Filter by supported device name prefixes
            if let name = peripheral.name, self.isSupportedDevice(name) {
                if !self.discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                    self.log("Discovered: \(name)")
                    self.discoveredDevices.append(peripheral)
                    
                    // Auto-connect to all known devices (not just one)
                    if self.isKnownDevice(peripheral) && !self.connectedDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                        self.log("Auto-connecting to known device: \(name)")
                        self.connect(to: peripheral)
                    }
                }
            }
        }
    }
    
    /// Check if device name matches any supported Zhiyun device prefix
    private func isSupportedDevice(_ name: String) -> Bool {
        for prefix in supportedPrefixes {
            if name.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }
    
    /// Extract model code from device name (e.g., "PL105_XXXX" -> "PL105")
    private func extractModelCode(from name: String) -> String? {
        for prefix in supportedPrefixes {
            if name.hasPrefix(prefix) {
                return prefix
            }
        }
        return nil
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.log("Connected to \(peripheral.name ?? "Unknown")")
            
            // Add to connected devices list
            if !self.connectedDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                self.connectedDevices.append(peripheral)
            }
            
            // Initialize state for this device
            var state = ZhiyunDeviceState()
            if let name = peripheral.name {
                state.deviceName = name
                if let modelCode = self.extractModelCode(from: name) {
                    state.modelCode = modelCode
                    state.modelName = self.modelNames[modelCode] ?? "Unknown Model"
                    self.log("Device model: \(modelCode) (\(state.modelName))")
                }
            }
            self.deviceStates[peripheral.identifier] = state
            
            // Select this device if none selected
            if self.selectedDeviceId == nil {
                self.selectedDeviceId = peripheral.identifier
            }
            
            peripheral.delegate = self
            
            // Save as known device for auto-reconnect
            self.saveKnownDevice(peripheral)
            
            // Discover services
            peripheral.discoverServices([ZhiyunProtocol.serviceUUID])
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.log("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "Unknown error")")
            self.lastError = error?.localizedDescription
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.log("Disconnected from \(peripheral.name ?? "Unknown")")
            
            let deviceId = peripheral.identifier
            
            // Remove from connected devices
            self.connectedDevices.removeAll { $0.identifier == deviceId }
            
            // Clean up device-specific data
            self.deviceStates.removeValue(forKey: deviceId)
            self.writeCharacteristics.removeValue(forKey: deviceId)
            self.notifyCharacteristics.removeValue(forKey: deviceId)
            self.sequenceNumbers.removeValue(forKey: deviceId)
            self.pendingBrightness.removeValue(forKey: deviceId)
            self.pendingColorTemp.removeValue(forKey: deviceId)
            self.brightnessDebounceTask[deviceId]?.cancel()
            self.brightnessDebounceTask.removeValue(forKey: deviceId)
            self.colorTempDebounceTask[deviceId]?.cancel()
            self.colorTempDebounceTask.removeValue(forKey: deviceId)
            
            // Update selected device if this was selected
            if self.selectedDeviceId == deviceId {
                self.selectedDeviceId = self.connectedDevices.first?.identifier
            }
            
            if let error = error {
                self.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension ZhiyunGATTController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.log("[\(peripheral.name ?? "?")] Error discovering services: \(error.localizedDescription)")
                return
            }
            
            guard let services = peripheral.services else {
                self.log("[\(peripheral.name ?? "?")] No services found")
                return
            }
            
            for service in services {
                self.log("[\(peripheral.name ?? "?")] Found service: \(service.uuid)")
                if service.uuid == ZhiyunProtocol.serviceUUID {
                    peripheral.discoverCharacteristics(
                        [ZhiyunProtocol.writeCharacteristicUUID, ZhiyunProtocol.notifyCharacteristicUUID],
                        for: service
                    )
                }
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            let deviceId = peripheral.identifier
            
            if let error = error {
                self.log("[\(peripheral.name ?? "?")] Error discovering characteristics: \(error.localizedDescription)")
                return
            }
            
            guard let characteristics = service.characteristics else {
                self.log("[\(peripheral.name ?? "?")] No characteristics found")
                return
            }
            
            for characteristic in characteristics {
                if characteristic.uuid == ZhiyunProtocol.writeCharacteristicUUID {
                    self.writeCharacteristics[deviceId] = characteristic
                    self.log("[\(peripheral.name ?? "?")] Write characteristic found")
                }
                
                if characteristic.uuid == ZhiyunProtocol.notifyCharacteristicUUID {
                    self.notifyCharacteristics[deviceId] = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    self.log("[\(peripheral.name ?? "?")] Notify characteristic found, subscribing...")
                }
            }
            
            // Initialize device once ready
            if self.writeCharacteristics[deviceId] != nil && self.notifyCharacteristics[deviceId] != nil {
                self.log("[\(peripheral.name ?? "?")] Ready! Initializing...")
                let peripheralId = peripheral.identifier
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self,
                          let p = self.connectedDevices.first(where: { $0.identifier == peripheralId }) else { return }
                    self.initializeDevice(p)
                }
            }
        }
    }
    
    /// Initialize a specific device with required queries
    private func initializeDevice(_ peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier
        guard let characteristic = writeCharacteristics[deviceId] else { return }
        
        // 1. Query device info
        let infoPacket = buildPacket(command: .getDeviceInfo, payload: [], for: deviceId)
        sendCommand(infoPacket, to: characteristic, from: peripheral)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 2. Query device name
            let namePacket = self.buildPacket(command: .getDeviceName, payload: [], for: deviceId)
            self.sendCommand(namePacket, to: characteristic, from: peripheral)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // 3. Get firmware version
            let fwPacket = self.buildPacket(command: .getFirmwareVersion, payload: [], for: deviceId)
            self.sendCommand(fwPacket, to: characteristic, from: peripheral)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 4. Read device state
            var payload: [UInt8] = []
            payload.append(contentsOf: ZhiyunProtocol.subCommandControl)
            payload.append(0x00)
            payload.append(0x00)
            let statePacket = self.buildPacket(command: .readDeviceState, payload: payload, for: deviceId)
            self.sendCommand(statePacket, to: characteristic, from: peripheral)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // 5. Query brightness state
            var payload: [UInt8] = []
            payload.append(contentsOf: ZhiyunProtocol.subCommandControl)
            payload.append(0x00)
            payload.append(0x00)
            let brightnessPacket = self.buildPacket(command: .queryBrightness, payload: payload, for: deviceId)
            self.sendCommand(brightnessPacket, to: characteristic, from: peripheral)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // 6. Query color temperature
            var payload: [UInt8] = []
            payload.append(contentsOf: ZhiyunProtocol.subCommandControl)
            payload.append(0x00)
            payload.append(0x00)
            payload.append(0x00)
            let colorTempPacket = self.buildPacket(command: .setColorTemperature, payload: payload, for: deviceId)
            self.sendCommand(colorTempPacket, to: characteristic, from: peripheral)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.log("[\(peripheral.name ?? "?")] Initialized, ready for control!")
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.log("[\(peripheral.name ?? "?")] Error receiving: \(error.localizedDescription)")
                return
            }
            
            guard let data = characteristic.value else { return }
            self.parseResponse(data, from: peripheral.identifier)
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.log("[\(peripheral.name ?? "?")] Error writing: \(error.localizedDescription)")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.log("[\(peripheral.name ?? "?")] Notification error: \(error.localizedDescription)")
            } else {
                self.log("[\(peripheral.name ?? "?")] Notifications enabled")
            }
        }
    }
}

// MARK: - Data Extension
extension Data {
    var hexString: String {
        return map { String(format: "%02X ", $0) }.joined().trimmingCharacters(in: .whitespaces)
    }
}
