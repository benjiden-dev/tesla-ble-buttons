//
//  PairingView.swift
//  TeslaButtons
//
//  One-time key enrollment. Requires: sitting in the car, Bluetooth on,
//  and an NFC key card in hand.
//

import SwiftUI

struct PairingView: View {
    @Environment(VehicleUIModel.self) private var model
    @State private var vinInput: String = ""

    var body: some View {
        Form {
            Section("Before you start") {
                Label("Sit in the car with this phone", systemImage: "car.fill")
                Label("Have your NFC key card ready", systemImage: "creditcard.fill")
                Label("Find your VIN under Controls → Software", systemImage: "number")
            }

            Section("Vehicle") {
                TextField("VIN (17 characters)", text: $vinInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            }

            Section {
                Button {
                    model.pair(rawVIN: vinInput)
                } label: {
                    if model.isPairing {
                        HStack {
                            ProgressView()
                            Text("Pairing — tap your key card on the console…")
                        }
                    } else {
                        Text("Pair with Vehicle")
                    }
                }
                .disabled(model.isPairing || vinInput.trimmingCharacters(in: .whitespaces).count != 17)
            } footer: {
                Text(
                    """
                    After tapping Pair: tap your NFC key card on the center \
                    console, then confirm the new key on the car's screen. \
                    The key appears under Controls → Locks — rename it to \
                    "Tesla Buttons" so it's easy to spot.
                    """,
                )
            }

            if let error = model.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Pair Your Tesla")
    }
}
