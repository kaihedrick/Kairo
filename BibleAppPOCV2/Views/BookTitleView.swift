// filepath: BibleAppPOCV2/Views/BookTitleView.swift
//
//  BookTitleView.swift
//  AIStudyBiblePOC
//
//  Created by Jeff Hedrick on 6/10/25.
//

import SwiftUI

struct BookTitleView: View {
    let bookName: String
    let chapterCount: Int
    
    var body: some View {
        VStack(spacing: 8) {
            Text(bookName)
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Text("\(chapterCount) chapters")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

#Preview {
    BookTitleView(bookName: "Genesis", chapterCount: 50)
}
