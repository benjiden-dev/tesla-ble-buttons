//
//  AppConstants.swift
//  TeslaButtons
//
//  Shared between the app target and the Controls widget extension.
//

import Foundation

enum AppConstants {
    /// Root identifier used for Keychain service names, UserDefaults keys,
    /// logger subsystems, and control kinds. Keep in sync with the bundle id
    /// prefix in `project.yml` if you change it.
    static let bundleRoot = "dev.benjiden.teslabuttons"

    /// Keychain service under which the per-VIN P-256 private key is stored
    /// (device-only, no iCloud sync — see `KeychainTeslaKeyStore`).
    static let keychainService = bundleRoot

    /// Seconds of command inactivity before the shared service drops the BLE
    /// session — applies only when the app UI is not in the foreground, so a
    /// burst of Action-button presses reuses one warm session.
    static let idleDisconnectSeconds = 90

    /// UserDefaults key for the preferred cabin temperature (°F).
    static let defaultTempKey = "\(bundleRoot).defaultTempF"
}

enum TeslaButtonsError: LocalizedError {
    case notPaired
    case invalidVIN

    var errorDescription: String? {
        switch self {
        case .notPaired:
            "No vehicle paired. Open Tesla Buttons and pair with your car first."
        case .invalidVIN:
            "A Tesla VIN is exactly 17 characters."
        }
    }
}
