//
//  RunTeslaCommandIntent.swift
//  TeslaButtons
//
//  The one intent that powers Siri, the Shortcuts app, the iPhone Action
//  button, and every Control Center / Lock Screen control in this project.
//
//  PROCESS ROUTING — the part that makes BLE work:
//  ─────────────────────────────────────────────────────────────────────────
//  • This file is a member of BOTH the app target and the Controls widget
//    extension target (required for controls to see the intent type).
//  • The `ForegroundContinuableIntent` conformance below — deliberately
//    compiled only into the app (it's unavailable in extensions) — tells the
//    system to always execute `perform()` in the MAIN APP PROCESS, launching
//    the app in the background if needed. That's where CoreBluetooth and the
//    Keychain-held key live. Without it, a control tapped while the app isn't
//    running would execute in the widget process and fail.
//  • `openAppWhenRun = false` keeps this invisible — no UI is presented.
//
//  iOS 26+: `ForegroundContinuableIntent` is deprecated in favor of
//  `static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]`.
//  The deprecated protocol still works; migrate when you bump the deployment
//  target past 26.
//

import AppIntents
import Foundation

struct RunTeslaCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Tesla Command"
    static let description = IntentDescription(
        "Sends a command to your Tesla over Bluetooth. Works with no internet — you just need to be within BLE range of the car.",
    )

    /// Never bring the app UI forward; commands run silently in the background.
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Command")
    var command: TeslaButtonCommand

    init() {}

    init(command: TeslaButtonCommand) {
        self.command = command
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PairedVehicle.storedVIN != nil else {
            throw TeslaButtonsError.notPaired
        }
        let outcome = try await VehicleService.shared.run(command.bleCommand)
        if case .alreadySatisfied = outcome {
            return .result(dialog: "Already set — no change needed.")
        }
        return .result(dialog: IntentDialog(stringLiteral: command.successDialog))
    }
}

// Forces execution in the main app process (see header comment).
@available(iOSApplicationExtension, unavailable)
extension RunTeslaCommandIntent: ForegroundContinuableIntent {}
