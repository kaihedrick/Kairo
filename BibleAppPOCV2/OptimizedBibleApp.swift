import SwiftUI

@main
struct OptimizedBibleApp: App {
    @State private var showPerformanceView = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                OptimizedBookGridView()
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                        handleGlobalMemoryWarning()
                    }

                // Performance testing overlay (DEBUG only)
                #if DEBUG
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            showPerformanceView = true
                        }) {
                            Text("⏱️")
                                .font(.system(size: 20))
                                .padding(12)
                                .background(Color.blue.opacity(0.8))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
                .sheet(isPresented: $showPerformanceView) {
                    PerformanceTestView()
                }
                #endif
            }
        }
    }

    private func handleGlobalMemoryWarning() {
        // Clear any global caches or temporary data
        print("🚨 Memory warning received - cleaning up resources")

        Task { @MainActor in
            await OptimizedBibleDataLoader().handleMemoryWarning()
        }

        // Force garbage collection
        autoreleasepool {
            // Any cleanup code will run in an autorelease pool
        }
    }
}

// MARK: - Performance Testing View

struct PerformanceTestView: View {
    @StateObject private var performanceTimer = PerformanceTestTimer()
    @State private var testResults: String = ""
    @State private var isRunningTest = false
    @State private var selectedBook = "Genesis"
    @State private var selectedChapters = "1,2,3"
    @State private var selectedChapter = "1"

    let availableBooks = ["Genesis", "Exodus", "Matthew", "Mark", "Luke", "John"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("⏱️ Performance Testing")
                        .font(.title)
                        .padding(.top)

                    // Chapter Loading Test
                    GroupBox(label: Text("📖 Chapter Loading Performance")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Book", selection: $selectedBook) {
                                ForEach(availableBooks, id: \.self) { book in
                                    Text(book)
                                }
                            }
                            .pickerStyle(.menu)

                            TextField("Chapters (comma-separated)", text: $selectedChapters)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)

                            Button(action: runChapterLoadingTest) {
                                HStack {
                                    if isRunningTest {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(isRunningTest ? "Running..." : "🧪 Run Chapter Loading Test")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(isRunningTest)
                        }
                        .padding()
                    }

                    // On-Screen Reader Test
                    GroupBox(label: Text("📱 On-Screen Reader Performance")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Book", selection: $selectedBook) {
                                ForEach(availableBooks, id: \.self) { book in
                                    Text(book)
                                }
                            }
                            .pickerStyle(.menu)

                            TextField("Chapter", text: $selectedChapter)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)

                            Button(action: runReaderPerformanceTest) {
                                Text("📖 Run Reader Performance Test")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(isRunningTest)
                        }
                        .padding()
                    }

                    // Cache Management
                    GroupBox(label: Text("💾 Cache Management")) {
                        VStack(spacing: 12) {
                            Button(action: clearPerformanceData) {
                                Text("🧹 Clear Performance Data")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }

                            Button(action: generateReport) {
                                Text("📊 Generate Report")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                    }

                    // Results Display
                    if !testResults.isEmpty {
                        GroupBox(label: Text("📈 Test Results")) {
                            ScrollView {
                                Text(testResults)
                                    .font(.system(.body, design: .monospaced))
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 300)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitle("Performance Tests", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                // This would be handled by the parent view
            })
        }
    }

    private func runChapterLoadingTest() {
        guard let chapters = parseChapters(selectedChapters) else {
            testResults = "❌ Invalid chapter format. Use comma-separated numbers."
            return
        }

        isRunningTest = true
        testResults = "🧪 Starting chapter loading test..."

        Task {
            await performanceTimer.testChapterLoadingPerformance(
                book: selectedBook,
                chapters: chapters,
                dataLoader: OptimizedBibleDataLoader()
            )

            testResults = performanceTimer.generatePerformanceReport()
            isRunningTest = false
        }
    }

    private func runReaderPerformanceTest() {
        guard let chapter = Int(selectedChapter) else {
            testResults = "❌ Invalid chapter number."
            return
        }

        isRunningTest = true
        testResults = "📖 Starting reader performance test..."

        Task {
            await performanceTimer.testOnScreenReaderPerformance(
                book: selectedBook,
                chapter: chapter,
                dataLoader: OptimizedBibleDataLoader()
            )

            testResults = performanceTimer.generatePerformanceReport()
            isRunningTest = false
        }
    }

    private func clearPerformanceData() {
        performanceTimer.clearMeasurements()
        testResults = "🧹 Performance data cleared."
    }

    private func generateReport() {
        testResults = performanceTimer.generatePerformanceReport()
    }

    private func parseChapters(_ input: String) -> [Int]? {
        let components = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return components.compactMap { Int($0) }
    }
}