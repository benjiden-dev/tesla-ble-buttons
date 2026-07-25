//
//  DashboardView.swift
//  TeslaButtons
//
//  Landscape-first sectioned dashboard for the in-car mount:
//
//  ┌─ Media ────────┬─ Climate ─────────┬─ Vehicle ──────┐
//  │ Now playing    │ Keeper mode       │ catalog tiles  │
//  │ slim controls  │ seat vents        │ (charge port,  │
//  │                │ climate tiles     │  trunk, frunk) │
//  └────────────────┴───────────────────┴────────────────┘
//
//  Landscape: three columns. Portrait: the same sections stacked.
//
//  Keeper mode and seat-vent levels are NOT reported back by the vehicle
//  snapshot, so those pickers reflect the last value sent from this app,
//  not necessarily car truth (e.g. changes made on the touchscreen).
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
    @State private var keeperMode: TeslaCommandExecutor.KeeperMode = .off
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

    private var mediaControls: some View {
        HStack(spacing: 6) {
            mediaButton("backward.fill", id: "media.previous", title: "Previous") {
                try await $0.mediaPrevious()
            }
            mediaButton("playpause.fill", id: "media.playPause", title: "Play / Pause") {
                try await $0.mediaPlayPause()
            }
            mediaButton("forward.fill", id: "media.next", title: "Next") {
                try await $0.mediaNext()
            }
            Divider()
                .frame(height: 20)
            mediaButton("speaker.wave.1", id: "media.volumeDown", title: "Volume Down") {
                try await $0.volumeDown()
            }
            mediaButton("speaker.wave.3", id: "media.volumeUp", title: "Volume Up") {
                try await $0.volumeUp()
            }
            Spacer(minLength: 0)
            if let volume = snapshot?.media?.audioVolume {
                Text(String(format: "%.1f", volume))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
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
            .frame(minWidth: 36, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .disabled(runningID != nil || snapshot?.media?.remoteControlEnabled == false)
    }

    // MARK: - Climate section

    private var climateSection: some View {
        sectionCard("Climate", systemImage: "fanblades.fill") {
            VStack(alignment: .leading, spacing: 12) {
                labeledPicker("Climate Keeper", selection: $keeperMode) { mode in
                    runRaw(id: "climate.keeper", title: "Climate Keeper") {
                        try await executor.setKeeperMode(mode)
                    }
                }
                labeledPicker("Driver Vent", selection: $driverVent) { level in
                    runRaw(id: "climate.vent.driver", title: "Driver Vent") {
                        try await executor.setSeatCooler(level: level, seat: .driver)
                    }
                }
                labeledPicker("Passenger Vent", selection: $passengerVent) { level in
                    runRaw(id: "climate.vent.passenger", title: "Passenger Vent") {
                        try await executor.setSeatCooler(level: level, seat: .passenger)
                    }
                }
                tileGrid(for: .climate)
            }
        }
    }

    /// Segmented picker with a caption label. Fires `onSelect` when the user
    /// picks a new value.
    private func labeledPicker<Value: Hashable & CaseIterable & PickerLabeled>(
        _ label: String,
        selection: Binding<Value>,
        onSelect: @escaping (Value) -> Void,
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                ForEach(Array(Value.allCases), id: \.self) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selection.wrappedValue) { _, newValue in
                onSelect(newValue)
            }
        }
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
    private func runRaw(
        id: String,
        title: String,
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

/// Types usable in the dashboard's segmented pickers.
protocol PickerLabeled {
    var label: String { get }
}

extension TeslaCommandExecutor.KeeperMode: PickerLabeled {}
extension TeslaCommandExecutor.VentLevel: PickerLabeled {}

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
