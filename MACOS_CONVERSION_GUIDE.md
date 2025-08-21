# 🍎 macOS Core ML Conversion Guide

## ✅ **Why macOS is Required**

Core ML conversion **only works on macOS** because:
- `coremltools.libcoremlpython` wheels don't exist for Windows
- Core ML conversion requires native macOS libraries
- Xcode integration is only available on macOS

## 🚀 **Step-by-Step macOS Conversion**

### **Step 1: Prepare macOS Environment**

1. **Ensure you have macOS 13+ with Xcode installed**
   ```bash
   # Check macOS version
   sw_vers
   
   # Check Xcode installation
   xcode-select --print-path
   ```

2. **Create a Python virtual environment**
   ```bash
   # Create virtual environment
   python3 -m venv ~/venvs/coreml
   source ~/venvs/coreml/bin/activate
   
   # Check Python version (3.10 or 3.11 recommended)
   python --version
   ```

3. **Install required packages**
   ```bash
   # Upgrade pip
   pip install --upgrade pip
   
   # Install tested versions
   pip install "torch==2.5.0" "transformers==4.43.3" "coremltools==7.2"
   
   # Verify installation
   python -c "import torch, transformers, coremltools; print('All packages installed successfully')"
   ```

### **Step 2: Copy Model Files to macOS**

1. **Copy the entire `bible_commentary_model_export` directory** to your macOS machine
2. **Navigate to the directory**
   ```bash
   cd path/to/bible_commentary_model_export
   ```

### **Step 3: Run Core ML Conversion**

1. **Run the conversion script**
   ```bash
   python export_to_coreml_mac.py
   ```

2. **Expected output**
   ```
   🚀 Converting to Core ML - macOS Version...
   ==================================================
   🔄 Loading model and tokenizer...
   ✅ Model and tokenizer loaded successfully
   🔄 Creating wrapper...
   ✅ Wrapper created successfully
   🔄 Creating example inputs...
   ✅ Example inputs created
   🔄 Converting to Core ML...
   🔄 Trying torch.export...
   ✅ torch.export successful
   🔄 Converting to Core ML MLProgram...
   ✅ Core ML conversion successful
   🔄 Saving Core ML model...
   ✅ Model saved: bible_commentary_model.mlmodel (475.2 MB)
   
   🎉 Conversion completed successfully!
   📁 Model file: bible_commentary_model.mlmodel
   ```

### **Step 4: Verify the Core ML Model**

1. **Check the model file**
   ```bash
   ls -la bible_commentary_model.mlmodel
   ```

2. **Open in Xcode to verify**
   - Drag `bible_commentary_model.mlmodel` into Xcode
   - It should show two inputs:
     - `input_ids` (Int32 [1×L])
     - `attention_mask` (Int32 [1×L])

## 🔧 **Troubleshooting**

### **Common Issues**

1. **"No module named 'coremltools'"**
   ```bash
   # Reinstall coremltools
   pip uninstall coremltools
   pip install "coremltools==7.2"
   ```

2. **"torch.export failed"**
   - This is expected - the script will fall back to TorchScript trace
   - The conversion will still work

3. **"Invalid deployment target"**
   ```bash
   # Update the script to use iOS16 instead of iOS17
   minimum_deployment_target=ct.target.iOS16
   ```

4. **"Model too large"**
   - The model is ~475MB, which is normal for GPT-2
   - Ensure you have enough disk space

### **Alternative: Manual Conversion**

If the script fails, you can try manual conversion:

```python
import torch
import coremltools as ct
from transformers import AutoModelForCausalLM, AutoTokenizer

# Load model
tokenizer = AutoTokenizer.from_pretrained(".")
model = AutoModelForCausalLM.from_pretrained(".", torch_dtype=torch.float32)
model.config.use_cache = False
model.eval()

# Create wrapper
class Wrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model
    def forward(self, input_ids, attention_mask):
        return self.model(input_ids=input_ids.long(), 
                         attention_mask=attention_mask.long(), 
                         return_dict=True).logits

wrapper = Wrapper(model).eval()

# Convert
ex_ids = torch.zeros(1, 512, dtype=torch.long)
ex_mask = torch.ones(1, 512, dtype=torch.long)

traced = torch.jit.trace(wrapper, (ex_ids, ex_mask))
traced = torch.jit.freeze(traced)

mlmodel = ct.convert(
    traced,
    source="pytorch",
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS17,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, 512), dtype=int),
        ct.TensorType(name="attention_mask", shape=(1, 512), dtype=int),
    ],
)

mlmodel.save("bible_commentary_model.mlmodel")
```

## 📱 **iOS Integration**

### **Step 1: Add to Xcode Project**

1. **Drag `bible_commentary_model.mlmodel` into Xcode**
2. **Ensure "Copy items if needed" is checked**
3. **Add to your app target**

### **Step 2: Update Swift Code**

```swift
import CoreML
import Foundation

class BibleCommentaryGenerator: ObservableObject {
    @Published var isGenerating = false
    @Published var generatedText = ""
    @Published var error: String?
    
    private var model: MLModel?
    
    init() {
        loadModel()
    }
    
    private func loadModel() {
        if let modelURL = Bundle.main.url(forResource: "bible_commentary_model", withExtension: "mlmodel") {
            do {
                model = try MLModel(contentsOf: modelURL)
                print("✅ Core ML model loaded successfully")
            } catch {
                print("❌ Failed to load Core ML model: \(error)")
                self.error = "Failed to load model: \(error.localizedDescription)"
            }
        } else {
            print("❌ Model not found in bundle")
            self.error = "Model not found in bundle"
        }
    }
    
    func generateCommentary(verseRef: String, verseText: String) async {
        await MainActor.run {
            isGenerating = true
            generatedText = ""
            error = nil
        }
        
        // Implementation for Core ML model inference
        // This will use the converted model
    }
}
```

## ✅ **Success Checklist**

- [ ] macOS 13+ with Xcode installed
- [ ] Python 3.10 or 3.11
- [ ] Virtual environment created
- [ ] Required packages installed
- [ ] Model files copied to macOS
- [ ] Conversion script runs successfully
- [ ] Core ML model file created (~475MB)
- [ ] Model opens in Xcode
- [ ] Model added to iOS project
- [ ] Swift code updated for Core ML

## 🎯 **Next Steps**

1. **Run the conversion on macOS**
2. **Test the model in Xcode**
3. **Integrate into your iOS app**
4. **Test generation functionality**

## 📞 **Support**

If you encounter issues:
1. **Check macOS version and Xcode installation**
2. **Verify Python version (3.10 or 3.11)**
3. **Ensure all packages are installed correctly**
4. **Check disk space (need ~1GB free)**
5. **Verify model files are complete**

---

**🚀 Your Bible commentary model will be ready for iOS deployment!**

