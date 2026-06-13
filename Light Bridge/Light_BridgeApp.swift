//
//  Light_BridgeApp.swift
//  Light Bridge
//
//  Created by Wolfgang Lienbacher on 02.02.26.
//

import SwiftUI

@main
struct Light_BridgeApp: App {
    @StateObject private var controller = BluetoothDeviceManager.shared
    
    // Using BluetoothDeviceManager with proprietary Zhiyun GATT protocol
    // (Bluetooth Mesh is only for provisioning, not light control)
    
    var body: some Scene {
        WindowGroup {
            GATTContentView(controller: controller)
        }
    }
}
