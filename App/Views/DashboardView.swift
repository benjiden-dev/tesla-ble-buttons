//
//  DashboardView.swift
//  TeslaButtons
//

import SwiftUI

struct DashboardView: View {
    @Environment(VehicleUIModel.self) private var model
    @AppStorage(AppConstants.defaultTempKey) private var defaultTempF: Int = 70

    private let columns = [
        GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusHeader

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TeslaButtonCommand.gridOrder, id: \.self) { command in
                        CommandButton(command: command)
                    }
                }

                climateRow

                if let error = model.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Tesla Buttons")
        .toolbar {
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.statusColor)
                .frame(width: 10, height: 10)
            Text(model.statusLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var climateRow: some View {
        HStack {
            Stepper(value: $defaultTempF, in: 59 ... 83) {
                Text("\(defaultTempF)°F")
                    .font(.headline)
                    .monospacedDigit()
            }
            .fixedSize()

            Spacer()

            Button {
                model.startClimate(fahrenheit: defaultTempF)
            } label: {
                Label("Set & Start", systemImage: "fanblades.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busyCommand != nil)
        }
        .padding(.vertical, 4)
    }
}
