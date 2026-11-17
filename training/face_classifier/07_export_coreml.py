#!/usr/bin/env python3
"""Export the best PyTorch checkpoint to CoreML (.mlpackage).

Steps:
  1. Load best checkpoint
  2. Trace with torch.jit.trace
  3. Convert via coremltools with ImageType input
  4. Set metadata
  5. Validate predictions match PyTorch within tolerance
"""

import sys
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from PIL import Image

from config import (
    CHECKPOINT_DIR,
    EXPORT_DIR,
    IMAGE_SIZE,
    IMAGENET_MEAN,
    IMAGENET_STD,
    PROCESSED_DIR,
)
from model import build_model, val_transform
from utils import get_device, setup_logging

logger = setup_logging()

TOLERANCE = 0.01
VALIDATION_SAMPLES = 10


def main() -> None:
    device = get_device()

    ckpt_path = CHECKPOINT_DIR / "best_model.pt"
    if not ckpt_path.exists():
        logger.error(f"No checkpoint at {ckpt_path}. Run 05_train.py first.")
        sys.exit(1)

    # Load model
    model = build_model(freeze_backbone=False)
    model.load_state_dict(torch.load(ckpt_path, map_location="cpu", weights_only=True))
    model.eval()
    logger.info("Loaded best checkpoint")

    # Trace the model
    example_input = torch.randn(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    traced = torch.jit.trace(model, example_input)
    logger.info("Model traced successfully")

    # Convert to CoreML
    logger.info("Converting to CoreML...")
    scale = 1.0 / (255.0 * np.array(IMAGENET_STD))
    bias = -np.array(IMAGENET_MEAN) / np.array(IMAGENET_STD)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="faceImage",
                shape=(1, 3, IMAGE_SIZE, IMAGE_SIZE),
                scale=scale.tolist(),
                bias=bias.tolist(),
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="strokeProbability")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
    )

    # Set metadata
    mlmodel.author = "StrokeSense"
    mlmodel.short_description = (
        "Face asymmetry classifier for stroke detection. "
        "MobileNetV3-Small trained on facial palsy data."
    )
    mlmodel.input_description["faceImage"] = "224x224 RGB face crop"
    mlmodel.output_description["strokeProbability"] = (
        "Raw logit; apply sigmoid for probability (>0.5 = stroke-like asymmetry)"
    )

    # Save
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    mlpackage_path = EXPORT_DIR / "FaceAsymmetryClassifier.mlpackage"
    mlmodel.save(str(mlpackage_path))
    logger.info(f"Saved CoreML model to {mlpackage_path}")

    # Report size
    import shutil
    size_bytes = sum(f.stat().st_size for f in mlpackage_path.rglob("*") if f.is_file())
    logger.info(f"Model size: {size_bytes / 1024 / 1024:.1f} MB")

    # Validate predictions
    logger.info(f"Validating CoreML vs PyTorch ({VALIDATION_SAMPLES} samples)...")

    # Find sample images
    sample_dirs = [PROCESSED_DIR / "stroke", PROCESSED_DIR / "normal"]
    sample_images = []
    for d in sample_dirs:
        if d.exists():
            sample_images.extend(sorted(d.glob("*.jpg"))[:VALIDATION_SAMPLES // 2])

    if not sample_images:
        logger.warning("No processed images found for validation. Skipping.")
        return

    max_diff = 0.0
    for img_path in sample_images[:VALIDATION_SAMPLES]:
        img = Image.open(img_path).convert("RGB")

        # PyTorch prediction
        tensor = val_transform(img).unsqueeze(0)
        with torch.no_grad():
            pt_logit = model(tensor).item()

        # CoreML prediction
        resized = img.resize((IMAGE_SIZE, IMAGE_SIZE))
        coreml_out = mlmodel.predict({"faceImage": resized})
        cml_logit = float(coreml_out["strokeProbability"].flatten()[0])

        diff = abs(pt_logit - cml_logit)
        max_diff = max(max_diff, diff)
        logger.info(f"  {img_path.name}: PyTorch={pt_logit:.4f}, CoreML={cml_logit:.4f}, diff={diff:.6f}")

    if max_diff < TOLERANCE:
        logger.info(f"Validation PASSED (max diff={max_diff:.6f} < {TOLERANCE})")
    else:
        logger.warning(f"Validation WARNING: max diff={max_diff:.6f} >= {TOLERANCE}")
        logger.warning("CoreML predictions may differ slightly. Check if acceptable.")

    logger.info("=" * 60)
    logger.info("Export complete!")
    logger.info(f"  Model: {mlpackage_path}")
    logger.info(f"  Copy to Xcode project to integrate with StrokeSense.")


if __name__ == "__main__":
    main()
