//
//  CommandCatalog.swift
//  TeslaButtons
//
//  Everything the dashboard is allowed to expose. Add new entries here,
//  then they become addable from the Edit → Add Function sheet
//  automatically — no other wiring needed.
//

import Foundation

enum ConfirmationRequirement: Sendable {
    case none
    case confirm
}

struct CatalogCommand: Identifiable, Sendable {
    let id: String
    let title: String
    let systemImage: String
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
        CatalogCommand(
            id: "climate.preset.68",
            title: "Climate 68°F",
            systemImage: "thermometer.low",
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
            confirmation: .none,
            action: { executor in
                try await executor.climateOn()
                try await executor.maxDefrost()
            },
        ),
        CatalogCommand(
            id: "charge.port.open",
            title: "Open Charge Port",
            systemImage: "bolt.fill",
            confirmation: .none,
            action: { try await $0.openChargePort() },
        ),
        CatalogCommand(
            id: "charge.port.close",
            title: "Close Charge Port",
            systemImage: "bolt.slash.fill",
            confirmation: .none,
            action: { try await $0.closeChargePort() },
        ),
        CatalogCommand(
            id: "trunk.actuate",
            title: "Trunk",
            systemImage: "car.side.rear.open",
            confirmation: .none,
            action: { try await $0.actuateTrunk() },
        ),
        CatalogCommand(
            id: "frunk.actuate",
            title: "Frunk",
            systemImage: "car.side.front.open",
            confirmation: .confirm,
            action: { try await $0.actuateFrunk() },
        ),
        CatalogCommand(
            id: "media.playPause",
            title: "Play / Pause",
            systemImage: "playpause.fill",
            confirmation: .none,
            action: { try await $0.mediaPlayPause() },
        ),
        CatalogCommand(
            id: "media.next",
            title: "Next Track",
            systemImage: "forward.fill",
            confirmation: .none,
            action: { try await $0.mediaNext() },
        ),
        CatalogCommand(
            id: "media.previous",
            title: "Previous Track",
            systemImage: "backward.fill",
            confirmation: .none,
            action: { try await $0.mediaPrevious() },
        ),
    ]

    static func command(id: String) -> CatalogCommand? {
        all.first { $0.id == id }
    }
}
