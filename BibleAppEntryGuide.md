# 📖 BibleAppPOCV2: High-Level System TL;DR

## What is this?

BibleAppPOCV2 is a Swift-based iOS Bible reader with advanced features:
- **Verse-by-verse reading with smooth pagination**
- **Tap any verse for an AI-generated summary/explanation**
- **All ML runs locally (no server calls)**

---

## How does it work?

### 1. **User Interaction**
- User scrolls and reads Bible text, paginated for device size.
- Tapping a verse opens a summary pop-up.

### 2. **Summary Generation Pipeline**
- **Verse text** is passed to the summary system.
- **Tokenizer** (`T5Tokenizer.swift` or similar) converts verse text to token IDs and attention masks.
- **Encoder Model** (`FlanT5Encoder.mlpackage` or similar) runs locally via Core ML, producing hidden states.
- **Decoder** (currently simulated in Swift) generates summary token IDs from encoder output.
- **Detokenizer** converts summary token IDs back to a readable string.
- **Summary** is displayed in a pop-up view.

### 3. **Architecture Overview**
- **Views**: SwiftUI files for Bible reading and summary pop-up.
- **ViewModels**: Manage state and orchestrate summary requests.
- **Services**: Handle ML model loading, tokenization, and inference.
- **ML Assets**: Core ML `.mlpackage` models and tokenizer JSONs in `/ML/` or `/Resources/ML/`.

---

## Key Files & Directories

- `Views/BibleReaderView.swift` — Main reading UI, handles verse taps.
- `Views/VerseSummaryPopupView.swift` — Shows the summary.
- `ViewModels/VerseSummaryViewModel.swift` — Orchestrates summary generation.
- `Services/LLMService.swift` — Loads/runs ML models, simulates decoding.
- `Services/T5Tokenizer.swift` — Tokenizes/detokenizes text.
- `ML/FlanT5Encoder.mlpackage` — Core ML encoder model.
- `ML/flan_vocab.json` — Tokenizer vocabulary.

---

## Quickstart for Devs

1. **Open the project in Xcode.**
2. **Build and run on a simulator or device.**
3. **Tap any verse** to see a summary pop-up (summary is generated locally).
4. **To update ML models or tokenizer:** Replace files in `/ML/` and ensure paths match in Swift code.
5. **To customize summary logic:** Edit `LLMService.swift` (for inference/decoding) or `VerseSummaryViewModel.swift` (for UI flow).

---

## Notes

- **No network required** for summaries—everything runs on-device.
- **Decoder is simulated** in Swift until a full Core ML decoder is available.
- **All code is modular**: swap out models, tokenizers, or UI as needed.

---

For deeper details, see the full docs in `/ENHANCED_BACKWARD_NAVIGATION.md`, `/flan-t5plan.md`, and