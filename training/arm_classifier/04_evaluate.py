#!/usr/bin/env python3
"""Evaluate the trained model on the held-out participants, side by side with
the app's current rule (drift ≥ 10° or turn ≥ 15° counts as drift).

The AI only earns weight in the app if it beats the rule on the same test set.
Reports real and synthetic test holds separately when both are present.
"""

import json

import numpy as np
import torch

from config import CHECKPOINT_DIR, OUTPUT_DIR, PROCESSED_DIR, STEPS
from model import ArmDriftCNN, scale
from utils import compute_metrics, setup_logging

logger = setup_logging()
WINDOW = 20  # 1 s at 20 Hz


def rule_predictions(X: np.ndarray) -> np.ndarray:
    """Mirror of the app's geometry: sink and turn from first to last second."""
    sink = X[:, 0, -WINDOW:].mean(1) - X[:, 0, :WINDOW].mean(1)
    turn = np.abs(X[:, 1, -WINDOW:].mean(1) - X[:, 1, :WINDOW].mean(1))
    return ((sink >= 10) | (turn >= 15)).astype(int)


def main():
    data = np.load(PROCESSED_DIR / "dataset.npz")
    test = data["test"]
    X, y, sources = data["X"][test], data["y"][test], data["sources"][test]

    model = ArmDriftCNN()
    model.load_state_dict(torch.load(CHECKPOINT_DIR / "best.pt", weights_only=True))
    model.eval()
    with torch.no_grad():
        probs = torch.sigmoid(model(scale(torch.from_numpy(X)))).numpy()
    ai = (probs >= 0.5).astype(int)
    rule = rule_predictions(X)

    report = {}
    for name in sorted(set(sources)) + ["all"]:
        mask = np.ones(len(y), bool) if name == "all" else sources == name
        if mask.sum() == 0:
            continue
        report[name] = {
            "holds": int(mask.sum()),
            "ai": compute_metrics(y[mask], ai[mask]),
            "rule": compute_metrics(y[mask], rule[mask]),
        }
        r = report[name]
        logger.info(f"[{name}] {r['holds']} holds")
        for k in ("ai", "rule"):
            m = r[k]
            logger.info(f"   {k:4s}  acc {m['accuracy']:.3f}  precision {m['precision']:.3f}  recall {m['recall']:.3f}  f1 {m['f1']:.3f}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / "test_metrics.json").write_text(json.dumps(report, indent=2))
    logger.info(f"Saved {OUTPUT_DIR / 'test_metrics.json'}")


if __name__ == "__main__":
    main()
