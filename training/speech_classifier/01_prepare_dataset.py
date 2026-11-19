#!/usr/bin/env python3
"""Decode TORGO, cut every clip to 4 s at 16 kHz, compute log-Mel spectrograms
with the same front end the app's model uses, and save them with labels and
speaker IDs.

Output: processed/torgo.npz  (spec float16 [N, 128, 401], y, speaker, severity)
"""

import glob
import io

import numpy as np
import pyarrow.parquet as pq
import soundfile as sf
import torch

from config import CLIP_SAMPLES, PROCESSED_DIR, SAMPLE_RATE, TORGO_DIR
from model import LogMel


def fit_clip(audio: np.ndarray) -> np.ndarray:
    """Centre-crop or zero-pad to exactly 4 s (same rule as the app)."""
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if len(audio) >= CLIP_SAMPLES:
        start = (len(audio) - CLIP_SAMPLES) // 2
        return audio[start:start + CLIP_SAMPLES]
    pad = CLIP_SAMPLES - len(audio)
    return np.pad(audio, (pad // 2, pad - pad // 2))


def main():
    frontend = LogMel().eval()
    specs, ys, speakers, severities = [], [], [], []
    files = sorted(glob.glob(str(TORGO_DIR / "*.parquet")))
    for f in files:
        table = pq.read_table(f, columns=["audio", "speech_status", "severity"])
        audio = table.column("audio").combine_chunks()
        raw, paths = audio.field("bytes").to_pylist(), audio.field("path").to_pylist()
        status, sev = table.column("speech_status").to_pylist(), table.column("severity").to_pylist()

        batch = []
        for data, path, st, sv in zip(raw, paths, status, sev):
            wave, sr = sf.read(io.BytesIO(data), dtype="float32")
            if sr != SAMPLE_RATE:
                continue
            batch.append(fit_clip(wave))
            ys.append(1 if st == "dysarthria" else 0)
            speakers.append(path.split("_")[0])
            severities.append(sv or "")
            if len(batch) == 256:
                with torch.no_grad():
                    specs.append(frontend(torch.from_numpy(np.stack(batch)))[:, 0].numpy().astype(np.float16))
                batch = []
        if batch:
            with torch.no_grad():
                specs.append(frontend(torch.from_numpy(np.stack(batch)))[:, 0].numpy().astype(np.float16))
        print(f"{f.split('/')[-1]}: {len(ys)} clips so far")

    spec = np.concatenate(specs)
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    np.savez(PROCESSED_DIR / "torgo.npz", spec=spec, y=np.array(ys), speaker=np.array(speakers),
             severity=np.array(severities))
    print(f"Saved {spec.shape} spectrograms → {PROCESSED_DIR / 'torgo.npz'}")


if __name__ == "__main__":
    main()
