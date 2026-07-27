//
//  SettingsView.swift
//  TeslaButtons
//

import SwiftUI

struct SettingsView: View {
    @Environment(VehicleUIModel.self) private var model
    @AppStorage(AppConstants.defaultTempKey) private var defaultTempF: Int = 70
    @State private var confirmingForget = false

    var body: some View {
        Form {
            Section("Vehicle") {
                LabeledContent("VIN", value: model.vin ?? "—")
                LabeledContent("Connection", value: model.statusLabel)
            }

            // Explicit header:/footer: closures — SwiftUI has no
            // Section(_ title:, content:, footer:) overload, so a string
            // title can't be combined with a footer.
            Section {
                Stepper("Default temperature: \(defaultTempF)°F", value: $defaultTempF, in: 59 ... 83)
            } header: {
                Text("Climate")
            } footer: {
                Text("Used by the in-app Set & Start button and the Control Center Climate control.")
            }

            Section {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
            } header: {
                Text("Troubleshooting")
            } footer: {
                Text("Live BLE log and a raw vehicle-data dump — every field the car reports, including ones the UI doesn't show.")
            }

            Section {
                Button("Forget Vehicle", role: .destructive) {
                    confirmingForget = true
                }
            } footer: {
                Text(
                    """
                    Deletes the private key from this phone and forgets the \
                    VIN. Also remove the "Tesla Buttons" key from the car \
                    itself: Controls → Locks on the touchscreen.
                    """,
                )
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Forget this vehicle?",
            isPresented: $confirmingForget,
            titleVisibility: .visible,
        ) {
            Button("Forget Vehicle", role: .destructive) {
                model.forget()
            }
        } message: {
            Text("The BLE key on this phone will be deleted. Remove it from the car's Locks screen too.")
        }
    }
}
