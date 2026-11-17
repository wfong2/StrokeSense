"""Shared constants for the face asymmetry classifier training pipeline."""

from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────
ROOT_DIR = Path(__file__).resolve().parent
DATA_DIR = ROOT_DIR / "data"
PROCESSED_DIR = ROOT_DIR / "processed"
SPLITS_DIR = ROOT_DIR / "splits"
CHECKPOINT_DIR = ROOT_DIR / "checkpoints"
OUTPUT_DIR = ROOT_DIR / "outputs"
EXPORT_DIR = ROOT_DIR / "exported"

# PalsyNet dataset
PALSYNET_DIR = DATA_DIR / "palsynet"
PALSYNET_FRAMES_DIR = PALSYNET_DIR / "frames"
PALSYNET_AFFECTED_DIR = PALSYNET_FRAMES_DIR / "affected"
PALSYNET_CONTROL_DIR = PALSYNET_FRAMES_DIR / "control"

# Celebrity-1000 dataset
CELEB_DIR = DATA_DIR / "celebrity1000"

# Processed face crops
STROKE_DIR = PROCESSED_DIR / "stroke"
NORMAL_DIR = PROCESSED_DIR / "normal"

# ── Image settings ─────────────────────────────────────────────────────
IMAGE_SIZE = 224
FACE_CROP_MARGIN = 20  # pixels of padding around detected face

# ── Training hyperparameters ───────────────────────────────────────────
BATCH_SIZE = 32
NUM_WORKERS = 0  # CPU-only, keep at 0 for compatibility

# Phase 1: frozen backbone
PHASE1_EPOCHS = 5
PHASE1_LR = 1e-3

# Phase 2: full fine-tuning
PHASE2_EPOCHS = 20
PHASE2_LR = 1e-4
PHASE2_LR_MIN = 1e-6

# Early stopping
PATIENCE = 5

# Frame extraction
EXTRACT_FPS = 2  # frames per second from PalsyNet videos

# Celebrity-1000 sampling
CELEB_SAMPLE_COUNT = 4000

# Train/val/test split ratios
TRAIN_RATIO = 0.80
VAL_RATIO = 0.10
TEST_RATIO = 0.10

# ImageNet normalization
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]

# Class labels
CLASSES = ["normal", "stroke"]
