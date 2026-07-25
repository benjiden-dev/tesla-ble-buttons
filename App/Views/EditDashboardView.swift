//
//  EditDashboardView.swift
//  TeslaButtons
//
//  Remove, reorder, and add dashboard tiles. New catalog entries become
//  addable here automatically.
//

import SwiftUI

struct EditDashboardView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                Section("On Dashboard") {
                    ForEach(store.tiles) { tile in
                        if let command = CommandCatalog.command(id: tile.commandID) {
                            HStack {
                                Image(systemName: command.systemImage)
                                Text(command.title)
                                if command.confirmation == .confirm {
                                    Spacer()
                                    Text("Confirm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.forEach { index in
                            store.remove(tileID: store.tiles[index].id)
                        }
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .navigationTitle("Edit Dashboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add Function", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddCommandView(store: store)
            }
        }
    }
}

private struct AddCommandView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(DashboardSection.allCases, id: \.self) { section in
                    let commands = store.availableToAdd.filter { $0.section == section }
                    if !commands.isEmpty {
                        Section(section.title) {
                            ForEach(commands) { command in
                                Button {
                                    store.add(commandID: command.id)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: command.systemImage)
                                        Text(command.title)
                                        if command.confirmation == .confirm {
                                            Spacer()
                                            Text("Confirm")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Function")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if store.availableToAdd.isEmpty {
                    ContentUnavailableView(
                        "Everything's added",
                        systemImage: "checkmark.circle",
                    )
                }
            }
        }
    }
}
