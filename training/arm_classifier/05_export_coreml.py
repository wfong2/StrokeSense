#!/usr/bin/env python3
"""Export the trained model to Core ML and check it matches PyTorch.

Output: exported/ArmDriftClassifier.mlpackage
Copy it to StrokeSense/ (the Xcode folder syncs it into the app automatically).
"""

import shutil

import coremltools as ct
import numpy as np
import torch

from config import CHECKPOINT_DIR, EXPORT_DIR, FEATURE_NAMES, PROCESSED_DIR, STEPS
from model import ArmDriftCNN, ScaledModel
from utils import setup_logging

logger = setup_logging()


def main():
    base = ArmDriftCNN()
    base.load_state_dict(torch.load(CHECKPOINT_DIR / "best.pt", weights_only=True))
    model = ScaledModel(base).eval()

    example = torch.zeros(1, len(FEATURE_NAMES), STEPS)
    traced = torch.jit.trace(model, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="motion", shape=example.shape, dtype=np.float32)],
        outputs=[ct.TensorType(name="driftLogit", dtype=np.float32)],
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
    )
    mlmodel.short_description = "Arm-drift classifier for the StrokeSense arm hold (1D-CNN on phone motion)."
    mlmodel.input_description["motion"] = f"Raw features {FEATURE_NAMES}, {STEPS} steps at 20 Hz"
    mlmodel.output_description["driftLogit"] = "Raw logit; sigmoid gives drift probability"

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    out = EXPORT_DIR / "ArmDriftClassifier.mlpackage"
    if out.exists():
        shutil.rmtree(out)
    mlmodel.save(str(out))
    logger.info(f"Saved {out}")

    # Parity check on real test inputs.
    data = np.load(PROCESSED_DIR / "dataset.npz")
    X = data["X"][data["test"]][:20]
    with torch.no_grad():
        torch_out = model(torch.from_numpy(X)).numpy()
    coreml_out = np.array([mlmodel.predict({"motion": x[None]})["driftLogit"].reshape(-1)[0] for x in X])
    diff = np.abs(torch_out - coreml_out).max()
    logger.info(f"Max |PyTorch − Core ML| logit difference on {len(X)} test holds: {diff:.4f}")


if __name__ == "__main__":
    main()
