//
//  CommandCatalog.swift
//  TeslaButtons
//
//  Everything the tile grid is allowed to expose, grouped into dashboard
//  sections. Add new entries here and they become addable from the
//  Edit → Add Function sheet automatically — no other wiring needed.
//
//  Media transport is deliberately NOT in the catalog: it's fixed chrome in
//  the dashboard's Media section (now playing + slim controls). Previously
//  stored media tile IDs are skipped gracefully by the tile renderer.
//

import Foundation

enum ConfirmationRequirement: Sendable {
    case none
    case confirm
}

/// Which dashboard section a catalog command renders under.
enum DashboardSection: String, CaseIterable, Sendable {
    case climate
    case vehicle

    var title: String {
        switch self {
        case .climate: "Climate"
        case .vehicle: "Vehicle"
        }
    }
}

struct CatalogCommand: Identifiable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let section: DashboardSection
    let confirmation: ConfirmationRequirement
    /// @Sendable so `CatalogCommand` (and the global `CommandCatalog.all`)
    /// satisfies Swift 6 strict concurrency — the closures only touch the
    /// stateless executor, so this is safe by construction.
    let action: @Sendable (TeslaCommandExecutor) async throws -> Void
}

/// Do NOT add security(.addKey), security(.removeKey), or
/// security(.eraseGuestData) to this catalog. Those commands can mint or
/// revoke persistent vehicle keys and must never be reachable from hardware
/// that's fixed in the car. See HANDOFF.md. Keep PIN-to-Drive enabled on
/// the vehicle regardless of what's on this dashboard.
enum CommandCatalog {
    static let all: [CatalogCommand] = [
        // MARK: Climate
        CatalogCommand(
            id: "climate.preset.68",
            title: "Climate 68°F",
            systemImage: "thermometer.low",
            section: .climate,
            confirmation: .none,
            action: { executor in
                try await executor.climateOn()
                try await executor.setTemperature(fahrenheit: 68)
            },
        ),
        CatalogCommand(
            id: "climate.preset.72",
            title: "Climate 72°F",
            systemImage: "thermometer.medium",
            section: .climate,
            confirmation: .none,
            action: { executor in
                try await executor.climateOn()
                try await executor.setTemperature(fahrenheit: 72)
            },
        ),
        CatalogCommand(
            id: "climate.preset.defrost",
            title: "Defrost",
            systemImage: "windshield.front.and.heat.waves",
            section: .climate,
            confirmation: .none,
            action: { executor in
                try await executor.climateOn()
                try await executor.maxDefrost()
            },
        ),
        CatalogCommand(
            id: "climate.off",
            title: "Climate Off",
            systemImage: "fanblades.slash.fill",
            section: .climate,
            confirmation: .none,
            action: { try await $0.climateOff() },
        ),
        // Cycles Off → 1 → 2 → 3 → Off from the car-reported level.
        CatalogCommand(
            id: "climate.seatHeat.driver",
            title: "Driver Heat",
            systemImage: "carseat.left.and.heat.waves",
            section: .climate,
            confirmation: .none,
            action: { try await $0.cycleSeatHeater(seat: .driver) },
        ),
        CatalogCommand(
            id: "climate.seatHeat.passenger",
            title: "Passenger Heat",
            systemImage: "carseat.right.and.heat.waves",
            section: .climate,
            confirmation: .none,
            action: { try await $0.cycleSeatHeater(seat: .passenger) },
        ),
        // Toggles based on the car-reported state.
        CatalogCommand(
            id: "climate.wheelHeat",
            title: "Wheel Heat",
            systemImage: "steeringwheel.and.heat.waves",
            section: .climate,
            confirmation: .none,
            action: { try await $0.toggleSteeringWheelHeater() },
        ),

        // MARK: Vehicle
        CatalogCommand(
            id: "charge.port.open",
            title: "Open Charge Port",
            systemImage: "bolt.fill",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.openChargePort() },
        ),
        CatalogCommand(
            id: "charge.port.close",
            title: "Close Charge Port",
            systemImage: "bolt.slash.fill",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.closeChargePort() },
        ),
        CatalogCommand(
            id: "trunk.actuate",
            title: "Trunk",
            systemImage: "car.side.rear.open",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.actuateTrunk() },
        ),
        CatalogCommand(
            id: "frunk.actuate",
            title: "Frunk",
            systemImage: "car.side.front.open",
            section: .vehicle,
            confirmation: .confirm,
            action: { try await $0.actuateFrunk() },
        ),
        CatalogCommand(
            id: "security.lock",
            title: "Lock",
            systemImage: "lock.fill",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.lock() },
        ),
        CatalogCommand(
            id: "security.unlock",
            title: "Unlock",
            systemImage: "lock.open.fill",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.unlock() },
        ),
        CatalogCommand(
            id: "windows.vent",
            title: "Vent Windows",
            systemImage: "wind",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.ventWindows() },
        ),
        CatalogCommand(
            id: "windows.close",
            title: "Close Windows",
            systemImage: "arrow.down.circle",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.closeWindows() },
        ),
        // Toggles based on the car-reported state.
        CatalogCommand(
            id: "sentry.toggle",
            title: "Sentry",
            systemImage: "shield.fill",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.toggleSentry() },
        ),
        CatalogCommand(
            id: "charge.limit.80",
            title: "Limit 80%",
            systemImage: "battery.75",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.setChargeLimit(percent: 80) },
        ),
        CatalogCommand(
            id: "charge.limit.100",
            title: "Limit 100%",
            systemImage: "battery.100",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.setChargeLimit(percent: 100) },
        ),
        CatalogCommand(
            id: "lights.flash",
            title: "Flash",
            systemImage: "rays",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.flashLights() },
        ),
        CatalogCommand(
            id: "horn.honk",
            title: "Honk",
            systemImage: "horn.fill",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.honk() },
        ),
        CatalogCommand(
            id: "vehicle.wake",
            title: "Wake",
            systemImage: "sun.max.fill",
            section: .vehicle,
            confirmation: .none,
            action: { try await $0.wake() },
        ),
    ]

    static func command(id: String) -> CatalogCommand? {
        all.first { $0.id == id }
    }
}
