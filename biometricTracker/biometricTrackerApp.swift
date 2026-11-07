//
//  biometricTrackerApp.swift
//  biometricTracker
//
//  Created by Prisha Marpu on 4/9/26.
//


import SwiftUI

@main
struct biometricTrackerApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 980, height: 820)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear   { appModel.immersiveSpaceState = .open   }
                .onDisappear { appModel.immersiveSpaceState = .closed }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
