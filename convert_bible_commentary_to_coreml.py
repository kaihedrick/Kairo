#!/usr/bin/env python3
"""
Convert Bible Commentary Model from Safetensors to CoreML

This script converts the GPT-2 based Bible commentary model from safetensors format
to CoreML format for use in iOS applications.

Usage:
    python convert_bible_commentary_to_coreml.py

Requirements:
    - transformers
    - torch
    - coremltools
    - safetensors
"""

import os
import json
import numpy as np
import torch
import coremltools as ct
from transformers import GPT2LMHeadModel, GPT2Tokenizer
from pathlib import Path

def load_model_and_tokenizer(model_path):
    """Load the GPT-2 model and tokenizer from the safetensors format."""
    print(f"🔍 Loading model from: {model_path}")
    
    # Load tokenizer
    tokenizer = GPT2Tokenizer.from_pretrained(model_path)
    
    # Load model
    model = GPT2LMHeadModel.from_pretrained(model_path)
    
    print(f"✅ Loaded model with {model.config.vocab_size} vocabulary size")
    print(f"✅ Model has {sum(p.numel() for p in model.parameters())} parameters")
    
    return model, tokenizer

def convert_to_coreml(model, tokenizer, output_path):
    """Convert the GPT-2 model to CoreML format."""
    print("🔧 Converting model to CoreML...")
    
    # Set model to evaluation mode
    model.eval()
    
    # Create a sample input for tracing - USE FULL SEQUENCE LENGTH
    sample_text = "[START_COMMENTARY] In the beginning God created the heaven and the earth."
    MAX_SEQ_LEN = 1024  # Match the export_report.json seq_len=1024
    inputs = tokenizer(sample_text, return_tensors="pt", max_length=MAX_SEQ_LEN, truncation=True, padding=True)

    print(f"📝 Sample input shape: {inputs['input_ids'].shape}")
    print(f"🔧 Exporting with sequence length: {MAX_SEQ_LEN}")

    # Define the input specification - USE FULL SEQUENCE LENGTH
    input_spec = [
        ct.TensorType(
            name="input_ids",
            shape=(1, MAX_SEQ_LEN),  # Batch size 1, max sequence length 1024
            dtype=np.int32
        ),
        ct.TensorType(
            name="attention_mask",
            shape=(1, MAX_SEQ_LEN),  # Batch size 1, max sequence length 1024
            dtype=np.int32
        )
    ]
    
    # Convert the model
    coreml_model = ct.convert(
        model,
        inputs=input_spec,
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.CPU_AND_GPU,
        convert_to="mlprogram"
    )
    
    # Save the model
    coreml_model.save(output_path)
    print(f"✅ CoreML model saved to: {output_path}")
    
    return coreml_model

def create_tokenizer_files(tokenizer, output_dir):
    """Create the necessary tokenizer files for iOS."""
    print("🔧 Creating tokenizer files...")
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Ensure PAD token consistency: PAD should equal EOS
    if tokenizer.pad_token is None:
        print("⚠️ Setting PAD token to EOS token for consistency")
        tokenizer.pad_token = tokenizer.eos_token
    
    # Save vocabulary
    vocab = tokenizer.get_vocab()
    vocab_path = os.path.join(output_dir, "vocab.json")
    with open(vocab_path, 'w') as f:
        json.dump(vocab, f, indent=2)
    print(f"✅ Vocabulary saved to: {vocab_path}")
    
    # Save BPE merges (critical for exact tokenization consistency)
    try:
        # Get the merges from the tokenizer
        if hasattr(tokenizer, 'bpe_ranks'):
            merges = []
            for pair, rank in sorted(tokenizer.bpe_ranks.items(), key=lambda x: x[1]):
                merges.append(f"{pair[0]} {pair[1]}")
            
            merges_path = os.path.join(output_dir, "merges.txt")
            with open(merges_path, 'w') as f:
                f.write("#version: 0.2\n")
                f.write("\n".join(merges))
            print(f"✅ BPE merges saved to: {merges_path}")
    except Exception as e:
        print(f"⚠️ Could not save BPE merges: {e}")
    
    # Save tokenizer config with comprehensive special token information
    tokenizer_config = {
        "vocab_size": len(vocab),
        "model_max_length": getattr(tokenizer, 'model_max_length', 1024),
        "bos_token": tokenizer.bos_token,
        "eos_token": tokenizer.eos_token,
        "unk_token": tokenizer.unk_token,
        "pad_token": tokenizer.pad_token,
        "additional_special_tokens": tokenizer.additional_special_tokens,
        "add_prefix_space": getattr(tokenizer, 'add_prefix_space', False),
        "added_tokens_decoder": {}
    }
    
    # Build comprehensive added_tokens_decoder for Swift compatibility
    # This ensures Swift can load the exact same special token IDs
    for token, token_id in vocab.items():
        if token in [tokenizer.bos_token, tokenizer.eos_token, tokenizer.unk_token, tokenizer.pad_token] or \
           token in tokenizer.additional_special_tokens:
            tokenizer_config["added_tokens_decoder"][str(token_id)] = {
                "content": token,
                "lstrip": False,
                "normalized": False,
                "rstrip": False,
                "single_word": False,
                "special": True
            }
    
    config_path = os.path.join(output_dir, "tokenizer_config.json")
    with open(config_path, 'w') as f:
        json.dump(tokenizer_config, f, indent=2)
    print(f"✅ Tokenizer config saved to: {config_path}")
    
    # Save special tokens map
    special_tokens = {
        "bos_token": tokenizer.bos_token,
        "eos_token": tokenizer.eos_token,
        "unk_token": tokenizer.unk_token,
        "pad_token": tokenizer.pad_token,
        "additional_special_tokens": tokenizer.additional_special_tokens
    }
    special_tokens_path = os.path.join(output_dir, "special_tokens_map.json")
    with open(special_tokens_path, 'w') as f:
        json.dump(special_tokens, f, indent=2)
    print(f"✅ Special tokens map saved to: {special_tokens_path}")
    
    # Create added_tokens.json for additional special tokens
    added_tokens = []
    for token in tokenizer.additional_special_tokens:
        if token in vocab:
            added_tokens.append({
                "id": vocab[token],
                "content": token,
                "single_word": False,
                "lstrip": False,
                "rstrip": False,
                "normalized": False,
                "special": True
            })
    
    if added_tokens:
        added_tokens_path = os.path.join(output_dir, "added_tokens.json")
        with open(added_tokens_path, 'w') as f:
            json.dump(added_tokens, f, indent=2)
        print(f"✅ Added tokens saved to: {added_tokens_path}")
    
    # PAD token consistency validation
    pad_id = vocab.get(tokenizer.pad_token)
    eos_id = vocab.get(tokenizer.eos_token)
    print(f"🔍 Token consistency check:")
    print(f"    PAD token: '{tokenizer.pad_token}' (ID: {pad_id})")
    print(f"    EOS token: '{tokenizer.eos_token}' (ID: {eos_id})")
    if pad_id == eos_id:
        print(f"✅ PAD == EOS: Consistent token handling")
    else:
        print(f"⚠️ PAD != EOS: Potential mismatch between training and Swift")

def main():
    """Main conversion function."""
    print("🚀 Starting Bible Commentary Model Conversion")
    
    # Define paths - POINT TO CORRECT MODEL LOCATION
    current_dir = Path(__file__).parent
    model_path = current_dir / "BibleAppPOCV2" / "ML" / "Models"  # Point to actual model location
    output_dir = current_dir / "BibleAppPOCV2" / "ML" / "Models"  # Save to same directory
    
    # Check if model path exists
    if not model_path.exists():
        print(f"❌ Model path not found: {model_path}")
        return
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    try:
        # Load model and tokenizer
        model, tokenizer = load_model_and_tokenizer(str(model_path))
        
        # Convert to CoreML
        coreml_path = output_dir / "bible_commentary_model.mlpackage"
        coreml_model = convert_to_coreml(model, tokenizer, str(coreml_path))
        
        # Create tokenizer files
        tokenizer_dir = output_dir / "tokenizer"
        create_tokenizer_files(tokenizer, str(tokenizer_dir))
        
        print("🎉 Conversion completed successfully!")
        print(f"📁 Output directory: {output_dir}")
        print(f"📦 CoreML model: {coreml_path}")
        print(f"🔤 Tokenizer files: {tokenizer_dir}")
        
    except Exception as e:
        print(f"❌ Conversion failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
