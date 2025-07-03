import SwiftUI

struct BackgroundView: View {
    var body: some View {
        if UIImage(named: "parchment-bg") != nil {
            Image("parchment-bg")
                .resizable()
                .scaledToFill()
                .opacity(0.25)
                .ignoresSafeArea()
        } else {
            Color(.systemBackground)
                .ignoresSafeArea()
        }
    }
}
