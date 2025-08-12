// filepath: BibleAppPOCV2/Views/ModelManagementView.swift
import SwiftUI

struct ModelManagementView: View {
    @StateObject private var modelManager = ModelManager()
    @State private var selectedModel: String?
    @State private var showingModelInfo = false
    @State private var selectedModelForInfo: String?
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Available Models")) {
                    if modelManager.availableModels.isEmpty {
                        Text("No models found")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(modelManager.availableModels, id: \.self) { model in
                            ModelRowView(
                                modelName: model,
                                isSelected: selectedModel == model,
                                onSelect: { selectedModel = model },
                                onInfo: {
                                    selectedModelForInfo = model
                                    showingModelInfo = true
                                }
                            )
                        }
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button("Refresh Models") {
                        modelManager.scanForModels()
                    }
                    
                    if let bestModel = modelManager.getBestModel() {
                        VStack(alignment: .leading) {
                            Text("Recommended Model")
                                .font(.headline)
                            Text(bestModel)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Model Management")
            .sheet(isPresented: $showingModelInfo) {
                if let modelName = selectedModelForInfo,
                   let info = modelManager.getModelInfo(modelName: modelName) {
                    ModelInfoView(modelInfo: info)
                }
            }
        }
        .onAppear {
            modelManager.scanForModels()
        }
    }
}

struct ModelRowView: View {
    let modelName: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onInfo: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(modelName)
                    .font(.headline)
                Text(getModelType())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
    
    private func getModelType() -> String {
        if modelName.contains("improved") {
            return "Improved Version"
        } else if modelName.contains("full") {
            return "Full Model"
        } else {
            return "Standard Model"
        }
    }
}

struct ModelInfoView: View {
    let modelInfo: [String: Any]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Model Details")) {
                    InfoRow(title: "Name", value: modelInfo["name"] as? String ?? "Unknown")
                    InfoRow(title: "Path", value: modelInfo["path"] as? String ?? "Unknown")
                }
                
                if let inputFeatures = modelInfo["inputFeatures"] as? [String] {
                    Section(header: Text("Input Features")) {
                        ForEach(inputFeatures, id: \.self) { feature in
                            Text(feature)
                        }
                    }
                }
                
                if let outputFeatures = modelInfo["outputFeatures"] as? [String] {
                    Section(header: Text("Output Features")) {
                        ForEach(outputFeatures, id: \.self) { feature in
                            Text(feature)
                        }
                    }
                }
                
                if let metadata = modelInfo["metadata"] as? [String: Any] {
                    Section(header: Text("Metadata")) {
                        ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                            if let value = metadata[key] {
                                InfoRow(title: key, value: "\(value)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Model Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ModelManagementView()
} 