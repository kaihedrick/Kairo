#!/usr/bin/env python3
"""
Optimized GPT-2 Training Script (Patched)
- No re-init after resize_token_embeddings
- evaluation_strategy + fp16 + fused AdamW + torch.compile
- Dynamic padding + loss masking before [START_COMMENTARY] in collator
- Optional "deep metrics" decoding switch
"""

import os
import json
import torch
import numpy as np
from transformers import (
    GPT2LMHeadModel,
    GPT2Tokenizer,
    TrainingArguments,
    Trainer,
    DataCollatorForLanguageModeling,
    StoppingCriteria,
)
from datasets import Dataset
from typing import List, Dict, Any
import logging

# ----------------------
# Logging
# ----------------------
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ----------------------
# Custom Stopping Criteria for [END_DEVOTIONAL]
# ----------------------
class EndDevotionalStoppingCriteria(StoppingCriteria):
    def __init__(self, tokenizer):
        self.tokenizer = tokenizer
        self.end_devotional_id = tokenizer.convert_tokens_to_ids("[END_DEVOTIONAL]")
    
    def __call__(self, input_ids, scores, **kwargs):
        # Stop if [END_DEVOTIONAL] appears in the generated sequence
        for sequence in input_ids:
            if self.end_devotional_id in sequence:
                return True
        return False

# ----------------------
# Collator: mask loss until [START_COMMENTARY]
# ----------------------
class StructureAwareCollator:
    def __init__(self, tokenizer, start_token="[START_COMMENTARY]"):
        self.tokenizer = tokenizer
        self.start_id = tokenizer.convert_tokens_to_ids(start_token)
        self.base = DataCollatorForLanguageModeling(tokenizer=tokenizer, mlm=False)

    def __call__(self, features):
        batch = self.base(features)
        labels = batch["labels"]
        # also ignore padding tokens for loss (-100 where attention_mask == 0)
        if "attention_mask" in batch:
            pad_mask = (batch["attention_mask"] == 0)
            labels[pad_mask] = -100
        # ignore everything before first [START_COMMENTARY]
        for i in range(labels.size(0)):
            ids = labels[i]
            pos = (ids == self.start_id).nonzero(as_tuple=True)[0]
            cutoff = int(pos[0]) if len(pos) else 0
            if cutoff > 0:
                labels[i, :cutoff] = -100
        batch["labels"] = labels
        return batch


class OptimizedGPT2Trainer:
    def __init__(self, model_name: str = "gpt2", data_dir: str = "data/output/all_books_by_chapter_concurrent"):
        self.model_name = model_name
        self.data_dir = data_dir
        self.max_length = 768  # Increased to accommodate full commentary + devotional + structure tokens
        self.tokenizer = None
        self.model = None

        self.special_tokens = {
            "start_commentary": "[START_COMMENTARY]",
            "end_commentary": "[END_COMMENTARY]",
            "start_devotional": "[START_DEVOTIONAL]",
            "end_devotional": "[END_DEVOTIONAL]",
            "verse_separator": "[VERSE]",
            "verse_reference": "[VERSE_REF]",
            "verse_text": "[VERSE_TEXT]",
            "verse_id": "[VERSE_ID]",
            "pad_token": "[PAD]",
        }

    def normalize_verse_id(self, verse_ref: str) -> str:
        return verse_ref.replace(" ", "_").replace(":", "_").upper()

    def validate_and_format_verse_reference(self, verse_id: str) -> str:
        """
        Ensures verse_id contains proper chapter:verse format.
        Returns formatted reference or None if invalid.
        """
        if not verse_id:
            return None
            
        # Remove any extra whitespace and normalize
        verse_id = verse_id.strip()
        
        # Check if it already has chapter:verse format
        if ":" in verse_id:
            # Already has verse number, validate format
            parts = verse_id.split(":")
            if len(parts) == 2 and parts[1].isdigit():
                return verse_id
        
        # Check if it's just a book name (e.g., "Matthew")
        # This would indicate missing chapter/verse info
        if verse_id and " " not in verse_id and ":" not in verse_id:
            logger.warning(f"Invalid verse reference format: '{verse_id}' - missing chapter and verse")
            return None
            
        # Check if it's book chapter format without verse (e.g., "Matthew 1")
        if " " in verse_id and ":" not in verse_id:
            parts = verse_id.split(" ")
            if len(parts) >= 2 and parts[-1].isdigit():
                logger.warning(f"Invalid verse reference format: '{verse_id}' - missing verse number")
                return None
        
        # If we get here, assume it's properly formatted
        return verse_id

    def load_tokenizer(self):
        logger.info(f"Loading tokenizer: {self.model_name}")
        self.tokenizer = GPT2Tokenizer.from_pretrained(self.model_name)
        # Register specials once
        special_tokens_dict = {
            "additional_special_tokens": [
                "[VERSE_ID]", "[VERSE_REF]", "[VERSE_TEXT]", "[VERSE]",
                "[START_COMMENTARY]", "[END_COMMENTARY]", "[START_DEVOTIONAL]",
                "[END_DEVOTIONAL]", "[PAD]",
            ]
        }
        self.tokenizer.add_special_tokens(special_tokens_dict)
        # pad_token = eos is fine for Causal LM when masking labels on pad
        self.tokenizer.pad_token = self.tokenizer.eos_token
        logger.info(f"Vocab size: {len(self.tokenizer)} | pad_token={self.tokenizer.pad_token}")
        return self.tokenizer

    def extend_position_embeddings(self, model, new_length=1024):
        # only extend if needed; keeping 1024 is friendlier for speed & iPhone
        old_len = model.config.max_position_embeddings
        if old_len >= new_length:
            return model
        logger.info(f"Extending pos embeddings: {old_len} -> {new_length}")
        old_wpe = model.transformer.wpe
        dim = old_wpe.weight.shape[1]
        new_wpe = torch.nn.Embedding(new_length, dim)
        with torch.no_grad():
            new_wpe.weight[:old_len] = old_wpe.weight
            # simple copy for extra positions; interpolation optional
            for i in range(old_len, new_length):
                new_wpe.weight[i] = old_wpe.weight[-1]
        model.transformer.wpe = new_wpe
        model.config.max_position_embeddings = new_length
        # keep these in sync for legacy consumers
        model.config.n_positions = new_length
        model.config.n_ctx = new_length
        return model

    def load_model(self):
        logger.info(f"Loading model: {self.model_name}")
        
        # Try to load from best checkpoint first, fallback to base model
        best_checkpoint = "models/gpt2_structured_20250808_1715/checkpoint-3900"  # Latest checkpoint
        if os.path.exists(best_checkpoint):
            try:
                logger.info(f"Loading from best checkpoint: {best_checkpoint}")
                self.model = GPT2LMHeadModel.from_pretrained(
                    best_checkpoint,
                    torch_dtype=torch.float32,
                    low_cpu_mem_usage=False
                )
                logger.info("✅ Successfully loaded from best checkpoint")
            except Exception as e:
                logger.warning(f"Failed to load from checkpoint: {e}")
                logger.info("Falling back to base model")
                self.model = GPT2LMHeadModel.from_pretrained(
                    self.model_name,
                    torch_dtype=torch.float32,
                    low_cpu_mem_usage=False
                )
        else:
            self.model = GPT2LMHeadModel.from_pretrained(
                self.model_name,
                torch_dtype=torch.float32,
                low_cpu_mem_usage=False
            )
        
        # modest context (1024) for speed; bump if you truly need 2048
        self.model = self.extend_position_embeddings(self.model, new_length=max(1024, self.max_length))
        # Resize for new tokens (no manual re-init!)
        self.model.resize_token_embeddings(len(self.tokenizer))
        # speed/VRAM knobs for 3080
        self.model.gradient_checkpointing_enable()
        torch.backends.cuda.matmul.allow_tf32 = True
        logger.info(f"Params: {sum(p.numel() for p in self.model.parameters()):,}")
        return self.model

    def load_training_data(self, data_dir: str) -> List[Dict[str, str]]:
        data = []
        files = [f for f in os.listdir(data_dir) if f.endswith(".json")]
        logger.info(f"Found {len(files)} JSON files in {data_dir}")
        for jf in files:
            fp = os.path.join(data_dir, jf)
            try:
                with open(fp, "r", encoding="utf-8") as f:
                    jd = json.load(f)
                if isinstance(jd, list):
                    logger.info(f"Loaded {len(jd)} items from {jf}")
                    for item in jd:
                        verse_id = item.get("verse_id", "")
                        verse_text = item.get("verse_text", "")
                        commentary = item.get("commentary", "")
                        devotional = item.get("devotional_summary", "")
                        
                        # Validate verse reference format
                        formatted_verse_id = self.validate_and_format_verse_reference(verse_id)
                        if not formatted_verse_id:
                            logger.warning(f"Skipping item with invalid verse_id: '{verse_id}'")
                            continue
                            
                        if formatted_verse_id and verse_text and commentary and devotional:
                            data.append({
                                "verse_id": formatted_verse_id,
                                "verse_text": verse_text,
                                "commentary": commentary,
                                "devotional": devotional,
                            })
            except Exception as e:
                logger.warning(f"Error loading {jf}: {e}")
        logger.info(f"Total training examples: {len(data)}")
        return data

    def format_complete_example(self, verse_id: str, verse_text: str, commentary: str, devotional: str) -> str:
        if not (verse_id and verse_text and commentary and devotional):
            return None
        verse_ref = verse_id.strip()
        verse_content = verse_text.strip()
        vid_norm = self.normalize_verse_id(verse_ref)

        prompt = (
            f"{self.special_tokens['verse_id']} {vid_norm}\n"
            f"{self.special_tokens['verse_reference']} {verse_ref}\n"
            f"{self.special_tokens['verse_text']} {verse_content}\n"
            f"{self.special_tokens['verse_separator']}\n"
        )
        target = (
            f"{self.special_tokens['verse_id']} {vid_norm}\n"
            f"{self.special_tokens['verse_reference']} {verse_ref}\n"
            f"{self.special_tokens['start_commentary']}\n"
            f"Commentary on {self.special_tokens['verse_reference']} {verse_ref}: {commentary}\n"
            f"{self.special_tokens['end_commentary']}\n\n"
            f"{self.special_tokens['start_devotional']}\n"
            f"Devotional on {self.special_tokens['verse_reference']} {verse_ref}: {devotional}\n"
            f"{self.special_tokens['end_devotional']}"
        )
        out = prompt + target
        essentials = ["[START_COMMENTARY]", "[END_COMMENTARY]", "[START_DEVOTIONAL]", "[END_DEVOTIONAL]"]
        return out if all(tok in out for tok in essentials) else None

    def prepare_dataset(self, data: List[Dict[str, Any]]) -> Dataset:
        texts = []
        for s in data:
            t = self.format_complete_example(
                s.get("verse_id",""),
                s.get("verse_text",""),
                s.get("commentary",""),
                s.get("devotional",""),
            )
            if t and len(t) > 200:
                texts.append({"text": t})

        if not texts:
            raise RuntimeError("No formatted examples generated.")
        ds = Dataset.from_list(texts)

        # dynamic padding — no "padding=max_length"
        def tok_map(batch):
            return self.tokenizer(
                batch["text"],
                truncation=True,
                max_length=self.max_length,
            )

        logger.info("Tokenizing dataset (dynamic padding)...")
        tds = ds.map(tok_map, batched=True, remove_columns=ds.column_names)
        return tds

    # Optional deep metrics (decoding-heavy). Gate behind a flag.
    def build_trainer(self, train_dataset, eval_dataset, output_dir, deep_metrics=False):
        from transformers import TrainerCallback

        class StructureTokenCallback(TrainerCallback):
            def on_evaluate(self, args, state, control, metrics=None, **kwargs):
                if metrics is None:
                    return
                logger.info("Structure Token Analysis (summary):")
                for k in ["eval_structure_score","eval_commentary_completeness","eval_devotional_completeness",
                          "eval_structure_token_completeness","eval_verse_accuracy","eval_hallucinations"]:
                    if k in metrics:
                        logger.info(f"  - {k}: {metrics[k]}")
                
                # Enhanced structure tracking
                if "eval_structure_score" in metrics:
                    score = metrics["eval_structure_score"]
                    if score >= 95:
                        logger.info("  🎯 EXCELLENT: Structure score >= 95/100")
                    elif score >= 80:
                        logger.info("  ✅ GOOD: Structure score >= 80/100")
                    elif score >= 60:
                        logger.info("  📈 IMPROVING: Structure score >= 60/100")
                    else:
                        logger.info("  ⚠️ NEEDS WORK: Structure score < 60/100")

        def compute_metrics(eval_pred):
            # Periodic deep metrics: every 1200 steps (roughly every 2 epochs)
            if not deep_metrics:
                # Get current global step from trainer state
                try:
                    current_step = trainer.state.global_step if hasattr(trainer, 'state') else 0
                    if current_step % 1200 != 0:  # Only compute deep metrics every 1200 steps
                        return {}
                except:
                    return {}
            
            preds, labels = eval_pred
            preds = np.argmax(preds, axis=-1)
            dec_p = self.tokenizer.batch_decode(preds, skip_special_tokens=False)
            dec_l = self.tokenizer.batch_decode(labels, skip_special_tokens=False)

            import re
            verse_pattern = r'\b(?:Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|Samuel|Kings|Chronicles|Ezra|Nehemiah|Esther|Job|Psalms?|Proverbs|Ecclesiastes|Song of Solomon|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|Matthew|Mark|Luke|John|Acts|Romans|Corinthians|Galatians|Ephesians|Philippians|Colossians|Thessalonians|Timothy|Titus|Philemon|Hebrews|James|Peter|John|Jude|Revelation)\s+\d+:\d+\b'
            ss, ca, da, stc, va, hall = [], [], [], [], [], []
            for p, l in zip(dec_p, dec_l):
                has_sc = "[START_COMMENTARY]" in p
                has_ec = "[END_COMMENTARY]" in p
                has_sd = "[START_DEVOTIONAL]" in p
                has_ed = "[END_DEVOTIONAL]" in p
                has_sep = "[VERSE]" in p
                score = 0
                score += 20 if has_sc else 0
                score += 20 if has_ec else 0
                score += 20 if has_sd else 0
                score += 20 if has_ed else 0
                score += 20 if has_sep else 0
                ss.append(score)
                ca.append(1 if (has_sc and has_ec) else 0)
                da.append(1 if (has_sd and has_ed) else 0)
                toks = ["[START_COMMENTARY]","[END_COMMENTARY]","[START_DEVOTIONAL]","[END_DEVOTIONAL]","[VERSE]"]
                stc.append(sum(tok in p for tok in toks)/len(toks))
                pred_refs = re.findall(verse_pattern, p, flags=re.IGNORECASE)
                lab_refs = re.findall(verse_pattern, l, flags=re.IGNORECASE)
                correct = sum(1 for r in pred_refs if r in lab_refs)
                va.append(correct/max(len(pred_refs),1))
                hall.append(sum(1 for r in pred_refs if r not in lab_refs))
            return {
                "eval_structure_score": float(np.mean(ss)),
                "eval_commentary_completeness": float(np.mean(ca)),
                "eval_devotional_completeness": float(np.mean(da)),
                "eval_structure_token_completeness": float(np.mean(stc)),
                "eval_verse_accuracy": float(np.mean(va)),
                "eval_hallucinations": float(np.sum(hall)),
            }

        data_collator = StructureAwareCollator(self.tokenizer)

        args = TrainingArguments(
            output_dir=output_dir,
            # core training knobs
            num_train_epochs=32,  # Increased to 32 epochs for complete structure learning
            per_device_train_batch_size=8,
            per_device_eval_batch_size=8,
            gradient_accumulation_steps=2,
            learning_rate=2e-4,
            lr_scheduler_type="cosine",
            warmup_ratio=0.03,
            weight_decay=0.1,

            # eval / logging / saving
            eval_strategy="steps",
            eval_steps=300,
            logging_strategy="steps",
            logging_steps=50,
            save_strategy="steps",
            save_steps=300,
            report_to="none",

            # model mgmt
            load_best_model_at_end=True,
            metric_for_best_model="eval_loss",
            greater_is_better=False,
            save_total_limit=3,
            remove_unused_columns=False,

            # speedups (tweak if needed)
            fp16=True,
            optim="adamw_torch",  # Standard optimizer for Windows compatibility
            torch_compile=False,  # Disabled for Windows compatibility
            dataloader_pin_memory=True,
            dataloader_num_workers=4,

            # optional: compute only loss during routine evals
            prediction_loss_only=(not deep_metrics),
            
            # avoid torch.load issues
            save_safetensors=True,
        )

        trainer = Trainer(
            model=self.model,
            args=args,
            train_dataset=train_dataset,
            eval_dataset=eval_dataset,
            processing_class=self.tokenizer,    # modern API
            data_collator=data_collator,
            compute_metrics=compute_metrics,
        )
        trainer.add_callback(StructureTokenCallback())
        return trainer

    def train(self, data_dir: str, output_dir: str = None, deep_metrics: bool = False):
        self.load_tokenizer()
        self.load_model()

        if output_dir is None:
            from datetime import datetime
            output_dir = f"models/gpt2_structured_{datetime.now().strftime('%Y%m%d_%H%M')}"

        os.makedirs(output_dir, exist_ok=True)
        os.makedirs(f"{output_dir}/debug_logs", exist_ok=True)

        data = self.load_training_data(data_dir)
        if not data:
            raise RuntimeError("No training data found!")

        dataset = self.prepare_dataset(data)
        # split
        train_size = int(0.9 * len(dataset))
        eval_size = len(dataset) - train_size
        train_dataset, eval_dataset = torch.utils.data.random_split(dataset, [train_size, eval_size])
        logger.info(f"Train: {len(train_dataset)} | Eval: {len(eval_dataset)}")

        trainer = self.build_trainer(train_dataset, eval_dataset, output_dir, deep_metrics=deep_metrics)

        # Robust checkpoint detection and resumption
        def find_resume_checkpoint(output_dir: str):
            """Find the best available checkpoint with trainer_state.json"""
            from pathlib import Path
            out = Path(output_dir)
            
            # Look for checkpoint-* directories with trainer_state.json
            ckpts = sorted(out.glob('checkpoint-*'), key=lambda p: int(p.name.split('-')[-1]))
            for p in reversed(ckpts):
                if (p / 'trainer_state.json').exists():
                    return str(p)
            return None
        
        # Try to resume from best checkpoint first
        best_checkpoint = "models/gpt2_structured_20250808_1715/checkpoint-3900"  # Latest checkpoint with trainer_state.json
        resume_from = None
        
        if os.path.exists(best_checkpoint) and os.path.exists(os.path.join(best_checkpoint, 'trainer_state.json')):
            logger.info(f"Resuming from best checkpoint: {best_checkpoint}")
            resume_from = best_checkpoint
        else:
            # Try to find a valid checkpoint in the output directory
            resume_ckpt = find_resume_checkpoint(output_dir)
            if resume_ckpt:
                logger.info(f"Resuming from last valid checkpoint: {resume_ckpt}")
                resume_from = resume_ckpt
            else:
                logger.info("No valid checkpoint found; starting fresh training")
                resume_from = None
        
        # Train with graceful error handling
        try:
            if resume_from:
                trainer.train(resume_from_checkpoint=resume_from)
            else:
                trainer.train()
        except FileNotFoundError as e:
            logger.warning(f"Checkpoint resume failed: {e}")
            logger.info("Falling back to fresh training without resume")
            trainer.train()

        trainer.save_model()
        self.tokenizer.save_pretrained(output_dir)
        logger.info(f"Training complete. Saved to {output_dir}")
        return trainer

    # Simple generation test (unchanged, but uses current max_length)
    def test_generation(self, verse: str, model_dir: str):
        self.model = GPT2LMHeadModel.from_pretrained(model_dir)
        self.tokenizer = GPT2Tokenizer.from_pretrained(model_dir)
        inp = f"{self.special_tokens['verse_reference']} {verse}\n{self.special_tokens['verse_separator']}\n"
        ids = self.tokenizer.encode(inp, return_tensors="pt")
        with torch.no_grad():
            out = self.model.generate(
                ids,
                max_length=min(self.max_length*2, 1024),
                temperature=0.7,
                do_sample=True,
                top_k=50,
                top_p=0.9,
                pad_token_id=self.tokenizer.eos_token_id,
                eos_token_id=self.tokenizer.eos_token_id,
                repetition_penalty=1.1,
                stopping_criteria=[EndDevotionalStoppingCriteria(self.tokenizer)],
            )
        txt = self.tokenizer.decode(out[0], skip_special_tokens=False)
        return txt


def main():
    trainer = OptimizedGPT2Trainer(
        model_name="gpt2",
        data_dir="data/output/all_books_by_chapter_concurrent",
    )
    # Start at 768 for full structure training
    trainer.max_length = 768

    trainer.train(
        data_dir="data/output/all_books_by_chapter_concurrent",
        output_dir=None,           # auto timestamp dir
        deep_metrics=False,        # True = enable decoding-heavy metrics
    )

    logger.info("Done. Ready for ONNX → Core ML export.")

if __name__ == "__main__":
    main()
