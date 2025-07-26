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

_See also: `/BIBLEAPP_BUILD_CONFIG.md`, `/TESTING_STRATEGY.md`, and `/flan-t5plan.md` for more