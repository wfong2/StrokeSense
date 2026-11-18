#!/usr/bin/env python3
"""Load labelled arm recordings, extract features, and split by participant.

Sources (both optional, at least one needed):
  data/recordings/**/*.json   real holds copied from the app
  data/synthetic/**/*.json    from 01_make_synthetic.py

Only recordings with a "label" of "normal" or "drift" are used; the app adds
one when data-collection mode is on. Splits are by participant, so the test
set measures how the model does on people it has never seen.

Usage:  python 02_prepare_dataset.py [--real-only | --synthetic-only]
"""

import argparse
import sys

import numpy as np
from sklearn.model_selection import GroupShuffleSplit

from config import LABELS, PROCESSED_DIR, REAL_DIR, SEED, SYNTHETIC_DIR, TEST_FRACTION, VAL_FRACTION
from features import extract, load_recording
from utils import setup_logging

logger = setup_logging()


def collect(dirs):
    X, y, groups, sources = [], [], [], []
    skipped = {"unlabelled": 0, "too short": 0}
    for d in dirs:
        for path in sorted(d.rglob("*.json")):
            rec = load_recording(path)
            label = rec.get("label")
            if label not in LABELS:
                skipped["unlabelled"] += 1
                continue
            feats = extract(rec.get("samples", []))
            if feats is None:
                skipped["too short"] += 1
                continue
            X.append(feats)
            y.append(LABELS[label])
            groups.append(rec.get("participant") or path.stem)
            sources.append(rec.get("source", "app"))
    logger.info(f"Skipped: {skipped}")
    return np.stack(X) if X else np.empty((0,)), np.array(y), np.array(groups), np.array(sources)


def split(groups: np.ndarray, y: np.ndarray):
    """Participant-level train/val/test split."""
    idx = np.arange(len(y))
    outer = GroupShuffleSplit(n_splits=1, test_size=TEST_FRACTION, random_state=SEED)
    trainval, test = next(outer.split(idx, y, groups))
    inner = GroupShuffleSplit(n_splits=1, test_size=VAL_FRACTION / (1 - TEST_FRACTION), random_state=SEED)
    tr, va = next(inner.split(trainval, y[trainval], groups[trainval]))
    return trainval[tr], trainval[va], test


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--real-only", action="store_true")
    parser.add_argument("--synthetic-only", action="store_true")
    args = parser.parse_args()

    dirs = [d for d, use in ((REAL_DIR, not args.synthetic_only), (SYNTHETIC_DIR, not args.real_only)) if use and d.exists()]
    X, y, groups, sources = collect(dirs)
    if len(y) == 0:
        logger.error("No labelled recordings found. Copy app recordings to data/recordings/ or run 01_make_synthetic.py.")
        sys.exit(1)

    n_people = len(set(groups))
    logger.info(f"{len(y)} holds from {n_people} participants "
                f"({(y == 0).sum()} normal, {(y == 1).sum()} drift; sources: {dict(zip(*np.unique(sources, return_counts=True)))})")
    if n_people < 6:
        logger.error("Need at least 6 participants for a participant-level split.")
        sys.exit(1)

    train, val, test = split(groups, y)
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    np.savez(PROCESSED_DIR / "dataset.npz", X=X, y=y, groups=groups, sources=sources,
             train=train, val=val, test=test)
    for name, part in (("train", train), ("val", val), ("test", test)):
        logger.info(f"  {name}: {len(part)} holds, {len(set(groups[part]))} participants, {y[part].mean():.0%} drift")
    logger.info(f"Saved {PROCESSED_DIR / 'dataset.npz'}")


if __name__ == "__main__":
    main()
