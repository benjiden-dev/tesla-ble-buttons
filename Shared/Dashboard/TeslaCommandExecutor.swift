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
//  key will fight.
//
//  All case names below are verified against the library's Command.swift.
//

import Foundation
import TeslaBLE

struct TeslaCommandExecutor {
    // MARK: - App-level control enums
    // Views use these instead of the library's nested wire enums.

    enum KeeperMode: String, CaseIterable, Sendable {
        case off, on, dog, camp

        var label: String {
            switch self {
            case .off: "Off"
            case .on: "Keep"
            case .dog: "Dog"
            case .camp: "Camp"
            }
        }
    }

    enum VentLevel: Int, CaseIterable, Sendable {
        case off = 0, low, medium, high

        var label: String {
            switch self {
            case .off: "Off"
            case .low: "1"
            case .medium: "2"
            case .high: "3"
            }
        }

        /// Cycle order for the dashboard's one-button control:
        /// Off → 1 → 2 → 3 → Off.
        var next: VentLevel {
            switch self {
            case .off: .low
            case .low: .medium
            case .medium: .high
            case .high: .off
            }
        }
    }

    enum FrontSeat: String, Sendable {
        case driver, passenger
    }

    // MARK: - Climate

    func climateOn() async throws {
        try await VehicleService.shared.run(.climate(.on))
    }

    func climateOff() async throws {
        try await VehicleService.shared.run(.climate(.off))
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

    /// Climate Keeper (Off / Keep / Dog / Camp). Note: the vehicle snapshot
    /// does not report keeper state back, so callers track last-sent locally.
    func setKeeperMode(_ mode: KeeperMode) async throws {
        let wire: Command.Climate.ClimateKeeperMode =
            switch mode {
            case .off: .off
            case .on: .on
            case .dog: .dog
            case .camp: .camp
            }
        try await VehicleService.shared.run(.climate(.setKeeperMode(wire)))
    }

    /// Seat ventilation (front seats only — the hardware has no rear vents).
    /// Driver maps to frontLeft (LHD/US). Snapshot does not report cooler
    /// levels back, so callers track last-sent locally.
    func setSeatCooler(level: VentLevel, seat: FrontSeat) async throws {
        let wireLevel: Command.Climate.SeatCoolerLevel =
            switch level {
            case .off: .off
            case .low: .low
            case .medium: .medium
            case .high: .high
            }
        let wireSeat: Command.Climate.FrontSeatPosition =
            seat == .driver ? .frontLeft : .frontRight
        try await VehicleService.shared.run(
            .climate(.setSeatCooler(level: wireLevel, seat: wireSeat)),
        )
    }

    /// Cycles the seat heater Off → 1 → 2 → 3 → Off using the car-reported
    /// current level (the snapshot DOES report seat heaters, unlike vents).
    /// Falls back to Low when no live state is available yet.
    func cycleSeatHeater(seat: FrontSeat) async throws {
        let snap = try await snapshotIfConnected()
        let reported = seat == .driver
            ? snap?.climate?.seatHeaterFrontLeft
            : snap?.climate?.seatHeaterFrontRight
        let nextRaw = ((reported?.rawValue ?? 0) + 1) % 4
        let wireLevel: Command.Climate.SeatHeaterLevel =
            switch nextRaw {
            case 1: .low
            case 2: .medium
            case 3: .high
            default: .off
            }
        let wireSeat: Command.Climate.SeatPosition =
            seat == .driver ? .frontLeft : .frontRight
        try await VehicleService.shared.run(
            .climate(.setSeatHeater(level: wireLevel, seat: wireSeat)),
        )
    }

    /// Flips the steering wheel heater based on car-reported state
    /// (defaults to turning it on when no state is available).
    func toggleSteeringWheelHeater() async throws {
        let snap = try await snapshotIfConnected()
        let currentlyOn = snap?.climate?.steeringWheelHeater ?? false
        try await VehicleService.shared.run(.climate(.setSteeringWheelHeater(!currentlyOn)))
    }

    // MARK: - Charge

    func openChargePort() async throws {
        try await VehicleService.shared.run(.charge(.openPort))
    }

    func closeChargePort() async throws {
        try await VehicleService.shared.run(.charge(.closePort))
    }

    /// Charge limit as a percentage (e.g. 80 for daily, 100 for trips).
    func setChargeLimit(percent: Int) async throws {
        try await VehicleService.shared.run(.charge(.setLimit(percent: Int32(percent))))
    }

    // MARK: - Security & closures

    func lock() async throws {
        try await VehicleService.shared.run(.security(.lock))
    }

    func unlock() async throws {
        try await VehicleService.shared.run(.security(.unlock))
    }

    func wake() async throws {
        try await VehicleService.shared.run(.security(.wakeVehicle))
    }

    /// Flips Sentry Mode based on car-reported state (closures snapshot
    /// reports sentryModeActive; defaults to enabling when unknown).
    func toggleSentry() async throws {
        let snap = try await snapshotIfConnected()
        let currentlyOn = snap?.closures?.sentryModeActive ?? false
        try await VehicleService.shared.run(.security(.setSentryMode(!currentlyOn)))
    }

    /// Opens or closes the powered trunk (toggle).
    func actuateTrunk() async throws {
        try await VehicleService.shared.run(.security(.actuateTrunk))
    }

    /// Frunk is open-only on the wire; there is no close/actuate case.
    func actuateFrunk() async throws {
        try await VehicleService.shared.run(.security(.openFrunk))
    }

    // MARK: - Actions

    func ventWindows() async throws {
        try await VehicleService.shared.run(.actions(.ventWindows))
    }

    func closeWindows() async throws {
        try await VehicleService.shared.run(.actions(.closeWindows))
    }

    func flashLights() async throws {
        try await VehicleService.shared.run(.actions(.flashLights))
    }

    func honk() async throws {
        try await VehicleService.shared.run(.actions(.honk))
    }

    // MARK: - Media

    func mediaPlayPause() async throws {
        try await VehicleService.shared.run(.media(.togglePlayback))
    }

    func mediaNext() async throws {
        try await VehicleService.shared.run(.media(.nextTrack))
    }

    func mediaPrevious() async throws {
        try await VehicleService.shared.run(.media(.previousTrack))
    }

    func volumeUp() async throws {
        try await VehicleService.shared.run(.media(.volumeUp))
    }

    func volumeDown() async throws {
        try await VehicleService.shared.run(.media(.volumeDown))
    }

    // MARK: - State

    /// Full state snapshot, but only when a session is already live — nil
    /// otherwise, so the dashboard's poll never triggers endless BLE scan
    /// timeouts while you're away from the car.
    func snapshotIfConnected() async throws -> TeslaVehicleSnapshot? {
        try await VehicleService.shared.fetchSnapshotIfConnected()
    }
}
