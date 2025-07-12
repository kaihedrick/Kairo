import SwiftUI

struct BookTileView: View {
    let abbreviation: String
    let fullName: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(abbreviation)
                .font(.system(size: 14, weight: .bold, design: .default))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(fullName)
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clear)
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack {
        BookTileView(abbreviation: "Gen", fullName: "Genesis")
            .frame(width: 70, height: 75)
            .glassTile(cornerRadius: 12, id: "Genesis", namespace: Namespace().wrappedValue)
        
        BookTileView(abbreviation: "Matt", fullName: "Matthew")
            .frame(width: 70, height: 75)
            .glassTile(cornerRadius: 12, id: "Matthew", namespace: Namespace().wrappedValue)
    }
    .padding()
}
