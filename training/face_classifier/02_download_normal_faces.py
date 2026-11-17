#!/usr/bin/env python3
"""Download celebrity-1000 dataset from HuggingFace for the normal face class.

Source: tonyassi/celebrity-1000 (191 MB)
Pre-cropped 256x256 face images. We sample ~4,000 for the normal class.
"""

import random
import shutil
import sys
from pathlib import Path

from datasets import load_dataset

from config import CELEB_DIR, CELEB_SAMPLE_COUNT
from utils import setup_logging

logger = setup_logging()


def main() -> None:
    CELEB_DIR.mkdir(parents=True, exist_ok=True)

    logger.info("Loading celebrity-1000 dataset from HuggingFace...")
    logger.info("Repository: tonyassi/celebrity-1000")

    try:
        ds = load_dataset("tonyassi/celebrity-1000", split="train")
    except Exception as e:
        logger.error(f"Failed to load dataset: {e}")
        sys.exit(1)

    total = len(ds)
    logger.info(f"Dataset has {total} images")

    # Sample a subset
    sample_count = min(CELEB_SAMPLE_COUNT, total)
    indices = random.sample(range(total), sample_count)
    logger.info(f"Sampling {sample_count} images...")

    saved = 0
    for i, idx in enumerate(indices):
        try:
            item = ds[idx]
            img = item["image"]  # PIL Image
            out_path = CELEB_DIR / f"celeb_{idx:05d}.jpg"
            img.save(out_path, "JPEG", quality=95)
            saved += 1

            if (i + 1) % 500 == 0:
                logger.info(f"  Saved {i + 1}/{sample_count}")
        except Exception as e:
            logger.warning(f"  Skipping index {idx}: {e}")

    logger.info(f"Done. Saved {saved} images to {CELEB_DIR}")


if __name__ == "__main__":
    main()
