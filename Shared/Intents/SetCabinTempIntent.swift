//
//  SetCabinTempIntent.swift
//  TeslaButtons
//
//  Parameterized intent: starts climate and sets both front zones to the
//  requested temperature. Demonstrates the numeric-parameter pattern —
//  "Hey Siri, precondition my Tesla" can ask for (or preconfigure) a value.
//
//  Same process-routing rules as RunTeslaCommandIntent (see that file).
//

import AppIntents
import Foundation

struct SetCabinTempIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Climate at Temperature"
    static let description = IntentDescription(
        "Starts climate over Bluetooth and sets the cabin temperature.",
    )

    static let openAppWhenRun: Bool = false

    @Parameter(title: "Temperature (°F)", default: 70)
    var fahrenheit: Int

    init() {}

    init(fahrenheit: Int) {
        self.fahrenheit = fahrenheit
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PairedVehicle.storedVIN != nil else {
            throw TeslaButtonsError.notPaired
        }
        let clamped = min(max(fahrenheit, 59), 83) // Tesla cabin range ≈ 15–28.5 °C
        let celsius = Float(clamped - 32) * 5.0 / 9.0

        try await VehicleService.shared.run(.climate(.on))
        try await VehicleService.shared.run(
            .climate(.setTemperature(driver: celsius, passenger: celsius)),
        )
        return .result(dialog: "Climate started at \(clamped)°F.")
    }
}

// Forces execution in the main app process (see RunTeslaCommandIntent).
@available(iOSApplicationExtension, unavailable)
extension SetCabinTempIntent: ForegroundContinuableIntent {}
