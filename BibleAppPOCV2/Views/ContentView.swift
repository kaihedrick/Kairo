import SwiftUI

struct ContentView: View {
    @StateObject private var generator = BibleCommentaryGenerator.shared
    @State private var verseRef = ""
    @State private var verseText = ""
    @State private var showDebugInfo = false
    
    init() {
        // Bypass smoke test to prove end-to-end Core ML pipeline
        Task.detached {
            try? await Task.sleep(nanoseconds: 800_000_000)
            let g = await BibleCommentaryGenerator.shared
            _ = """
            [VERSE_REF] Matthew 1:3
            [VERSE_TEXT] And Judas begat Phares...
            [VERSE]
            [START_COMMENTARY]
            """
            let txt = await g.generateCommentary(for: "Matthew 1:3", verseText: "And Judas begat Phares...")
            print("✅ SMOKE OUTPUT:\n\(txt.prefix(120))")
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                Text("Bible Commentary Generator")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                // Debug Button
                Button(action: {
                    showDebugInfo = true
                }) {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Debug Model Files")
                    }
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
                
                // Input Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Verse Reference")
                        .font(.headline)
                    TextField("e.g., Genesis 1:1", text: $verseRef)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Text("Verse Text")
                        .font(.headline)
                    TextEditor(text: $verseText)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.horizontal)
                
                HStack(spacing: 12) {
                    Button(action: {
                        print("🚀 ContentView: Generate button pressed, gen id:", ObjectIdentifier(generator))
                        Task { _ = await generator.generateCommentary(for: verseRef, verseText: verseText) }
                    }) {
                        HStack {
                            if generator.isGenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(generator.isGenerating ? "Generating..." : "Generate")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(generator.isGenerating || verseRef.isEmpty || verseText.isEmpty)

                    Button(action: {
                        verseRef = "Matthew 1:3"
                        verseText = "And Judas begat Phares..."
                        print("🚀 ContentView: Smoke Test button pressed, gen id:", ObjectIdentifier(generator))
                        Task { _ = await generator.generateCommentary(for: verseRef, verseText: verseText) }
                    }) {
                        Text("Smoke Test")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                    }
                    .disabled(generator.isGenerating)
                }
                .padding(.horizontal)
                
                // Output Section
                if !generator.generatedText.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Generated Commentary")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ScrollView {
                            Text(generator.generatedText)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(10)
                        }
                        .frame(maxHeight: 300)
                        .padding(.horizontal)
                    }
                }
                
                // Error Display
                if let error = generator.error {
                    Text("Error: \(error)").foregroundColor(.red).padding()
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
            .alert("Debug Information", isPresented: $showDebugInfo) {
                Button("OK") { }
            } message: {
                Text("Ensure 'bible_commentary_model.mlpackage' and 'id_to_token.json' are added to the app target in `Resources/ML/`. See console logs for details.")
            }
        }
    }
}

#Preview {
    ContentView()
}
