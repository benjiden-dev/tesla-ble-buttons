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
    @State private var commandNotice: String?
    @State private var snapshot: TeslaVehicleSnapshot?

    /// Mirrors the current geometry orientation so the floating bar (which
    /// lives outside the GeometryReader) can adapt its layout.
    @State private var isLandscapeLayout = false

    /// Retry closure for the last failed command, surfaced in the banner.
    @State private var lastFailedAction: (() -> Void)?

    // Custom climate popover
    @State private var showTempPopover = false
    @State private var customTempF: Double = 70
    @AppStorage(AppConstants.defaultTempKey) private var defaultTempF: Int = 70

    // Last-sent local state for controls the snapshot doesn't report back.
    @State private var keeperOn = false
    @State private var driverVent: TeslaCommandExecutor.VentLevel = .off
    @State private var passengerVent: TeslaCommandExecutor.VentLevel = .off

    private let executor: TeslaCommandExecutor

    /// Only the visible TabView page polls; the parent flips this.
    private let isActive: Bool

    /// Snapshot poll cadence while the dashboard is on screen and someone
    /// is around to look at it.
    private static let snapshotPollSeconds = 5

    /// How often to check for reconnection while polling is paused
    /// (local state read only — zero BLE traffic).
    private static let pausedProbeSeconds = 10

    init(isActive: Bool = true, executor: TeslaCommandExecutor = TeslaCommandExecutor()) {
        self.isActive = isActive
        self.executor = executor
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            Group {
                if isLandscape {
                    // Two independently scrolling columns — media lives in
                    // the top bar in landscape.
                    HStack(alignment: .top, spacing: 12) {
                        scrollColumn { climateSection }
                        scrollColumn { vehicleSection }
                    }
                    .padding(.horizontal)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            mediaSection
                            climateSection
                            vehicleSection
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .contentMargins(.top, 56, for: .scrollContent)
                }
            }
            .onChange(of: geo.size, initial: true) { _, size in
                isLandscapeLayout = size.width > size.height
            }
        }
        // No navigation bar on the dashboard — discrete floating controls
        // instead (the pushed Settings screen shows its own bar + back).
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { floatingBar }
        .overlay(alignment: .bottom) { errorBanner }
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
        .task(id: isActive) {
            guard isActive else { return }
            await pollSnapshot()
        }
    }

    // MARK: - Floating chrome

    /// Discrete floating controls in place of a navigation bar: settings
    /// (top-left), status capsule beside it, edit (top-right). Content
    /// scrolls underneath.
    private var floatingBar: some View {
        HStack(spacing: 8) {
            NavigationLink {
                SettingsView()
            } label: {
                floatingIcon("gearshape.fill")
            }

            statusCapsule

            if isLandscapeLayout {
                // Content-sized when idle, so an empty strip doesn't hog
                // the bar; a leading Spacer keeps Edit pinned right.
                if !isPlayingSomething {
                    Spacer()
                }
                mediaStrip
                if !isPlayingSomething {
                    Spacer()
                }
            } else {
                Spacer()
            }

            Button {
                isEditing = true
            } label: {
                floatingIcon("pencil")
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private func floatingIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(9)
            .background(.thinMaterial, in: Circle())
    }

    /// Slim capsule: colored dot for connection state; when live data is
    /// available it shows battery + inside temp, otherwise the state label.
    private var statusCapsule: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.statusColor)
                .frame(width: 8, height: 8)
            Text(compactStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }

    private var compactStatus: String {
        var parts: [String] = []
        if let battery = snapshot?.charge?.batteryLevel {
            parts.append("\(battery)%")
        }
        if let celsius = snapshot?.climate?.insideTempCelsius {
            let fahrenheit = Int((celsius * 9 / 5 + 32).rounded())
            parts.append("\(fahrenheit)°F")
        }
        return parts.isEmpty ? model.statusLabel : parts.joined(separator: " · ")
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
        compact: Bool = false,
        action: @escaping @Sendable (TeslaCommandExecutor) async throws -> CommandOutcome,
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
            .frame(
                minWidth: compact ? 30 : nil,
                maxWidth: compact ? nil : .infinity,
                minHeight: compact ? 26 : 32,
            )
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .small : .regular)
        .disabled(runningID != nil || snapshot?.media?.remoteControlEnabled == false)
    }

    /// Compact now-playing strip for the landscape top bar: title · artist,
    /// a thin progress bar, and small transport controls. Sizes to content
    /// when nothing is playing (so the bar isn't a wall of empty material),
    /// expands to fill the middle when there's a track to show.
    private var mediaStrip: some View {
        HStack(spacing: 10) {
            if isPlayingSomething {
                mediaStripTitle
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Nothing playing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let progress = trackProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(minWidth: 50, maxWidth: 140)
            }

            HStack(spacing: 6) {
                mediaButton("backward.fill", id: "media.previous", title: "Previous", compact: true) {
                    try await $0.mediaPrevious()
                }
                mediaButton("playpause.fill", id: "media.playPause", title: "Play / Pause", compact: true) {
                    try await $0.mediaPlayPause()
                }
                mediaButton("forward.fill", id: "media.next", title: "Next", compact: true) {
                    try await $0.mediaNext()
                }
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }

    /// True when the car reports an actual track title.
    private var isPlayingSomething: Bool {
        guard let title = snapshot?.media?.nowPlayingTitle else { return false }
        return !title.isEmpty
    }

    private var mediaStripTitle: Text {
        let title = snapshot?.media?.nowPlayingTitle ?? "Nothing playing"
        var text = Text(title)
            .font(.footnote.weight(.medium))
        if let artist = snapshot?.media?.nowPlayingArtist, !artist.isEmpty {
            text = text + Text(" · \(artist)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        return text
    }

    /// 0...1 progress of the current track; nil when the car doesn't report
    /// timing. Advances in steps with the snapshot poll cadence.
    private var trackProgress: Double? {
        guard
            let duration = snapshot?.mediaDetail?.nowPlayingDurationSeconds,
            duration > 0,
            let elapsed = snapshot?.mediaDetail?.nowPlayingElapsedSeconds
        else { return nil }
        return min(max(elapsed / duration, 0), 1)
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
                setClimateButton
            }
        }
    }

    /// "…or pick an exact temperature": pops an anchored slider popover.
    private var setClimateButton: some View {
        Button {
            customTempF = seededTempF
            showTempPopover = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium")
                Text("Set Climate")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .disabled(runningID != nil)
        .popover(isPresented: $showTempPopover, arrowEdge: .bottom) {
            tempPopover
        }
    }

    /// Seed the slider from the car's current driver setpoint when known,
    /// otherwise the Settings default.
    private var seededTempF: Double {
        if let celsius = snapshot?.climate?.driverTempSettingCelsius {
            return (celsius * 9 / 5 + 32).rounded()
        }
        return Double(defaultTempF)
    }

    private var tempPopover: some View {
        VStack(spacing: 14) {
            Text("\(Int(customTempF))°F")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Slider(value: $customTempF, in: 59 ... 83, step: 1) {
                Text("Temperature")
            } minimumValueLabel: {
                Text("59")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("83")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 240)

            Button {
                showTempPopover = false
                let target = Int(customTempF)
                runRaw(id: "climate.custom", title: "Climate \(target)°F") {
                    try await executor.climateOn()
                    return try await executor.setTemperature(fahrenheit: Double(target))
                }
            } label: {
                Label("Set & Start", systemImage: "fanblades.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationCompactAdaptation(.popover)
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

    /// One independently scrolling landscape column. Content starts below
    /// the floating chrome but scrolls underneath it.
    private func scrollColumn(@ViewBuilder content: () -> some View) -> some View {
        ScrollView(showsIndicators: false) {
            content()
                .padding(.bottom)
        }
        .contentMargins(.top, 56, for: .scrollContent)
    }

    /// Floating bottom banner: red for real failures, quiet secondary for
    /// notices ("already set", "connecting…") which auto-dismiss. Tap to
    /// dismiss. Connection failures offer a Retry button rather than just
    /// stating the problem. Lives outside the scroll views so it's visible
    /// in both orientations.
    @ViewBuilder
    private var errorBanner: some View {
        if let text = commandError ?? commandNotice {
            HStack(spacing: 10) {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(
                        commandError != nil
                            ? AnyShapeStyle(.red)
                            : AnyShapeStyle(.secondary),
                    )
                    .lineLimit(2)

                if let retry = lastFailedAction {
                    Button("Retry") {
                        commandError = nil
                        retry()
                    }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 8)
            .onTapGesture {
                commandError = nil
                commandNotice = nil
                lastFailedAction = nil
            }
        }
    }

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
                let display = command.presentation?(snapshot)
                    ?? (title: command.title, systemImage: command.systemImage)
                CommandTileView(
                    title: display.title,
                    systemImage: display.systemImage,
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
    /// the triggering control. Real failures go to the red error banner;
    /// "already set" outcomes show a quiet auto-dismissing notice instead.
    /// `onFailure` lets stateful controls (keeper, vents) revert their
    /// last-sent appearance when the send fails.
    private func runRaw(
        id: String,
        title: String,
        onFailure: (() -> Void)? = nil,
        _ action: @escaping @Sendable () async throws -> CommandOutcome,
    ) {
        guard runningID == nil else { return }
        runningID = id
        commandError = nil
        commandNotice = nil
        lastFailedAction = nil

        // Cold start: tell the user we're bringing the link up rather than
        // leaving a silent spinner (scan + connect + handshake takes a few
        // seconds). Cancelled as soon as the command settles.
        let connectHint = Task {
            guard await VehicleService.shared.latestState != .connected else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            commandNotice = "Connecting to the car…"
        }

        Task {
            do {
                let outcome = try await action()
                connectHint.cancel()
                if commandNotice == "Connecting to the car…" {
                    commandNotice = nil
                }
                if case .alreadySatisfied(let reason) = outcome {
                    showNotice("\(title): \(Self.prettyReason(reason))")
                }
                // Refresh shortly after so toggle tiles flip their label to
                // the next action without waiting for the regular poll.
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    await refreshSnapshot()
                }
            } catch {
                connectHint.cancel()
                commandNotice = nil
                commandError = Self.bannerMessage(title: title, error: error)
                if Self.isRetryable(error) {
                    lastFailedAction = {
                        runRaw(id: id, title: title, onFailure: onFailure, action)
                    }
                }
                onFailure?()
            }
            runningID = nil
        }
    }

    private func showNotice(_ text: String) {
        commandNotice = text
        Task {
            try? await Task.sleep(for: .seconds(4))
            if commandNotice == text {
                commandNotice = nil
            }
        }
    }

    private static func prettyReason(_ reason: String?) -> String {
        guard let reason, !reason.isEmpty else { return "already set" }
        return reason.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Snapshot

    /// Repeating poll while the dashboard is visible; the `.task` modifier
    /// cancels this loop automatically when the view disappears. Gated on an
    /// already-live session inside the executor, so it never spins BLE scans
    /// while away from the car.
    ///
    /// Sleep-safety: when the car is in Park with no user present, polling
    /// pauses AND the BLE session is dropped, so this app can never be the
    /// reason the vehicle stays awake. It resumes automatically once
    /// anything reconnects (a command tap, or the app returning to the
    /// foreground — scene activation calls connectNow).
    private func pollSnapshot() async {
        while !Task.isCancelled {
            await refreshSnapshot()

            if shouldPauseForSleep {
                showNotice("Pausing updates so the car can sleep")
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

    /// True when the car reports Park AND explicitly reports no user
    /// present. Unknown/missing state never pauses (conservative).
    private var shouldPauseForSleep: Bool {
        guard let snap = snapshot else { return false }
        return snap.drive?.shiftState == .park
            && snap.closures?.isUserPresent == false
    }

    private func refreshSnapshot() async {
        do {
            snapshot = try await executor.snapshotIfConnected()
        } catch {
            snapshot = nil
        }
    }

    /// Connection-class failures are worth a Retry button; command
    /// rejections and config problems are not.
    private static func isRetryable(_ error: Error) -> Bool {
        guard let ble = error as? TeslaBLEError else { return false }
        switch ble {
        case .scanTimeout, .connectionFailed, .commandTimeout, .notConnected:
            return true
        default:
            return false
        }
    }

    /// Plain-language banner text. Connection problems get a full sentence
    /// without the command name prefix (the command is beside the point if
    /// the car isn't reachable); other failures stay prefixed.
    private static func bannerMessage(title: String, error: Error) -> String {
        if let ble = error as? TeslaBLEError {
            switch ble {
            case .scanTimeout:
                return "Can't find the car — move closer or wake it, then retry."
            case .connectionFailed:
                return "Bluetooth connection dropped. Try again."
            case .commandTimeout:
                return "The car didn't respond in time. Try again."
            case .notConnected:
                return "Not connected to the car yet. Try again."
            case .bluetoothUnavailable:
                return "Bluetooth is off or not permitted for this app."
            case .handshakeFailed:
                return "Couldn't authenticate with the car. Re-pair in Settings if this persists."
            case .keychain:
                return "Couldn't read this phone's vehicle key. Re-pair in Settings."
            case .commandRejected(let code, let reason):
                if let reason {
                    return "\(title): rejected (\(prettyReason(reason)))"
                }
                return "\(title): rejected (code \(code))"
            default:
                break
            }
        }
        return "\(title): \(message(for: error))"
    }

    private static func message(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return String(describing: error)
    }
}

private struct CommandTileView: View {
    let title: String
    let systemImage: String
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .opacity(isRunning ? 0 : 1)
                    if isRunning {
                        ProgressView()
                    }
                }
                Text(title)
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
