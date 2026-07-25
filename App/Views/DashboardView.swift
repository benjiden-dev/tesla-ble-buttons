//
//  DashboardView.swift
//  TeslaButtons
//
//  Landscape-first sectioned dashboard for the in-car mount:
//
//  ┌─ Media ────────┬─ Climate ─────────┬─ Vehicle ──────┐
//  │ Now playing    │ keeper toggle +   │ catalog tiles  │
//  │ slim controls  │ vent cycle btns   │ (charge port,  │
//  │                │ climate tiles     │  trunk, frunk) │
//  └────────────────┴───────────────────┴────────────────┘
//
//  Landscape: three columns. Portrait: the same sections stacked.
//
//  Keeper mode and seat-vent levels are NOT reported back by the vehicle
//  snapshot, so those buttons reflect the last value sent from this app
//  (they revert if the send fails), not necessarily car truth — e.g.
//  changes made on the touchscreen won't show here.
//
//  Note: RootView provides the NavigationStack — don't nest one.
//

import SwiftUI
import TeslaBLE

struct DashboardView: View {
    @Environment(VehicleUIModel.self) private var model

    @StateObject private var store = DashboardStore()
    @State private var pendingConfirmation: CatalogCommand?
    @State private var isEditing = false
    @State private var runningID: String?
    @State private var commandError: String?
    @State private var snapshot: TeslaVehicleSnapshot?

    // Last-sent local state for controls the snapshot doesn't report back.
    @State private var keeperOn = false
    @State private var driverVent: TeslaCommandExecutor.VentLevel = .off
    @State private var passengerVent: TeslaCommandExecutor.VentLevel = .off

    private let executor: TeslaCommandExecutor

    /// Snapshot poll cadence while the dashboard is on screen.
    private static let snapshotPollSeconds = 8

    init(executor: TeslaCommandExecutor = TeslaCommandExecutor()) {
        self.executor = executor
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ScrollView {
                VStack(spacing: 10) {
                    if let commandError {
                        Text(commandError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if isLandscape {
                        HStack(alignment: .top, spacing: 12) {
                            mediaSection
                            climateSection
                            vehicleSection
                        }
                    } else {
                        VStack(spacing: 12) {
                            mediaSection
                            climateSection
                            vehicleSection
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditDashboardView(store: store)
        }
        .confirmationDialog(
            pendingConfirmation?.title ?? "",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } },
            ),
            titleVisibility: .visible,
        ) {
            Button("Confirm", role: .destructive) {
                if let command = pendingConfirmation {
                    run(command)
                }
                pendingConfirmation = nil
            }
            Button("Cancel", role: .cancel) { pendingConfirmation = nil }
        }
        .task { await pollSnapshot() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.statusColor)
                .frame(width: 10, height: 10)
            Text(model.statusLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(headerStats)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var headerStats: String {
        var parts: [String] = []
        if let battery = snapshot?.charge?.batteryLevel {
            parts.append("Battery \(battery)%")
        }
        if let celsius = snapshot?.climate?.insideTempCelsius {
            let fahrenheit = Int((celsius * 9 / 5 + 32).rounded())
            parts.append("Inside \(fahrenheit)°F")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // MARK: - Media section

    private var mediaSection: some View {
        sectionCard("Media", systemImage: "music.note") {
            VStack(alignment: .leading, spacing: 12) {
                nowPlaying
                mediaControls
            }
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot?.media?.nowPlayingTitle ?? "Nothing playing")
                .font(.headline)
                .lineLimit(2)
            let subtitle = [
                snapshot?.media?.nowPlayingArtist,
                snapshot?.mediaDetail?.nowPlayingSource,
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Slim transport row: three equal-width buttons, no volume controls.
    private var mediaControls: some View {
        HStack(spacing: 8) {
            mediaButton("backward.fill", id: "media.previous", title: "Previous") {
                try await $0.mediaPrevious()
            }
            mediaButton("playpause.fill", id: "media.playPause", title: "Play / Pause") {
                try await $0.mediaPlayPause()
            }
            mediaButton("forward.fill", id: "media.next", title: "Next") {
                try await $0.mediaNext()
            }
        }
    }

    private func mediaButton(
        _ symbol: String,
        id: String,
        title: String,
        action: @escaping @Sendable (TeslaCommandExecutor) async throws -> Void,
    ) -> some View {
        Button {
            runRaw(id: id, title: title) { try await action(executor) }
        } label: {
            ZStack {
                Image(systemName: symbol)
                    .opacity(runningID == id ? 0 : 1)
                if runningID == id {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .disabled(runningID != nil || snapshot?.media?.remoteControlEnabled == false)
    }

    // MARK: - Climate section

    private var climateSection: some View {
        sectionCard("Climate", systemImage: "fanblades.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    keeperButton
                    ventButton(
                        "Driver",
                        symbolBase: "carseat.left.fan",
                        seat: .driver,
                        level: $driverVent,
                    )
                    ventButton(
                        "Passenger",
                        symbolBase: "carseat.right.fan",
                        seat: .passenger,
                        level: $passengerVent,
                    )
                }
                tileGrid(for: .climate)
            }
        }
    }

    /// Two-state Climate Keeper toggle (Off / Keep). Dog and Camp modes are
    /// intentionally not exposed here.
    private var keeperButton: some View {
        let core = Button {
            guard runningID == nil else { return }
            let previous = keeperOn
            keeperOn.toggle()
            let target: TeslaCommandExecutor.KeeperMode = keeperOn ? .on : .off
            runRaw(
                id: "climate.keeper",
                title: "Climate Keeper",
                onFailure: { keeperOn = previous },
            ) {
                try await executor.setKeeperMode(target)
            }
        } label: {
            stateButtonLabel(
                symbol: keeperOn ? "infinity.circle.fill" : "infinity.circle",
                text: keeperOn ? "Keeper On" : "Keeper Off",
                busy: runningID == "climate.keeper",
            )
        }

        return Group {
            if keeperOn {
                core.buttonStyle(.borderedProminent).tint(.green)
            } else {
                core.buttonStyle(.bordered)
            }
        }
    }

    /// One-button seat-vent control: tap cycles Off → 1 → 2 → 3 → Off, and
    /// the button's prominence/fill reflects the current (last-sent) level.
    private func ventButton(
        _ title: String,
        symbolBase: String,
        seat: TeslaCommandExecutor.FrontSeat,
        level: Binding<TeslaCommandExecutor.VentLevel>,
    ) -> some View {
        let current = level.wrappedValue
        let id = "climate.vent.\(seat.rawValue)"

        let core = Button {
            guard runningID == nil else { return }
            let previous = current
            let target = current.next
            level.wrappedValue = target
            runRaw(
                id: id,
                title: "\(title) Vent",
                onFailure: { level.wrappedValue = previous },
            ) {
                try await executor.setSeatCooler(level: target, seat: seat)
            }
        } label: {
            stateButtonLabel(
                symbol: current == .off ? symbolBase : "\(symbolBase).fill",
                text: current == .off ? title : "\(title) · \(current.label)",
                busy: runningID == id,
            )
        }

        return Group {
            if current == .off {
                core.buttonStyle(.bordered)
            } else {
                core.buttonStyle(.borderedProminent).tint(.cyan)
            }
        }
    }

    private func stateButtonLabel(symbol: String, text: String, busy: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Image(systemName: symbol)
                    .font(.title3)
                    .opacity(busy ? 0 : 1)
                if busy {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            Text(text)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    // MARK: - Vehicle section

    private var vehicleSection: some View {
        sectionCard("Vehicle", systemImage: "car.fill") {
            tileGrid(for: .vehicle)
        }
    }

    // MARK: - Shared pieces

    private func sectionCard(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func tileGrid(for section: DashboardSection) -> some View {
        let commands = store.tiles
            .compactMap { CommandCatalog.command(id: $0.commandID) }
            .filter { $0.section == section }
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
            spacing: 10,
        ) {
            ForEach(commands) { command in
                CommandTileView(
                    command: command,
                    isRunning: runningID == command.id,
                ) {
                    handleTap(on: command)
                }
            }
        }
    }

    // MARK: - Command dispatch

    private func handleTap(on command: CatalogCommand) {
        switch command.confirmation {
        case .none:
            run(command)
        case .confirm:
            pendingConfirmation = command
        }
    }

    private func run(_ command: CatalogCommand) {
        runRaw(id: command.id, title: command.title) {
            try await command.action(executor)
        }
    }

    /// Single-flight command runner: one command at a time, busy spinner on
    /// the triggering control, failures surfaced in the error line.
    /// `onFailure` lets stateful controls (keeper, vents) revert their
    /// last-sent appearance when the send fails.
    private func runRaw(
        id: String,
        title: String,
        onFailure: (() -> Void)? = nil,
        _ action: @escaping @Sendable () async throws -> Void,
    ) {
        guard runningID == nil else { return }
        runningID = id
        commandError = nil
        Task {
            do {
                try await action()
            } catch {
                commandError = "\(title): \(Self.message(for: error))"
                onFailure?()
            }
            runningID = nil
        }
    }

    // MARK: - Snapshot

    /// Repeating poll while the dashboard is visible; the `.task` modifier
    /// cancels this loop automatically when the view disappears. Gated on an
    /// already-live session inside the executor, so it never spins BLE scans
    /// while away from the car.
    private func pollSnapshot() async {
        while !Task.isCancelled {
            await refreshSnapshot()
            try? await Task.sleep(for: .seconds(Self.snapshotPollSeconds))
        }
    }

    private func refreshSnapshot() async {
        do {
            snapshot = try await executor.snapshotIfConnected()
        } catch {
            snapshot = nil
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return String(describing: error)
    }
}

private struct CommandTileView: View {
    let command: CatalogCommand
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Image(systemName: command.systemImage)
                        .font(.title2)
                        .opacity(isRunning ? 0 : 1)
                    if isRunning {
                        ProgressView()
                    }
                }
                Text(command.title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
