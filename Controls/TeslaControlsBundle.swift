//
//  TeslaControlsBundle.swift
//  TeslaButtonsControls
//

import SwiftUI
import WidgetKit

@main
struct TeslaControlsBundle: WidgetBundle {
    var body: some Widget {
        FrunkControl()
        TrunkControl()
        ClimateControl()
        LockControl()
    }
}
