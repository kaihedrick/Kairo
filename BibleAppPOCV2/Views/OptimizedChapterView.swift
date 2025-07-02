import SwiftUI

struct OptimizedChapterView: View {
    let bookName: String
    let chapterCount: Int
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    private let tileSize: CGFloat = 50
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...chapterCount, id: \.self) { chapterNumber in
                    NavigationLink {
                        OptimizedVerseView(bookName: bookName, chapterNumber: chapterNumber)
                    } label: {
                        Text("\(chapterNumber)")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(width: tileSize, height: tileSize)
                            .glassBackground(cornerRadius: 10)
                    }
                }
            }
            .padding()
        }
        .background {
            Image("parchment-bg")
                .resizable()
                .scaledToFill()
                .opacity(0.25)
                .ignoresSafeArea()
        }
        .navigationTitle(bookName)
    }
}