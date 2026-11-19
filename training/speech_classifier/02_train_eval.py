#!/usr/bin/env python3
"""Leave-speakers-out evaluation, then a final model on all speakers.

TORGO has 15 speakers, so one train/test split would depend on which two
people happen to be held out. Each fold here holds out two dysarthric and two
healthy speakers the model never trained on; results are reported per clip and
per speaker (the average probability over a speaker's clips).

Usage:
  python 02_train_eval.py            # all folds + final model
  python 02_train_eval.py --final    # final model only
"""

import argparse
import json

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

from config import BATCH_SIZE, CHECKPOINT_DIR, EPOCHS, FOLDS, LR, OUTPUT_DIR, PROCESSED_DIR, SEED
from model import SpeechCNN


def device() -> torch.device:
    return torch.device("mps") if torch.backends.mps.is_available() else torch.device("cpu")


def augment(x: torch.Tensor) -> torch.Tensor:
    """SpecAugment-style masking: one random frequency band and time span per clip."""
    x = x.clone()
    b, _, mels, frames = x.shape
    for i in range(b):
        f0 = np.random.randint(0, mels - 16); x[i, :, f0:f0 + np.random.randint(0, 16)] = 0
        t0 = np.random.randint(0, frames - 40); x[i, :, :, t0:t0 + np.random.randint(0, 40)] = 0
    return x


def train(spec: np.ndarray, y: np.ndarray, idx: np.ndarray, dev: torch.device) -> SpeechCNN:
    torch.manual_seed(SEED); np.random.seed(SEED)
    model = SpeechCNN().to(dev)
    pos = float(y[idx].mean())
    criterion = nn.BCEWithLogitsLoss(pos_weight=torch.tensor((1 - pos) / max(pos, 1e-6), dtype=torch.float32, device=dev))
    opt = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=1e-3)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=LR, total_steps=EPOCHS * int(np.ceil(len(idx) / BATCH_SIZE)))
    ds = TensorDataset(torch.from_numpy(spec[idx]), torch.from_numpy(y[idx]).float())
    for epoch in range(EPOCHS):
        model.train(); total = 0.0
        for xb, yb in DataLoader(ds, batch_size=BATCH_SIZE, shuffle=True):
            xb = augment(xb.float()[:, None]).to(dev); yb = yb.to(dev)
            opt.zero_grad(); loss = criterion(model(xb), yb); loss.backward(); opt.step(); sched.step()
            total += loss.item() * len(yb)
        print(f"    epoch {epoch + 1}/{EPOCHS} loss {total / len(idx):.4f}", flush=True)
    return model


def predict(model: SpeechCNN, spec: np.ndarray, idx: np.ndarray, dev: torch.device) -> np.ndarray:
    model.eval(); out = []
    with torch.no_grad():
        for s in range(0, len(idx), 256):
            xb = torch.from_numpy(spec[idx[s:s + 256]]).float()[:, None].to(dev)
            out.append(torch.sigmoid(model(xb)).cpu().numpy())
    return np.concatenate(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--final", action="store_true")
    args = parser.parse_args()

    data = np.load(PROCESSED_DIR / "torgo.npz")
    spec, y, speaker, severity = data["spec"], data["y"], data["speaker"], data["severity"]
    dev = device()
    print(f"{len(y)} clips, {len(set(speaker))} speakers, device {dev}")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True); CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)

    if not args.final:
        per_speaker, clip_hits, clip_total = {}, 0, 0
        for fold, held in enumerate(FOLDS, 1):
            test = np.where(np.isin(speaker, held))[0]
            train_idx = np.where(~np.isin(speaker, held))[0]
            print(f"Fold {fold}/{len(FOLDS)}: holding out {', '.join(held)}", flush=True)
            model = train(spec, y, train_idx, dev)
            probs = predict(model, spec, test, dev)
            clip_hits += int(((probs >= 0.5) == y[test]).sum()); clip_total += len(test)
            for s in held:
                m = speaker[test] == s
                per_speaker[s] = {
                    "label": "dysarthria" if y[test][m][0] == 1 else "healthy",
                    "severity": str(severity[test][m][0]),
                    "clips": int(m.sum()),
                    "mean_prob": float(probs[m].mean()),
                    "clip_accuracy": float(((probs[m] >= 0.5) == y[test][m]).mean()),
                }
                r = per_speaker[s]
                print(f"    {s:5s} {r['label']:10s} {r['severity']:16s} mean p={r['mean_prob']:.2f}  clip acc {r['clip_accuracy']:.0%}", flush=True)

        speaker_correct = sum((r["mean_prob"] >= 0.5) == (r["label"] == "dysarthria") for r in per_speaker.values())
        summary = {"clip_accuracy": clip_hits / clip_total,
                   "speakers_correct": f"{speaker_correct}/{len(per_speaker)}",
                   "per_speaker": per_speaker}
        (OUTPUT_DIR / "cv_results.json").write_text(json.dumps(summary, indent=2))
        print(f"Unseen-speaker clip accuracy {summary['clip_accuracy']:.1%}; speakers classified correctly {summary['speakers_correct']}")

    print("Final model on all speakers", flush=True)
    model = train(spec, y, np.arange(len(y)), dev)
    torch.save(model.cpu().state_dict(), CHECKPOINT_DIR / "final.pt")
    print(f"Saved {CHECKPOINT_DIR / 'final.pt'}")


if __name__ == "__main__":
    main()
