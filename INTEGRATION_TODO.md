# Bible Commentary Model – Integration TODOs

Status legend: [x] done, [ ] pending

## Prompt + Tokenizer
- [x] Normalize verse IDs in `formatInput` to training shape `BOOK_CHAPTER_VERSE` (spaces/colons/dashes → underscores; strip non `[A-Z0-9_]`). Files: `Services/GPT2Tokenizer.swift`, `Services/TokenizerService.swift`.
- [x] Use canonical GPT‑2 token pattern (Unicode letters/numbers; preserves underscores). File: `Tokenizer/GPT2BPEEncoder.swift`.
- [x] Make BPE assets mandatory (no placeholder fallback). Abort if missing/mismatched.
- [x] Add encode→decode round‑trip assertion to verify encoder/decoder pair matches bundled assets.
- [ ] Add a build‑phase check that verifies presence of required tokenizer assets in the app bundle: `vocab.json`, `merges.txt`, `special_tokens_map.json`, `added_tokens.json`, `id_to_token.json`. Fail the build with a clear message if missing.

## Generation quality
- [x] Support logits rank 2 or 3; sample last step robustly.
- [x] Ban `[PAD]` from sampling; add mild defaults `temperature=0.8`, `topK=40`.
- [x] Replace fixed `maxNew=128` with `maxNew = seqLen - prefixLen`; stop on `[END_COMMENTARY]` or `[END_DEVOTIONAL]`.
- [ ] Optional: add repetition penalty or nucleus (`topP`) for further quality tuning.

## Model/config wiring
- [x] Load special token IDs dynamically from tokenizer config; validate mappings at startup.
- [ ] Read `seq_len` (and other model metadata) from `export_report.json` at startup and set `seqLen` automatically.
- [ ] If re‑exported with larger context and KV cache, update app to use the reported `seq_len` and confirm end‑to‑end.

## Export recommendations (external to app)
- [ ] Re‑export the Core ML model with:
  - `seq_len` 768 or 1024 (to cover both commentary + devotional comfortably)
  - key–value cache enabled (`use_cache=True`) for faster generation
  - FP16 weights where applicable

## Diagnostics and tests
- [x] Remove hardcoded “verified test IDs” branch.
- [x] Log logits shape path (2D vs 3D) on first generation step.
- [x] Unit test: `formatInput` produces `MATTHEW_1_3` from "Matthew 1:3".
- [ ] UI smoke test: assert we reach `[END_COMMENTARY]` and `[END_DEVOTIONAL]` with default settings.

## Notes
- Device runs use `.cpuAndNeuralEngine`; simulator uses `.cpuOnly` to avoid MPSGraph issues. Keep as-is.
- Ensure all tokenizer assets live together in `Resources/ML/` and have target membership in the app target.


