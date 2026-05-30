"""Pure-torch ORPO loss math (no toolkit/tamm dependency, so it's unit-testable
without loading the 3B). Imported by train_adapter_orpo.py."""
import torch
import torch.nn.functional as F


def seq_mean_logprob(logits, labels, pad_id, ignore_id=-100):
    """Mean per-token log-prob over each sequence's RESPONSE tokens. Returns [batch].

    Matches the Apple toolkit's CrossEntropyLoss alignment (no extra shift — labels
    are already aligned to logit positions). Masks prompt+padding (pad_id/ignore_id).
    """
    logp = F.log_softmax(logits.float(), dim=-1)
    safe = labels.clamp(min=0).unsqueeze(-1)
    tok_logp = logp.gather(-1, safe).squeeze(-1)              # [B, T]
    valid = (labels != ignore_id) & (labels != pad_id) & (labels >= 0)
    counts = valid.sum(dim=1).clamp(min=1)
    return (tok_logp * valid).sum(dim=1) / counts             # [B]


def orpo_ratio_loss(seq_lp_c, seq_lp_r):
    """ORPO odds-ratio term from per-sequence mean log-probs (chosen, rejected).
    Lower when chosen is preferred over rejected."""
    log1m_c = torch.log1p(-torch.exp(seq_lp_c).clamp(max=1 - 1e-6))
    log1m_r = torch.log1p(-torch.exp(seq_lp_r).clamp(max=1 - 1e-6))
    log_odds_c = seq_lp_c - log1m_c
    log_odds_r = seq_lp_r - log1m_r
    return (-F.logsigmoid(log_odds_c - log_odds_r)).mean()
