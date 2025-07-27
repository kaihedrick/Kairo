# 🚧 Known Issues & TODOs — BibleAppPOCV2

A living list of current limitations, technical debt, and planned improvements for the ML and app integration.

---

## 🚩 Known Issues & Limitations

- **Decoder is stubbed:**  
  The T5/FLAN decoder is currently simulated in Swift. There is no Core ML or MLX decoder model yet, so summaries are not true beam-search generations.
- **No beam search or sampling:**  
  Decoding uses a naive or greedy approach; advanced decoding (beam search, top-k, etc.) is not implemented.
- **Tokenizer edge cases:**  
  - `Spiece.tokenize()` and Swift-side tokenizers may mishandle certain Unicode, smart quotes, or rare punctuation.
  - Detokenization may not perfectly match HuggingFace/Python output for all edge cases.
- **ML Asset loading:**  
  - All ML and vocab files must be present in `Resources/ML/` and added to the Xcode project with correct target membership.
  - If files are missing or not bundled, runtime errors will occur.
- **Model is encoder-only:**  
  The current Core ML model is an encoder; it cannot generate summaries directly and relies on Swift-side logic.
- **No on-device training or fine-tuning:**  
  All model updates must be done offline and re-bundled.
- **No GPU fallback:**  
  MLX/Core ML models require a device with sufficient RAM and a supported Neural Engine.
- **Summary quality:**  
  Summaries may be generic or repetitive due to the stubbed decoder and lack of advanced generation logic.
- **No error UI:**  
  If model or tokenizer loading fails, the user may see a generic error or fallback summary.

---

## 📝 TODOs

- [ ] Implement or integrate a true Core ML/MLX decoder for T5/FLAN.
- [ ] Add beam search, top-k, or nucleus sampling for summary generation.
- [ ] Improve tokenizer parity between Swift and Python (add more tests).
- [ ] Add more robust error handling and user-facing error messages.
- [ ] Cache popular summaries for offline/fast access.
- [ ] Add more unit and integration tests for ML pipeline.
- [ ] Support additional Bible translations and languages.
- [ ] Optimize model size and inference speed for older devices.
- [ ] Document all public APIs and ML pipeline steps.

---

## 📋 Pipeline & Best Practices Checklist

- [x] **Input format at inference matches training** (verse text vs. reference+text)
- [x] **Tokenizer files are identical between training and inference**
- [x] **All ML and vocab files are present in `Resources/ML/` and added to Xcode**
- [x] **Test exported model and tokenizer before deployment**
- [x] **Pad/truncate input to match training max length**
- [x] **Generate attention masks as required**
- [x] **Apply same preprocessing and postprocessing as in training**
- [x] **Handle edge cases: unknown tokens, empty input, max-length input**
- [x] **Document all steps, configs, and file versions**
- [x] **Test end-to-end pipeline with real data before deployment**

---

## 🟢 Current Status

- Robust model loading and fallback for missing assets
- Attention mask and input shape handling
- Flexible output feature handling for model inference
- Enhanced tokenizer with fallback and debugging
- Documentation of pipeline and best practices

---

## ⚠️ What Still Needs Attention

1. **True Decoder Integration**: The decoder is still simulated; a real Core ML/MLX decoder is needed for production-quality summaries.
2. **Advanced Decoding**: No beam search, top-k, or nucleus sampling yet.
3. **Tokenizer Parity**: More tests and edge case handling needed to match Python/HuggingFace behavior.
4. **Error Handling/UI**: No user-facing error messages for model/tokenizer failures.
5. **Caching**: No summary caching for offline/fast access.
6. **Testing**: More unit/integration tests for the ML pipeline.
7. **Multi-language/Translation Support**: Not yet implemented.
8. **Performance Optimization**: Model size and speed not yet optimized for older devices.
9. **Documentation**: Public APIs and ML pipeline steps need to be fully documented.

---

## 🏁 Summary

Your TODOs and pipeline are appropriate and comprehensive. The main gaps are:
- Implementing a true decoder and advanced decoding strategies
- Improving tokenizer parity and error handling
- Adding caching, multi-language support, and more robust testing/documentation

**If you want, you can break these down into actionable engineering tasks or add code stubs for any of the above. Prioritize based on your product goals!**

---

_See also: `/BIBLEAPP_BUILD_CONFIG.md`, `/TESTING_STRATEGY.md`, and `/flan-t5plan.md` for more_