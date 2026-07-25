//
//  DashboardStore.swift
//  TeslaButtons
//
//  Persists which commands are on the dashboard and in what order.
//

import Combine
import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var tiles: [DashboardTile] = []

    private let defaultsKey = "dashboard.tiles.v1"

    init() {
        load()
        if tiles.isEmpty {
            tiles = Self.defaultTiles()
            save()
        }
    }

    func add(commandID: String) {
        guard CommandCatalog.command(id: commandID) != nil else { return }
        guard !tiles.contains(where: { $0.commandID == commandID }) else { return }
        tiles.append(DashboardTile(commandID: commandID, order: tiles.count))
        save()
    }

    func remove(tileID: UUID) {
        tiles.removeAll { $0.id == tileID }
        reindex()
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        tiles.move(fromOffsets: fromOffsets, toOffset: toOffset)
        reindex()
        save()
    }

    var availableToAdd: [CatalogCommand] {
        let activeIDs = Set(tiles.map(\.commandID))
        return CommandCatalog.all.filter { !activeIDs.contains($0.id) }
    }

    private func reindex() {
        for index in tiles.indices {
            tiles[index].order = index
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tiles) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([DashboardTile].self, from: data)
        else { return }
        tiles = decoded.sorted { $0.order < $1.order }
    }

    private static func defaultTiles() -> [DashboardTile] {
        let defaultIDs = [
            "climate.preset.68",
            "climate.preset.72",
            "charge.port.open",
            "trunk.actuate",
            "frunk.actuate",
            "media.playPause",
        ]
        return defaultIDs.enumerated().map { index, id in
            DashboardTile(commandID: id, order: index)
        }
    }
}
