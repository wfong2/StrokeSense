"""Shared constants for the speech (dysarthria) classifier pipeline."""

from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent
TORGO_DIR = ROOT_DIR / "data" / "torgo"           # Hugging Face abnerh/TORGO-database parquet files
APP_DIR = ROOT_DIR / "data" / "recordings"         # .wav + .json copied from the app (Files › StrokeSense › SpeechRecordings)
PROCESSED_DIR = ROOT_DIR / "processed"
CHECKPOINT_DIR = ROOT_DIR / "checkpoints"
OUTPUT_DIR = ROOT_DIR / "outputs"
EXPORT_DIR = ROOT_DIR / "exported"

# ── Audio / features (must match SpeechClassifierService in the app) ──
SAMPLE_RATE = 16_000
CLIP_SECONDS = 4.0
CLIP_SAMPLES = int(SAMPLE_RATE * CLIP_SECONDS)     # 64,000
N_FFT = 512
HOP = 160                                          # 10 ms
N_MELS = 128                                       # ML plan: 128-band Mel spectrogram
F_MIN, F_MAX = 20.0, 8_000.0

# ── Training ───────────────────────────────────────────────────────────
SEED = 7
BATCH_SIZE = 64
EPOCHS = 5
LR = 1e-3

# Leave-speakers-out folds: each fold holds out two dysarthric and two healthy
# speakers (one of each sex where possible). TORGO has only 15 speakers, so a
# single split would mostly measure who happened to be held out.
FOLDS = [
    ("F01", "M03", "FC01", "MC01"), ("F03", "M01", "FC02", "MC02"),
    ("F04", "M02", "FC03", "MC03"), ("M04", "M05", "MC04"),
]
