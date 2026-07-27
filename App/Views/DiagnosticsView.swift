//
//  DiagnosticsView.swift
//  TeslaButtons
//
//  Live diagnostic log viewer: what the app pulled from the car, what the
//  BLE library reported, and every command outcome. Reachable from
//  Settings → Diagnostics; shareable as plain text.
//

import SwiftUI
import TeslaBLE

struct DiagnosticsView: View {
    @State private var log = DiagnosticsLog.shared
    @State private var isDumping = false

    private let executor = TeslaCommandExecutor()

    var body: some View {
        List {
            Section {
                Button {
                    dumpSnapshot()
                } label: {
                    HStack {
                        Label("Dump Raw Vehicle Data", systemImage: "arrow.down.doc")
                        if isDumping {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDumping)
            } footer: {
                Text(
                    """
                    Fetches a full snapshot plus a media-only follow-up and \
                    logs every field the car returned — including the ones \
                    the UI doesn't show. Requires a live connection.
                    """,
                )
            }

            Section("Log") {
                if log.entries.isEmpty {
                    Text("No entries yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                            Text("\(entry.timestamp)  ·  \(entry.category)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShareLink(item: log.exportText) {
                        Label("Share Log", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        log.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    /// Logs every field of a fresh snapshot — the "show me the raw data"
    /// button. Media is fetched separately too, since that's the field set
    /// most often missing from the combined response.
    private func dumpSnapshot() {
        isDumping = true
        Task {
            defer { isDumping = false }
            let log = DiagnosticsLog.shared

            do {
                guard let snap = try await executor.snapshotIfConnected() else {
                    log.append(category: "dump", "No live connection — connect first (tap any control).")
                    return
                }

                log.append(category: "dump", "── full snapshot ──")

                if let c = snap.charge {
                    log.append(
                        category: "charge",
                        """
                        level=\(str(c.batteryLevel)) range=\(str(c.batteryRangeMiles)) \
                        est=\(str(c.estBatteryRangeMiles)) status=\(str(c.chargingStatus)) \
                        limit=\(str(c.chargeLimitPercent)) V=\(str(c.chargerVoltage)) \
                        A=\(str(c.chargerCurrent)) kW=\(str(c.chargerPower)) \
                        rate=\(str(c.chargeRateMph)) minsToFull=\(str(c.minutesToFullCharge)) \
                        portOpen=\(str(c.chargePortOpen)) portLatched=\(str(c.chargePortLatched))
                        """,
                    )
                } else {
                    log.append(category: "charge", "nil (car omitted charge section)")
                }

                if let d = snap.drive {
                    log.append(
                        category: "drive",
                        """
                        shift=\(str(d.shiftState)) speed=\(str(d.speedMph)) \
                        powerKW=\(str(d.powerKW)) odo=\(str(d.odometerHundredthsMile)) \
                        dest=\(str(d.activeRouteDestination)) \
                        minsToArrival=\(str(d.activeRouteMinutesToArrival))
                        """,
                    )
                } else {
                    log.append(category: "drive", "nil (car omitted drive section)")
                }

                if let cl = snap.climate {
                    log.append(
                        category: "climate",
                        """
                        inside=\(str(cl.insideTempCelsius)) outside=\(str(cl.outsideTempCelsius)) \
                        driverSet=\(str(cl.driverTempSettingCelsius)) \
                        passSet=\(str(cl.passengerTempSettingCelsius)) fan=\(str(cl.fanStatus)) \
                        on=\(str(cl.isClimateOn)) seatFL=\(str(cl.seatHeaterFrontLeft)) \
                        seatFR=\(str(cl.seatHeaterFrontRight)) wheel=\(str(cl.steeringWheelHeater)) \
                        defrost=\(str(cl.defrostOn)) battHeater=\(str(cl.isBatteryHeaterOn))
                        """,
                    )
                } else {
                    log.append(category: "climate", "nil (car omitted climate section)")
                }

                if let cs = snap.closures {
                    log.append(
                        category: "closures",
                        """
                        locked=\(str(cs.locked)) userPresent=\(str(cs.isUserPresent)) \
                        frunk=\(str(cs.frontTrunk)) trunk=\(str(cs.rearTrunk)) \
                        winDF=\(str(cs.windowDriverFront)) winPF=\(str(cs.windowPassengerFront)) \
                        winDR=\(str(cs.windowDriverRear)) winPR=\(str(cs.windowPassengerRear)) \
                        sentry=\(str(cs.sentryModeActive))
                        """,
                    )
                } else {
                    log.append(category: "closures", "nil (car omitted closures section)")
                }

                // The interesting one for issue #4.
                logMedia(label: "media (from full snapshot)", snap.media, snap.mediaDetail)

                log.append(category: "dump", "── media-only fetch ──")
                if let (media, detail) = try await executor.mediaIfConnected() {
                    logMedia(label: "media (targeted fetch)", media, detail)
                } else {
                    log.append(category: "media", "media-only fetch returned nil (not connected)")
                }
            } catch {
                log.append(category: "dump", "failed: \(String(describing: error))")
            }
        }
    }

    private func logMedia(label: String, _ media: MediaState?, _ detail: MediaDetailState?) {
        let log = DiagnosticsLog.shared
        guard media != nil || detail != nil else {
            log.append(category: "media", "\(label): BOTH SECTIONS NIL — car returned no media data")
            return
        }
        log.append(
            category: "media",
            """
            \(label): title=\(str(media?.nowPlayingTitle)) artist=\(str(media?.nowPlayingArtist)) \
            volume=\(str(media?.audioVolume))/\(str(media?.audioVolumeMax)) \
            remoteEnabled=\(str(media?.remoteControlEnabled)) \
            album=\(str(detail?.nowPlayingAlbum)) station=\(str(detail?.nowPlayingStation)) \
            source=\(str(detail?.nowPlayingSource)) a2dp=\(str(detail?.a2dpSourceName)) \
            elapsed=\(str(detail?.nowPlayingElapsedSeconds))/\(str(detail?.nowPlayingDurationSeconds))
            """,
        )
    }

    /// Renders optionals as "nil" instead of "Optional(…)" noise.
    private func str(_ value: Any?) -> String {
        guard let value else { return "nil" }
        if let string = value as? String {
            return string.isEmpty ? "\"\"" : string
        }
        return String(describing: value)
    }
}
