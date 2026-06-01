#!/usr/bin/env python3
"""Turn judged GRPO rollouts into advantage-labelled training rows.

Input: the `score_rollouts.py` output — on-policy drafts, each with a scalar `reward`
and a `group` id (the corpus task). Here we compute the GROUP-RELATIVE advantage for
every draft (the defining step of GRPO — the group's own mean is the baseline, no
critic) and emit one training row per draft:

    A_i = (r_i - mean_group) / (std_group + eps)            # matches grpo_loss.group_advantages

Advantages are computed HERE, with the whole group in hand, and stored per-row — so the
trainer's batching can never split a group and corrupt the normalisation. A group whose
drafts all scored equally (std 0) carries no preference signal and is dropped.

Prompt + completion use the byte-identical contract from gen_orpo_pairs_onpolicy.py
(same system+user turns, same assistant JSON schema), so a GRPO row is an ORPO row with
`advantage` replacing `chosen`/`rejected`. Train/valid split is by GROUP (all drafts of a
task land in the same split) so no task leaks across the boundary.

Usage:
    python build_grpo_data.py --rewards results/grpo_rewards.jsonl \
        [--out adapter/data_grpo] [--eps 1e-4] [--valid-frac 0.1]
"""
import argparse, json, random, statistics, pathlib
from collections import defaultdict

from gen_orpo_pairs_onpolicy import DEFAULT, INSTR, draft_json   # byte-identical contract

PKG = pathlib.Path(__file__).resolve().parent.parent


def advantages(rewards, eps, normalize_std=True):
    mean = statistics.fmean(rewards)
    centered = [r - mean for r in rewards]
    if not normalize_std:
        return centered
    std = statistics.pstdev(rewards)            # population std, matches unbiased=False
    return [c / (std + eps) for c in centered]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rewards", required=True, help="score_rollouts.py output jsonl")
    ap.add_argument("--out", default=str(PKG / "adapter" / "data_grpo"))
    ap.add_argument("--eps", type=float, default=1e-4)
    ap.add_argument("--valid-frac", type=float, default=0.1)
    ap.add_argument("--keep-flat", action="store_true", help="keep std-0 groups (advantage 0; default drops them)")
    args = ap.parse_args()

    groups = defaultdict(list)
    for line in pathlib.Path(args.rewards).read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            r = json.loads(line)
            groups[r["group"]].append(r)

    rows_by_group, dropped_flat = {}, 0
    for gid, members in groups.items():
        rewards = [m["reward"] for m in members]
        if not args.keep_flat and statistics.pstdev(rewards) == 0.0:
            dropped_flat += 1
            continue
        advs = advantages(rewards, args.eps)
        rows = []
        for m, a in zip(members, advs):
            rows.append({
                "prompt": [
                    {"role": "system", "content": DEFAULT + INSTR},
                    {"role": "user", "content": f'Task the user entered: "{m["input"]}"'},
                ],
                "completion": draft_json(m),
                "advantage": a,
            })
        rows_by_group[gid] = rows

    gids = sorted(rows_by_group)
    random.seed(0)
    random.shuffle(gids)
    n_valid = max(1, int(len(gids) * args.valid_frac))
    valid_gids, train_gids = set(gids[:n_valid]), gids[n_valid:]

    train = [row for g in train_gids for row in rows_by_group[g]]
    valid = [row for g in valid_gids for row in rows_by_group[g]]
    random.shuffle(train)

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "train.jsonl").write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in train), encoding="utf-8")
    (out / "valid.jsonl").write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in valid), encoding="utf-8")
    nonzero = sum(1 for r in train if abs(r["advantage"]) > 1e-9)
    print(f"wrote {len(train)} train / {len(valid)} valid GRPO rows from "
          f"{len(rows_by_group)} groups ({dropped_flat} flat groups dropped); "
          f"{nonzero}/{len(train)} train rows have non-zero advantage")


if __name__ == "__main__":
    main()
