#!/usr/bin/env python3
"""Rubric correlation audit (the RRD/RULERS lever, offline) — is the broad
~1-point-per-dimension gap FIVE independent capacity deficits, or largely ONE
latent quality factor the judge re-reports across correlated dimensions?

Mines every per-case rubric vector [atomicity, specificity, coverage, naturalness,
nonRedundancy] from results/*.json (the eval harness writes one per judged case),
then computes:
  - the 5x5 Pearson correlation matrix between dimensions,
  - PCA (via SVD) — how much variance PC1 explains, and its loadings,
  - coverage's mean correlation with the other four, and its variance.

Interpretation (printed):
  * PC1 explains most variance + all dims load together  -> the gap is largely one
    latent factor; "coverage" is not a special separable axis, just the symptom the
    judge names. GAD chasing coverage specifically would be misguided.
  * coverage weakly correlated / its own axis                -> coverage is a genuine
    separable target, and a teacher-grounded method (GAD) chasing it makes sense.

Pure numpy, no API. Frozen ruler untouched (read-only).
    python rubric_audit.py
"""
import json, pathlib
import numpy as np

PKG = pathlib.Path(__file__).resolve().parent.parent
RES = PKG / "results"
DIMS = ["atomicity", "specificity", "coverage", "naturalness", "nonRedundancy"]
SKIP = {"costs.json", "operators.json", "types.json", "adapter_provenance.json", "runs.jsonl"}


def mine_rows():
    rows = []
    for f in sorted(RES.glob("*.json")):
        if f.name in SKIP:
            continue
        try:
            data = json.loads(f.read_text())
        except Exception:
            continue
        if not isinstance(data, list):
            continue
        for c in data:
            r = (c.get("verdict") or {}).get("rubric") if isinstance(c, dict) else None
            if r and all(k in r for k in DIMS):
                rows.append([float(r[k]) for k in DIMS])
    return np.array(rows)


def main():
    X = mine_rows()
    n = len(X)
    print(f"mined {n} per-case rubric rows ({X.shape[1]} dimensions)\n")

    means = X.mean(0)
    stds = X.std(0)
    print("per-dimension mean / std / range:")
    for i, d in enumerate(DIMS):
        print(f"  {d:14s} mean {means[i]:.2f}  std {stds[i]:.2f}  range [{X[:,i].min():.0f}, {X[:,i].max():.0f}]")

    # Correlation matrix (guard zero-variance dims)
    safe = stds.copy(); safe[safe == 0] = 1.0
    Z = (X - means) / safe
    C = np.corrcoef(Z, rowvar=False)
    print("\ncorrelation matrix:")
    print("                " + "".join(f"{d[:5]:>8s}" for d in DIMS))
    for i, d in enumerate(DIMS):
        print(f"  {d:14s}" + "".join(f"{C[i,j]:8.2f}" for j in range(len(DIMS))))

    # PCA via SVD on standardized data
    U, S, Vt = np.linalg.svd(Z - Z.mean(0), full_matrices=False)
    var = S**2 / (S**2).sum()
    print("\nPCA (standardized) variance share per component:")
    print("  " + "  ".join(f"PC{i+1} {var[i]*100:4.1f}%" for i in range(len(var))))
    print("  PC1 loadings: " + ", ".join(f"{d[:5]} {Vt[0,j]:+.2f}" for j, d in enumerate(DIMS)))

    ci = DIMS.index("coverage")
    cov_corrs = [C[ci, j] for j in range(len(DIMS)) if j != ci]
    mean_off = (C[np.triu_indices(len(DIMS), 1)]).mean()
    print(f"\ncoverage mean |corr| with others: {np.mean(np.abs(cov_corrs)):.2f}  "
          f"(overall mean off-diagonal corr: {mean_off:.2f})")

    print("\n── read ──")
    pc1 = var[0] * 100
    if pc1 >= 55:
        print(f"  PC1 explains {pc1:.0f}% of variance — the five dimensions move LARGELY TOGETHER.")
        print("  The broad ~1-point gap is substantially ONE latent quality factor, not five")
        print("  independent deficits. 'Coverage' is largely the symptom the judge can name.")
    else:
        print(f"  PC1 explains only {pc1:.0f}% — the dimensions are fairly INDEPENDENT.")
        print("  The deficits are largely distinct; coverage is a separable axis worth targeting.")
    if np.mean(np.abs(cov_corrs)) < 0.3:
        print("  Coverage is weakly correlated with the others — a genuinely separable target")
        print("  → a teacher-grounded method (GAD) chasing coverage specifically is well-posed.")
    else:
        print("  Coverage co-moves with the other dimensions — chasing it in isolation is suspect;")
        print("  the target is the shared latent factor, which is what capacity bounds.")


if __name__ == "__main__":
    main()
