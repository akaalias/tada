"""Unit tests for grpo_loss.py — runs without the 3B toolkit (pure torch).
    python research/FMDiscovery/autoresearch/test_grpo_loss.py
"""
import torch
from grpo_loss import group_advantages, grpo_policy_loss


def test_advantages_center_and_normalize():
    # one group, rewards [0,1] → centered/std should be standardized (mean 0, unit-ish)
    r = torch.tensor([0.0, 1.0])
    g = torch.tensor([0, 0])
    a = group_advantages(r, g)
    assert torch.isclose(a.mean(), torch.tensor(0.0), atol=1e-5), a
    # higher reward → higher (positive) advantage
    assert a[1] > a[0]


def test_flat_group_zero_advantage():
    # a group whose drafts all scored equally gives NO signal (std 0 → zeros)
    r = torch.tensor([0.5, 0.5, 0.5])
    g = torch.tensor([7, 7, 7])
    a = group_advantages(r, g)
    assert torch.allclose(a, torch.zeros(3)), a


def test_groups_are_independent():
    # two groups normalised separately; group B's offset doesn't leak into A
    r = torch.tensor([0.0, 1.0, 10.0, 11.0])
    g = torch.tensor([0, 0, 1, 1])
    a = group_advantages(r, g)
    assert torch.isclose(a[0], a[2], atol=1e-4), a  # same within-group rank/shape
    assert torch.isclose(a[1], a[3], atol=1e-4), a


def test_policy_loss_pushes_up_high_advantage():
    # loss gradient should INCREASE logprob of positive-advantage drafts (dL/dlp = -A/B)
    lp = torch.tensor([-1.0, -1.0], requires_grad=True)
    adv = torch.tensor([1.0, -1.0])
    loss = grpo_policy_loss(lp, adv)
    loss.backward()
    # grad on the +adv draft is negative (gradient DESCENT raises its logprob)
    assert lp.grad[0] < 0 < lp.grad[1], lp.grad


def test_advantages_are_constants_in_loss():
    # advantages must not carry gradient even if passed with grad
    lp = torch.tensor([-0.5, -0.7], requires_grad=True)
    adv = torch.tensor([0.3, -0.3], requires_grad=True)
    grpo_policy_loss(lp, adv).backward()
    assert adv.grad is None, "advantages must be detached (treated as constants)"


def test_kl_anchor_penalizes_drift():
    lp = torch.tensor([-2.0, -2.0], requires_grad=True)
    ref = torch.tensor([-1.0, -1.0])
    adv = torch.tensor([0.0, 0.0])              # no PG signal → only the anchor acts
    loss = grpo_policy_loss(lp, adv, ref_logprobs=ref, beta_kl=1.0)
    assert torch.isclose(loss, torch.tensor(1.0), atol=1e-5), loss   # mean((-2 - -1)^2) = 1
    loss.backward()
    assert torch.all(lp.grad < 0), lp.grad      # pulls lp back UP toward ref (-1)


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn(); print(f"  ok  {fn.__name__}")
    print(f"\nall {len(fns)} grpo_loss tests passed")
