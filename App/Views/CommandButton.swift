//
//  CommandButton.swift
//  TeslaButtons
//

import SwiftUI

struct CommandButton: View {
    @Environment(VehicleUIModel.self) private var model
    let command: TeslaButtonCommand

    var body: some View {
        Button {
            model.run(command)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Image(systemName: command.symbol)
                        .font(.title2)
                        .opacity(isBusy ? 0 : 1)
                    if isBusy {
                        ProgressView()
                    }
                }
                Text(command.title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.bordered)
        .disabled(model.busyCommand != nil)
    }

    private var isBusy: Bool {
        model.busyCommand == command
    }
}
