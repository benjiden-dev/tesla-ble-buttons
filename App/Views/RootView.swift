//
//  RootView.swift
//  TeslaButtons
//

import SwiftUI

struct RootView: View {
    @Environment(VehicleUIModel.self) private var model
    @State private var page = 0

    var body: some View {
        NavigationStack {
            if model.vin == nil {
                PairingView()
            } else {
                // Swipe between the control dashboard and the live stats
                // page. Only the visible page polls (isActive gate).
                TabView(selection: $page) {
                    DashboardView(isActive: page == 0)
                        .tag(0)
                    StatsView(isActive: page == 1)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}
