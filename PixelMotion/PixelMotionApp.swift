//
//  PixelMotionApp.swift
//  PixelMotion
//
//  Created by Ahmed Chellali on 12/10/2026.
//

import SwiftUI
import AppKit
import Combine
import ServiceManagement

@main
struct PixelMotionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        MenuBarExtra("PixelMotion", systemImage: "checkerboard.rectangle") {
            MenuContent(model: AppModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
