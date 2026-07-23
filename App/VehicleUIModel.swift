//
//  VehicleUIModel.swift
//  TeslaButtons
//
//  Main-actor observable bridging VehicleService to SwiftUI. The service is
//  the single source of truth; this model mirrors its state for bindings and
//  owns per-tap busy/error presentation.
//

import Observation
import SwiftUI
import TeslaBLE

@MainActor
@Observable
final class VehicleUIModel {
    var vin: String? = PairedVehicle.storedVIN
    var connectionState: ConnectionState = .disconnected
    var busyCommand: TeslaButtonCommand?
    var isPairing = false
    var isBusy = false
    var lastError: String?

    private var observationTask: Task<Void, Never>?

    func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            let stream = await VehicleService.shared.states()
            for await state in stream {
                self?.connectionState = state
            }
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        Task {
            await VehicleService.shared.setPinned(phase == .active)
            // Warm the session whenever the app comes forward with a paired car.
            if phase == .active, vin != nil {
                try? await VehicleService.shared.connectNow()
            }
        }
    }

    func pair(rawVIN: String) {
        let candidate = rawVIN
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !isPairing else { return }
        isPairing = true
        lastError = nil
        Task {
            do {
                try await VehicleService.shared.pair(vin: candidate)
                vin = candidate
            } catch {
                lastError = Self.message(for: error)
            }
            isPairing = false
        }
    }

    func forget() {
        Task {
            do {
                try await VehicleService.shared.forget()
                vin = nil
            } catch {
                lastError = Self.message(for: error)
            }
        }
    }

    func run(_ command: TeslaButtonCommand) {
        guard busyCommand == nil, !isBusy else { return }
        busyCommand = command
        lastError = nil
        Task {
            do {
                try await VehicleService.shared.run(command.bleCommand)
            } catch {
                lastError = Self.message(for: error)
            }
            busyCommand = nil
        }
    }

    func startClimate(fahrenheit: Int) {
        guard busyCommand == nil, !isBusy else { return }
        isBusy = true
        busyCommand = .climateOn
        lastError = nil
        Task {
            do {
                let celsius = Float(fahrenheit - 32) * 5.0 / 9.0
                try await VehicleService.shared.run(.climate(.on))
                try await VehicleService.shared.run(
                    .climate(.setTemperature(driver: celsius, passenger: celsius)),
                )
            } catch {
                lastError = Self.message(for: error)
            }
            busyCommand = nil
            isBusy = false
        }
    }

    var statusLabel: String {
        switch connectionState {
        case .disconnected: "Disconnected"
        case .scanning: "Scanning…"
        case .connecting: "Connecting…"
        case .handshaking: "Authenticating…"
        case .connected: "Connected"
        }
    }

    var statusColor: Color {
        switch connectionState {
        case .connected: .green
        case .disconnected: .secondary
        default: .orange
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return String(describing: error)
    }
}
