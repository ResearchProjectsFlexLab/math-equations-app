//
//  AppModel.swift
//  biometricTracker
//
//  Created by Prisha Marpu on 4/9/26.
//

//
//  AppModel.swift
//  biometricTracker
//

import SwiftUI
import Observation

@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    static let controlWindowID = "control"

    /// Set while Start waits for the immersive space; the space begins the session when it appears.
    var isOpeningSpace = false
    var controlWindowIsOpen = false

    enum ImmersiveSpaceState {
        case closed, inTransition, open
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var mathManager         = MathProblemManager()
}
