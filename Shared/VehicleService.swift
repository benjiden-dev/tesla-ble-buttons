//
//  VehicleService.swift
//  TeslaButtons
//
//  Shared gateway to the vehicle for BOTH the SwiftUI app and App Intents.
//
//  One process-wide instance owns at most one `TeslaVehicleClient`. App
//  Intents (Siri / Action button / Control Center) are forced to run in the
//  app's process (see RunTeslaCommandIntent), so this single actor serializes
//  all BLE work and no two clients ever fight over the same key/session —
//  which matters because the signed protocol keeps per-session counters.
//

import CryptoKit
import Foundation
import OSLog
import TeslaBLE

actor VehicleService {
    static let shared = VehicleService()

    private let keyStore = KeychainTeslaKeyStore(service: AppConstants.keychainService)
    private let logger = Logger(subsystem: AppConstants.bundleRoot, category: "vehicle-service")

    private var client: TeslaVehicleClient?
    private var forwardTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?

    /// While true (app UI visible), the idle timer never tears the session down.
    private var pinned = false

    private var continuations: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]
    private(set) var latestState: ConnectionState = .disconnected

    // MARK: - State observation

    /// A stream of connection-state changes, starting with the current state.
    /// Multiple observers are supported (the app UI is the main consumer).
    func states() -> AsyncStream<ConnectionState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectionState.self)
        continuation.yield(latestState)
        continuations[id] = continuation
        continuation.onTermination = { _ in
            Task { await self.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func broadcast(_ state: ConnectionState) {
        latestState = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    // MARK: - Pairing

    /// First-time key enrollment. Run while sitting in the car with an NFC
    /// key card handy: immediately after this call is sent, tap the card on
    /// the center console and confirm the new key on the vehicle's screen.
    func pair(vin: String) async throws {
        guard vin.count == 17 else { throw TeslaButtonsError.invalidVIN }

        // Reuse an existing key if present so re-pairing is idempotent.
        let privateKey: P256.KeyAgreement.PrivateKey
        if let existing = try keyStore.loadPrivateKey(forVIN: vin) {
            privateKey = existing
        } else {
            privateKey = KeyPairFactory.generateKeyPair()
            try keyStore.savePrivateKey(privateKey, forVIN: vin)
        }
        let publicKey = KeyPairFactory.publicKeyBytes(of: privateKey)

        await teardown()

        let pairingClient = TeslaVehicleClient(vin: vin, keyStore: keyStore)
        do {
            try await pairingClient.connect(mode: .pairing)
            try await pairingClient.send(
                .security(.addKey(publicKey: publicKey, role: .owner, formFactor: .iosDevice)),
            )
            await pairingClient.disconnect()
        } catch {
            await pairingClient.disconnect()
            throw error
        }

        PairedVehicle.set(vin)
    }

    /// Drops the session, deletes the local private key, and forgets the VIN.
    /// Also remove the key from the car itself: Controls → Locks on the screen.
    func forget() async throws {
        let vin = PairedVehicle.storedVIN
        await teardown()
        if let vin {
            try keyStore.deletePrivateKey(forVIN: vin)
        }
        PairedVehicle.set(nil)
    }

    // MARK: - Commands

    /// Ensures a live signed session, sends the command, then (when the app
    /// UI isn't in the foreground) schedules an idle teardown so background
    /// launches don't hold BLE forever.
    func run(_ command: Command) async throws {
        let session = try await ensureConnected()
        try await session.send(command)
        scheduleIdleTeardown()
    }

    func setPinned(_ value: Bool) {
        pinned = value
        if value {
            idleTask?.cancel()
            idleTask = nil
        } else if client != nil {
            scheduleIdleTeardown()
        }
    }

    func connectNow() async throws {
        _ = try await ensureConnected()
    }

    func disconnectNow() async {
        await teardown()
    }

    // MARK: - Internals

    private static let maxConnectAttempts = 2
    private static let connectRetryDelay: Duration = .seconds(1)

    private func ensureConnected() async throws -> TeslaVehicleClient {
        if let existing = client {
            let state = await existing.state
            if state == .connected {
                return existing
            }
        }
        await teardown()

        guard let vin = PairedVehicle.storedVIN else {
            throw TeslaButtonsError.notPaired
        }

        let newClient = TeslaVehicleClient(vin: vin, keyStore: keyStore)
        client = newClient

        forwardTask = Task { [weak self] in
            for await state in newClient.stateStream {
                guard let self else { return }
                await self.broadcast(state)
            }
        }

        var lastError: Error = TeslaBLEError.scanTimeout
        for attempt in 1 ... Self.maxConnectAttempts {
            do {
                try await newClient.connect(mode: .normal)
                return newClient
            } catch let error as TeslaBLEError
                where Self.isRetryable(error) && attempt < Self.maxConnectAttempts
            {
                logger.debug("connect attempt \(attempt, privacy: .public) failed; retrying")
                lastError = error
                try? await Task.sleep(for: Self.connectRetryDelay)
            } catch {
                await teardown()
                throw error
            }
        }
        await teardown()
        throw lastError
    }

    /// Transient BLE races worth one retry. Handshake / auth / keystore
    /// errors are configuration problems retrying won't fix.
    private static func isRetryable(_ error: TeslaBLEError) -> Bool {
        switch error {
        case .scanTimeout, .connectionFailed:
            true
        default:
            false
        }
    }

    private func scheduleIdleTeardown() {
        guard !pinned else { return }
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConstants.idleDisconnectSeconds))
            guard !Task.isCancelled else { return }
            await self?.disconnectNow()
        }
    }

    private func teardown() async {
        idleTask?.cancel()
        idleTask = nil
        forwardTask?.cancel()
        forwardTask = nil
        if let client {
            await client.disconnect()
        }
        client = nil
        broadcast(.disconnected)
    }
}
