#!/usr/bin/env python3
"""Export front end + CNN as one Core ML model and check it matches PyTorch.

Output: exported/SpeechClarityClassifier.mlpackage
Input "audio": 64,000 samples (4 s at 16 kHz). Output "dysarthriaLogit".
"""

import shutil

import coremltools as ct
import numpy as np
import torch

from config import CHECKPOINT_DIR, CLIP_SAMPLES, EXPORT_DIR
from model import SpeechCNN, WaveformModel


def main():
    cnn = SpeechCNN()
    cnn.load_state_dict(torch.load(CHECKPOINT_DIR / "final.pt", weights_only=True))
    model = WaveformModel(cnn).eval()

    example = torch.randn(1, CLIP_SAMPLES) * 0.05
    traced = torch.jit.trace(model, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="audio", shape=example.shape, dtype=np.float32)],
        outputs=[ct.TensorType(name="dysarthriaLogit", dtype=np.float32)],
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
    )
    mlmodel.short_description = "Slurred-speech (dysarthria) classifier trained on TORGO; info-only in StrokeSense."
    mlmodel.input_description["audio"] = "4 s of mono audio at 16 kHz, float in [-1, 1]"
    mlmodel.output_description["dysarthriaLogit"] = "Raw logit; sigmoid gives dysarthria probability"

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    out = EXPORT_DIR / "SpeechClarityClassifier.mlpackage"
    if out.exists():
        shutil.rmtree(out)
    mlmodel.save(str(out))
    print(f"Saved {out}")

    rng = np.random.default_rng(0)
    diffs = []
    for _ in range(5):
        x = (rng.standard_normal((1, CLIP_SAMPLES)) * 0.05).astype(np.float32)
        with torch.no_grad():
            t = model(torch.from_numpy(x)).item()
        c = float(mlmodel.predict({"audio": x})["dysarthriaLogit"].reshape(-1)[0])
        diffs.append(abs(t - c))
    print(f"Max |PyTorch − Core ML| logit difference: {max(diffs):.4f}")


if __name__ == "__main__":
    main()
