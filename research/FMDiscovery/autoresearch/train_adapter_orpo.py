#!/usr/bin/env python3
"""ORPO preference fine-tuning of the Apple 3B LoRA adapter — judgment transfer.

Plain SFT (v1/v2a/v2b) only ever maximised the likelihood of POSITIVE targets, so
it transferred the surface form of high-coverage question sets but not the
JUDGMENT of which axes matter (v2b's coverage stayed at rubric 3). ORPO adds a
preference signal WITHOUT a reference model: a standard SFT term on the CHOSEN set
plus an odds-ratio term that pushes the model to prefer CHOSEN over REJECTED.

We reuse the Apple toolkit wholesale (model load, tokenisation/collate via
`create_dataloader`, optimiser, scheduler, checkpoint saver, .fmadapter export) and
only add: (1) a second forward pass on the rejected set, (2) the ORPO loss. Chosen
and rejected loaders are both shuffle=False over index-aligned data, so zipping them
yields aligned pairs.

ORPO loss (Hong et al., EMNLP 2024):
    L = L_SFT(chosen) + lambda * L_OR
    L_OR = -log sigmoid( log_odds(chosen) - log_odds(rejected) )
    log_odds(y) = log p - log(1-p),  p = exp( mean token log-prob over y's response )

Usage (run inside the toolkit venv; see train_adapter_orpo.sh):
    python train_adapter_orpo.py --pairs adapter/data_orpo/train.jsonl \
        --eval-pairs adapter/data_orpo/valid.jsonl --epochs 6 --learning-rate 5e-4 \
        --batch-size 2 --gradient-accumulation-steps 2 --lambda-or 0.2 \
        --checkpoint-dir adapter/checkpoints --activation-checkpointing
"""
import argparse
import json
import os
import sys
from pathlib import Path

import torch
import torch.nn.functional as F
from tqdm import tqdm

PKG = Path(__file__).resolve().parent.parent
TOOLKIT = Path(os.environ.get("TOOLKIT", PKG / "adapter_training_toolkit_v26_0_0"))
sys.path.insert(0, str(TOOLKIT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from orpo_loss import orpo_ratio_loss, seq_mean_logprob  # noqa: E402

from examples.data import BatchKey, create_dataloader  # noqa: E402
from examples.train_adapter import (  # noqa: E402
    AdapterTrainingConfiguration,
    CrossEntropyLoss,
    _create_learning_rate_scheduler,
    _create_optimizer,
)
from examples.utils import (  # noqa: E402
    AdapterCheckpointSaver,
    apply_activation_checkpointing,
    autocast,
    get_device,
    get_logger,
    load_base_model,
    load_tokenizer,
)

logger = get_logger()


def _load_pairs(path):
    """Read ORPO pairs and split into two index-aligned message lists."""
    chosen, rejected = [], []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        p = json.loads(line)
        chosen.append(p["prompt"] + [{"role": "assistant", "content": p["chosen"]}])
        rejected.append(p["prompt"] + [{"role": "assistant", "content": p["rejected"]}])
    return chosen, rejected


def train_orpo(pairs, eval_pairs, config, checkpoint_dir, lambda_or):
    device = get_device()
    logger.info(f"ORPO fine-tuning (lambda_or={lambda_or}) on {device}, precision {config.model_dtype}")
    model = load_base_model(dtype=config.model_dtype, device=device)
    saver = AdapterCheckpointSaver(checkpoint_dir=checkpoint_dir, prefix="adapter", model=model)
    if config.enable_activation_checkpointing:
        apply_activation_checkpointing(model)
    logger.info(f"Total trainable parameters {sum(p.numel() for p in model.parameters() if p.requires_grad)}")

    tokenizer = load_tokenizer()
    pad_id = tokenizer.pad_id

    def loaders(path):
        c, r = _load_pairs(path)
        mk = lambda data: create_dataloader(  # noqa: E731
            data=data, tokenizer=tokenizer, batch_size=config.batch_size,
            max_sequence_length=config.max_sequence_length,
            fixed_sized_sequences=config.fixed_sized_sequences, packing=False, shuffle=False)
        return mk(c), mk(r), len(c)

    c_train, r_train, n_train = loaders(pairs)
    eval_loaders = loaders(eval_pairs) if eval_pairs else None

    optimizer = _create_optimizer(model=model, learning_rate=config.learning_rate, weight_decay=config.weight_decay)
    scheduler = _create_learning_rate_scheduler(
        optimizer=optimizer, batch_size=config.batch_size,
        gradient_accumulation_steps=config.gradient_accumulation_steps,
        training_samples=n_train, epochs=config.epochs, linear_warmup_epochs=config.linear_warmup_epochs)
    sft_loss = CrossEntropyLoss(pad_id=pad_id, ignore_id=-100)
    scaler = torch.GradScaler(device=device, enabled=config.use_gradient_scaling)

    def forward(batch):
        inp = batch[BatchKey.INPUT].to(device, non_blocking=True)
        lab = batch[BatchKey.LABEL].to(device, non_blocking=True)
        seg = batch[BatchKey.SEGMENT_ID].to(device, non_blocking=True)
        logits = model(inp, segment_ids=seg).logits
        return logits, lab

    def run_epoch(c_loader, r_loader, train):
        model.train() if train else model.eval()
        total, n = 0.0, 0
        pbar = tqdm(zip(c_loader, r_loader), total=len(c_loader),
                    desc="ORPO-train" if train else "ORPO-eval", ascii=" =")
        for batch_idx, (cb, rb) in enumerate(pbar):
            with autocast(device=device, dtype=config.autocast_dtype):
                logits_c, lab_c = forward(cb)
                logits_r, lab_r = forward(rb)
                l_sft = sft_loss(logits_c, lab_c)
                lp_c = seq_mean_logprob(logits_c, lab_c, pad_id)
                lp_r = seq_mean_logprob(logits_r, lab_r, pad_id)
                l_or = orpo_ratio_loss(lp_c, lp_r)
                loss = l_sft + lambda_or * l_or
            if train:
                scaled = scaler.scale(loss / config.gradient_accumulation_steps)
                scaled.backward()
                if ((batch_idx + 1) % config.gradient_accumulation_steps == 0) or (batch_idx + 1 == len(c_loader)):
                    if config.clip_grad_norm is not None:
                        torch.nn.utils.clip_grad_norm_(model.parameters(), config.clip_grad_norm)
                    scaler.step(optimizer); scaler.update(); optimizer.zero_grad(set_to_none=True); scheduler.step()
            total += loss.detach().item(); n += 1
            pbar.set_postfix(loss=total / max(1, n), sft=l_sft.detach().item(), orpo=l_or.detach().item())
        return total / max(1, n)

    for epoch in range(config.epochs):
        logger.info(f"Epoch {epoch + 1}/{config.epochs}")
        train_loss = run_epoch(c_train, r_train, train=True)
        eval_loss = None
        if eval_loaders:
            with torch.inference_mode():
                eval_loss = run_epoch(eval_loaders[0], eval_loaders[1], train=False)
            logger.info(f"eval loss {eval_loss:.4f}")
        saver.save(state_dict=model.state_dict(), epoch=epoch + 1, metric=eval_loss or train_loss)


def main():
    ap = argparse.ArgumentParser(description="ORPO preference fine-tuning of the 3B LoRA adapter")
    ap.add_argument("--pairs", required=True, help="train ORPO pairs jsonl (prompt/chosen/rejected)")
    ap.add_argument("--eval-pairs", default=None, help="eval ORPO pairs jsonl")
    ap.add_argument("--epochs", type=int, default=6)
    ap.add_argument("--learning-rate", type=float, default=5e-4)
    ap.add_argument("--batch-size", type=int, default=2)
    ap.add_argument("--gradient-accumulation-steps", type=int, default=2)
    ap.add_argument("--warmup-epochs", type=int, default=1)
    ap.add_argument("--weight-decay", type=float, default=1e-2)
    ap.add_argument("--clip-grad-norm", type=float, default=1.0)
    ap.add_argument("--max-sequence-length", type=int, default=1024)
    ap.add_argument("--activation-checkpointing", action="store_true")
    ap.add_argument("--precision", default="bf16-mixed")
    ap.add_argument("--lambda-or", type=float, default=0.2, help="weight of the ORPO odds-ratio term")
    ap.add_argument("--checkpoint-dir", required=True)
    args = ap.parse_args()

    config = AdapterTrainingConfiguration(
        epochs=args.epochs, learning_rate=args.learning_rate, batch_size=args.batch_size,
        linear_warmup_epochs=args.warmup_epochs, gradient_accumulation_steps=args.gradient_accumulation_steps,
        enable_activation_checkpointing=args.activation_checkpointing, precision=args.precision,
        weight_decay=args.weight_decay, clip_grad_norm=args.clip_grad_norm,
        max_sequence_length=args.max_sequence_length, fixed_sized_sequences=False, pack_sequences=False)
    train_orpo(args.pairs, args.eval_pairs, config, args.checkpoint_dir, args.lambda_or)


if __name__ == "__main__":
    main()
