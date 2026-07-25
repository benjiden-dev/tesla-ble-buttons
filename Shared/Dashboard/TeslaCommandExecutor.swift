//
//  TeslaCommandExecutor.swift
//  TeslaButtons
//
//  The seam between dashboard tiles and the BLE stack. Stateless: every
//  call routes through the process-wide `VehicleService`, which owns the
//  single `TeslaVehicleClient`, connects on demand (with retry), keeps the
//  session warm for repeat taps, and tears it down when idle.
//
//  Do NOT construct a second TeslaVehicleClient here — the signed protocol
//  keeps per-session anti-replay counters and parallel clients on the same
//  key will fight. This also means the dashboard needs no "connect at app
//  launch" wiring: the first command (or the snapshot poll, once connected
//  elsewhere) brings the session up on demand.
//
//  All case names below are verified against the library's Command.swift.
//

import Foundation
import TeslaBLE

struct TeslaCommandExecutor {
    func climateOn() async throws {
        try await VehicleService.shared.run(.climate(.on))
    }

    /// Sets both front zones. The wire signature is
    /// `.climate(.setTemperature(driver: Float, passenger: Float))` in °C.
    func setTemperature(fahrenheit: Double) async throws {
        let celsius = Float((fahrenheit - 32) * 5 / 9)
        try await VehicleService.shared.run(
            .climate(.setTemperature(driver: celsius, passenger: celsius)),
        )
    }

    /// Max defrost via the dedicated preconditioning case — no temperature
    /// hack needed. `manualOverride: true` marks it user-initiated.
    func maxDefrost() async throws {
        try await VehicleService.shared.run(
            .climate(.setPreconditioningMax(enabled: true, manualOverride: true)),
        )
    }

    func openChargePort() async throws {
        try await VehicleService.shared.run(.charge(.openPort))
    }

    func closeChargePort() async throws {
        try await VehicleService.shared.run(.charge(.closePort))
    }

    /// Opens or closes the powered trunk (toggle).
    func actuateTrunk() async throws {
        try await VehicleService.shared.run(.security(.actuateTrunk))
    }

    /// Frunk is open-only on the wire; there is no close/actuate case.
    func actuateFrunk() async throws {
        try await VehicleService.shared.run(.security(.openFrunk))
    }

    /// Media cases are `.togglePlayback` / `.nextTrack` / `.previousTrack`.
    func mediaPlayPause() async throws {
        try await VehicleService.shared.run(.media(.togglePlayback))
    }

    func mediaNext() async throws {
        try await VehicleService.shared.run(.media(.nextTrack))
    }

    func mediaPrevious() async throws {
        try await VehicleService.shared.run(.media(.previousTrack))
    }

    /// Full state snapshot, but only when a session is already live — nil
    /// otherwise, so the dashboard's poll never triggers endless BLE scan
    /// timeouts while you're away from the car.
    func snapshotIfConnected() async throws -> TeslaVehicleSnapshot? {
        try await VehicleService.shared.fetchSnapshotIfConnected()
    }
}
