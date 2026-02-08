//
//  Light_BridgeApp.swift
//  Light Bridge
//
//  Created by Wolfgang Lienbacher on 02.02.26.
//

import SwiftUI

@main
struct Light_BridgeApp: App {
    // Using ZhiyunGATTController with proprietary Zhiyun GATT protocol
    // (Bluetooth Mesh is only for provisioning, not light control)
    
    var body: some Scene {
        WindowGroup {
            GATTContentView()
        }
    }
}
