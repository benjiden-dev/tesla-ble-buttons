//
//  PairedVehicle.swift
//  TeslaButtons
//
//  Persists the single paired VIN. Standard UserDefaults is sufficient
//  because every App Intent in this project runs in the *app's* process
//  (see RunTeslaCommandIntent's ForegroundContinuableIntent conformance).
//  If you ever allow intents to run in the widget extension process, move
//  this to an App Group container.
//

import Foundation

enum PairedVehicle {
    private static let key = "\(AppConstants.bundleRoot).pairedVIN"

    static var storedVIN: String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func set(_ vin: String?) {
        if let vin {
            UserDefaults.standard.set(vin, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
