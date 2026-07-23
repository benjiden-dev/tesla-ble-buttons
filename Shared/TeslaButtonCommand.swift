//
//  TeslaButtonCommand.swift
//  TeslaButtons
//
//  The curated command catalog: one enum drives the in-app button grid, the
//  Shortcuts/Action-button parameter picker, and the Control Center buttons.
//

import AppIntents
import TeslaBLE

enum TeslaButtonCommand: String, CaseIterable, AppEnum {
    case unlock
    case lock
    case frunk
    case trunk
    case climateOn
    case climateOff
    case ventWindows
    case closeWindows
    case chargePortOpen
    case chargePortClose
    case flashLights
    case honk
    case wake

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tesla Command"

    static let caseDisplayRepresentations: [TeslaButtonCommand: DisplayRepresentation] = [
        .unlock: DisplayRepresentation(title: "Unlock"),
        .lock: DisplayRepresentation(title: "Lock"),
        .frunk: DisplayRepresentation(title: "Open Frunk"),
        .trunk: DisplayRepresentation(title: "Toggle Trunk"),
        .climateOn: DisplayRepresentation(title: "Start Climate"),
        .climateOff: DisplayRepresentation(title: "Stop Climate"),
        .ventWindows: DisplayRepresentation(title: "Vent Windows"),
        .closeWindows: DisplayRepresentation(title: "Close Windows"),
        .chargePortOpen: DisplayRepresentation(title: "Open Charge Port"),
        .chargePortClose: DisplayRepresentation(title: "Close Charge Port"),
        .flashLights: DisplayRepresentation(title: "Flash Lights"),
        .honk: DisplayRepresentation(title: "Honk Horn"),
        .wake: DisplayRepresentation(title: "Wake Vehicle"),
    ]

    /// The underlying signed BLE command.
    var bleCommand: Command {
        switch self {
        case .unlock: .security(.unlock)
        case .lock: .security(.lock)
        case .frunk: .security(.openFrunk)
        case .trunk: .security(.actuateTrunk)
        case .climateOn: .climate(.on)
        case .climateOff: .climate(.off)
        case .ventWindows: .actions(.ventWindows)
        case .closeWindows: .actions(.closeWindows)
        case .chargePortOpen: .charge(.openPort)
        case .chargePortClose: .charge(.closePort)
        case .flashLights: .actions(.flashLights)
        case .honk: .actions(.honk)
        case .wake: .security(.wakeVehicle)
        }
    }

    /// Short label for grid tiles.
    var title: String {
        switch self {
        case .unlock: "Unlock"
        case .lock: "Lock"
        case .frunk: "Frunk"
        case .trunk: "Trunk"
        case .climateOn: "Climate On"
        case .climateOff: "Climate Off"
        case .ventWindows: "Vent"
        case .closeWindows: "Close Windows"
        case .chargePortOpen: "Charge Port"
        case .chargePortClose: "Close Port"
        case .flashLights: "Flash"
        case .honk: "Honk"
        case .wake: "Wake"
        }
    }

    var symbol: String {
        switch self {
        case .unlock: "lock.open.fill"
        case .lock: "lock.fill"
        case .frunk: "car.side.front.open"
        case .trunk: "car.side.rear.open"
        case .climateOn: "fanblades.fill"
        case .climateOff: "fanblades.slash.fill"
        case .ventWindows: "wind"
        case .closeWindows: "arrow.down.circle"
        case .chargePortOpen: "bolt.fill"
        case .chargePortClose: "bolt.slash.fill"
        case .flashLights: "rays"
        case .honk: "horn.fill"
        case .wake: "sun.max.fill"
        }
    }

    /// Spoken/shown confirmation when triggered via Siri or a control.
    var successDialog: String {
        switch self {
        case .unlock: "Unlocked."
        case .lock: "Locked."
        case .frunk: "Frunk opened."
        case .trunk: "Trunk actuated."
        case .climateOn: "Climate started."
        case .climateOff: "Climate stopped."
        case .ventWindows: "Windows vented."
        case .closeWindows: "Windows closed."
        case .chargePortOpen: "Charge port opened."
        case .chargePortClose: "Charge port closed."
        case .flashLights: "Lights flashed."
        case .honk: "Honked."
        case .wake: "Vehicle awake."
        }
    }

    /// Order used by the in-app grid.
    static let gridOrder: [TeslaButtonCommand] = [
        .frunk, .trunk, .unlock, .lock,
        .climateOn, .climateOff, .ventWindows, .closeWindows,
        .chargePortOpen, .flashLights, .honk, .wake,
    ]
}
