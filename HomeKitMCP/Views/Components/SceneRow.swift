import SwiftUI

struct SceneRow: View {
    let scene: SceneModel
    let onExecute: () -> Void

    @State private var isHovered = false

    private var sceneColor: Color {
        scene.isExecuting ? Theme.Status.active : Theme.Tint.main
    }

    private var typeIcon: String {
        switch scene.type {
        case "Wake Up": return "sunrise.fill"
        case "Sleep": return "moon.fill"
        case "Home Departure": return "figure.walk.departure"
        case "Home Arrival": return "figure.walk.arrival"
        default: return "play.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(sceneColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                if scene.isExecuting {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: typeIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(sceneColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(scene.name)
                    .font(.headline)
                    .foregroundColor(Theme.Text.primary)

                HStack(spacing: 8) {
                    Text(scene.type)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sceneColor.opacity(0.1))
                        .foregroundColor(sceneColor)
                        .cornerRadius(4)

                    Text("\(scene.actions.count) action\(scene.actions.count == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundColor(Theme.Text.secondary)
                }
            }

            Spacer()

            Button {
                onExecute()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(sceneColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(scene.isExecuting)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(isHovered ? Theme.Tint.main.opacity(0.04) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
