#!/usr/bin/env python3
"""GRPO policy fine-tuning of the Apple 3B LoRA adapter — on-policy judge reward.

SFT (v1/v2a) maximised the likelihood of POSITIVE targets; ORPO added a pairwise
odds-ratio term. Both plateaued ~0.41 with coverage pinned at 3. GRPO instead pushes
the policy directly up the JUDGE's reward: for a GROUP of the model's OWN drafts of the
same task, each scored by the frozen Sonnet rubric, the group mean is the baseline (no
critic) and the policy is moved toward the above-average drafts and away from the
below-average ones — the first objective in this project to optimise the metric itself
rather than imitate a target.

We reuse the Apple toolkit wholesale (model load, create_dataloader, optimiser,
scheduler, checkpoint saver, export) and the ORPO `seq_mean_logprob`, and add only:
  (1) WARM-START from the 0.409 SFT champion (adapter/checkpoints_v2a/adapter-epoch1.pt)
      so RL refines a good policy instead of relearning the task from base;
  (2) the GRPO policy-gradient loss (grpo_loss.grpo_policy_loss).
Advantages are PRE-COMPUTED per row by build_grpo_data.py (whole group in hand), so the
dataloader can batch freely without corrupting group normalisation. Rows are loaded
shuffle=False and the advantage array is sliced by the batch's actual sequence count, so
advantages stay aligned to their completions.

Usage (inside the toolkit venv; see run_grpo.sh):
    python train_adapter_grpo.py --rows adapter/data_grpo/train.jsonl \
        --eval-rows adapter/data_grpo/valid.jsonl --warm-start adapter/checkpoints_v2a/adapter-epoch1.pt \
        --epochs 3 --learning-rate 1e-4 --batch-size 2 --gradient-accumulation-steps 2 \
        --checkpoint-dir adapter/checkpoints_grpo --activation-checkpointing
"""
import argparse
import json
import os
import sys
from pathlib import Path

import torch

PKG = Path(__file__).resolve().parent.parent
TOOLKIT = Path(os.environ.get("TOOLKIT", PKG / "adapter_training_toolkit_v26_0_0"))
sys.path.insert(0, str(TOOLKIT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from grpo_loss import grpo_policy_loss  # noqa: E402
from orpo_loss import seq_mean_logprob  # noqa: E402

from examples.data import BatchKey, create_dataloader  # noqa: E402
from examples.train_adapter import (  # noqa: E402
    AdapterTrainingConfiguration,
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


def _load_rows(path):
    """Read GRPO rows → (message lists, advantages) index-aligned."""
    msgs, advs = [], []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        r = json.loads(line)
        msgs.append(r["prompt"] + [{"role": "assistant", "content": r["completion"]}])
        advs.append(float(r["advantage"]))
    return msgs, advs


def train_grpo(rows, eval_rows, config, checkpoint_dir, warm_start, beta_kl):
    device = get_device()
    logger.info(f"GRPO fine-tuning on {device}, precision {config.model_dtype}, beta_kl={beta_kl}")
    model = load_base_model(dtype=config.model_dtype, device=device)
    if warm_start:
        sd = torch.load(warm_start, map_location=device)
        sd = sd.get("model", sd) if isinstance(sd, dict) else sd
        missing, unexpected = model.load_state_dict(sd, strict=False)
        logger.info(f"warm-started from {warm_start} (missing {len(missing)}, unexpected {len(unexpected)})")
    saver = AdapterCheckpointSaver(checkpoint_dir=checkpoint_dir, prefix="adapter", model=model)
    if config.enable_activation_checkpointing:
        apply_activation_checkpointing(model)
    logger.info(f"Total trainable parameters {sum(p.numel() for p in model.parameters() if p.requires_grad)}")

    tokenizer = load_tokenizer()
    pad_id = tokenizer.pad_id

    def loader(path):
        msgs, advs = _load_rows(path)
        dl = create_dataloader(
            data=msgs, tokenizer=tokenizer, batch_size=config.batch_size,
            max_sequence_length=config.max_sequence_length,
            fixed_sized_sequences=config.fixed_sized_sequences, packing=False, shuffle=False)
        return dl, torch.tensor(advs, dtype=torch.float32), len(msgs)

    train_dl, train_advs, n_train = loader(rows)
    eval_pack = loader(eval_rows) if eval_rows else None

    optimizer = _create_optimizer(model=model, learning_rate=config.learning_rate, weight_decay=config.weight_decay)
    scheduler = _create_learning_rate_scheduler(
        optimizer=optimizer, batch_size=config.batch_size,
        gradient_accumulation_steps=config.gradient_accumulation_steps,
        training_samples=n_train, epochs=config.epochs, linear_warmup_epochs=config.linear_warmup_epochs)
    scaler = torch.GradScaler(device=device, enabled=config.use_gradient_scaling)

    def seq_logprobs_over(dl):
        """One frozen forward pass over a loader → [N] per-sequence mean log-probs,
        in loader order (shuffle=False), for the KL reference anchor."""
        chunks = []
        with torch.inference_mode():
            model.eval()
            for batch in dl:
                inp = batch[BatchKey.INPUT].to(device, non_blocking=True)
                lab = batch[BatchKey.LABEL].to(device, non_blocking=True)
                seg = batch[BatchKey.SEGMENT_ID].to(device, non_blocking=True)
                with autocast(device=device, dtype=config.autocast_dtype):
                    lp = seq_mean_logprob(model(inp, segment_ids=seg).logits, lab, pad_id)
                chunks.append(lp.detach().float().cpu())
        return torch.cat(chunks)

    # KL anchor: freeze the warm-start policy's log-probs on the fixed drafts BEFORE any
    # optimiser step, so beta_kl actually penalises drift from the 0.409 init (without a
    # second model in the loop). beta_kl=0 → no anchor (reproduces the exp057 run exactly).
    ref_train = None
    if beta_kl > 0:
        logger.info("precomputing reference log-probs from the frozen warm-start policy (KL anchor)")
        ref_train = seq_logprobs_over(train_dl)

    def run_epoch(dl, advs, ref, train):
        model.train() if train else model.eval()
        total, n, ptr = 0.0, 0, 0
        from tqdm import tqdm
        pbar = tqdm(dl, total=len(dl), desc="GRPO-train" if train else "GRPO-eval", ascii=" =")
        for batch_idx, batch in enumerate(pbar):
            inp = batch[BatchKey.INPUT].to(device, non_blocking=True)
            lab = batch[BatchKey.LABEL].to(device, non_blocking=True)
            seg = batch[BatchKey.SEGMENT_ID].to(device, non_blocking=True)
            bsz = inp.shape[0]
            adv = advs[ptr:ptr + bsz].to(device)
            ref_b = ref[ptr:ptr + bsz].to(device) if ref is not None else None
            ptr += bsz
            with autocast(device=device, dtype=config.autocast_dtype):
                logits = model(inp, segment_ids=seg).logits
                seq_lp = seq_mean_logprob(logits, lab, pad_id)
                loss = grpo_policy_loss(seq_lp, adv, ref_logprobs=ref_b, beta_kl=beta_kl)
            if train:
                scaled = scaler.scale(loss / config.gradient_accumulation_steps)
                scaled.backward()
                if ((batch_idx + 1) % config.gradient_accumulation_steps == 0) or (batch_idx + 1 == len(dl)):
                    if config.clip_grad_norm is not None:
                        torch.nn.utils.clip_grad_norm_(model.parameters(), config.clip_grad_norm)
                    scaler.step(optimizer); scaler.update(); optimizer.zero_grad(set_to_none=True); scheduler.step()
            total += loss.detach().item(); n += 1
            pbar.set_postfix(loss=total / max(1, n), adv=adv.mean().item())
        return total / max(1, n)

    for epoch in range(config.epochs):
        logger.info(f"Epoch {epoch + 1}/{config.epochs}")
        train_loss = run_epoch(train_dl, train_advs, ref_train, train=True)
        eval_loss = None
        if eval_pack:
            with torch.inference_mode():
                eval_loss = run_epoch(eval_pack[0], eval_pack[1], None, train=False)
            logger.info(f"eval loss {eval_loss:.4f}")
        saver.save(state_dict=model.state_dict(), epoch=epoch + 1, metric=eval_loss or train_loss)


def main():
    ap = argparse.ArgumentParser(description="GRPO policy fine-tuning of the 3B LoRA adapter")
    ap.add_argument("--rows", required=True, help="train GRPO rows jsonl (prompt/completion/advantage)")
    ap.add_argument("--eval-rows", default=None)
    ap.add_argument("--warm-start", default=None, help=".pt checkpoint to initialise from (the SFT champion)")
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--learning-rate", type=float, default=1e-4)
    ap.add_argument("--batch-size", type=int, default=2)
    ap.add_argument("--gradient-accumulation-steps", type=int, default=2)
    ap.add_argument("--warmup-epochs", type=int, default=1)
    ap.add_argument("--weight-decay", type=float, default=1e-2)
    ap.add_argument("--clip-grad-norm", type=float, default=1.0)
    ap.add_argument("--max-sequence-length", type=int, default=1024)
    ap.add_argument("--activation-checkpointing", action="store_true")
    ap.add_argument("--precision", default="bf16-mixed")
    ap.add_argument("--beta-kl", type=float, default=0.0, help="weight of the optional logprob anchor to init (0=off)")
    ap.add_argument("--checkpoint-dir", required=True)
    args = ap.parse_args()

    config = AdapterTrainingConfiguration(
        epochs=args.epochs, learning_rate=args.learning_rate, batch_size=args.batch_size,
        linear_warmup_epochs=args.warmup_epochs, gradient_accumulation_steps=args.gradient_accumulation_steps,
        enable_activation_checkpointing=args.activation_checkpointing, precision=args.precision,
        weight_decay=args.weight_decay, clip_grad_norm=args.clip_grad_norm,
        max_sequence_length=args.max_sequence_length, fixed_sized_sequences=False, pack_sequences=False)
    train_grpo(args.rows, args.eval_rows, config, args.checkpoint_dir, args.warm_start, args.beta_kl)


if __name__ == "__main__":
    main()
