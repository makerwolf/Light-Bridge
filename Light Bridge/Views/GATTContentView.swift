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

private struct MeterMetricTileView: View {
    let title: String
    let value: String
    let unit: String
    let accent: Color
    let tileHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: .leading)
        .padding(10)
        .background(accent.opacity(0.12))
        .cornerRadius(10)
    }
}

private struct MeterTintTileView: View {
    let duv: Double?
    let tileHeight: CGFloat

    private var tintRange: ClosedRange<Double> { -0.08...0.08 }
    private var tintText: String { duv.map { String(format: "%.4f", $0) } ?? "--" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tint")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(tintText) Duv")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                let normalized = {
                    guard let duv else { return 0.5 }
                    let clamped = min(max(duv, tintRange.lowerBound), tintRange.upperBound)
                    return (clamped - tintRange.lowerBound) / (tintRange.upperBound - tintRange.lowerBound)
                }()
                let indicatorSize: CGFloat = 10
                let markerX = max(0, min(geometry.size.width - indicatorSize, (geometry.size.width * normalized) - (indicatorSize / 2)))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.74, blue: 0.82),
                                    Color(red: 0.96, green: 0.90, blue: 0.94),
                                    Color(red: 0.92, green: 0.95, blue: 0.92),
                                    Color(red: 0.77, green: 0.88, blue: 0.78)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)

                    Circle()
                        .fill(Color.white)
                        .frame(width: indicatorSize, height: indicatorSize)
                        .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 0.5)
                        .offset(x: markerX)
                }
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: .leading)
        .padding(10)
        .background(Color(.systemGray5))
        .cornerRadius(10)
    }
}

private enum ExposureManualField: String {
    case shutter = "Shutter"
    case aperture = "Aperture"
    case iso = "ISO"
}

private struct MeterExposureCalculatorView: View {
    let ev100: Double?

    @State private var aperture: Double = 2.8
    @State private var shutter: Double = 1.0 / 50.0
    @State private var iso: Double = 100.0
    @State private var manualField: ExposureManualField = .aperture
    @State private var pinnedFields: [ExposureManualField] = [.aperture]
    @State private var didInitialize = false
    private let tileHeight: CGFloat = 72

    private static let apertureValues: [Double] = [
        1.0, 1.1, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.5, 2.8,
        3.2, 3.5, 4.0, 4.5, 5.0, 5.6, 6.3, 7.1, 8.0, 9.0,
        10.0, 11.0, 13.0, 14.0, 16.0, 18.0, 20.0, 22.0
    ]

    private static let shutterValues: [Double] = [
        1.0 / 8000.0, 1.0 / 6400.0, 1.0 / 5000.0, 1.0 / 4000.0, 1.0 / 3200.0,
        1.0 / 2500.0, 1.0 / 2000.0, 1.0 / 1600.0, 1.0 / 1250.0, 1.0 / 1000.0,
        1.0 / 800.0, 1.0 / 640.0, 1.0 / 500.0, 1.0 / 400.0, 1.0 / 320.0,
        1.0 / 250.0, 1.0 / 200.0, 1.0 / 160.0, 1.0 / 125.0, 1.0 / 100.0,
        1.0 / 80.0, 1.0 / 60.0, 1.0 / 50.0, 1.0 / 40.0, 1.0 / 30.0,
        1.0 / 25.0, 1.0 / 20.0, 1.0 / 15.0, 1.0 / 13.0, 1.0 / 10.0,
        1.0 / 8.0, 1.0 / 6.0, 1.0 / 5.0, 1.0 / 4.0, 0.3, 0.4, 0.5,
        0.6, 0.8, 1.0, 1.3, 1.6, 2.0, 2.5, 3.2, 4.0, 5.0,
        6.0, 8.0, 10.0, 13.0, 15.0, 20.0, 25.0, 30.0
    ]

    private static let isoValues: [Double] = [
        100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
        1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Shutter")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 4)
                        Button {
                            togglePin(.shutter)
                        } label: {
                            Image(systemName: isPinned(.shutter) ? "pin.fill" : "pin")
                                .font(.caption2)
                                .foregroundColor(isPinned(.shutter) ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Menu {
                        ForEach(Array(Self.shutterValues.enumerated()), id: \.offset) { index, value in
                            Button(Self.shutterText(value)) {
                                selectShutter(index)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(Self.shutterText(shutter))
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.primary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(ev100 == nil)
                }
                .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: .leading)
                .padding(10)
                .background(Color.blue.opacity(isPinned(.shutter) ? 0.16 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isPinned(.shutter) ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Aperture")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 4)
                        Button {
                            togglePin(.aperture)
                        } label: {
                            Image(systemName: isPinned(.aperture) ? "pin.fill" : "pin")
                                .font(.caption2)
                                .foregroundColor(isPinned(.aperture) ? .orange : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Menu {
                        ForEach(Array(Self.apertureValues.enumerated()), id: \.offset) { index, value in
                            Button(Self.apertureText(value)) {
                                selectAperture(index)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(Self.apertureText(aperture))
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.primary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(ev100 == nil)
                }
                .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: .leading)
                .padding(10)
                .background(Color.orange.opacity(isPinned(.aperture) ? 0.16 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isPinned(.aperture) ? Color.orange.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("ISO")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 4)
                        Button {
                            togglePin(.iso)
                        } label: {
                            Image(systemName: isPinned(.iso) ? "pin.fill" : "pin")
                                .font(.caption2)
                                .foregroundColor(isPinned(.iso) ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Menu {
                        ForEach(Array(Self.isoValues.enumerated()), id: \.offset) { index, value in
                            Button("ISO \(Int(value))") {
                                selectISO(index)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(Int(iso.rounded()))")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.primary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(ev100 == nil)
                }
                .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: .leading)
                .padding(10)
                .background(Color.green.opacity(isPinned(.iso) ? 0.16 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isPinned(.iso) ? Color.green.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .cornerRadius(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if ev100 == nil {
                Text("Waiting for EV value from meter...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            recalculate()
        }
        .onChange(of: ev100) { _, _ in
            recalculate()
        }
    }

    private func isPinned(_ field: ExposureManualField) -> Bool {
        pinnedFields.contains(field)
    }

    private var effectiveFixedFields: [ExposureManualField] {
        if pinnedFields.isEmpty {
            return [manualField]
        }
        return Array(pinnedFields.prefix(2))
    }

    private func togglePin(_ field: ExposureManualField) {
        if let index = pinnedFields.firstIndex(of: field) {
            pinnedFields.remove(at: index)
        } else {
            pinAsMostRecent(field)
        }
        recalculate(previous: (aperture, shutter, iso))
    }

    private func selectAperture(_ index: Int) {
        let old = (aperture, shutter, iso)
        aperture = Self.apertureValues[index]
        manualField = .aperture
        pinAsMostRecent(.aperture)
        recalculate(previous: old)
    }

    private func selectShutter(_ index: Int) {
        let old = (aperture, shutter, iso)
        shutter = Self.shutterValues[index]
        manualField = .shutter
        pinAsMostRecent(.shutter)
        recalculate(previous: old)
    }

    private func selectISO(_ index: Int) {
        let old = (aperture, shutter, iso)
        iso = Self.isoValues[index]
        manualField = .iso
        pinAsMostRecent(.iso)
        recalculate(previous: old)
    }

    private func pinAsMostRecent(_ field: ExposureManualField) {
        if let existingIndex = pinnedFields.firstIndex(of: field) {
            pinnedFields.remove(at: existingIndex)
        }
        pinnedFields.append(field)
        if pinnedFields.count > 2 {
            pinnedFields.removeFirst()
        }
    }

    private func recalculate(previous: (Double, Double, Double)? = nil) {
        guard let ev100 else { return }

        let fixedFields = effectiveFixedFields

        if fixedFields.count >= 2 {
            let fixed = Set(fixedFields.prefix(2))

            if fixed.contains(.aperture) && fixed.contains(.iso) {
                let exactShutter = Self.shutterFrom(ev100: ev100, aperture: aperture, iso: iso)
                shutter = Self.closestValue(to: exactShutter, in: Self.shutterValues)
                return
            }

            if fixed.contains(.shutter) && fixed.contains(.iso) {
                let exactAperture = Self.apertureFrom(ev100: ev100, shutter: shutter, iso: iso)
                aperture = Self.closestValue(to: exactAperture, in: Self.apertureValues)
                return
            }

            if fixed.contains(.aperture) && fixed.contains(.shutter) {
                let exactISO = 100.0 * (aperture * aperture) / (shutter * pow(2.0, ev100))
                iso = Self.closestValue(to: exactISO, in: Self.isoValues)
                return
            }
        }

        let manual = fixedFields.first ?? manualField
        let oldAperture = previous?.0 ?? aperture
        let oldShutter = previous?.1 ?? shutter
        let oldISO = previous?.2 ?? iso

        var x0 = Self.x(aperture: oldAperture)
        var y0 = Self.y(shutter: oldShutter)
        var z0 = Self.z(iso: oldISO)

        var x = x0
        var y = y0
        var z = z0

        switch manual {
        case .aperture:
            x = Self.x(aperture: aperture)
            let c = ev100 - x // y - z = c
            y = (y0 + z0 + c) / 2.0
            z = (y0 + z0 - c) / 2.0

            iso = Self.closestValue(to: Self.iso(from: z), in: Self.isoValues)
            let exactShutter = Self.shutterFrom(ev100: ev100, aperture: aperture, iso: iso)
            shutter = Self.closestValue(to: exactShutter, in: Self.shutterValues)

        case .shutter:
            y = Self.y(shutter: shutter)
            let c = ev100 - y // x - z = c
            x = (x0 + z0 + c) / 2.0
            z = (x0 + z0 - c) / 2.0

            iso = Self.closestValue(to: Self.iso(from: z), in: Self.isoValues)
            let exactAperture = Self.apertureFrom(ev100: ev100, shutter: shutter, iso: iso)
            aperture = Self.closestValue(to: exactAperture, in: Self.apertureValues)

        case .iso:
            z = Self.z(iso: iso)
            let c = ev100 + z // x + y = c
            x = (c + x0 - y0) / 2.0
            y = c - x

            aperture = Self.closestValue(to: Self.aperture(from: x), in: Self.apertureValues)
            let exactShutter = Self.shutterFrom(ev100: ev100, aperture: aperture, iso: iso)
            shutter = Self.closestValue(to: exactShutter, in: Self.shutterValues)
        }
    }

    private static func closestValue(to value: Double, in values: [Double]) -> Double {
        values.min { abs($0 - value) < abs($1 - value) } ?? values[0]
    }

    private static func x(aperture: Double) -> Double {
        log2(aperture * aperture)
    }

    private static func y(shutter: Double) -> Double {
        -log2(shutter)
    }

    private static func z(iso: Double) -> Double {
        log2(iso / 100.0)
    }

    private static func aperture(from x: Double) -> Double {
        pow(2.0, x / 2.0)
    }

    private static func iso(from z: Double) -> Double {
        100.0 * pow(2.0, z)
    }

    private static func shutterFrom(ev100: Double, aperture: Double, iso: Double) -> Double {
        let exposureAtISO = ev100 + log2(iso / 100.0)
        return (aperture * aperture) / pow(2.0, exposureAtISO)
    }

    private static func apertureFrom(ev100: Double, shutter: Double, iso: Double) -> Double {
        let exposureAtISO = ev100 + log2(iso / 100.0)
        return sqrt(shutter * pow(2.0, exposureAtISO))
    }

    private static func shutterText(_ value: Double) -> String {
        if value >= 1.0 {
            if abs(value.rounded() - value) < 0.05 {
                return "\(Int(value.rounded()))s"
            }
            return String(format: "%.1fs", value)
        }

        let denominator = Int((1.0 / value).rounded())
        return "1/\(denominator)s"
    }

    private static func apertureText(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return "f/\(Int(value.rounded()))"
        }
        return String(format: "f/%.1f", value)
    }
}

// MARK: - GATT Content View
struct GATTContentView: View {
    @ObservedObject private var controller: BluetoothDeviceManager
    @State private var showDeviceList = false
    @State private var controlMode: ControlMode = .individual
    private let meterTileHeight: CGFloat = 72
    
    init(controller: BluetoothDeviceManager) {
        self.controller = controller
    }
    
    enum ControlMode {
        case individual
        case all
        case combined
    }
    
    private var connectedLightDevices: [CBPeripheral] {
        controller.connectedLightDevices
    }
    
    private var connectedMeterDevices: [CBPeripheral] {
        controller.connectedMeterDevices
    }
    
    private func iconForDevice(_ peripheral: CBPeripheral) -> (name: String, color: Color) {
        if controller.profile(for: peripheral) == .oppleLightMaster {
            return ("gauge.with.dots.needle.50percent", .blue)
        }
        return ("lightbulb.fill", .yellow)
    }
    
    private func deviceTypeLabel(_ peripheral: CBPeripheral) -> String {
        switch controller.profile(for: peripheral) {
        case .zhiyunLight:
            return "Light"
        case .oppleLightMaster:
            return "Meter"
        }
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
            return "\(connectedCount) device(s) connected"
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
                        Text("Searching for devices...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Found \(controller.discoveredDevices.count) device(s)...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    Text("No devices found")
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
                            let icon = iconForDevice(peripheral)
                            HStack {
                                Image(systemName: icon.name)
                                    .foregroundColor(icon.color)
                                VStack(alignment: .leading) {
                                    Text(controller.state(for: peripheral).modelName.isEmpty ?
                                         (peripheral.name ?? "Unknown") :
                                         controller.state(for: peripheral).modelName)
                                        .font(.headline)
                                    Text("\(deviceTypeLabel(peripheral)) • \(peripheral.name ?? "")")
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
                            let icon = iconForDevice(peripheral)
                            Button(action: {
                                controller.connect(to: peripheral)
                            }) {
                                HStack {
                                    Image(systemName: icon.name)
                                        .foregroundColor(icon.color)
                                    VStack(alignment: .leading) {
                                        Text(peripheral.name ?? "Unknown Device")
                                            .font(.headline)
                                        Text("\(deviceTypeLabel(peripheral)) • \(peripheral.identifier.uuidString)")
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
        let allDevices = controller.connectedDevices
        let lightDevices = connectedLightDevices
        let meterDevices = connectedMeterDevices
        let hasLights = !lightDevices.isEmpty
        
        return VStack(spacing: 0) {
            if hasLights {
                Picker("Control Mode", selection: $controlMode) {
                    Text("Individual").tag(ControlMode.individual)
                    Text("All Lights").tag(ControlMode.all)
                    Text("Combined").tag(ControlMode.combined)
                }
                .pickerStyle(.segmented)
                .padding()
            }

            if controlMode == .individual || !hasLights {
                if allDevices.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allDevices, id: \.identifier) { peripheral in
                                deviceTab(for: peripheral)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }

                ScrollView {
                    if let selectedId = controller.selectedDeviceId,
                       let selected = allDevices.first(where: { $0.identifier == selectedId }) {
                        devicePanel(for: selected)
                            .padding(.top, 8)
                    } else if let firstDevice = allDevices.first {
                        devicePanel(for: firstDevice)
                            .padding(.top, 8)
                    }
                }
            } else if controlMode == .all {
                ScrollView {
                    VStack(spacing: 16) {
                        allDevicesInfoCard
                        allLightsControlsCard
                        if !meterDevices.isEmpty {
                            meterDevicesCard(devices: meterDevices)
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                // Combined mode - all lights with simplified controls on one page.
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(lightDevices, id: \.identifier) { peripheral in
                            simplifiedLightControlsCard(for: peripheral)
                        }
                        if !meterDevices.isEmpty {
                            meterDevicesCard(devices: meterDevices)
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

    private func devicePanel(for peripheral: CBPeripheral) -> some View {
        let profile = controller.profile(for: peripheral)

        return VStack(spacing: 16) {
            deviceInfoCard(for: peripheral)
            if profile == .oppleLightMaster {
                meterDeviceCard(for: peripheral)
                    .padding(.horizontal)
            } else {
                lightControlsCard(for: peripheral)
            }
        }
    }
    
    // MARK: - Device Tab
    private func deviceTab(for peripheral: CBPeripheral) -> some View {
        let isSelected = controller.selectedDeviceId == peripheral.identifier
        let state = controller.state(for: peripheral)
        let isMeter = controller.profile(for: peripheral) == .oppleLightMaster
        let iconName = isMeter ? "gauge.with.dots.needle.50percent" : (state.isOn ? "lightbulb.fill" : "lightbulb")
        let iconColor: Color = isMeter ? .blue : (state.isOn ? .yellow : .gray)
        
        return Button(action: {
            controller.selectDevice(peripheral)
        }) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(iconColor)
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
        let isMeter = controller.profile(for: peripheral) == .oppleLightMaster
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Device Info")
                .font(.headline)

            if !isMeter {
                HStack {
                    Label("Model", systemImage: "lightbulb.led.fill")
                    Spacer()
                    Text(state.modelName.isEmpty ? "..." : state.modelName)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Label("Device", systemImage: "tag")
                Spacer()
                Text(peripheral.name ?? "Unknown")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            if !isMeter {
                HStack {
                    Label("Firmware", systemImage: "cpu")
                    Spacer()
                    Text(state.firmwareVersion.isEmpty ? "..." : state.firmwareVersion)
                        .foregroundColor(.secondary)
                }
            }
            
            if isMeter {
                HStack {
                    Label("Readings", systemImage: "waveform.path.ecg")
                    Spacer()
                    Text(state.meterCCT == nil ? "Waiting..." : "Live")
                        .foregroundColor(state.meterCCT == nil ? .secondary : .green)
                        .fontWeight(.bold)
                }
            } else {
                HStack {
                    Label("State", systemImage: "power")
                    Spacer()
                    Text(state.isOn ? "ON" : "OFF")
                        .foregroundColor(state.isOn ? .green : .gray)
                        .fontWeight(.bold)
                }
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
                Text("\(connectedLightDevices.count) light(s)")
                    .foregroundColor(.secondary)
            }
            
            ForEach(connectedLightDevices, id: \.identifier) { peripheral in
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
    
    private func meterDevicesCard(devices: [CBPeripheral]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(devices, id: \.identifier) { peripheral in
                meterDeviceCard(for: peripheral)
            }
        }
        .padding(.horizontal)
    }

    private func meterDeviceCard(for peripheral: CBPeripheral) -> some View {
        let state = controller.state(for: peripheral)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.modelName.isEmpty ?
                         (peripheral.name ?? "Unknown Meter") :
                         state.modelName)
                        .font(.headline)
                    Text(peripheral.name ?? peripheral.identifier.uuidString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let profileName = state.meterMetricsProfileName {
                        Text("Profile: \(profileName)\(state.meterMetricsProfileIsProvisional ? " (provisional)" : "")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            let wbText = state.meterCCT.map { "\(Int($0.rounded()))" } ?? "--"
            let luxText = state.meterLux.map { "\(Int($0.rounded()))" } ?? "--"
            let evText = state.meterEV100.map { String(format: "%.2f", $0) } ?? "--"
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    MeterMetricTileView(
                        title: "WB",
                        value: wbText,
                        unit: "K",
                        accent: .orange,
                        tileHeight: meterTileHeight
                    )
                    MeterMetricTileView(
                        title: "Lux",
                        value: luxText,
                        unit: "",
                        accent: .yellow,
                        tileHeight: meterTileHeight
                    )
                }
                HStack(spacing: 8) {
                    MeterMetricTileView(
                        title: "EV",
                        value: evText,
                        unit: "100",
                        accent: .blue,
                        tileHeight: meterTileHeight
                    )
                    MeterTintTileView(duv: state.meterDuv, tileHeight: meterTileHeight)
                }
            }

            MeterExposureCalculatorView(ev100: state.meterEV100)

            if state.meterCCT == nil || state.meterLux == nil || state.meterEV100 == nil {
                Text("Waiting for measurement data...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        let count = connectedLightDevices.count
        let totalBrightness = connectedLightDevices.reduce(0.0) { $0 + Double(controller.state(for: $1).brightness) }
        let totalColorTemp = connectedLightDevices.reduce(0.0) { $0 + Double(controller.state(for: $1).colorTemperature) }
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
                            let count: Double = Double(connectedLightDevices.count)
                            if count == 0 { return 0.0 }
                            let total: Double = connectedLightDevices.reduce(0.0) { partial, p in
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
                            let count: Double = Double(connectedLightDevices.count)
                            if count == 0 { return 0.0 }
                            let total: Double = connectedLightDevices.reduce(0.0) { partial, p in
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
class MockBluetoothDeviceManager: BluetoothDeviceManager {
    override init() {
        super.init()
        // Setup mock state
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
                
                Text("Found 2 device(s)...")
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
            
            Text(isConnected ? "\(count) device(s) connected" : "Scanning...")
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
    let devices: [(name: String, icon: String, color: Color)] = [
        ("MOLUS X100", "lightbulb.fill", .yellow),
        ("SigMesh", "gauge.with.dots.needle.50percent", .blue),
        ("FIVERAY M20C", "lightbulb.fill", .yellow)
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(devices.enumerated()), id: \.offset) { index, device in
                    Button(action: { selectedIndex = index }) {
                        VStack(spacing: 4) {
                            Image(systemName: device.icon)
                                .font(.title2)
                                .foregroundColor(device.color)
                            Text(device.name)
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

struct PreviewMeterTiles: View {
    private let tileHeight: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                MeterMetricTileView(
                    title: "WB",
                    value: "4320",
                    unit: "K",
                    accent: .orange,
                    tileHeight: tileHeight
                )
                MeterMetricTileView(
                    title: "Lux",
                    value: "286",
                    unit: "",
                    accent: .yellow,
                    tileHeight: tileHeight
                )
            }
            HStack(spacing: 8) {
                MeterMetricTileView(
                    title: "EV",
                    value: "6.83",
                    unit: "100",
                    accent: .blue,
                    tileHeight: tileHeight
                )
                MeterTintTileView(
                    duv: 0.0124,
                    tileHeight: tileHeight
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Previews
struct GATTContentView_Previews: PreviewProvider {
    static var previews: some View {
        GATTContentView(controller: .shared)
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

struct MeterTiles_Previews: PreviewProvider {
    static var previews: some View {
        PreviewMeterTiles()
            .previewDisplayName("Meter Tiles")
            .previewLayout(.sizeThatFits)
            .padding(.vertical)
    }
}

struct MeterExposureCalculator_Previews: PreviewProvider {
    static var previews: some View {
        MeterExposureCalculatorView(ev100: 6.83)
            .padding()
            .previewDisplayName("Meter Exposure Calculator")
            .previewLayout(.sizeThatFits)
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
                .navigationTitle("Light Bridge")
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

struct ConnectedMeterView_Previews: PreviewProvider {
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
                    PreviewMeterTiles()
                    MeterExposureCalculatorView(ev100: 6.83)
                        .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("Light Bridge")
            .navigationBarTitleDisplayMode(.inline)
        }
        .previewDisplayName("Connected View - Meter")
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
