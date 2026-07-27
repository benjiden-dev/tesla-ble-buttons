//
//  DiagnosticsLog.swift
//  TeslaButtons
//
//  In-app ring buffer of diagnostic lines, mirrored to os.Logger.
//
//  Console.app is awkward to use while sitting in a car, so everything also
//  lands here and is viewable (and shareable) from Settings → Diagnostics.
//  Also serves as the sink for the TeslaBLE library's internal logging,
//  which is otherwise dropped entirely — TeslaVehicleClient silently
//  discards its logs unless a logger is supplied at init.
//
//  ── Failsafes ────────────────────────────────────────────────────────────
//  Capture is OFF by default and never persists across launches, so normal
//  driving costs nothing. When enabled it:
//    • auto-disables after `sessionTimeout` (no way to leave it running),
//    • caps the buffer at `capacity` entries (bounded memory),
//    • truncates any single message to `maxMessageLength`,
//    • coalesces identical consecutive messages into a repeat count, so a
//      retry loop can't flood the buffer,
//    • drops library logs below `.info` without building their strings.
//  While disabled, `Diag.log` returns after one atomic read — no Task is
//  spawned, no string is interpolated at the call site's autoclosure.
//
//  Concurrency: the store is @MainActor (it drives SwiftUI). Callers from
//  other isolation domains — the VehicleService actor, the library's
//  Sendable logger shim — go through `Diag.log`, which is nonisolated and
//  hops to the main actor. Never reference `DiagnosticsLog.shared` directly
//  from an actor or nonisolated context.
//

import Foundation
import os
import OSLog
import TeslaBLE

struct DiagnosticEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let category: String
    var message: String
    /// Number of identical consecutive occurrences collapsed into this row.
    var repeatCount: Int = 1

    var timestamp: String {
        date.formatted(.dateTime.hour().minute().second())
    }

    var displayMessage: String {
        repeatCount > 1 ? "\(message)  (×\(repeatCount))" : message
    }

    var line: String {
        "\(timestamp)  [\(category)] \(displayMessage)"
    }
}

/// Nonisolated logging entry point, safe to call from anywhere.
///
/// The `message` parameter is an autoclosure so that when capture is off —
/// the normal state — the string is never even built.
enum Diag {
    /// Cheap, thread-safe gate checked before any work happens.
    private static let enabled = OSAllocatedUnfairLock(initialState: false)

    static var isEnabled: Bool {
        enabled.withLock { $0 }
    }

    static func setEnabled(_ value: Bool) {
        enabled.withLock { $0 = value }
    }

    static func log(_ category: String, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        Task { @MainActor in
            DiagnosticsLog.shared.append(category: category, text)
        }
    }

    /// Bypasses the gate for explicitly user-initiated output (the raw data
    /// dump), which should work even if capture was never switched on.
    static func logForced(_ category: String, _ message: String) {
        Task { @MainActor in
            DiagnosticsLog.shared.append(category: category, message)
        }
    }
}

@MainActor
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    /// Newest first, capped so a long drive can't grow without bound.
    private(set) var entries: [DiagnosticEntry] = []

    /// Mirrors `Diag.isEnabled` for SwiftUI binding; setting it also arms or
    /// cancels the auto-disable timer.
    var isCapturing = false {
        didSet {
            guard isCapturing != oldValue else { return }
            Diag.setEnabled(isCapturing)
            expiryTask?.cancel()
            expiryTask = nil
            if isCapturing {
                append(category: "diag", "capture on (auto-off in \(Self.sessionTimeoutMinutes) min)")
                expiryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.sessionTimeoutMinutes * 60))
                    guard !Task.isCancelled else { return }
                    self?.isCapturing = false
                }
            } else {
                append(category: "diag", "capture off")
            }
        }
    }

    private static let capacity = 500
    private static let maxMessageLength = 512
    private static let sessionTimeoutMinutes = 15

    private var expiryTask: Task<Void, Never>?
    private let logger = Logger(subsystem: AppConstants.bundleRoot, category: "diagnostics")

    func append(category: String, _ message: String) {
        // Bound a single pathological line (a giant error description
        // shouldn't be able to eat memory 500 times over).
        var text = message
        if text.count > Self.maxMessageLength {
            text = String(text.prefix(Self.maxMessageLength)) + "… (truncated)"
        }

        // Collapse identical consecutive lines — retry loops and repeated
        // state transitions otherwise flood the buffer.
        if var newest = entries.first, newest.category == category, newest.message == text {
            newest.repeatCount += 1
            entries[0] = newest
            return
        }

        entries.insert(
            DiagnosticEntry(date: Date(), category: category, message: text),
            at: 0,
        )
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
        logger.debug("[\(category, privacy: .public)] \(text, privacy: .public)")
    }

    func clear() {
        entries.removeAll()
    }

    /// Oldest-first plain text. This is O(n) — call it when the user taps
    /// share, never from a view body (which re-renders on every entry).
    func makeExportText() -> String {
        entries.reversed().map(\.line).joined(separator: "\n")
    }
}

/// Bridges the library's internal logging into `DiagnosticsLog`.
///
/// The library's own `OSLogTeslaBLELogger` defaults to `privacy: .private`,
/// which renders every value as `<private>` in Console. This shim keeps the
/// text readable in-app. Level is filtered to `.info` and above by default
/// so per-packet transport chatter doesn't drown the buffer; pass `.debug`
/// when chasing a transport-level problem.
struct AppTeslaBLELogger: TeslaBLELogger {
    var minimumLevel: TeslaBLELogLevel = .info

    func log(
        _ level: TeslaBLELogLevel,
        category: String,
        _ message: @autoclosure () -> String,
    ) {
        // Two cheap gates before the message closure is ever evaluated.
        guard level >= minimumLevel, Diag.isEnabled else { return }
        let prefix =
            switch level {
            case .debug: "ble/debug"
            case .info: "ble"
            case .warning: "ble/warn"
            case .error: "ble/error"
            }
        Diag.log(prefix, message())
    }
}
