import SwiftUI

struct RefreshBarView: View {
    let isRefreshing: Bool
    @State private var animationOffset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            if isRefreshing {
                let barWidth = geo.size.width * 0.4
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.Tint.main.opacity(0.0),
                                Theme.Tint.main,
                                Theme.Tint.main.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth, height: 3)
                    .offset(x: animationOffset * (geo.size.width + barWidth) - barWidth / 2)
                    .onAppear {
                        animationOffset = -0.2
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            animationOffset = 1.2
                        }
                    }
                    .onDisappear {
                        animationOffset = -1.0
                    }
            }
        }
        .frame(height: isRefreshing ? 3 : 0)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: isRefreshing)
    }
}

struct RefreshBarModifier: ViewModifier {
    let isRefreshing: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            RefreshBarView(isRefreshing: isRefreshing)
            content
        }
    }
}

extension View {
    func refreshBar(isRefreshing: Bool) -> some View {
        modifier(RefreshBarModifier(isRefreshing: isRefreshing))
    }
}
