#!/usr/bin/env python3
"""Oracle-gap gate for the PAIRWISE coverage critic (#2).

For each disjoint corpus rollout pool (6 drafts), run a round-robin tournament: every
ordered pair (i as SET A, j as SET B) is scored by the critic's P(A wins) read from the
A/B logits; the draft with the most wins across all 30 ordered comparisons is the pick.
Both orders are evaluated, so position bias is averaged out. Compare the picked draft's
mean coverage to random (2.94) and oracle (3.31); the pointwise critic captured 32%.

Run in the venv:  TOOLKIT=... python critic_gate_pairwise.py --checkpoint adapter/checkpoints_critic_pw/adapter-final.pt
"""
import argparse, json, os, sys, pathlib
import numpy as np
import torch

PKG = pathlib.Path(__file__).resolve().parent.parent
TOOLKIT = pathlib.Path(os.environ.get("TOOLKIT", PKG / "adapter_training_toolkit_v26_0_0"))
sys.path.insert(0, str(TOOLKIT)); sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from format_critic_pairwise_data import SYSTEM, user_msg
from examples.data import BatchKey, create_dataloader  # noqa: E402
from examples.utils import autocast, get_device, get_logger, load_base_model, load_tokenizer  # noqa: E402
from examples.train_adapter import AdapterTrainingConfiguration  # noqa: E402

logger = get_logger()
IGNORE = -100


def load_pools():
    pools = {}
    for r in (json.loads(l) for l in (PKG / "results/grpo_rewards.jsonl").read_text().splitlines() if l.strip()):
        cov = r.get("rubric", {}).get("coverage"); qs = r.get("questions", [])
        if cov is None or len(qs) != 7:
            continue
        pools.setdefault(r["group"], []).append((r["input"], qs, int(cov)))
    return pools


def chat(inp, qa, qb, ans="A"):
    return [{"role": "system", "content": SYSTEM},
            {"role": "user", "content": user_msg(inp, qa, qb)},
            {"role": "assistant", "content": ans}]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--batch-size", type=int, default=8)
    args = ap.parse_args()
    device = get_device()
    cfg = AdapterTrainingConfiguration(epochs=1, learning_rate=1e-4, batch_size=args.batch_size,
                                       max_sequence_length=1024, fixed_sized_sequences=False, pack_sequences=False)
    model = load_base_model(dtype=cfg.model_dtype, device=device)
    sd = torch.load(args.checkpoint, map_location=device); sd = sd.get("model", sd) if isinstance(sd, dict) else sd
    miss, unexp = model.load_state_dict(sd, strict=False)
    logger.info(f"loaded pairwise critic {args.checkpoint} (missing {len(miss)}, unexpected {len(unexp)})")
    model.eval()
    tok = load_tokenizer()

    ab_tok = {}
    for L in "AB":
        dl = create_dataloader(data=[chat("x", [{"title": "y"}] * 7, [{"title": "z"}] * 7, L)], tokenizer=tok,
                               batch_size=1, max_sequence_length=1024, fixed_sized_sequences=False, packing=False, shuffle=False)
        b = next(iter(dl)); lab = b[BatchKey.LABEL][0]; p = int((lab != IGNORE).nonzero()[0])
        ab_tok[L] = int(lab[p])
    ids = [ab_tok["A"], ab_tok["B"]]
    logger.info(f"A/B token-ids: {ab_tok}")

    pools = load_pools()
    # every ordered pair (i as A, j as B) per task
    items, data = [], []
    for t, drafts in pools.items():
        for i in range(len(drafts)):
            for j in range(len(drafts)):
                if i == j:
                    continue
                items.append((t, i, j))
                data.append(chat(drafts[t and 0 or 0] if False else drafts[i][0], drafts[i][1], drafts[j][1]))
    dl = create_dataloader(data=data, tokenizer=tok, batch_size=args.batch_size,
                           max_sequence_length=1024, fixed_sized_sequences=False, packing=False, shuffle=False)
    pA = []
    with torch.inference_mode():
        for batch in dl:
            inp = batch[BatchKey.INPUT].to(device); lab = batch[BatchKey.LABEL].to(device)
            seg = batch[BatchKey.SEGMENT_ID].to(device)
            with autocast(device=device, dtype=cfg.autocast_dtype):
                logits = model(inp, segment_ids=seg).logits.float()
            for k in range(inp.shape[0]):
                p = int((lab[k] != IGNORE).nonzero()[0])
                pr = torch.softmax(logits[k, p, ids], dim=-1).cpu().numpy()
                pA.append(float(pr[0]))

    wins = {t: np.zeros(len(d)) for t, d in pools.items()}
    for (t, i, j), pa in zip(items, pA):
        wins[t][i if pa > 0.5 else j] += 1
    rng = np.random.RandomState(0)
    rand_c, crit_c, orac_c = [], [], []
    for t, drafts in pools.items():
        covs = np.array([c for _, _, c in drafts])
        crit_c.append(covs[int(wins[t].argmax())]); orac_c.append(covs.max()); rand_c.append(covs[rng.randint(len(covs))])
    rand_c, crit_c, orac_c = map(np.array, (rand_c, crit_c, orac_c))
    print(f"\nPAIRWISE-critic tournament best-of-6 over {len(crit_c)} disjoint corpus tasks:")
    print(f"  RANDOM draw mean coverage: {rand_c.mean():.3f}")
    print(f"  CRITIC pick mean coverage: {crit_c.mean():.3f}")
    print(f"  ORACLE pick mean coverage: {orac_c.mean():.3f}")
    gap = orac_c.mean() - rand_c.mean()
    cap = (crit_c.mean() - rand_c.mean()) / gap if gap > 1e-9 else 0.0
    print(f"  captured {cap*100:.0f}% of the oracle headroom  (pointwise critic: 32%, MiniLM: 18%)")
    print("\n── read ──")
    if cap > 0.40 and crit_c.mean() - rand_c.mean() > 0.10:
        print("  PASS — relative judgment recognises coverage well enough to select. Worth wiring")
        print("  best-of-N on-device (subject to the no-logprob + dimension-tradeoff ceilings).")
    else:
        print(f"  Below the 40% bar. Pairwise {'beat' if cap>0.32 else 'did not beat'} pointwise (32%);")
        print("  recognition stays bounded — the discrimination route does not clear the wall.")


if __name__ == "__main__":
    main()
