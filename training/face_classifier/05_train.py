#!/usr/bin/env python3
"""Train MobileNetV3-Small for face asymmetry (stroke) detection.

Two-phase training:
  Phase 1: Frozen backbone, train classifier head only (5 epochs)
  Phase 2: Full fine-tuning with cosine annealing (up to 20 epochs)

Early stopping on validation F1 (patience=5).
"""

import csv
import sys

import torch
import torch.nn as nn
from torch.optim.lr_scheduler import CosineAnnealingLR
from torch.utils.data import DataLoader
from tqdm import tqdm

from config import (
    BATCH_SIZE,
    CHECKPOINT_DIR,
    NUM_WORKERS,
    OUTPUT_DIR,
    PATIENCE,
    PHASE1_EPOCHS,
    PHASE1_LR,
    PHASE2_EPOCHS,
    PHASE2_LR,
    PHASE2_LR_MIN,
    SPLITS_DIR,
)
from model import FaceDataset, build_model, train_transform, unfreeze_backbone, val_transform
from utils import compute_metrics, count_parameters, get_device, setup_logging

logger = setup_logging()


# ── Training loop ──────────────────────────────────────────────────────


def train_one_epoch(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    optimizer: torch.optim.Optimizer,
    device: torch.device,
) -> tuple[float, dict]:
    model.train()
    running_loss = 0.0
    all_preds = []
    all_labels = []

    for images, labels in tqdm(loader, desc="  Train", leave=False):
        images = images.to(device)
        labels = labels.to(device)

        optimizer.zero_grad()
        logits = model(images).squeeze(1)
        loss = criterion(logits, labels)
        loss.backward()
        optimizer.step()

        running_loss += loss.item() * images.size(0)
        preds = (torch.sigmoid(logits) >= 0.5).long()
        all_preds.extend(preds.cpu().tolist())
        all_labels.extend(labels.cpu().long().tolist())

    avg_loss = running_loss / len(loader.dataset)
    metrics = compute_metrics(all_labels, all_preds)
    return avg_loss, metrics


@torch.no_grad()
def evaluate(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    device: torch.device,
) -> tuple[float, dict]:
    model.eval()
    running_loss = 0.0
    all_preds = []
    all_labels = []

    for images, labels in tqdm(loader, desc="  Val", leave=False):
        images = images.to(device)
        labels = labels.to(device)

        logits = model(images).squeeze(1)
        loss = criterion(logits, labels)

        running_loss += loss.item() * images.size(0)
        preds = (torch.sigmoid(logits) >= 0.5).long()
        all_preds.extend(preds.cpu().tolist())
        all_labels.extend(labels.cpu().long().tolist())

    avg_loss = running_loss / len(loader.dataset)
    metrics = compute_metrics(all_labels, all_preds)
    return avg_loss, metrics


def main() -> None:
    device = get_device()
    logger.info(f"Using device: {device}")

    # Check splits exist
    for split in ["train", "val"]:
        if not (SPLITS_DIR / f"{split}.csv").exists():
            logger.error(f"Missing {split}.csv. Run 04_prepare_dataset.py first.")
            sys.exit(1)

    # Datasets
    train_ds = FaceDataset(SPLITS_DIR / "train.csv", transform=train_transform)
    val_ds = FaceDataset(SPLITS_DIR / "val.csv", transform=val_transform)
    logger.info(f"Train: {len(train_ds)} | Val: {len(val_ds)}")

    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True, num_workers=NUM_WORKERS)
    val_loader = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False, num_workers=NUM_WORKERS)

    # Compute class weights for imbalanced data
    train_labels = [s[1] for s in train_ds.samples]
    n_pos = sum(train_labels)
    n_neg = len(train_labels) - n_pos
    pos_weight = torch.tensor([n_neg / max(n_pos, 1)], dtype=torch.float32).to(device)
    logger.info(f"Class balance: normal={n_neg}, stroke={n_pos}, pos_weight={pos_weight.item():.2f}")

    criterion = nn.BCEWithLogitsLoss(pos_weight=pos_weight)

    # Prepare output dirs
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Training log
    log_path = OUTPUT_DIR / "training_log.csv"
    log_file = open(log_path, "w", newline="")
    log_writer = csv.DictWriter(
        log_file,
        fieldnames=["phase", "epoch", "train_loss", "val_loss", "train_acc", "val_acc",
                     "train_f1", "val_f1", "train_prec", "val_prec", "train_rec", "val_rec", "lr"],
    )
    log_writer.writeheader()

    best_val_f1 = 0.0
    patience_counter = 0

    # ── Phase 1: Frozen backbone ───────────────────────────────────────
    logger.info("=" * 60)
    logger.info("Phase 1: Training classifier head (backbone frozen)")

    model = build_model(freeze_backbone=True).to(device)
    total_p, trainable_p = count_parameters(model)
    logger.info(f"Parameters: {total_p:,} total, {trainable_p:,} trainable")

    optimizer = torch.optim.Adam(
        filter(lambda p: p.requires_grad, model.parameters()), lr=PHASE1_LR
    )

    for epoch in range(1, PHASE1_EPOCHS + 1):
        logger.info(f"Epoch {epoch}/{PHASE1_EPOCHS}")
        train_loss, train_m = train_one_epoch(model, train_loader, criterion, optimizer, device)
        val_loss, val_m = evaluate(model, val_loader, criterion, device)

        log_writer.writerow({
            "phase": 1, "epoch": epoch,
            "train_loss": f"{train_loss:.4f}", "val_loss": f"{val_loss:.4f}",
            "train_acc": f"{train_m['accuracy']:.4f}", "val_acc": f"{val_m['accuracy']:.4f}",
            "train_f1": f"{train_m['f1']:.4f}", "val_f1": f"{val_m['f1']:.4f}",
            "train_prec": f"{train_m['precision']:.4f}", "val_prec": f"{val_m['precision']:.4f}",
            "train_rec": f"{train_m['recall']:.4f}", "val_rec": f"{val_m['recall']:.4f}",
            "lr": f"{PHASE1_LR:.6f}",
        })
        log_file.flush()

        logger.info(
            f"  Loss: {train_loss:.4f}/{val_loss:.4f} | "
            f"Acc: {train_m['accuracy']:.3f}/{val_m['accuracy']:.3f} | "
            f"F1: {train_m['f1']:.3f}/{val_m['f1']:.3f}"
        )

        if val_m["f1"] > best_val_f1:
            best_val_f1 = val_m["f1"]
            torch.save(model.state_dict(), CHECKPOINT_DIR / "best_model.pt")
            logger.info(f"  New best val F1: {best_val_f1:.4f} — saved checkpoint")

    # ── Phase 2: Full fine-tuning ──────────────────────────────────────
    logger.info("=" * 60)
    logger.info("Phase 2: Full fine-tuning (all layers)")

    unfreeze_backbone(model)
    total_p, trainable_p = count_parameters(model)
    logger.info(f"Parameters: {total_p:,} total, {trainable_p:,} trainable")

    optimizer = torch.optim.Adam(model.parameters(), lr=PHASE2_LR)
    scheduler = CosineAnnealingLR(optimizer, T_max=PHASE2_EPOCHS, eta_min=PHASE2_LR_MIN)

    patience_counter = 0

    for epoch in range(1, PHASE2_EPOCHS + 1):
        current_lr = optimizer.param_groups[0]["lr"]
        logger.info(f"Epoch {epoch}/{PHASE2_EPOCHS} (lr={current_lr:.6f})")

        train_loss, train_m = train_one_epoch(model, train_loader, criterion, optimizer, device)
        val_loss, val_m = evaluate(model, val_loader, criterion, device)
        scheduler.step()

        log_writer.writerow({
            "phase": 2, "epoch": epoch,
            "train_loss": f"{train_loss:.4f}", "val_loss": f"{val_loss:.4f}",
            "train_acc": f"{train_m['accuracy']:.4f}", "val_acc": f"{val_m['accuracy']:.4f}",
            "train_f1": f"{train_m['f1']:.4f}", "val_f1": f"{val_m['f1']:.4f}",
            "train_prec": f"{train_m['precision']:.4f}", "val_prec": f"{val_m['precision']:.4f}",
            "train_rec": f"{train_m['recall']:.4f}", "val_rec": f"{val_m['recall']:.4f}",
            "lr": f"{current_lr:.6f}",
        })
        log_file.flush()

        logger.info(
            f"  Loss: {train_loss:.4f}/{val_loss:.4f} | "
            f"Acc: {train_m['accuracy']:.3f}/{val_m['accuracy']:.3f} | "
            f"F1: {train_m['f1']:.3f}/{val_m['f1']:.3f}"
        )

        if val_m["f1"] > best_val_f1:
            best_val_f1 = val_m["f1"]
            patience_counter = 0
            torch.save(model.state_dict(), CHECKPOINT_DIR / "best_model.pt")
            logger.info(f"  New best val F1: {best_val_f1:.4f} — saved checkpoint")
        else:
            patience_counter += 1
            if patience_counter >= PATIENCE:
                logger.info(f"  Early stopping (no improvement for {PATIENCE} epochs)")
                break

    log_file.close()

    # Save final model too
    torch.save(model.state_dict(), CHECKPOINT_DIR / "final_model.pt")

    logger.info("=" * 60)
    logger.info(f"Training complete. Best val F1: {best_val_f1:.4f}")
    logger.info(f"Best checkpoint: {CHECKPOINT_DIR / 'best_model.pt'}")
    logger.info(f"Training log: {log_path}")


if __name__ == "__main__":
    main()
