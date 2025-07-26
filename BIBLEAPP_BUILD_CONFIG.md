# ⚙️ Build Configuration & ML Asset Bundling (Xcode)

This guide explains how to set up your Xcode project for BibleAppPOCV2, including .xcodeproj settings, ML file bundling, and iOS target configuration. Follow these steps to ensure your ML models and tokenizer files are available at runtime.

---

## 1. Xcode Project Setup

- Open `BibleAppPOCV2.xcodeproj` in Xcode (Xcode 15+ recommended).
- Ensure your iOS Deployment Target is set to at least iOS 16.0 (for Core ML/MLX support).
- The main app target should be `BibleAppPOCV2`.

---

## 2. ML Asset Placement

- Place all ML models and tokenizer files in the `Resources/ML/` directory in your project folder.
  - Examples:
    - `Resources/ML/FlanT5Encoder.mlpackage`
    - `Resources/ML/flan_vocab.json`
    - `Resources/ML/tokenizer_config.json`
    - `Resources/ML/special_tokens_map.json`
    - `Resources/ML/model.npz` (if using MLX)
    - `Resources/ML/spiece.model`

---

## 3. Add ML Files to Xcode Project

1. In Xcode, right-click the `Resources/ML/` folder in the Project Navigator.
2. Select **Add Files to "BibleAppPOCV2"...**
3. Select all `.mlpackage`, `.json`, `.npz`, and related files.
4. In the dialog, ensure **Copy items if needed** is checked.
5. Add to the main app target (checkbox checked).

---

## 4. Ensure Files Are Bundled in Build

- Select each ML file in the Project Navigator.
- In the **File Inspector** (right sidebar), ensure **Target Membership** is checked for your app target.
- For `.mlpackage` files, Xcode will automatically handle Core ML integration.
- For `.json`, `.npz`, and other data files, set the file type to **Data** (not Source or Header).

---

## 5. Accessing Files at Runtime

- Use `Bundle.main.url(forResource:withExtension:subdirectory:)` to load files in Swift:

```swift
if let modelURL = Bundle.main.url(forResource: "FlanT5Encoder", withExtension: "mlpackage", subdirectory: "Resources/ML") {
    // Load model
}

if let vocabURL = Bundle.main.url(forResource: "flan_vocab", withExtension: "json", subdirectory: "Resources/ML") {
    // Load vocab
}
```

---

## 6. Troubleshooting

- If files are missing at runtime, double-check **Target Membership** and that files are in the correct subdirectory.
- Clean build folder (Shift+Cmd+K) and rebuild if changes are not picked up.
- For MLX `.npz` files, ensure your runtime code can read from the app bundle.

---

## 7. Summary Checklist

- [x] All ML/data files in `Resources/ML/`
- [x] Files added to Xcode project and target
- [x] File Inspector: Type = Data, Target Membership checked
- [x] Access files via `Bundle.main` in Swift

---

For more, see `/flan-t5plan.md` and code comments in `LLMService.swift`.
