#!/usr/bin/env python3
"""Prepare the face classification dataset.

1. Run MTCNN face detection on all images
2. Crop and resize to 224x224 with margin
3. Save to processed/stroke/ and processed/normal/
4. Train/val/test split grouped by source video (prevents data leakage)
5. Output split CSVs
"""

import csv
import sys
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np
from facenet_pytorch import MTCNN
from PIL import Image
from sklearn.model_selection import GroupShuffleSplit
from tqdm import tqdm

from config import (
    CELEB_DIR,
    FACE_CROP_MARGIN,
    IMAGE_SIZE,
    NORMAL_DIR,
    PALSYNET_AFFECTED_DIR,
    PALSYNET_CONTROL_DIR,
    SPLITS_DIR,
    STROKE_DIR,
    TRAIN_RATIO,
    VAL_RATIO,
)
from utils import setup_logging

logger = setup_logging()


def detect_and_crop_face(
    img_path: Path, mtcnn: MTCNN, output_path: Path, margin: int = FACE_CROP_MARGIN
) -> bool:
    """Detect face, crop with margin, resize to IMAGE_SIZE. Returns True on success."""
    try:
        img = Image.open(img_path).convert("RGB")
    except Exception:
        return False

    # Detect faces
    boxes, probs = mtcnn.detect(img)

    if boxes is None or len(boxes) == 0:
        return False

    # Take the highest-confidence face
    best_idx = int(np.argmax(probs))
    box = boxes[best_idx]

    # Add margin
    x1, y1, x2, y2 = box
    w, h = img.size
    x1 = max(0, int(x1) - margin)
    y1 = max(0, int(y1) - margin)
    x2 = min(w, int(x2) + margin)
    y2 = min(h, int(y2) + margin)

    # Crop and resize
    face = img.crop((x1, y1, x2, y2))
    face = face.resize((IMAGE_SIZE, IMAGE_SIZE), Image.LANCZOS)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    face.save(output_path, "JPEG", quality=95)
    return True


def get_group_id(img_path: Path, source: str) -> str:
    """Get a group identifier for split grouping.

    For PalsyNet frames, group by parent directory (video name).
    For celebrity images, group by filename (each is independent).
    """
    if source == "palsynet":
        # Parent directory is the video name
        return f"palsynet_{img_path.parent.name}"
    else:
        return f"celeb_{img_path.stem}"


def process_palsynet_frames(mtcnn: MTCNN) -> list[dict]:
    """Process PalsyNet affected + control frames."""
    records = []

    # Affected → stroke class
    if PALSYNET_AFFECTED_DIR.exists():
        frames = sorted(PALSYNET_AFFECTED_DIR.rglob("*.jpg"))
        logger.info(f"Processing {len(frames)} affected frames...")
        for img_path in tqdm(frames, desc="Affected"):
            out_name = f"palsy_{img_path.parent.name}_{img_path.stem}.jpg"
            out_path = STROKE_DIR / out_name
            if detect_and_crop_face(img_path, mtcnn, out_path):
                records.append({
                    "path": str(out_path),
                    "label": 1,
                    "group": get_group_id(img_path, "palsynet"),
                    "source": "palsynet_affected",
                })
    else:
        logger.warning(f"No affected frames at {PALSYNET_AFFECTED_DIR}")

    # Control → normal class
    if PALSYNET_CONTROL_DIR.exists():
        frames = sorted(PALSYNET_CONTROL_DIR.rglob("*.jpg"))
        logger.info(f"Processing {len(frames)} control frames...")
        for img_path in tqdm(frames, desc="Control"):
            out_name = f"control_{img_path.parent.name}_{img_path.stem}.jpg"
            out_path = NORMAL_DIR / out_name
            if detect_and_crop_face(img_path, mtcnn, out_path):
                records.append({
                    "path": str(out_path),
                    "label": 0,
                    "group": get_group_id(img_path, "palsynet"),
                    "source": "palsynet_control",
                })
    else:
        logger.warning(f"No control frames at {PALSYNET_CONTROL_DIR}")

    return records


def process_celebrity_images(mtcnn: MTCNN) -> list[dict]:
    """Process celebrity-1000 images → normal class."""
    records = []

    if not CELEB_DIR.exists():
        logger.warning(f"No celebrity images at {CELEB_DIR}")
        return records

    images = sorted(CELEB_DIR.glob("*.jpg"))
    logger.info(f"Processing {len(images)} celebrity images...")

    for img_path in tqdm(images, desc="Celebrity"):
        out_path = NORMAL_DIR / f"celeb_{img_path.stem}.jpg"
        if detect_and_crop_face(img_path, mtcnn, out_path):
            records.append({
                "path": str(out_path),
                "label": 0,
                "group": get_group_id(img_path, "celebrity"),
                "source": "celebrity1000",
            })

    return records


def create_splits(records: list[dict]) -> None:
    """Create train/val/test splits grouped by source video."""
    SPLITS_DIR.mkdir(parents=True, exist_ok=True)

    paths = [r["path"] for r in records]
    labels = [r["label"] for r in records]
    groups = [r["group"] for r in records]

    # First split: train+val vs test
    test_size = 1.0 - TRAIN_RATIO - VAL_RATIO
    gss1 = GroupShuffleSplit(n_splits=1, test_size=test_size, random_state=42)
    trainval_idx, test_idx = next(gss1.split(paths, labels, groups))

    # Second split: train vs val (from trainval)
    trainval_groups = [groups[i] for i in trainval_idx]
    trainval_labels = [labels[i] for i in trainval_idx]
    relative_val_size = VAL_RATIO / (TRAIN_RATIO + VAL_RATIO)

    gss2 = GroupShuffleSplit(n_splits=1, test_size=relative_val_size, random_state=42)
    train_sub_idx, val_sub_idx = next(
        gss2.split(trainval_idx, trainval_labels, trainval_groups)
    )

    train_idx = [trainval_idx[i] for i in train_sub_idx]
    val_idx = [trainval_idx[i] for i in val_sub_idx]

    # Write CSVs
    for split_name, indices in [("train", train_idx), ("val", val_idx), ("test", test_idx)]:
        csv_path = SPLITS_DIR / f"{split_name}.csv"
        with open(csv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["path", "label", "group", "source"])
            writer.writeheader()
            for i in indices:
                writer.writerow(records[i])

        # Count labels
        split_labels = [labels[i] for i in indices]
        n_pos = sum(split_labels)
        n_neg = len(split_labels) - n_pos
        logger.info(f"  {split_name}: {len(indices)} images (normal={n_neg}, stroke={n_pos})")

    logger.info(f"Split CSVs saved to {SPLITS_DIR}")


def main() -> None:
    logger.info("Initializing MTCNN face detector (CPU)...")
    mtcnn = MTCNN(
        image_size=IMAGE_SIZE,
        margin=0,  # We handle margin ourselves
        min_face_size=40,
        thresholds=[0.6, 0.7, 0.7],
        post_process=False,
        device="cpu",
    )

    STROKE_DIR.mkdir(parents=True, exist_ok=True)
    NORMAL_DIR.mkdir(parents=True, exist_ok=True)

    all_records = []

    # Process PalsyNet
    palsy_records = process_palsynet_frames(mtcnn)
    all_records.extend(palsy_records)
    logger.info(f"PalsyNet: {len(palsy_records)} face crops")

    # Process celebrity images
    celeb_records = process_celebrity_images(mtcnn)
    all_records.extend(celeb_records)
    logger.info(f"Celebrity: {len(celeb_records)} face crops")

    # Summary
    n_stroke = sum(1 for r in all_records if r["label"] == 1)
    n_normal = sum(1 for r in all_records if r["label"] == 0)
    logger.info("=" * 60)
    logger.info(f"Total face crops: {len(all_records)}")
    logger.info(f"  Stroke (positive): {n_stroke}")
    logger.info(f"  Normal (negative): {n_normal}")

    if len(all_records) < 100:
        logger.error("Too few face crops. Check your data downloads.")
        sys.exit(1)

    # Create train/val/test splits
    logger.info("Creating train/val/test splits (grouped by source)...")
    create_splits(all_records)

    logger.info("Dataset preparation complete.")


if __name__ == "__main__":
    main()
