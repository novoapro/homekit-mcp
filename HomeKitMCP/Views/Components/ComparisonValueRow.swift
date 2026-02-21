import SwiftUI

/// A compact row combining a comparison operator menu and inline value editor.
/// For slider-based values, the comparison + readout appear on row 1 and the slider on row 2.
struct ComparisonValueRow: View {
    @Binding var comparisonType: ComparisonType
    @Binding var value: String
    let characteristicType: String
    let devices: [DeviceModel]
    let deviceId: String

    private var characteristic: CharacteristicModel? {
        devices.first(where: { $0.id == deviceId })?
            .services.flatMap(\.characteristics)
            .first(where: { $0.type == characteristicType })
    }

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
            HStack {
                comparisonMenu
                Spacer()
                Toggle("", isOn: boolBinding)
                    .labelsHidden()
                    .tint(Theme.Tint.main)
            }

        case let .slider(min, max, step, unit):
            VStack(spacing: 4) {
                HStack {
                    comparisonMenu
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
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in }
                        .onEnded { _ in }
                )
            }

        case let .picker(options):
            HStack {
                comparisonMenu
                Spacer()
                Menu {
                    ForEach(options, id: \.value) { option in
                        Button(option.label) {
                            value = option.value
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentPickerLabel(options) ?? "Select…")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(Theme.Text.secondary)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill))
                    .cornerRadius(8)
                }
            }

        case let .textField(inputType):
            HStack {
                comparisonMenu
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

    // MARK: - Comparison Menu

    private var comparisonMenu: some View {
        Menu {
            ForEach(ComparisonType.allCases) { type in
                Button {
                    comparisonType = type
                } label: {
                    HStack {
                        Text(type.displayName)
                        if type == comparisonType {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(comparisonType.symbol)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundColor(Theme.Text.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill))
            .cornerRadius(8)
        }
    }

    // MARK: - Bindings

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
            get: { Double(self.value) ?? 0 },
            set: { newVal in
                if newVal == newVal.rounded() {
                    self.value = "\(Int(newVal))"
                } else {
                    self.value = String(format: "%.1f", newVal)
                }
            }
        )
    }

    // MARK: - Helpers

    private func currentPickerLabel(_ options: [(label: String, value: String)]) -> String? {
        options.first(where: { $0.value == value })?.label
    }

    private func keyboardType(for inputType: TextFieldInputType) -> UIKeyboardType {
        switch inputType {
        case .decimal: return .decimalPad
        case .number: return .numberPad
        case .text: return .default
        }
    }
}
