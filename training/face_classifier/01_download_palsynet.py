#!/usr/bin/env python3
"""Download PalsyNet dataset from HuggingFace.

Source: jasir/palsynet-data (CC-BY-4.0)
Contains 49 videos: 27 Bell's palsy affected + 22 control.
"""

import sys
from pathlib import Path

from huggingface_hub import snapshot_download

from config import PALSYNET_DIR
from utils import setup_logging

logger = setup_logging()


def main() -> None:
    PALSYNET_DIR.mkdir(parents=True, exist_ok=True)

    logger.info("Downloading PalsyNet dataset from HuggingFace...")
    logger.info("Repository: jasir/palsynet-data")
    logger.info(f"Destination: {PALSYNET_DIR}")

    try:
        local_path = snapshot_download(
            repo_id="jasir/palsynet-data",
            repo_type="dataset",
            local_dir=str(PALSYNET_DIR / "raw"),
        )
        logger.info(f"Download complete: {local_path}")
    except Exception as e:
        logger.error(f"Download failed: {e}")
        sys.exit(1)

    # List downloaded files
    raw_dir = PALSYNET_DIR / "raw"
    video_files = list(raw_dir.rglob("*.mp4")) + list(raw_dir.rglob("*.avi"))
    logger.info(f"Found {len(video_files)} video files")

    for f in sorted(video_files)[:5]:
        logger.info(f"  {f.relative_to(raw_dir)}")
    if len(video_files) > 5:
        logger.info(f"  ... and {len(video_files) - 5} more")


if __name__ == "__main__":
    main()
