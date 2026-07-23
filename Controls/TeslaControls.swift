//
//  TeslaControls.swift
//  TeslaButtonsControls
//
//  iOS 18 Control Center / Lock Screen / Action-button controls.
//
//  Each control is a stateless button whose action is one of the shared App
//  Intents. The intents execute in the MAIN APP process (see
//  RunTeslaCommandIntent), so these buttons work even when the app isn't
//  running — the system background-launches it.
//
//  After installing: Control Center → "+" → Add a Control → Tesla Buttons.
//  They can also replace the Lock Screen flashlight/camera buttons.
//

import AppIntents
import SwiftUI
import WidgetKit

struct FrunkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(AppConstants.bundleRoot).controls.frunk") {
            ControlWidgetButton(action: RunTeslaCommandIntent(command: .frunk)) {
                Label("Frunk", systemImage: "car.side.front.open")
            }
        }
        .displayName("Open Frunk")
        .description("Opens the frunk over Bluetooth.")
    }
}

struct TrunkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(AppConstants.bundleRoot).controls.trunk") {
            ControlWidgetButton(action: RunTeslaCommandIntent(command: .trunk)) {
                Label("Trunk", systemImage: "car.side.rear.open")
            }
        }
        .displayName("Toggle Trunk")
        .description("Opens or closes the trunk over Bluetooth.")
    }
}

struct ClimateControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(AppConstants.bundleRoot).controls.climate") {
            ControlWidgetButton(action: SetCabinTempIntent()) {
                Label("Climate", systemImage: "fanblades.fill")
            }
        }
        .displayName("Start Climate")
        .description("Starts climate at your default temperature.")
    }
}

struct LockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(AppConstants.bundleRoot).controls.lock") {
            ControlWidgetButton(action: RunTeslaCommandIntent(command: .lock)) {
                Label("Lock", systemImage: "lock.fill")
            }
        }
        .displayName("Lock Vehicle")
        .description("Locks the vehicle over Bluetooth.")
    }
}
