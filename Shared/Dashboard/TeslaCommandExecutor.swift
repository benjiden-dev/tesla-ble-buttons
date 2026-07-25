//
//  TeslaCommandExecutor.swift
//  TeslaButtons
//
//  The seam between dashboard tiles and the BLE stack. Stateless: every
//  call routes through the process-wide `VehicleService`, which owns the
//  single `TeslaVehicleClient`, connects on demand (with retry), keeps the
//  session warm for repeat taps, and tears it down when idle.
//
//  Graceful no-op handling: methods return `CommandOutcome`. Where the
//  vehicle snapshot reports the relevant state, methods preemptively skip
//  commands whose target state is already true (using VehicleService's
//  short-lived cache — no extra round-trip). Redundant sends the vehicle
//  rejects with "already …" are also converted to `.alreadySatisfied` by
//  VehicleService.run rather than thrown.
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

    /// Fresh-enough cached state for preemptive no-op checks (nil when the
    /// last snapshot is older than ~20s or none exists).
    private func cached() async -> TeslaVehicleSnapshot? {
        await VehicleService.shared.cachedSnapshot()
    }

    // MARK: - Climate

    @discardableResult
    func climateOn() async throws -> CommandOutcome {
        if await cached()?.climate?.isClimateOn == true {
            return .alreadySatisfied(reason: "climate already on")
        }
        return try await VehicleService.shared.run(.climate(.on))
    }

    @discardableResult
    func climateOff() async throws -> CommandOutcome {
        if await cached()?.climate?.isClimateOn == false {
            return .alreadySatisfied(reason: "climate already off")
        }
        return try await VehicleService.shared.run(.climate(.off))
    }

    /// Sets both front zones. The wire signature is
    /// `.climate(.setTemperature(driver: Float, passenger: Float))` in °C.
    @discardableResult
    func setTemperature(fahrenheit: Double) async throws -> CommandOutcome {
        let celsius = Float((fahrenheit - 32) * 5 / 9)
        return try await VehicleService.shared.run(
            .climate(.setTemperature(driver: celsius, passenger: celsius)),
        )
    }

    /// Max defrost via the dedicated preconditioning case — no temperature
    /// hack needed. `manualOverride: true` marks it user-initiated.
    @discardableResult
    func maxDefrost() async throws -> CommandOutcome {
        try await VehicleService.shared.run(
            .climate(.setPreconditioningMax(enabled: true, manualOverride: true)),
        )
    }

    /// Climate Keeper (Off / Keep / Dog / Camp). Note: the vehicle snapshot
    /// does not report keeper state back, so callers track last-sent locally.
    @discardableResult
    func setKeeperMode(_ mode: KeeperMode) async throws -> CommandOutcome {
        let wire: Command.Climate.ClimateKeeperMode =
            switch mode {
            case .off: .off
            case .on: .on
            case .dog: .dog
            case .camp: .camp
            }
        return try await VehicleService.shared.run(.climate(.setKeeperMode(wire)))
    }

    /// Seat ventilation (front seats only — the hardware has no rear vents).
    /// Driver maps to frontLeft (LHD/US). Snapshot does not report cooler
    /// levels back, so callers track last-sent locally.
    @discardableResult
    func setSeatCooler(level: VentLevel, seat: FrontSeat) async throws -> CommandOutcome {
        let wireLevel: Command.Climate.SeatCoolerLevel =
            switch level {
            case .off: .off
            case .low: .low
            case .medium: .medium
            case .high: .high
            }
        let wireSeat: Command.Climate.FrontSeatPosition =
            seat == .driver ? .frontLeft : .frontRight
        return try await VehicleService.shared.run(
            .climate(.setSeatCooler(level: wireLevel, seat: wireSeat)),
        )
    }

    /// Cycles the seat heater Off → 1 → 2 → 3 → Off using the car-reported
    /// current level (the snapshot DOES report seat heaters, unlike vents).
    /// Falls back to Low when no live state is available yet.
    @discardableResult
    func cycleSeatHeater(seat: FrontSeat) async throws -> CommandOutcome {
        let snap = await cached() ?? (try await snapshotIfConnected())
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
        return try await VehicleService.shared.run(
            .climate(.setSeatHeater(level: wireLevel, seat: wireSeat)),
        )
    }

    /// Flips the steering wheel heater based on car-reported state
    /// (defaults to turning it on when no state is available).
    @discardableResult
    func toggleSteeringWheelHeater() async throws -> CommandOutcome {
        let snap = await cached() ?? (try await snapshotIfConnected())
        let currentlyOn = snap?.climate?.steeringWheelHeater ?? false
        return try await VehicleService.shared.run(.climate(.setSteeringWheelHeater(!currentlyOn)))
    }

    // MARK: - Charge

    @discardableResult
    func openChargePort() async throws -> CommandOutcome {
        if await cached()?.charge?.chargePortOpen == true {
            return .alreadySatisfied(reason: "charge port already open")
        }
        return try await VehicleService.shared.run(.charge(.openPort))
    }

    @discardableResult
    func closeChargePort() async throws -> CommandOutcome {
        if await cached()?.charge?.chargePortOpen == false {
            return .alreadySatisfied(reason: "charge port already closed")
        }
        return try await VehicleService.shared.run(.charge(.closePort))
    }

    /// Charge limit as a percentage (e.g. 80 for daily, 100 for trips).
    @discardableResult
    func setChargeLimit(percent: Int) async throws -> CommandOutcome {
        if let current = await cached()?.charge?.chargeLimitPercent, current == percent {
            return .alreadySatisfied(reason: "charge limit already \(percent)%")
        }
        return try await VehicleService.shared.run(.charge(.setLimit(percent: Int32(percent))))
    }

    // MARK: - Security & closures

    @discardableResult
    func lock() async throws -> CommandOutcome {
        if await cached()?.closures?.locked == true {
            return .alreadySatisfied(reason: "already locked")
        }
        return try await VehicleService.shared.run(.security(.lock))
    }

    @discardableResult
    func unlock() async throws -> CommandOutcome {
        if await cached()?.closures?.locked == false {
            return .alreadySatisfied(reason: "already unlocked")
        }
        return try await VehicleService.shared.run(.security(.unlock))
    }

    @discardableResult
    func wake() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.security(.wakeVehicle))
    }

    /// Flips Sentry Mode based on car-reported state (closures snapshot
    /// reports sentryModeActive; defaults to enabling when unknown).
    @discardableResult
    func toggleSentry() async throws -> CommandOutcome {
        let snap = await cached() ?? (try await snapshotIfConnected())
        let currentlyOn = snap?.closures?.sentryModeActive ?? false
        return try await VehicleService.shared.run(.security(.setSentryMode(!currentlyOn)))
    }

    /// Opens or closes the powered trunk (toggle) — never preempted.
    @discardableResult
    func actuateTrunk() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.security(.actuateTrunk))
    }

    /// Frunk is open-only on the wire; there is no close/actuate case.
    /// Preempted when the car already reports it open.
    @discardableResult
    func actuateFrunk() async throws -> CommandOutcome {
        if await cached()?.closures?.frontTrunk == true {
            return .alreadySatisfied(reason: "frunk already open")
        }
        return try await VehicleService.shared.run(.security(.openFrunk))
    }

    // MARK: - Actions

    @discardableResult
    func ventWindows() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.actions(.ventWindows))
    }

    @discardableResult
    func closeWindows() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.actions(.closeWindows))
    }

    @discardableResult
    func flashLights() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.actions(.flashLights))
    }

    @discardableResult
    func honk() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.actions(.honk))
    }

    // MARK: - Media

    @discardableResult
    func mediaPlayPause() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.media(.togglePlayback))
    }

    @discardableResult
    func mediaNext() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.media(.nextTrack))
    }

    @discardableResult
    func mediaPrevious() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.media(.previousTrack))
    }

    @discardableResult
    func volumeUp() async throws -> CommandOutcome {
        try await VehicleService.shared.run(.media(.volumeUp))
    }

    @discardableResult
    func volumeDown() async throws -> CommandOutcome {
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
