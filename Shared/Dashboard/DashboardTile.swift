//
//  DashboardTile.swift
//  TeslaButtons
//

import Foundation

/// One command placed on the dashboard. Order determines grid position.
/// commandID must match an entry in CommandCatalog.
struct DashboardTile: Identifiable, Codable, Equatable {
    let id: UUID
    var commandID: String
    var order: Int

    init(commandID: String, order: Int, id: UUID = UUID()) {
        self.id = id
        self.commandID = commandID
        self.order = order
    }
}
