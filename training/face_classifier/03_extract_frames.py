#!/usr/bin/env python3
"""Extract video frames from PalsyNet at 2 FPS.

Routes frames to affected/ and control/ subdirectories based on the
PalsyNet directory structure (affected vs control videos).
"""

import sys
from pathlib import Path

import cv2

from config import (
    EXTRACT_FPS,
    PALSYNET_DIR,
    PALSYNET_AFFECTED_DIR,
    PALSYNET_CONTROL_DIR,
)
from utils import setup_logging

logger = setup_logging()

VIDEO_EXTENSIONS = {".mp4", ".avi", ".mov", ".mkv"}


def extract_frames(video_path: Path, output_dir: Path, fps: int) -> int:
    """Extract frames from a video at the given FPS. Returns count saved."""
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        logger.warning(f"Cannot open: {video_path}")
        return 0

    video_fps = cap.get(cv2.CAP_PROP_FPS)
    if video_fps <= 0:
        logger.warning(f"Invalid FPS for: {video_path}")
        cap.release()
        return 0

    frame_interval = max(1, int(video_fps / fps))
    video_name = video_path.stem
    output_dir.mkdir(parents=True, exist_ok=True)

    count = 0
    frame_idx = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % frame_interval == 0:
            out_path = output_dir / f"{video_name}_f{count:04d}.jpg"
            cv2.imwrite(str(out_path), frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
            count += 1

        frame_idx += 1

    cap.release()
    return count


def classify_video(video_path: Path) -> str | None:
    """Determine if a video is affected or control based on path."""
    path_lower = str(video_path).lower()
    # PalsyNet typically organizes by subdirectory or filename convention
    if "affected" in path_lower or "palsy" in path_lower:
        return "affected"
    elif "control" in path_lower or "normal" in path_lower or "healthy" in path_lower:
        return "control"
    return None


def main() -> None:
    raw_dir = PALSYNET_DIR / "raw"
    if not raw_dir.exists():
        logger.error(f"PalsyNet raw data not found at {raw_dir}")
        logger.error("Run 01_download_palsynet.py first.")
        sys.exit(1)

    # Find all video files
    videos = [f for f in raw_dir.rglob("*") if f.suffix.lower() in VIDEO_EXTENSIONS]
    logger.info(f"Found {len(videos)} video files in {raw_dir}")

    if not videos:
        logger.error("No video files found. Check the download.")
        sys.exit(1)

    total_affected = 0
    total_control = 0
    unclassified = []

    for video in sorted(videos):
        label = classify_video(video)

        if label == "affected":
            out_dir = PALSYNET_AFFECTED_DIR / video.stem
            count = extract_frames(video, out_dir, EXTRACT_FPS)
            total_affected += count
            logger.info(f"  [AFFECTED] {video.name}: {count} frames")
        elif label == "control":
            out_dir = PALSYNET_CONTROL_DIR / video.stem
            count = extract_frames(video, out_dir, EXTRACT_FPS)
            total_control += count
            logger.info(f"  [CONTROL]  {video.name}: {count} frames")
        else:
            unclassified.append(video)
            logger.warning(f"  [UNKNOWN]  {video.name} — cannot classify, skipping")

    logger.info("=" * 60)
    logger.info(f"Extraction complete:")
    logger.info(f"  Affected frames: {total_affected}")
    logger.info(f"  Control frames:  {total_control}")

    if unclassified:
        logger.warning(f"  Unclassified videos: {len(unclassified)}")
        logger.warning("  You may need to manually sort these videos.")
        logger.warning("  Place them in affected/ or control/ subdirectories")
        logger.warning("  within the raw download, then re-run this script.")
        for v in unclassified:
            logger.warning(f"    {v.relative_to(raw_dir)}")


if __name__ == "__main__":
    main()
