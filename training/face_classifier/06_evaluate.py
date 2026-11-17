#!/usr/bin/env python3
"""Evaluate the best checkpoint on the test set.

Generates:
  - Confusion matrix plot
  - ROC curve with AUC
  - Precision-recall curve
  - Threshold analysis plot
  - Sample prediction grid
  - test_metrics.json
"""

import csv
import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
import torch
import torch.nn as nn
from PIL import Image
from sklearn.metrics import (
    auc,
    confusion_matrix,
    precision_recall_curve,
    roc_curve,
)
from torch.utils.data import DataLoader
from tqdm import tqdm

from config import (
    BATCH_SIZE,
    CHECKPOINT_DIR,
    IMAGE_SIZE,
    IMAGENET_MEAN,
    IMAGENET_STD,
    NUM_WORKERS,
    OUTPUT_DIR,
    SPLITS_DIR,
)
from utils import compute_metrics, get_device, setup_logging

from model import FaceDataset, build_model, val_transform

logger = setup_logging()


@torch.no_grad()
def get_predictions(
    model: nn.Module, loader: DataLoader, device: torch.device
) -> tuple[list, list, list]:
    """Return (true_labels, predicted_probs, image_paths)."""
    model.eval()
    all_labels = []
    all_probs = []
    all_paths = []

    for images, labels in tqdm(loader, desc="Evaluating"):
        images = images.to(device)
        logits = model(images).squeeze(1)
        probs = torch.sigmoid(logits)

        all_labels.extend(labels.long().tolist())
        all_probs.extend(probs.cpu().tolist())

    return all_labels, all_probs, all_paths


def plot_confusion_matrix(y_true, y_pred, output_path: Path) -> None:
    cm = confusion_matrix(y_true, y_pred)
    plt.figure(figsize=(6, 5))
    sns.heatmap(
        cm, annot=True, fmt="d", cmap="Blues",
        xticklabels=["Normal", "Stroke"],
        yticklabels=["Normal", "Stroke"],
    )
    plt.xlabel("Predicted")
    plt.ylabel("Actual")
    plt.title("Confusion Matrix")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()


def plot_roc_curve(y_true, y_probs, output_path: Path) -> float:
    fpr, tpr, _ = roc_curve(y_true, y_probs)
    roc_auc = auc(fpr, tpr)

    plt.figure(figsize=(6, 5))
    plt.plot(fpr, tpr, color="blue", lw=2, label=f"ROC (AUC = {roc_auc:.3f})")
    plt.plot([0, 1], [0, 1], color="gray", linestyle="--", lw=1)
    plt.xlim([0, 1])
    plt.ylim([0, 1.02])
    plt.xlabel("False Positive Rate")
    plt.ylabel("True Positive Rate")
    plt.title("ROC Curve")
    plt.legend(loc="lower right")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()

    return roc_auc


def plot_precision_recall(y_true, y_probs, output_path: Path) -> float:
    precision, recall, _ = precision_recall_curve(y_true, y_probs)
    pr_auc = auc(recall, precision)

    plt.figure(figsize=(6, 5))
    plt.plot(recall, precision, color="green", lw=2, label=f"PR (AUC = {pr_auc:.3f})")
    plt.xlim([0, 1])
    plt.ylim([0, 1.02])
    plt.xlabel("Recall")
    plt.ylabel("Precision")
    plt.title("Precision-Recall Curve")
    plt.legend(loc="lower left")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()

    return pr_auc


def plot_threshold_analysis(y_true, y_probs, output_path: Path) -> dict:
    """Sweep thresholds and plot F1, precision, recall vs threshold."""
    thresholds = np.arange(0.05, 0.96, 0.05)
    f1s, precisions, recalls, accuracies = [], [], [], []

    for t in thresholds:
        preds = [1 if p >= t else 0 for p in y_probs]
        m = compute_metrics(y_true, preds)
        f1s.append(m["f1"])
        precisions.append(m["precision"])
        recalls.append(m["recall"])
        accuracies.append(m["accuracy"])

    best_idx = int(np.argmax(f1s))
    best_threshold = float(thresholds[best_idx])

    plt.figure(figsize=(8, 5))
    plt.plot(thresholds, f1s, label="F1", lw=2)
    plt.plot(thresholds, precisions, label="Precision", lw=1.5, linestyle="--")
    plt.plot(thresholds, recalls, label="Recall", lw=1.5, linestyle="--")
    plt.plot(thresholds, accuracies, label="Accuracy", lw=1.5, linestyle=":")
    plt.axvline(x=best_threshold, color="red", linestyle=":", alpha=0.7, label=f"Best F1 @ {best_threshold:.2f}")
    plt.xlabel("Threshold")
    plt.ylabel("Score")
    plt.title("Threshold Analysis")
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()

    return {"best_threshold": best_threshold, "best_f1": float(f1s[best_idx])}


def main() -> None:
    device = get_device()
    logger.info(f"Using device: {device}")

    # Check checkpoint exists
    ckpt_path = CHECKPOINT_DIR / "best_model.pt"
    if not ckpt_path.exists():
        logger.error(f"No checkpoint at {ckpt_path}. Run 05_train.py first.")
        sys.exit(1)

    if not (SPLITS_DIR / "test.csv").exists():
        logger.error("Missing test.csv. Run 04_prepare_dataset.py first.")
        sys.exit(1)

    # Load model
    model = build_model(freeze_backbone=False)
    model.load_state_dict(torch.load(ckpt_path, map_location=device, weights_only=True))
    model = model.to(device)
    logger.info("Loaded best checkpoint")

    # Test dataset
    test_ds = FaceDataset(SPLITS_DIR / "test.csv", transform=val_transform)
    test_loader = DataLoader(test_ds, batch_size=BATCH_SIZE, shuffle=False, num_workers=NUM_WORKERS)
    logger.info(f"Test set: {len(test_ds)} images")

    # Get predictions
    y_true, y_probs, _ = get_predictions(model, test_loader, device)
    y_pred = [1 if p >= 0.5 else 0 for p in y_probs]

    # Compute metrics
    metrics = compute_metrics(y_true, y_pred)
    logger.info("Test metrics (threshold=0.5):")
    for k, v in metrics.items():
        logger.info(f"  {k}: {v:.4f}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Plots
    logger.info("Generating plots...")

    plot_confusion_matrix(y_true, y_pred, OUTPUT_DIR / "confusion_matrix.png")
    logger.info("  Saved confusion_matrix.png")

    roc_auc = plot_roc_curve(y_true, y_probs, OUTPUT_DIR / "roc_curve.png")
    logger.info(f"  Saved roc_curve.png (AUC={roc_auc:.4f})")

    pr_auc = plot_precision_recall(y_true, y_probs, OUTPUT_DIR / "precision_recall.png")
    logger.info(f"  Saved precision_recall.png (AUC={pr_auc:.4f})")

    threshold_info = plot_threshold_analysis(y_true, y_probs, OUTPUT_DIR / "threshold_analysis.png")
    logger.info(f"  Saved threshold_analysis.png (best_threshold={threshold_info['best_threshold']:.2f})")

    # Save all metrics
    results = {
        **metrics,
        "roc_auc": roc_auc,
        "pr_auc": pr_auc,
        "best_threshold": threshold_info["best_threshold"],
        "best_f1_at_threshold": threshold_info["best_f1"],
        "test_size": len(test_ds),
        "positive_count": sum(y_true),
        "negative_count": len(y_true) - sum(y_true),
    }

    metrics_path = OUTPUT_DIR / "test_metrics.json"
    with open(metrics_path, "w") as f:
        json.dump(results, f, indent=2)
    logger.info(f"Saved metrics to {metrics_path}")

    logger.info("=" * 60)
    logger.info(f"Test accuracy: {metrics['accuracy']:.4f}")
    logger.info(f"Test F1: {metrics['f1']:.4f}")
    logger.info(f"ROC AUC: {roc_auc:.4f}")


if __name__ == "__main__":
    main()
