#!/usr/bin/env python3
"""Generate synthetic arm-hold recordings in the app's JSON format.

These exist so the whole pipeline (prepare → train → evaluate → export →
app) can run before real recordings are collected. They are NOT stroke data:
"drift" holds are modelled on the published iPronator numbers (stroke
patients averaged ~27° drift and ~29° pronation; controls ~-2° and ~4°).
A model trained only on this learns our simulation, not real weakness.
"""

import json
import math
import shutil

import numpy as np

from config import SEED, SYNTHETIC_DIR, SYNTHETIC_HOLDS_PER_LABEL, SYNTHETIC_PARTICIPANTS
from utils import setup_logging

logger = setup_logging()
RATE = 50.0
DURATION = 8.0


def gravity(grip_pitch: float, sink: float, turn: float) -> list[float]:
    """Gravity in the phone frame for a grip, arm sink and forearm turn (degrees)."""
    th = math.radians(grip_pitch + sink)
    r = math.radians(turn)
    # Rotation by th around x from upright (0,-1,0), then turn around the arm axis.
    return [math.sin(r), -math.cos(r) * math.cos(th), -math.cos(r) * math.sin(th)]


def make_hold(rng: np.random.Generator, label: str, participant_tremor: float) -> list[dict]:
    upright = rng.random() < 0.75
    grip_pitch = (0.0 if upright else 90.0) + rng.normal(10.0 if upright else 0.0, 6.0)

    t = np.arange(0, DURATION, 1 / RATE) + rng.normal(0, 0.002, int(DURATION * RATE))
    t = np.sort(np.clip(t, 0, None))
    progress = np.clip((t - 1.0) / (DURATION - 1.0), 0, 1)

    if label == "drift":
        total_sink = rng.uniform(8, 35)
        total_turn = rng.uniform(10, 40) * rng.choice([-1, 1])
        shape = progress ** rng.uniform(0.6, 1.6)          # steady or accelerating
        tremor_amp = participant_tremor * rng.uniform(1.0, 2.5)
    else:
        total_sink = rng.normal(0, 1.5)
        total_turn = rng.normal(0, 3)
        shape = progress
        tremor_amp = participant_tremor

    # Slow wander + physiological tremor (several 4–10 Hz components).
    wander = np.cumsum(rng.normal(0, 0.05, t.size))
    tremor = sum(
        tremor_amp * rng.uniform(0.3, 1.0) * np.sin(2 * math.pi * rng.uniform(4, 10) * t + rng.uniform(0, 6.3))
        for _ in range(3)
    )
    sink = total_sink * shape + wander + tremor
    turn = total_turn * shape + 0.5 * wander

    pitch_rate = np.gradient(sink, t)  # deg/s
    samples = []
    for i in range(t.size):
        rot = np.radians([pitch_rate[i], rng.normal(0, 2), rng.normal(0, 2)])
        acc = rng.normal(0, 0.01, 3)
        samples.append({
            "t": float(t[i]),
            "gravity": gravity(grip_pitch, float(sink[i]), float(turn[i])),
            "rotationRate": rot.tolist(),
            "userAcceleration": acc.tolist(),
        })
    return samples


def main():
    rng = np.random.default_rng(SEED)
    if SYNTHETIC_DIR.exists():
        shutil.rmtree(SYNTHETIC_DIR)
    SYNTHETIC_DIR.mkdir(parents=True)

    count = 0
    for p in range(SYNTHETIC_PARTICIPANTS):
        participant = f"syn{p:02d}"
        tremor = rng.uniform(0.05, 0.6)
        for label in ("normal", "drift"):
            for i in range(SYNTHETIC_HOLDS_PER_LABEL):
                side = "right" if i % 2 == 0 else "left"
                entry = {
                    "source": "synthetic",
                    "participant": participant,
                    "label": label,
                    "side": side,
                    "context": "check",
                    "samples": make_hold(rng, label, tremor),
                }
                path = SYNTHETIC_DIR / f"{participant}-{label}-{i}-{side}.json"
                path.write_text(json.dumps(entry))
                count += 1

    logger.info(f"Wrote {count} synthetic recordings to {SYNTHETIC_DIR}")


if __name__ == "__main__":
    main()
