//
//  RootView.swift
//  TeslaButtons
//

import SwiftUI

struct RootView: View {
    @Environment(VehicleUIModel.self) private var model

    var body: some View {
        NavigationStack {
            if model.vin == nil {
                PairingView()
            } else {
                DashboardView()
            }
        }
    }
}
