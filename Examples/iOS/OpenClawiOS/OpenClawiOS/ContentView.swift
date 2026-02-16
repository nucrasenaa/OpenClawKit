//
//  ContentView.swift
//  OpenClawiOS
//
//  Created by Marcus Arnett on 2/15/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: OpenClawAppState

    var body: some View {
        TabView {
            DeployView()
                .tabItem {
                    Label("Deploy", systemImage: "antenna.radiowaves.left.and.right")
                }

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
                .badge(appState.isDeployed ? nil : "!")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(OpenClawAppState())
}
