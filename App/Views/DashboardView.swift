//
//  DashboardView.swift
//  TeslaButtons
//
//  Configurable dashboard: user-arranged command tiles backed by
//  DashboardStore, with a live snapshot readout and per-command
//  confirmation tiers. Supersedes the original fixed grid.
//
//  Note: RootView already provides the NavigationStack — don't nest one.
//

import SwiftUI

struct DashboardView: View {
    @Environment(VehicleUIModel.self) private var model

    @StateObject private var store = DashboardStore()
    @State private var pendingConfirmation: CatalogCommand?
    @State private var isEditing = false
    @State private var runningCommandID: String?
    @State private var commandError: String?
    @State private var snapshotText = "—"

    private let executor: TeslaCommandExecutor
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 16)]

    /// Snapshot poll cadence while the dashboard is on screen.
    private static let snapshotPollSeconds = 8

    init(executor: TeslaCommandExecutor = TeslaCommandExecutor()) {
        self.executor = executor
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.tiles) { tile in
                        if let command = CommandCatalog.command(id: tile.commandID) {
                            CommandTileView(
                                command: command,
                                isRunning: runningCommandID == command.id,
                            ) {
                                handleTap(on: command)
                            }
                        }
                    }
                }
                .padding()

                if let commandError {
                    Text(commandError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
            }
        }
        .navigationTitle("Dashboard")
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

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.statusColor)
                .frame(width: 10, height: 10)
            Text(model.statusLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(snapshotText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Commands

    private func handleTap(on command: CatalogCommand) {
        switch command.confirmation {
        case .none:
            run(command)
        case .confirm:
            pendingConfirmation = command
        }
    }

    private func run(_ command: CatalogCommand) {
        guard runningCommandID == nil else { return }
        runningCommandID = command.id
        commandError = nil
        Task {
            do {
                try await command.action(executor)
            } catch {
                commandError = "\(command.title): \(Self.message(for: error))"
            }
            runningCommandID = nil
        }
    }

    // MARK: - Snapshot

    /// Repeating poll while the dashboard is visible; the `.task` modifier
    /// cancels this loop automatically when the view disappears.
    private func pollSnapshot() async {
        while !Task.isCancelled {
            await refreshSnapshot()
            try? await Task.sleep(for: .seconds(Self.snapshotPollSeconds))
        }
    }

    private func refreshSnapshot() async {
        do {
            guard let snapshot = try await executor.snapshotIfConnected() else {
                snapshotText = "—"
                return
            }
            var parts: [String] = []
            if let battery = snapshot.charge?.batteryLevel {
                parts.append("Battery \(battery)%")
            }
            if let celsius = snapshot.climate?.insideTempCelsius {
                let fahrenheit = Int((celsius * 9 / 5 + 32).rounded())
                parts.append("Inside \(fahrenheit)°F")
            }
            snapshotText = parts.isEmpty ? "—" : parts.joined(separator: " · ")
        } catch {
            snapshotText = "—"
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
            VStack(spacing: 8) {
                ZStack {
                    Image(systemName: command.systemImage)
                        .font(.title)
                        .opacity(isRunning ? 0 : 1)
                    if isRunning {
                        ProgressView()
                    }
                }
                Text(command.title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
