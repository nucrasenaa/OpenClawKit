//
//  OpenClawiOSApp.swift
//  OpenClawiOS
//
//  Created by Marcus Arnett on 2/15/26.
//

import AppIntents
import SwiftUI

/// Entry point for the OpenClaw iOS sample application.
@main
struct OpenClawiOSApp: App {
    @StateObject private var appState = OpenClawAppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
