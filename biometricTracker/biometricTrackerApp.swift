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
        WindowGroup(id: AppModel.controlWindowID) {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 760, height: 600)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
