"""Turn an app arm recording into the model's input.

This is the single definition of the features. The iOS app computes the
same thing in ArmRecording.modelInput (BaselineData.swift); keep them in sync.
"""

import json
import math
from pathlib import Path

import numpy as np

from config import HOLD_SECONDS, MIN_SAMPLES, SETTLE_SECONDS, STEPS, WINDOW_SECONDS


def pitch_deg(g) -> float:
    """Tilt around the phone's side-to-side axis (grows as the arm sinks, any grip)."""
    return math.degrees(math.atan2(-g[2], -g[1]))


def turn_deg(g) -> float:
    """How far the phone's side edge dips out of level (forearm turning)."""
    return math.degrees(math.asin(max(-1.0, min(1.0, g[0]))))


def extract(samples: list[dict]) -> np.ndarray | None:
    """Return a (5, STEPS) float32 array, or None if the hold is too short."""
    held = [s for s in samples if s["t"] >= SETTLE_SECONDS]
    if len(held) < MIN_SAMPLES or held[-1]["t"] - held[0]["t"] < 2.0:
        return None

    t = np.array([s["t"] for s in held])
    pitch = np.array([pitch_deg(s["gravity"]) for s in held])
    turn = np.array([turn_deg(s["gravity"]) for s in held])
    rot = np.array([s["rotationRate"] for s in held]) * (180.0 / math.pi)
    acc = np.array([s["userAcceleration"] for s in held])

    start = t < t[0] + WINDOW_SECONDS
    d_pitch = pitch - pitch[start].mean()
    d_turn = turn - turn[start].mean()
    pitch_rate = rot[:, 0]
    rot_mag = np.linalg.norm(rot, axis=1)
    acc_mag = np.linalg.norm(acc, axis=1)

    # Linear resample onto a fixed 20 Hz grid; values past the end are held.
    grid = t[0] + np.arange(STEPS) * (HOLD_SECONDS / STEPS)
    channels = [d_pitch, d_turn, pitch_rate, rot_mag, acc_mag]
    return np.stack([np.interp(grid, t, c) for c in channels]).astype(np.float32)


def load_recording(path: Path) -> dict:
    with open(path) as f:
        return json.load(f)
