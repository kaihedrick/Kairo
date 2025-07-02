import Foundation
import SwiftUI

@available(*, deprecated, message: "Use OnDemandPageGenerator instead")
class StreamingPaginatorV5: ObservableObject {
    @Published var pages: [PageSlice] = []
    @Published var versePageMap: [String: Int] = [:]
    
    init(bible: Bible, pageSize: CGSize) {
        // Use a simpler initialization since we're deprecating this
        // and should migrate to OnDemandPageGenerator
        self.pages = [PageSlice(content: AttributedString("This component is deprecated. Please use OnDemandPageGenerator."), verseKeys: [])]
        self.versePageMap = [:]
        
        // Log deprecation warning
        print("⚠️ StreamingPaginatorV5 is deprecated. Use OnDemandPageGenerator for better performance.")
    }
}
