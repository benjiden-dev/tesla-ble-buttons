//
//  StatsView.swift
//  TeslaButtons
//
//  Live stats page — swipe left from the dashboard.
//
//  Driving mode: speed + power gauges polled on the fetchDrive fast path
//  (~3Hz) with rated/estimated range below. Charging mode: whenever a
//  cable is connected (charging / starting / complete / stopped), the page
//  becomes a charging monitor. Same sleep-safety rule as the dashboard:
//  Park + no user present pauses everything and drops the BLE session.
//
//  Deliberately minimal: no tires/temps/odometer — the car's own screen
//  covers those. This page exists for the power gauge and the charge stats.
//

import SwiftUI
import TeslaBLE

struct StatsView: View {
    @Environment(VehicleUIModel.self) private var model

    /// Only the visible TabView page polls; the parent flips this.
    let isActive: Bool

    @State private var snapshot: TeslaVehicleSnapshot?
    @State private var drive: DriveState?

    private let executor = TeslaCommandExecutor()

    private static let snapshotPollSeconds = 5
    private static let drivePollMilliseconds = 350 // ≈3Hz
    private static let pausedProbeSeconds = 10

    init(isActive: Bool = true) {
        self.isActive = isActive
    }

    var body: some View {
        Group {
            if isChargingMode {
                chargingPanel
            } else {
                drivingPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Matches the dashboard's discrete top band so the two pages line up.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                statusCapsule
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .task(id: isActive) {
            guard isActive else { return }
            await pollSnapshot()
        }
        .task(id: isActive) {
            guard isActive else { return }
            await pollDrive()
        }
    }

    // MARK: - Mode

    /// Charging monitor whenever a cable is connected, in any session state.
    private var isChargingMode: Bool {
        switch snapshot?.charge?.chargingStatus {
        case .charging, .starting, .complete, .stopped: true
        default: false
        }
    }

    // MARK: - Driving panel

    private var drivingPanel: some View {
        VStack(spacing: 20) {
            HStack(spacing: 28) {
                ArcGauge(
                    value: drive?.speedMph ?? 0,
                    range: 0 ... 120,
                    display: String(Int((drive?.speedMph ?? 0).rounded())),
                    label: "mph",
                    tint: .blue,
                )
                ArcGauge(
                    value: Double(drive?.powerKW ?? 0),
                    range: -100 ... 250,
                    display: "\(drive?.powerKW ?? 0)",
                    label: "kW",
                    tint: (drive?.powerKW ?? 0) < 0 ? .green : .orange,
                )
            }
            rangeLine
        }
        .padding()
    }

    private var rangeLine: some View {
        VStack(spacing: 2) {
            if let range = snapshot?.charge?.batteryRangeMiles {
                Text("\(Int(range.rounded())) mi")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("— mi")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let est = snapshot?.charge?.estBatteryRangeMiles {
                Text("est \(Int(est.rounded())) mi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Charging panel

    private var chargingPanel: some View {
        VStack(spacing: 16) {
            Text(chargingStatusLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(chargerPowerText)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()

            VStack(spacing: 4) {
                batteryToLimitBar
                    .frame(height: 10)
                    .frame(maxWidth: 360)
                Text(batteryToLimitText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 10) {
                GridRow {
                    statCell("Supply", supplyText)
                    statCell("Rate", rateText)
                }
                GridRow {
                    statCell("Range", chargingRangeText)
                    statCell("Time to limit", timeToLimitText)
                }
            }
        }
        .padding()
    }

    private var chargingStatusLabel: String {
        switch snapshot?.charge?.chargingStatus {
        case .charging: "Charging"
        case .starting: "Starting"
        case .complete: "Charge Complete"
        case .stopped: "Charging Stopped"
        default: "Charging"
        }
    }

    private var chargerPowerText: String {
        guard let kw = snapshot?.charge?.chargerPower else { return "— kW" }
        return "\(kw) kW"
    }

    private var batteryToLimitBar: some View {
        let percent = Double(snapshot?.charge?.batteryLevel ?? 0) / 100
        let limit = Double(snapshot?.charge?.chargeLimitPercent ?? 100) / 100
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(.green)
                    .frame(width: max(6, geo.size.width * percent))
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 2)
                    .offset(x: geo.size.width * limit - 1)
            }
        }
    }

    private var batteryToLimitText: String {
        let percent = snapshot?.charge?.batteryLevel.map { "\($0)%" } ?? "—"
        let limit = snapshot?.charge?.chargeLimitPercent.map { "\($0)%" } ?? "—"
        return "\(percent) → \(limit)"
    }

    private var supplyText: String {
        guard
            let volts = snapshot?.charge?.chargerVoltage,
            let amps = snapshot?.charge?.chargerCurrent
        else { return "—" }
        return "\(volts) V × \(amps) A"
    }

    private var rateText: String {
        guard let rate = snapshot?.charge?.chargeRateMph else { return "—" }
        return "\(Int(rate.rounded())) mi/hr"
    }

    private var chargingRangeText: String {
        guard let range = snapshot?.charge?.batteryRangeMiles else { return "—" }
        return "\(Int(range.rounded())) mi"
    }

    private var timeToLimitText: String {
        guard let minutes = snapshot?.charge?.minutesToFullCharge, minutes > 0 else { return "—" }
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
    }

    // MARK: - Chrome

    private var statusCapsule: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.statusColor)
                .frame(width: 8, height: 8)
            Text(model.statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }

    // MARK: - Polling

    private func pollSnapshot() async {
        while !Task.isCancelled {
            snapshot = try? await executor.snapshotIfConnected()

            if shouldPauseForSleep {
                await VehicleService.shared.disconnectNow()
                while !Task.isCancelled {
                    if await VehicleService.shared.latestState == .connected {
                        break
                    }
                    try? await Task.sleep(for: .seconds(Self.pausedProbeSeconds))
                }
                continue
            }

            try? await Task.sleep(for: .seconds(Self.snapshotPollSeconds))
        }
    }

    /// Gauge-speed drive polling; only runs while connected and not in
    /// charging mode (gauges are hidden there anyway).
    private func pollDrive() async {
        while !Task.isCancelled {
            if !isChargingMode, await VehicleService.shared.latestState == .connected {
                drive = try? await VehicleService.shared.fetchDriveIfConnected()
            } else if drive != nil {
                drive = nil
            }
            try? await Task.sleep(for: .milliseconds(Self.drivePollMilliseconds))
        }
    }

    private var shouldPauseForSleep: Bool {
        guard let snap = snapshot else { return false }
        return snap.drive?.shiftState == .park
            && snap.closures?.isUserPresent == false
    }
}

/// Minimal automotive arc gauge: 270° track starting at the lower-left.
private struct ArcGauge: View {
    let value: Double
    let range: ClosedRange<Double>
    let display: String
    let label: String
    let tint: Color

    private var fraction: Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.3), value: fraction)
            VStack(spacing: 0) {
                Text(display)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .frame(width: 150, height: 150)
    }
}
