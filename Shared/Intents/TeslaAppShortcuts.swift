//
//  TeslaAppShortcuts.swift
//  TeslaButtons
//
//  Zero-setup Siri phrases. These appear in the Shortcuts app immediately
//  after install and can be bound to the iPhone Action button
//  (Settings → Action Button → Shortcut).
//

import AppIntents

struct TeslaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunTeslaCommandIntent(command: .frunk),
            phrases: [
                "Open the frunk with \(.applicationName)",
                "\(.applicationName) frunk",
            ],
            shortTitle: "Frunk",
            systemImageName: "car.side.front.open",
        )
        AppShortcut(
            intent: RunTeslaCommandIntent(command: .trunk),
            phrases: [
                "Open the trunk with \(.applicationName)",
                "\(.applicationName) trunk",
            ],
            shortTitle: "Trunk",
            systemImageName: "car.side.rear.open",
        )
        AppShortcut(
            intent: SetCabinTempIntent(),
            phrases: [
                "Precondition my Tesla with \(.applicationName)",
                "Start climate with \(.applicationName)",
            ],
            shortTitle: "Climate",
            systemImageName: "fanblades.fill",
        )
        AppShortcut(
            intent: RunTeslaCommandIntent(command: .lock),
            phrases: [
                "Lock my Tesla with \(.applicationName)",
            ],
            shortTitle: "Lock",
            systemImageName: "lock.fill",
        )
    }
}
