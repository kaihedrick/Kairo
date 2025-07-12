import SwiftUI

extension View {
    @ViewBuilder func glassedEffect(shape: any Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background {
                shape
                    .fill(.ultraThinMaterial)
                    .stroke(.primary.opacity(0.2), lineWidth: 0.7)
            }
        }
    }
}
