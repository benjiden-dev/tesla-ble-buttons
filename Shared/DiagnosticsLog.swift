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

import Foundation
import OSLog
import TeslaBLE

struct DiagnosticEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let category: String
    let message: String

    var line: String {
        "\(DiagnosticsLog.timeFormatter.string(from: date))  [\(category)] \(message)"
    }
}

@MainActor
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    /// Newest first, capped so a long drive can't grow without bound.
    private(set) var entries: [DiagnosticEntry] = []

    private static let capacity = 500
    private let logger = Logger(subsystem: AppConstants.bundleRoot, category: "diagnostics")

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func append(category: String, _ message: String) {
        entries.insert(
            DiagnosticEntry(date: Date(), category: category, message: message),
            at: 0,
        )
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
        logger.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
    }

    func clear() {
        entries.removeAll()
    }

    /// Oldest-first plain text, for the share sheet.
    var exportText: String {
        entries.reversed().map(\.line).joined(separator: "\n")
    }

    /// Thread-safe entry point for non-main-actor callers (the BLE actor,
    /// the library's logger shim).
    nonisolated func record(category: String, _ message: String) {
        Task { @MainActor in
            append(category: category, message)
        }
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
        guard level >= minimumLevel else { return }
        let prefix =
            switch level {
            case .debug: "ble/debug"
            case .info: "ble"
            case .warning: "ble/warn"
            case .error: "ble/error"
            }
        DiagnosticsLog.shared.record(category: prefix, message())
    }
}
