#!/usr/bin/env python3
"""Oracle-gap gate (#9) for the FM coverage critic — the make-or-break test.

Loads the trained critic-adapter and asks: on the DISJOINT 145 corpus rollout pools
(6 same-adapter samples per task, never seen in critic training), can it pick the
higher-coverage draft? We score each draft by the critic's EXPECTED coverage (the
softmax over its 1-5 digit logits — read in PyTorch, where logits ARE available),
take the critic's best-of-6, and compare its mean actual coverage to:
  - RANDOM draw  (2.94, no selection)
  - ORACLE pick  (3.31, a perfect critic)
The MiniLM probe captured only 18% of that headroom. PASS if the FM critic captures
>40% — i.e. capacity rescued recognition; FAIL if it lands near random — the wall holds.

Tokenisation reuses the toolkit's own create_dataloader (no chat-template guessing):
each draft becomes the critic chat with a placeholder assistant digit; the first
assistant-label position p is where the score is predicted, so softmax(logits[p]) over
the digit token-ids gives the critic's coverage distribution, independent of the
placeholder. One forward per draft.

Run in the venv:  TOOLKIT=... python critic_gate.py --checkpoint adapter/checkpoints_critic/adapter-epoch6.pt
"""
import argparse, json, os, sys, pathlib
import numpy as np
import torch

PKG = pathlib.Path(__file__).resolve().parent.parent
TOOLKIT = pathlib.Path(os.environ.get("TOOLKIT", PKG / "adapter_training_toolkit_v26_0_0"))
sys.path.insert(0, str(TOOLKIT)); sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from format_critic_data import SYSTEM, user_msg  # exact training prompt
from examples.data import BatchKey, create_dataloader  # noqa: E402
from examples.utils import autocast, get_device, get_logger, load_base_model, load_tokenizer  # noqa: E402

logger = get_logger()
IGNORE = -100


def load_pools():
    pools = {}
    for r in (json.loads(l) for l in (PKG / "results/grpo_rewards.jsonl").read_text().splitlines() if l.strip()):
        cov = r.get("rubric", {}).get("coverage")
        qs = r.get("questions", [])
        if cov is None or len(qs) != 7:
            continue
        pools.setdefault(r["group"], []).append((r["input"], qs, int(cov)))
    return pools


def chat(inp, qs, digit="3"):
    return [{"role": "system", "content": SYSTEM},
            {"role": "user", "content": user_msg(inp, qs)},
            {"role": "assistant", "content": digit}]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--batch-size", type=int, default=8)
    ap.add_argument("--precision", default="bf16-mixed")
    args = ap.parse_args()
    device = get_device()

    from examples.train_adapter import AdapterTrainingConfiguration
    cfg = AdapterTrainingConfiguration(epochs=1, learning_rate=1e-4, batch_size=args.batch_size,
                                       max_sequence_length=1024, fixed_sized_sequences=False, pack_sequences=False)
    model = load_base_model(dtype=cfg.model_dtype, device=device)
    sd = torch.load(args.checkpoint, map_location=device)
    sd = sd.get("model", sd) if isinstance(sd, dict) else sd
    miss, unexp = model.load_state_dict(sd, strict=False)
    logger.info(f"loaded critic {args.checkpoint} (missing {len(miss)}, unexpected {len(unexp)})")
    model.eval()
    tok = load_tokenizer(); pad_id = tok.pad_id

    # digit token-ids: tokenise a sample per digit, read the token at the first assistant-label slot
    digit_tok = {}
    for d in "12345":
        dl = create_dataloader(data=[chat("x", [{"title": "y"}] * 7, d)], tokenizer=tok, batch_size=1,
                               max_sequence_length=1024, fixed_sized_sequences=False, packing=False, shuffle=False)
        b = next(iter(dl)); lab = b[BatchKey.LABEL][0]
        p = int((lab != IGNORE).nonzero()[0])
        digit_tok[int(d)] = int(lab[p])
    ids = [digit_tok[d] for d in range(1, 6)]
    vals = np.arange(1, 6)
    logger.info(f"digit token-ids: {digit_tok}")

    pools = load_pools()
    flat = [(t, i, inp, qs, cov) for t, items in pools.items() for i, (inp, qs, cov) in enumerate(items)]
    data = [chat(inp, qs) for _, _, inp, qs, _ in flat]
    dl = create_dataloader(data=data, tokenizer=tok, batch_size=args.batch_size,
                           max_sequence_length=1024, fixed_sized_sequences=False, packing=False, shuffle=False)

    exp_scores, ptr = [], 0
    with torch.inference_mode():
        for batch in dl:
            inp = batch[BatchKey.INPUT].to(device); lab = batch[BatchKey.LABEL].to(device)
            seg = batch[BatchKey.SEGMENT_ID].to(device)
            with autocast(device=device, dtype=cfg.autocast_dtype):
                logits = model(inp, segment_ids=seg).logits.float()
            for j in range(inp.shape[0]):
                p = int((lab[j] != IGNORE).nonzero()[0])           # first assistant slot
                probs = torch.softmax(logits[j, p, ids], dim=-1).cpu().numpy()
                exp_scores.append(float((probs * vals).sum()))
            ptr += inp.shape[0]

    # group back, select best-of-6 by critic expected score
    by = {}
    for (t, i, inp, qs, cov), s in zip(flat, exp_scores):
        by.setdefault(t, []).append((s, cov))
    rng = np.random.RandomState(0)
    rand_c, crit_c, orac_c = [], [], []
    for t, items in by.items():
        covs = np.array([c for _, c in items]); scores = np.array([s for s, _ in items])
        crit_c.append(covs[int(scores.argmax())]); orac_c.append(covs.max()); rand_c.append(covs[rng.randint(len(covs))])
    rand_c, crit_c, orac_c = map(np.array, (rand_c, crit_c, orac_c))
    print(f"\nFM-critic best-of-6 over {len(crit_c)} disjoint corpus tasks:")
    print(f"  RANDOM draw mean coverage: {rand_c.mean():.3f}")
    print(f"  CRITIC pick mean coverage: {crit_c.mean():.3f}")
    print(f"  ORACLE pick mean coverage: {orac_c.mean():.3f}")
    gap = orac_c.mean() - rand_c.mean()
    cap = (crit_c.mean() - rand_c.mean()) / gap if gap > 1e-9 else 0.0
    print(f"  captured {cap*100:.0f}% of the oracle headroom  (MiniLM probe: 18%)")
    print("\n── read ──")
    if cap > 0.40 and crit_c.mean() - rand_c.mean() > 0.10:
        print("  PASS — the FM critic recognises coverage on unseen tasks far better than the")
        print("  shallow probe. Capacity DID rescue recognition → build best-of-N (#6) for real.")
    else:
        print("  FAIL — the FM critic barely beats random, like the MiniLM probe. Recognising the")
        print("  pivotal unknown needs the same judgment as generating it; the wall holds on the")
        print("  discrimination side too. A shipped coverage critic would not lift coverage.")


if __name__ == "__main__":
    main()
