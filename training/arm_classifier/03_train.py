#!/usr/bin/env python3
"""Train the 1D-CNN on processed/dataset.npz with early stopping on val F1."""

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

from config import BATCH_SIZE, CHECKPOINT_DIR, EPOCHS, LR, PATIENCE, PROCESSED_DIR, SEED
from model import ArmDriftCNN, scale
from utils import compute_metrics, setup_logging

logger = setup_logging()


def loader(X, y, idx, shuffle):
    ds = TensorDataset(scale(torch.from_numpy(X[idx])), torch.from_numpy(y[idx]).float())
    return DataLoader(ds, batch_size=BATCH_SIZE, shuffle=shuffle)


def evaluate(model, dl):
    model.eval()
    preds, labels = [], []
    with torch.no_grad():
        for xb, yb in dl:
            preds += (torch.sigmoid(model(xb)) >= 0.5).long().tolist()
            labels += yb.long().tolist()
    return compute_metrics(labels, preds)


def main():
    torch.manual_seed(SEED)
    data = np.load(PROCESSED_DIR / "dataset.npz")
    X, y = data["X"], data["y"]
    train_dl = loader(X, y, data["train"], shuffle=True)
    val_dl = loader(X, y, data["val"], shuffle=False)

    model = ArmDriftCNN()
    logger.info(f"Parameters: {sum(p.numel() for p in model.parameters()):,}")
    pos_weight = torch.tensor((y[data["train"]] == 0).sum() / max((y[data["train"]] == 1).sum(), 1))
    criterion = nn.BCEWithLogitsLoss(pos_weight=pos_weight)
    optimizer = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=1e-4)

    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    best_f1, stale = -1.0, 0
    for epoch in range(1, EPOCHS + 1):
        model.train()
        total = 0.0
        for xb, yb in train_dl:
            optimizer.zero_grad()
            loss = criterion(model(xb), yb)
            loss.backward()
            optimizer.step()
            total += loss.item() * len(yb)
        m = evaluate(model, val_dl)
        logger.info(f"Epoch {epoch:2d}  loss {total / len(train_dl.dataset):.4f}  val acc {m['accuracy']:.3f}  f1 {m['f1']:.3f}")

        if m["f1"] > best_f1:
            best_f1, stale = m["f1"], 0
            torch.save(model.state_dict(), CHECKPOINT_DIR / "best.pt")
        else:
            stale += 1
            if stale >= PATIENCE:
                logger.info(f"Early stopping (no val F1 gain for {PATIENCE} epochs)")
                break

    logger.info(f"Best val F1 {best_f1:.3f} → {CHECKPOINT_DIR / 'best.pt'}")


if __name__ == "__main__":
    main()
