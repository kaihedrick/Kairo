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
    
    # Create a sample input for tracing
    sample_text = "[START_COMMENTARY] In the beginning God created the heaven and the earth."
    inputs = tokenizer(sample_text, return_tensors="pt", max_length=512, truncation=True, padding=True)
    
    print(f"📝 Sample input shape: {inputs['input_ids'].shape}")
    
    # Define the input specification
    input_spec = [
        ct.TensorType(
            name="input_ids",
            shape=(1, 512),  # Batch size 1, max sequence length 512
            dtype=np.int32
        ),
        ct.TensorType(
            name="attention_mask",
            shape=(1, 512),  # Batch size 1, max sequence length 512
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
    
    # Save vocabulary
    vocab = tokenizer.get_vocab()
    vocab_path = os.path.join(output_dir, "vocab.json")
    with open(vocab_path, 'w') as f:
        json.dump(vocab, f, indent=2)
    print(f"✅ Vocabulary saved to: {vocab_path}")
    
    # Save tokenizer config
    config_path = os.path.join(output_dir, "tokenizer_config.json")
    with open(config_path, 'w') as f:
        json.dump(tokenizer.init_kwargs, f, indent=2)
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

def main():
    """Main conversion function."""
    print("🚀 Starting Bible Commentary Model Conversion")
    
    # Define paths
    current_dir = Path(__file__).parent
    model_path = current_dir / "BibleAppPOCV2" / "Resources" / "ML" / "bible_commentary_model_export"
    output_dir = current_dir / "BibleAppPOCV2" / "Resources" / "ML" / "bible_commentary_coreml"
    
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
