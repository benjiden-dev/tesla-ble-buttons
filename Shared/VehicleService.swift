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

/// How a command request concluded. `alreadySatisfied` means the vehicle (or
/// a preemptive state check) reported the requested state is already in
/// effect — the goal is met, so callers should treat it as success and at
/// most show a quiet notice.
enum CommandOutcome: Sendable {
    case executed
    case alreadySatisfied(reason: String?)
}

actor VehicleService {
    static let shared = VehicleService()

    private let keyStore = KeychainTeslaKeyStore(service: AppConstants.keychainService)
    private let logger = Logger(subsystem: AppConstants.bundleRoot, category: "vehicle-service")

    /// Sink for the TeslaBLE library's internal logs. Without this the
    /// library discards them silently — see DiagnosticsLog.
    private static let bleLogger = AppTeslaBLELogger()

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
        if state != latestState {
            Diag.log("conn", "state → \(state)")
        }
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

        let pairingClient = TeslaVehicleClient(vin: vin, keyStore: keyStore, logger: Self.bleLogger)
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
    ///
    /// Vehicles reject redundant commands (e.g. setting the charge limit to
    /// its current value) with an "already …" style reason. Those are
    /// treated as success (`.alreadySatisfied`) rather than thrown — the
    /// requested state is in effect either way.
    @discardableResult
    func run(_ command: Command) async throws -> CommandOutcome {
        let session = try await ensureConnected()
        do {
            try await session.send(command)
            scheduleIdleTeardown()
            Diag.log("cmd", "sent \(command)")
            return .executed
        } catch let error as TeslaBLEError {
            scheduleIdleTeardown()
            if case .commandRejected(_, let reason) = error, Self.isBenignRejection(reason) {
                logger.info("redundant command (\(reason ?? "already set", privacy: .public)) — treated as success")
                Diag.log("cmd", "already satisfied: \(command) — \(reason ?? "already set")")
                return .alreadySatisfied(reason: reason)
            }
            logger.error("command failed: \(String(describing: error), privacy: .public)")
            Diag.log("cmd/error", "\(command) failed: \(error)")
            throw error
        } catch {
            scheduleIdleTeardown()
            logger.error("command failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Rejection reasons that mean "the requested state is already true".
    /// Deliberately narrow — unknown reasons stay errors.
    private static func isBenignRejection(_ reason: String?) -> Bool {
        guard let reason = reason?.lowercased() else { return false }
        return reason.contains("already")
            || reason.contains("not_charging")
            || reason.contains("not charging")
            || reason.contains("is_charging")
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

    /// Fetches a full state snapshot, but only when a session is already
    /// live — returns nil otherwise so UI polls never trigger BLE scan
    /// loops while away from the car. Refreshes the idle-teardown window
    /// like any other traffic, and feeds the short-lived state cache used
    /// for preemptive no-op checks.
    func fetchSnapshotIfConnected() async throws -> TeslaVehicleSnapshot? {
        guard let existing = client else { return nil }
        let state = await existing.state
        guard state == .connected else { return nil }
        let snapshot = try await existing.fetch(.all)
        cachedSnapshotValue = snapshot
        cachedSnapshotAt = Date()
        scheduleIdleTeardown()
        return snapshot
    }

    private var cachedSnapshotValue: TeslaVehicleSnapshot?
    private var cachedSnapshotAt: Date?

    /// Media-only fetch. Some firmware omits media sections from the
    /// combined `.all` response even while a track is playing; requesting
    /// the two media categories on their own reliably returns them.
    /// Connected-only, like the other fetches.
    func fetchMediaIfConnected() async throws -> (MediaState?, MediaDetailState?)? {
        guard let existing = client else { return nil }
        let state = await existing.state
        guard state == .connected else { return nil }
        let snapshot = try await existing.fetch(.categories([.media, .mediaDetail]))
        scheduleIdleTeardown()
        // Mirrored into the in-app log too — this is the line that answers
        // whether missing now-playing info is car-side or ours (issue #4).
        // The string is an autoclosure, so with capture off it's never
        // built — this runs on every fallback fetch.
        Diag.log(
            "media",
            """
            targeted fetch: mediaSection=\(snapshot.media == nil ? "NIL" : "present") \
            detailSection=\(snapshot.mediaDetail == nil ? "NIL" : "present") \
            title=\(snapshot.media?.nowPlayingTitle ?? "nil") \
            artist=\(snapshot.media?.nowPlayingArtist ?? "nil") \
            album=\(snapshot.mediaDetail?.nowPlayingAlbum ?? "nil") \
            station=\(snapshot.mediaDetail?.nowPlayingStation ?? "nil") \
            source=\(snapshot.mediaDetail?.nowPlayingSource ?? "nil") \
            a2dp=\(snapshot.mediaDetail?.a2dpSourceName ?? "nil") \
            remote=\(String(describing: snapshot.media?.remoteControlEnabled))
            """,
        )
        return (snapshot.media, snapshot.mediaDetail)
    }

    /// Drive-state fast path (a few hundred ms round-trip, designed for
    /// gauge-speed polling). Connected-only, same contract as
    /// `fetchSnapshotIfConnected` — nil without a live session.
    func fetchDriveIfConnected() async throws -> DriveState? {
        guard let existing = client else { return nil }
        let state = await existing.state
        guard state == .connected else { return nil }
        let drive = try await existing.fetchDrive()
        scheduleIdleTeardown()
        return drive
    }

    /// The most recent snapshot if it's fresh enough (default 20s — the
    /// dashboard polls every 5s while visible). Used to skip commands whose
    /// target state is already true, without a live round-trip per tap.
    func cachedSnapshot(maxAge: TimeInterval = 20) -> TeslaVehicleSnapshot? {
        guard
            let cachedSnapshotValue,
            let cachedSnapshotAt,
            Date().timeIntervalSince(cachedSnapshotAt) <= maxAge
        else { return nil }
        return cachedSnapshotValue
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

        let newClient = TeslaVehicleClient(vin: vin, keyStore: keyStore, logger: Self.bleLogger)
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
