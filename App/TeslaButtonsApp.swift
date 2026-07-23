//
//  TeslaButtonsApp.swift
//  TeslaButtons
//

import SwiftUI

@main
struct TeslaButtonsApp: App {
    @State private var model = VehicleUIModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { model.start() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            model.scenePhaseChanged(newPhase)
        }
    }
}
