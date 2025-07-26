# 📘 FLAN-T5 MLX Integration for Summarized Bible Verse View

## 🎯 Goal

Enable a feature in your Swift-based Bible app where tapping on a verse opens a pop-up window that uses a locally deployed MLX-converted FLAN-T5 model to display a summarized explanation of the verse.

---

## 🧠 Logic Flow Overview

1. **User taps on a verse**
2. **App opens a pop-up summary view**
3. **Verse text is tokenized locally** using the custom `T5Tokenizer.swift`
4. **Tokens are passed to `FlanT5Encoder.mlpackage`** → outputs encoder hidden states
5. **Decoder is simulated using Swift code and logits mapping** (MLX decoder model not available yet)
6. **Decoded token IDs are converted back into text** → summary string
7. **Summary is shown in the UI popup**

---

## 📁 Directory Structure

```
KairoBibleApp/
├── ML/
│   ├── FlanT5Encoder.mlpackage        # ✅ Exported encoder model
│   ├── flan_vocab.json                # ✅ Tokenizer vocabulary
│   ├── special_tokens_map.json        # ✅ Special tokens for tokenizer
│   ├── tokenizer_config.json          # ✅ Tokenizer config
│   └── convert_to_mlx.py              # ✅ Converts final_model to MLX format
├── Views/
│   ├── BibleReaderView.swift          # ✅ Verse tap logic
│   ├── VerseSummaryPopupView.swift    # ✅ UI popup for summary
├── Services/
│   ├── LLMService.swift               # ✅ MLX runtime + Core ML inference
│   ├── T5Tokenizer.swift              # ✅ Tokenization + detokenization
│   ├── VerseSummaryViewModel.swift    # ✅ Handles summary pipeline logic
│   └── InferenceCache.swift           # 🔧 Optional, for caching encoder outputs
└── Models/
    └── VerseSummary.swift             # ✅ JSON summary object
```

---

## 📄 Related Files (Python Side)

```
scripts/
├── convert_to_mlx.py                    # ✅ Converts PyTorch to MLX
├── trace_flan_t5_encoder_decoder.py     # ✅ Traces encoder and decoder
├── export_tokenizer_json.py             # ✅ Creates tokenizer JSONs
models/
├── bible-verse-commentator/final_model/ # ✅ Trained HuggingFace model
├── torchscript/                         # ✅ Traced .pt versions
├── coreml/                              # ✅ Saved .mlpackage files
```

---

## 🔌 File-Specific Updates

### `BibleReaderView.swift`

* ✅ Already has GeometryReader for verse placement
* 🔧 Add `.onTapGesture` to verse text element
* 🔧 Call `VerseSummaryViewModel.getSummary(for:)`
* 🔧 Trigger `.sheet` or `.popover` for `VerseSummaryPopupView`

### `VerseSummaryPopupView.swift`

* ✅ Already structured
* 🔧 Update to display `viewModel.summaryText`

### `VerseSummaryViewModel.swift`

* ✅ Partially present
* 🔧 Add `getSummary(for:verseText)` that:

  * Uses `T5Tokenizer`
  * Calls `LLMService.runEncoder`
  * Maps decoder output to token IDs
  * Returns detokenized summary

### `LLMService.swift`

* 🔧 New file
* 🧠 Responsibilities:

  * Load `FlanT5Encoder.mlpackage` using `MLModel`
  * Run inference with `input_ids` and `attention_mask`
  * Stub or simulate decoder if `FlanT5Decoder.mlpackage` unavailable

### `T5Tokenizer.swift`

* ✅ Implemented
* 🔧 Add support for `attention_mask` auto-generation

### `convert_to_mlx.py`

* ✅ Converts `final_model` checkpoint into MLX encoder and vocab JSONs
* 🔧 Ensure path output is redirected to your `KairoBibleApp/ML/` directory

---

## 🧪 Optional Enhancements

* [ ] Decoder `.mlpackage` via logits + sampling (Core ML or MLX)
* [ ] Offline summarization cache for popular verses
* [ ] History log for past viewed summaries

---

## 🛠️ Tooling Needed

* ✅ Python: Conversion + training scripts
* ✅ Core ML: Encoder already converted
* 🔧 MLX: Optional decoder/sampling
* ✅ Swift: Custom tokenizer, model runners, summary view

---

## ✅ Final Notes

You have the encoder `.mlpackage` working and Swift-side inference logic partially implemented. You’ve structured the project logically with clean separation between views, services, and ML assets. We are now wiring it together so when a verse is tapped, the encoder runs and produces a summary via Swift-managed decoding. All additions and migrations are being done **within your structure** — no unrelated files are being created.

Let me know when you're ready to:

* Finalize `LLMService.swift`
* Wire gesture handlers in `BibleReaderView.swift`
* Simulate decoding until a decoder `.mlpackage` becomes viable
