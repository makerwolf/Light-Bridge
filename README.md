# Light Bridge

An open-source iOS/macOS app for controlling Bluetooth-enabled photo and video studio lights with a simple, intuitive interface.

## Overview

Light Bridge provides seamless connectivity to Bluetooth-controllable studio lighting equipment, allowing photographers and videographers to adjust their lighting setups directly from their Apple devices. The app focuses on quick connection times and an easy-to-use interface for efficient workflow integration.

## Features

- **Swift Bluetooth Connectivity**: Quick pairing and connection to supported studio lights
- **Simple User Interface**: Clean, intuitive controls for adjusting light parameters
- **Real-time Control**: Adjust brightness, color temperature, and other settings on the fly
- **Native iOS/macOS App**: Built with SwiftUI for optimal performance and integration

## Screenshots

<table>
  <tr>
    <td width="30%">
      <h3>Scanning for Devices</h3>
      <a href="screenshots/Scanning%20View.png">
        <img src="screenshots/Scanning%20View.png" width="400" alt="Scanning View">
      </a>
    </td>
    <td width="30%">
      <h3>Connected View - Individual Control</h3>
      <a href="screenshots/Connected%20View%20-%20Individual.png">
        <img src="screenshots/Connected%20View%20-%20Individual.png" width="400" alt="Connected View - Individual">
      </a>
    </td>
  </tr>
  <tr>
    <td width="30%">
      <h3>Combined Mode</h3>
      <a href="screenshots/Combined%20Mode.png">
        <img src="screenshots/Combined%20Mode.png" width="400" alt="Combined Mode">
      </a>
    </td>
    <td width="30%">
      <h3>All Lights Mode</h3>
      <a href="screenshots/All%20Lights%20Mode.png">
        <img src="screenshots/All%20Lights%20Mode.png" width="400" alt="All Lights Mode">
      </a>
    </td>
  </tr>
</table>

## Supported Devices

### Currently Supported
- **Zhiyun Bi-Color Lights**: Full support for Zhiyun's bi-color LED lighting systems

### Planned Support
We're actively working to add support for additional lighting brands and models. Contributions and feature requests are welcome!

## Requirements

- iOS 15.0+ / macOS 12.0+
- Xcode 13.0+
- Swift 5.5+
- Bluetooth-enabled device
- Compatible studio lighting equipment

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/light-bridge.git
   cd light-bridge
   ```

2. Open the project in Xcode:
   ```bash
   open "Light Bridge.xcodeproj"
   ```

3. Build and run the project on your device or simulator

## Usage

1. Launch the Light Bridge app on your device
2. Enable Bluetooth if not already enabled
3. Power on your compatible studio light
4. The app will automatically scan for available devices
5. Select your light from the list to connect
6. Use the interface controls to adjust brightness, color temperature, and other settings

## Architecture

The app is built using SwiftUI and follows a clean architecture pattern:

- **Views**: SwiftUI-based user interface components
  - `ContentView.swift`: Main application view
  - `GATTContentView.swift`: Bluetooth GATT service interface
  
- **Managers**: Business logic and service controllers
  - `ZhiyunGATTController.swift`: Handles Bluetooth GATT communication with Zhiyun devices
  
- **Models**: Data structures and business entities

## Contributing

Contributions are welcome! Whether you want to:
- Add support for new lighting brands
- Improve the user interface
- Fix bugs or improve performance
- Enhance documentation

Please feel free to:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Roadmap

- [ ] Support for additional Zhiyun light models
- [ ] Integration with other major lighting brands (Aputure, Godox, etc.)
- [ ] Preset saving and management
- [ ] Scene/lighting setup profiles
- [ ] Multi-light control and synchronization
- [ ] Remote triggering capabilities

## Technical Details

Light Bridge uses Bluetooth Low Energy (BLE) and GATT (Generic Attribute Profile) to communicate with studio lights. The app implements custom GATT service handlers for each supported device manufacturer, ensuring reliable and efficient control.

## License

This project is open source and available under the MIT License.

## Acknowledgments

- Thanks to the photographers and videographers who provided feedback and testing
- Inspired by the need for a unified, open-source lighting control solution

## Support

If you encounter any issues or have questions:
- Open an issue on GitHub
- Check existing issues for solutions
- Contribute to the documentation

---

**Note**: This is an independent open-source project and is not affiliated with or endorsed by any lighting equipment manufacturer.
