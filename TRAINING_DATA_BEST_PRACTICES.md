# Training Data Best Practices for Bible Commentary Model

## 🚨 Problem: Verse ID Duplication in Training Data

### Current Issue
The `format_complete_example` function duplicates VERSE_ID and VERSE_REF in both prompt and target, which can cause:
- Model to repeat verse references in commentary/devotional
- Confusion during inference where model gets stuck outputting references
- Inefficient token usage

### ❌ Problematic Format (To Avoid)
```python
def format_complete_example(verse_ref, verse_text, commentary, devotional):
    # PROBLEMATIC: Duplicates verse metadata in target
    prompt = f"""[VERSE_ID] {verse_ref.replace(' ', '_').upper()}
[VERSE_REF] {verse_ref}
[VERSE_TEXT] {verse_text}
[VERSE]
[START_COMMENTARY]"""
    
    target = f"""[VERSE_ID] {verse_ref.replace(' ', '_').upper()}
[VERSE_REF] {verse_ref}
[VERSE_TEXT] {verse_text}
[VERSE]
[START_COMMENTARY] {commentary} [END_COMMENTARY]
[START_DEVOTIONAL] {devotional} [END_DEVOTIONAL]"""
    
    return prompt, target
```

### ✅ Recommended Format (Clean Target)
```python
def format_complete_example(verse_ref, verse_text, commentary, devotional):
    # CLEAN: No duplicate verse metadata in target
    prompt = f"""[VERSE_ID] {verse_ref.replace(' ', '_').upper()}
[VERSE_REF] {verse_ref}
[VERSE_TEXT] {verse_text}
[VERSE]
[START_COMMENTARY]"""
    
    # Target only contains the generated content
    target = f"""[START_COMMENTARY] {commentary} [END_COMMENTARY]
[START_DEVOTIONAL] {devotional} [END_DEVOTIONAL]"""
    
    return prompt, target
```

## 🔧 PAD Token Consistency

### Problem
Training uses `pad_token = eos_token`, but CoreML export may add separate `[PAD]` token.

### Solution
```python
# In training setup
tokenizer.pad_token = tokenizer.eos_token  # Ensure consistency

# In export validation
def validate_pad_token_consistency(tokenizer):
    pad_id = tokenizer.convert_tokens_to_ids(tokenizer.pad_token)
    eos_id = tokenizer.convert_tokens_to_ids(tokenizer.eos_token)
    
    if pad_id != eos_id:
        print(f"⚠️ PAD mismatch: PAD={pad_id}, EOS={eos_id}")
        print("Consider setting tokenizer.pad_token = tokenizer.eos_token")
    else:
        print(f"✅ PAD == EOS: {pad_id}")
```

## 🛑 Stop Token Best Practices

### Multiple Stop Conditions
Ensure training data consistently uses both stop tokens:

```python
def create_training_example(verse_ref, verse_text, commentary, devotional):
    # Always include both commentary and devotional sections
    target = f"""[START_COMMENTARY] {commentary} [END_COMMENTARY]
[START_DEVOTIONAL] {devotional} [END_DEVOTIONAL]"""
    
    return target
```

### Swift Generation Should Handle Both
```swift
// In BibleCommentaryGenerator.swift
if next == endDevotionalId || next == endCommentaryId { 
    done = true 
}
```

## 🔍 Data Validation Checklist

### Pre-Training Validation
- [ ] No duplicate verse metadata in targets
- [ ] PAD token == EOS token
- [ ] All examples end with `[END_DEVOTIONAL]`
- [ ] Commentary and devotional sections are clearly separated
- [ ] Special tokens are consistently applied

### Post-Export Validation
- [ ] Swift tokenizer loads same vocab.json and merges.txt
- [ ] Special token IDs match between Python and Swift
- [ ] PAD token consistency verified
- [ ] Stop conditions handle both end tokens

## 🧪 Testing Recommendations

### Round-Trip Testing
```python
def test_tokenizer_consistency():
    # Test that Python and Swift produce identical token sequences
    test_text = "[VERSE_ID] JOHN_3_16 [VERSE_REF] John 3:16 [VERSE_TEXT] For God so loved..."
    
    python_tokens = python_tokenizer.encode(test_text)
    # Compare with Swift output
    
    assert python_tokens == swift_tokens, "Tokenizer mismatch detected"
```

### Generation Testing
```python
def test_generation_stops():
    # Verify model stops on both end tokens
    test_cases = [
        "Should stop on [END_COMMENTARY]",
        "Should stop on [END_DEVOTIONAL]", 
        "Should handle incomplete generation gracefully"
    ]
```

## 📋 Migration Steps

If you need to fix existing training data:

1. **Audit Current Data Format**
   ```bash
   grep -n "VERSE_ID.*VERSE_ID" training_data.txt
   ```

2. **Remove Target Duplication**
   ```python
   # Script to clean existing training data
   def clean_training_example(example):
       # Remove duplicate verse metadata from targets
       # Keep only commentary/devotional content
   ```

3. **Validate Token Consistency**
   ```python
   # Run tokenizer validation before training
   validate_pad_token_consistency(tokenizer)
   ```

4. **Test Generation Quality**
   ```python
   # Generate samples and check for repetition
   sample_generations = model.generate(test_prompts)
   check_for_verse_repetition(sample_generations)
   ```

## 🎯 Expected Benefits

After implementing these fixes:
- ✅ No repeated verse references in output
- ✅ Cleaner, more focused commentary/devotional content  
- ✅ Consistent tokenization between Python and Swift
- ✅ Reliable stop conditions in generation
- ✅ Better token efficiency during training and inference

---

*This guide should be implemented before retraining any models to ensure optimal quality and consistency.*
