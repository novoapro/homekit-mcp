import SwiftUI

struct ValueEditor: View {
    @Binding var value: String
    let characteristicType: String
    let devices: [DeviceModel]
    let deviceId: String

    private var characteristic: CharacteristicModel? {
        devices.first(where: { $0.id == deviceId })?
            .services.flatMap(\.characteristics)
            .first(where: { $0.type == characteristicType })
    }

    private var format: String? { characteristic?.format }

    private var inputControlType: InputControlType {
        guard let char = characteristic else {
            return .textField(inputType: .text)
        }
        return CharacteristicInputConfig.getInputType(
            for: characteristicType,
            format: char.format,
            minValue: char.minValue,
            maxValue: char.maxValue,
            validValues: char.validValues
        )
    }

    var body: some View {
        switch inputControlType {
        case .toggle:
            Toggle("Value", isOn: boolBinding)
                .tint(Theme.Tint.main)

        case let .slider(min, max, step, unit):
            VStack(spacing: 4) {
                HStack {
                    Text("Value")
                    Spacer()
                    Text("\(Int(doubleValue))\(unit ?? "")")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Theme.Text.secondary)
                }
                Slider(
                    value: doubleBinding,
                    in: min...max,
                    step: step
                )
                .tint(Theme.Tint.main)
            }

        case let .picker(options):
            HStack {
                Text("Value")
                Spacer()
                Menu {
                    ForEach(options, id: \.value) { option in
                        Button(option.label) {
                            value = option.value
                        }
                    }
                } label: {
                    Text(currentPickerLabel(options) ?? "Select...")
                        .foregroundColor(.primary)
                }
            }

        case let .textField(inputType):
            HStack {
                Text("Value")
                Spacer()
                TextField(
                    inputType == .decimal ? "0.0" : "0",
                    text: $value
                )
                .keyboardType(keyboardType(for: inputType))
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { value.lowercased() == "true" || value == "1" },
            set: { value = $0 ? "true" : "false" }
        )
    }

    private var doubleValue: Double {
        Double(value) ?? 0
    }

    private var doubleBinding: Binding<Double> {
        Binding(
            get: {
                Double(self.value) ?? 0
            },
            set: { newVal in
                if newVal == newVal.rounded() {
                    self.value = "\(Int(newVal))"
                } else {
                    self.value = String(format: "%.1f", newVal)
                }
            }
        )
    }

    private func currentPickerLabel(_ options: [(label: String, value: String)]) -> String? {
        options.first(where: { $0.value == value })?.label
    }

    private func keyboardType(for inputType: TextFieldInputType) -> UIKeyboardType {
        switch inputType {
        case .decimal:
            return .decimalPad
        case .number:
            return .numberPad
        case .text:
            return .default
        }
    }
}
