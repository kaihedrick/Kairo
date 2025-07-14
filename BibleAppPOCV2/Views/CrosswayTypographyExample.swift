// CrosswayTypographyExample.swift
// Example demonstrating Crossway-compatible Bible typography in SwiftUI

import SwiftUI

/// Example view showing the ideal Crossway-compatible Bible layout
struct CrosswayTypographyExample: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Example: Matthew 1:1-3 with proper typography
                sampleBiblePage()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .navigationTitle("Crossway Typography")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    /// Sample Bible page demonstrating typography hierarchy
    private func sampleBiblePage() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Book Title (.largeTitle.bold() ≈ 34pt)
            Text("Matthew")
                .font(.system(size: 34, weight: .bold, design: .default))
                .foregroundColor(.primary)
                .padding(.bottom, 8)
            
            // Chapter Number (.title2.bold() ≈ 28pt)
            Text("1")
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundColor(.primary)
                .padding(.bottom, 6)
            
            // Verses with proper spacing
            VStack(alignment: .leading, spacing: 2) {
                // Verse 1
                verseView(
                    number: "1",
                    text: "The book of the genealogy of Jesus Christ, the son of David, the son of Abraham."
                )
                
                // Verse 2
                verseView(
                    number: "2",
                    text: "Abraham was the father of Isaac, and Isaac the father of Jacob, and Jacob the father of Judah and his brothers,"
                )
                
                // Verse 3
                verseView(
                    number: "3",
                    text: "and Judah the father of Perez and Zerah by Tamar, and Perez the father of Hezron, and Hezron the father of Ram,"
                )
                
                // Additional verses would continue...
            }
        }
    }
    
    /// Individual verse with proper typography
    private func verseView(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            // Verse number (.caption2 ≈ 10pt with superscript effect)
            Text(number)
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundColor(.secondary)
                .baselineOffset(6) // Superscript positioning
            
            // Verse text (.body ≈ 17pt)
            Text(text)
                .font(.system(size: 17, weight: .regular, design: .default))
                .foregroundColor(.primary)
                .lineSpacing(4) // Slight line spacing for readability
        }
        .padding(.bottom, 2) // Small spacing between verses
    }
}

// MARK: - Typography Specifications
/// Documentation of Crossway-compatible typography specifications
enum CrosswayTypography {
    case bookTitle      // .largeTitle.bold() ≈ 34pt
    case chapterNumber  // .title2.bold() ≈ 28pt  
    case verseNumber    // .caption2 ≈ 10pt with baselineOffset: 6
    case verseText      // .body ≈ 17pt with lineSpacing: 4
    
    var font: Font {
        switch self {
        case .bookTitle:
            return .system(size: 34, weight: .bold, design: .default)
        case .chapterNumber:
            return .system(size: 28, weight: .bold, design: .default)
        case .verseNumber:
            return .system(size: 10, weight: .medium, design: .default)
        case .verseText:
            return .system(size: 17, weight: .regular, design: .default)
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .bookTitle, .chapterNumber, .verseText:
            return .primary
        case .verseNumber:
            return .secondary
        }
    }
    
    var baselineOffset: CGFloat {
        switch self {
        case .verseNumber:
            return 6.0 // Superscript effect
        default:
            return 0.0
        }
    }
    
    var lineSpacing: CGFloat {
        switch self {
        case .verseText:
            return 4.0 // Enhance readability
        default:
            return 0.0
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        CrosswayTypographyExample()
    }
}
