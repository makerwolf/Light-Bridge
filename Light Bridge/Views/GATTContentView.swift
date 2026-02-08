import SwiftUI
import CoreBluetooth

// MARK: - Custom Vertical Bar Slider
struct VerticalBarSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let trackColor: Color
    let fillColor: Color?
    let gradient: LinearGradient?
    let height: CGFloat
    
    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1, trackColor: Color = Color(.systemGray4), fillColor: Color = .blue, height: CGFloat = 44) {
        self._value = value
        self.range = range
        self.step = step
        self.trackColor = trackColor
        self.fillColor = fillColor
        self.gradient = nil
        self.height = height
    }
    
    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1, trackColor: Color = Color(.systemGray4), gradient: LinearGradient, height: CGFloat = 44) {
        self._value = value
        self.range = range
        self.step = step
        self.trackColor = trackColor
        self.fillColor = nil
        self.gradient = gradient
        self.height = height
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background - show gradient on full track for color temp style
                if let gradient = gradient {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gradient)
                        .frame(height: height)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(trackColor)
                        .frame(height: height)
                    
                    // Filled portion (only for solid color mode)
                    if let fillColor = fillColor {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(fillColor)
                            .frame(width: max(0, filledWidth(in: geometry.size.width)), height: height)
                    }
                }
                
                // Vertical bar thumb
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 6, height: height)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .offset(x: thumbOffset(in: geometry.size.width))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, in: geometry.size.width)
                    }
            )
        }
        .frame(height: height)
    }
    
    private func filledWidth(in totalWidth: CGFloat) -> CGFloat {
        let percentage = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return totalWidth * CGFloat(percentage)
    }
    
    private func thumbOffset(in totalWidth: CGFloat) -> CGFloat {
        let percentage = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let offset = (totalWidth - 6) * CGFloat(percentage)
        return max(0, min(totalWidth - 6, offset))
    }
    
    private func updateValue(at x: CGFloat, in totalWidth: CGFloat) {
        let percentage = max(0, min(1, x / totalWidth))
        var newValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(percentage)
        
        // Snap to step
        newValue = (newValue / step).rounded() * step
        newValue = max(range.lowerBound, min(range.upperBound, newValue))
        
        value = newValue
    }
}

// Color temperature gradient (warm yellow to cool blue)
private let colorTempGradient = LinearGradient(
    colors: [Color.orange, Color.yellow, Color.white, Color(red: 0.7, green: 0.85, blue: 1.0), Color(red: 0.5, green: 0.7, blue: 1.0)],
    startPoint: .leading,
    endPoint: .trailing
)

// MARK: - GATT Content View
struct GATTContentView: View {
    @StateObject private var controller = ZhiyunGATTController()
    @State private var showDeviceList = false
    @State private var controlMode: ControlMode = .individual
    
    enum ControlMode {
        case individual
        case all
        case combined
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                connectionStatusView
                
                if controller.isConnected {
                    connectedDevicesView
                } else {
                    scanningView
                }
                
                //logView
            }
            .navigationTitle("Light Bridge")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDeviceList) {
                deviceListSheet
            }
        }
    }
    
    // MARK: - Connection Status View
    private var connectionStatusView: some View {
        HStack {
            Circle()
                .fill(controller.isConnected ? Color.green : (controller.isScanning ? Color.orange : Color.gray))
                .frame(width: 12, height: 12)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if let error = controller.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    private var statusText: String {
        let connectedCount = controller.connectedDevices.count
        if connectedCount > 0 {
            return "\(connectedCount) light(s) connected"
        } else if !controller.discoveredDevices.isEmpty && controller.isScanning {
            return "Found \(controller.discoveredDevices.count) device(s)..."
        } else if controller.isScanning {
            return "Scanning..."
        } else {
            return "Not connected"
        }
    }
    
    // MARK: - Scanning View
    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            if controller.isScanning {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    if controller.discoveredDevices.isEmpty {
                        Text("Searching for lights...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Found \(controller.discoveredDevices.count) light(s)...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    Text("No lights found")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            }
            
            if !controller.discoveredDevices.isEmpty {
                Button(action: {
                    showDeviceList = true
                }) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("\(controller.discoveredDevices.count) device(s) found - tap to connect")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            Button(action: {
                if controller.isScanning {
                    controller.stopScanning()
                } else {
                    controller.startScanning()
                }
            }) {
                HStack {
                    Image(systemName: controller.isScanning ? "stop.fill" : "antenna.radiowaves.left.and.right")
                    Text(controller.isScanning ? "Stop Scan" : "Scan for Devices")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(controller.isScanning ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
        }
    }
    
    // MARK: - Device List Sheet
    private var deviceListSheet: some View {
        NavigationView {
            List {
                if !controller.connectedDevices.isEmpty {
                    Section("Connected") {
                        ForEach(controller.connectedDevices, id: \.identifier) { peripheral in
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text(controller.state(for: peripheral).modelName.isEmpty ?
                                         (peripheral.name ?? "Unknown") :
                                         controller.state(for: peripheral).modelName)
                                        .font(.headline)
                                    Text(peripheral.name ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Disconnect") {
                                    controller.disconnect(from: peripheral)
                                }
                                .foregroundColor(.red)
                                .font(.caption)
                            }
                        }
                    }
                }
                
                let availableDevices = controller.discoveredDevices.filter { discovered in
                    !controller.connectedDevices.contains(where: { $0.identifier == discovered.identifier })
                }
                
                if !availableDevices.isEmpty {
                    Section("Available") {
                        ForEach(availableDevices, id: \.identifier) { peripheral in
                            Button(action: {
                                controller.connect(to: peripheral)
                            }) {
                                HStack {
                                    Image(systemName: "lightbulb")
                                        .foregroundColor(.yellow)
                                    VStack(alignment: .leading) {
                                        Text(peripheral.name ?? "Unknown Device")
                                            .font(.headline)
                                        Text(peripheral.identifier.uuidString)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showDeviceList = false
                    }
                }
            }
        }
    }
    
    // MARK: - Connected Devices View
    private var connectedDevicesView: some View {
        VStack(spacing: 0) {
            Picker("Control Mode", selection: $controlMode) {
                Text("Individual").tag(ControlMode.individual)
                Text("All Lights").tag(ControlMode.all)
                Text("Combined").tag(ControlMode.combined)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if controlMode == .individual {
                if controller.connectedDevices.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(controller.connectedDevices, id: \.identifier) { peripheral in
                                deviceTab(for: peripheral)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }
                
                if let selectedId = controller.selectedDeviceId,
                   let peripheral = controller.connectedDevices.first(where: { $0.identifier == selectedId }) {
                    ScrollView {
                        VStack(spacing: 16) {
                            deviceInfoCard(for: peripheral)
                            lightControlsCard(for: peripheral)
                        }
                        .padding(.top, 8)
                    }
                }
            } else if controlMode == .all {
                ScrollView {
                    VStack(spacing: 16) {
                        allDevicesInfoCard
                        allLightsControlsCard
                    }
                    .padding(.top, 8)
                }
            } else {
                // Combined mode - all devices with simplified controls on one page
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(controller.connectedDevices, id: \.identifier) { peripheral in
                            simplifiedLightControlsCard(for: peripheral)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    showDeviceList = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Manage")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    controller.disconnectAll()
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Disconnect All")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Device Tab
    private func deviceTab(for peripheral: CBPeripheral) -> some View {
        let isSelected = controller.selectedDeviceId == peripheral.identifier
        let state = controller.state(for: peripheral)
        
        return Button(action: {
            controller.selectDevice(peripheral)
        }) {
            VStack(spacing: 4) {
                Image(systemName: state.isOn ? "lightbulb.fill" : "lightbulb")
                    .font(.title2)
                    .foregroundColor(state.isOn ? .yellow : .gray)
                Text(state.modelName.isEmpty ? (peripheral.name ?? "?") : state.modelName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.2) : Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Device Info Card
    private func deviceInfoCard(for peripheral: CBPeripheral) -> some View {
        let state = controller.state(for: peripheral)
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Device Info")
                .font(.headline)
            
            HStack {
                Label("Model", systemImage: "lightbulb.led.fill")
                Spacer()
                Text(state.modelName.isEmpty ? "..." : state.modelName)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Device", systemImage: "tag")
                Spacer()
                Text(peripheral.name ?? "Unknown")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            HStack {
                Label("Firmware", systemImage: "cpu")
                Spacer()
                Text(state.firmwareVersion.isEmpty ? "..." : state.firmwareVersion)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("State", systemImage: "power")
                Spacer()
                Text(state.isOn ? "ON" : "OFF")
                    .foregroundColor(state.isOn ? .green : .gray)
                    .fontWeight(.bold)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - All Devices Info Card
    private var allDevicesInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All Lights")
                .font(.headline)
            
            HStack {
                Label("Connected", systemImage: "lightbulb.2.fill")
                Spacer()
                Text("\(controller.connectedDevices.count) light(s)")
                    .foregroundColor(.secondary)
            }
            
            ForEach(controller.connectedDevices, id: \.identifier) { peripheral in
                let state = controller.state(for: peripheral)
                HStack {
                    Image(systemName: state.isOn ? "lightbulb.fill" : "lightbulb")
                        .foregroundColor(state.isOn ? .yellow : .gray)
                    Text(state.modelName.isEmpty ? (peripheral.name ?? "?") : state.modelName)
                        .font(.caption)
                    Spacer()
                    Text(state.isOn ? "\(Int(state.brightness))%" : "OFF")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Light Controls Card
    private func lightControlsCard(for peripheral: CBPeripheral) -> some View {
        let deviceId = peripheral.identifier
        let state = controller.state(for: peripheral)
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Light Controls")
                .font(.headline)
            
            HStack {
                Button(action: {
                    controller.turnOn(for: deviceId)
                }) {
                    Label("ON", systemImage: "lightbulb.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    controller.turnOff(for: deviceId)
                }) {
                    Label("OFF", systemImage: "lightbulb")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                    Text("Brightness: \(Int(state.brightness))%")
                    Spacer()
                }
                
                VerticalBarSlider(
                    value: Binding(
                        get: { Double(state.brightness) },
                        set: { (newValue: Double) in controller.setBrightness(Float(newValue), for: deviceId) }
                    ),
                    in: 0...100,
                    step: 1,
                    fillColor: .yellow,
                    height: 44
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "thermometer")
                        .foregroundColor(.orange)
                    Text("Color Temp: \(state.colorTemperature)K")
                    Spacer()
                }
                
                VerticalBarSlider(
                    value: Binding(
                        get: { Double(state.colorTemperature) },
                        set: { (newValue: Double) in controller.setColorTemperature(UInt16(newValue), for: deviceId) }
                    ),
                    in: 2700...6500,
                    step: 100,
                    gradient: colorTempGradient,
                    height: 44
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Presets")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    presetButton("Warm", kelvin: 2700, brightness: 50, for: deviceId)
                    presetButton("Neutral", kelvin: 4500, brightness: 75, for: deviceId)
                    presetButton("Cool", kelvin: 6500, brightness: 100, for: deviceId)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Simplified Light Controls Card (for Combined mode)
    private func simplifiedLightControlsCard(for peripheral: CBPeripheral) -> some View {
        let deviceId = peripheral.identifier
        let state = controller.state(for: peripheral)
        let deviceModel = peripheral.name ?? "Unknown Device"
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(deviceModel)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                    Text("Brightness: \(Int(state.brightness))%")
                    Spacer()
                }
                
                VerticalBarSlider(
                    value: Binding(
                        get: { Double(state.brightness) },
                        set: { (newValue: Double) in controller.setBrightness(Float(newValue), for: deviceId) }
                    ),
                    in: 0...100,
                    step: 1,
                    fillColor: .yellow,
                    height: 44
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "thermometer")
                        .foregroundColor(.orange)
                    Text("Color Temp: \(state.colorTemperature)K")
                    Spacer()
                }
                
                VerticalBarSlider(
                    value: Binding(
                        get: { Double(state.colorTemperature) },
                        set: { (newValue: Double) in controller.setColorTemperature(UInt16(newValue), for: deviceId) }
                    ),
                    in: 2700...6500,
                    step: 100,
                    gradient: colorTempGradient,
                    height: 44
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - All Lights Controls Card
    private var allLightsControlsCard: some View {
        let count = controller.connectedDevices.count
        let totalBrightness = controller.connectedDevices.reduce(0.0) { $0 + Double(controller.state(for: $1).brightness) }
        let totalColorTemp = controller.connectedDevices.reduce(0.0) { $0 + Double(controller.state(for: $1).colorTemperature) }
        let averageBrightness: Int = count == 0 ? 0 : Int(totalBrightness / Double(count))
        let averageColorTemp: Int = count == 0 ? 0 : Int(totalColorTemp / Double(count))
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Control All Lights")
                .font(.headline)
            
            HStack {
                Button(action: {
                    controller.turnOn(for: nil, allDevices: true)
                }) {
                    Label("ALL ON", systemImage: "lightbulb.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    controller.turnOff(for: nil, allDevices: true)
                }) {
                    Label("ALL OFF", systemImage: "lightbulb")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                    Text("Brightness: \(averageBrightness)%")
                    Spacer()
                }
                
                VerticalBarSlider(
                    value: Binding(
                        get: {
                            let count: Double = Double(controller.connectedDevices.count)
                            if count == 0 { return 0.0 }
                            let total: Double = controller.connectedDevices.reduce(0.0) { partial, p in
                                partial + Double(controller.state(for: p).brightness)
                            }
                            return total / count
                        },
                        set: { (newValue: Double) in
                            controller.setBrightness(Float(newValue), for: nil, allDevices: true)
                        }
                    ),
                    in: 0...100,
                    step: 1,
                    fillColor: .yellow,
                    height: 44
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "thermometer")
                        .foregroundColor(.orange)
                    Text("Color Temp: \(averageColorTemp)K")
                    Spacer()
                }
                
                VerticalBarSlider(
                    value: Binding(
                        get: {
                            let count: Double = Double(controller.connectedDevices.count)
                            if count == 0 { return 0.0 }
                            let total: Double = controller.connectedDevices.reduce(0.0) { partial, p in
                                partial + Double(controller.state(for: p).colorTemperature)
                            }
                            return total / count
                        },
                        set: { newValue in
                            let temp: UInt16 = UInt16(exactly: newValue) ?? UInt16(newValue.rounded())
                            controller.setColorTemperature(temp, for: nil, allDevices: true)
                        }
                    ),
                    in: 2700...6500,
                    step: 100,
                    gradient: colorTempGradient,
                    height: 44
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Presets (All)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    presetButton("Warm", kelvin: 2700, brightness: 50, for: nil, allDevices: true)
                    presetButton("Neutral", kelvin: 4500, brightness: 75, for: nil, allDevices: true)
                    presetButton("Cool", kelvin: 6500, brightness: 100, for: nil, allDevices: true)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func presetButton(_ title: String, kelvin: UInt16, brightness: Float, for deviceId: UUID?, allDevices: Bool = false) -> some View {
        Button(action: {
            controller.setBrightness(brightness, for: deviceId, allDevices: allDevices)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                controller.setColorTemperature(kelvin, for: deviceId, allDevices: allDevices)
            }
        }) {
            Text(title)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(6)
        }
    }
    
    // MARK: - Log View
    private var logView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Log")
                    .font(.caption)
                    .fontWeight(.bold)
                Spacer()
                Button("Clear") {
                    controller.logMessages.removeAll()
                }
                .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray5))
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(controller.logMessages.enumerated()), id: \.offset) { index, message in
                            Text(message)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .id(index)
                        }
                    }
                    .padding(4)
                }
                .onChange(of: controller.logMessages.count) { oldValue, newValue in
                    if let lastIndex = controller.logMessages.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
        .frame(height: 100)
        .background(Color(.systemGray6))
    }
}

// MARK: - Mock Controller for Previews
class MockZhiyunGATTController: ZhiyunGATTController {
    override init() {
        super.init()
    }
}

// MARK: - Preview Helper Views
struct PreviewDeviceInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device Info")
                .font(.headline)
            
            HStack {
                Label("Model", systemImage: "lightbulb.led.fill")
                Spacer()
                Text("MOLUS X100")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Device", systemImage: "tag")
                Spacer()
                Text("PL105_ABC123")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            HStack {
                Label("Firmware", systemImage: "cpu")
                Spacer()
                Text("v1.2.3")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("State", systemImage: "power")
                Spacer()
                Text("ON")
                    .foregroundColor(.green)
                    .fontWeight(.bold)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct PreviewLightControlsCard: View {
    @State private var brightness: Double = 75
    @State private var colorTemp: Double = 4500
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Light Controls")
                .font(.headline)
            
            HStack {
                Button(action: {}) {
                    Label("ON", systemImage: "lightbulb.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: {}) {
                    Label("OFF", systemImage: "lightbulb")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                    Text("Brightness: \(Int(brightness))%")
                    Spacer()
                }
                
                VerticalBarSlider(value: $brightness, in: 0...100, step: 1, fillColor: .yellow, height: 44)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "thermometer")
                        .foregroundColor(.orange)
                    Text("Color Temp: \(Int(colorTemp))K")
                    Spacer()
                }
                
                VerticalBarSlider(value: $colorTemp, in: 2700...6500, step: 100, gradient: colorTempGradient, height: 44)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Presets")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(["Warm", "Neutral", "Cool"], id: \.self) { title in
                        Button(action: {}) {
                            Text(title)
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct PreviewSimplifiedLightControlsCard: View {
    let deviceName: String
    @State private var brightness: Double = 75
    @State private var colorTemp: Double = 4500
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(deviceName)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                    Text("Brightness: \(Int(brightness))%")
                    Spacer()
                }
                
                VerticalBarSlider(value: $brightness, in: 0...100, step: 1, fillColor: .yellow, height: 44)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "thermometer")
                        .foregroundColor(.orange)
                    Text("Color Temp: \(Int(colorTemp))K")
                    Spacer()
                }
                
                VerticalBarSlider(value: $colorTemp, in: 2700...6500, step: 100, gradient: colorTempGradient, height: 44)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct PreviewAllDevicesInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All Lights")
                .font(.headline)
            
            HStack {
                Label("Connected", systemImage: "lightbulb.2.fill")
                Spacer()
                Text("3 light(s)")
                    .foregroundColor(.secondary)
            }
            
            ForEach(["MOLUS X100", "MOLUS G60", "FIVERAY M20C"], id: \.self) { name in
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text(name)
                        .font(.caption)
                    Spacer()
                    Text("75%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct PreviewScanningView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("Found 2 light(s)...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {}) {
                HStack {
                    Image(systemName: "list.bullet")
                    Text("2 device(s) found - tap to connect")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            Button(action: {}) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop Scan")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
        }
    }
}

struct PreviewConnectionStatusView: View {
    let isConnected: Bool
    let count: Int
    
    var body: some View {
        HStack {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 12, height: 12)
            
            Text(isConnected ? "\(count) light(s) connected" : "Scanning...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

struct PreviewDeviceTabs: View {
    @State private var selectedIndex = 0
    let devices = ["MOLUS X100", "MOLUS G60", "FIVERAY M20C"]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(devices.enumerated()), id: \.offset) { index, name in
                    Button(action: { selectedIndex = index }) {
                        VStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)
                            Text(name)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(index == selectedIndex ? Color.blue.opacity(0.2) : Color(.systemGray6))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(index == selectedIndex ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Previews
struct GATTContentView_Previews: PreviewProvider {
    static var previews: some View {
        GATTContentView()
            .previewDisplayName("Main View")
    }
}

struct DeviceInfoCard_Previews: PreviewProvider {
    static var previews: some View {
        PreviewDeviceInfoCard()
            .previewDisplayName("Device Info Card")
            .previewLayout(.sizeThatFits)
            .padding(.vertical)
    }
}

struct LightControlsCard_Previews: PreviewProvider {
    static var previews: some View {
        PreviewLightControlsCard()
            .previewDisplayName("Light Controls")
            .previewLayout(.sizeThatFits)
            .padding(.vertical)
    }
}

struct AllDevicesInfoCard_Previews: PreviewProvider {
    static var previews: some View {
        PreviewAllDevicesInfoCard()
            .previewDisplayName("All Devices Info")
            .previewLayout(.sizeThatFits)
            .padding(.vertical)
    }
}

struct ScanningView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PreviewScanningView()
                .navigationTitle("Zhiyun Light Control")
                .navigationBarTitleDisplayMode(.inline)
        }
        .previewDisplayName("Scanning View")
    }
}

struct ConnectionStatus_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            PreviewConnectionStatusView(isConnected: true, count: 2)
            PreviewConnectionStatusView(isConnected: false, count: 0)
        }
        .previewDisplayName("Connection Status")
        .previewLayout(.sizeThatFits)
    }
}

struct DeviceTabs_Previews: PreviewProvider {
    static var previews: some View {
        PreviewDeviceTabs()
            .previewDisplayName("Device Tabs")
            .previewLayout(.sizeThatFits)
            .padding(.vertical)
    }
}

struct ConnectedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    PreviewConnectionStatusView(isConnected: true, count: 3)
                    
                    Picker("Control Mode", selection: .constant(0)) {
                        Text("Individual").tag(0)
                        Text("All Lights").tag(1)
                        Text("Combined").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    PreviewDeviceTabs()
                        .padding(.bottom, 8)
                    
                    PreviewDeviceInfoCard()
                    PreviewLightControlsCard()
                    
                    Spacer()
                }
            }
            .navigationTitle("Light Bridge")
            .navigationBarTitleDisplayMode(.inline)
        }
        .previewDisplayName("Connected View - Individual")
    }
}

struct AllLightsMode_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    PreviewConnectionStatusView(isConnected: true, count: 3)
                    
                    Picker("Control Mode", selection: .constant(1)) {
                        Text("Individual").tag(0)
                        Text("All Lights").tag(1)
                        Text("Combined").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    PreviewAllDevicesInfoCard()
                    PreviewLightControlsCard()
                    
                    Spacer()
                }
            }
            .navigationTitle("Light Bridge")
            .navigationBarTitleDisplayMode(.inline)
        }
        .previewDisplayName("All Lights Mode")
    }
}

struct CombinedMode_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    PreviewConnectionStatusView(isConnected: true, count: 3)
                    
                    Picker("Control Mode", selection: .constant(2)) {
                        Text("Individual").tag(0)
                        Text("All Lights").tag(1)
                        Text("Combined").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    VStack(spacing: 16) {
                        PreviewSimplifiedLightControlsCard(deviceName: "PLB105")
                        PreviewSimplifiedLightControlsCard(deviceName: "PLB108")
                        PreviewSimplifiedLightControlsCard(deviceName: "PLX114")
                    }
                    .padding(.top, 8)
                    
                    Spacer()
                }
            }
            .navigationTitle("Light Bridge")
            .navigationBarTitleDisplayMode(.inline)
        }
        .previewDisplayName("Combined Mode")
    }
}

