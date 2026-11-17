"""Shared model definition and data loading for training and evaluation."""

import csv
from pathlib import Path

import torch
import torch.nn as nn
from torch.utils.data import Dataset
from torchvision import models, transforms
from PIL import Image

from config import IMAGE_SIZE, IMAGENET_MEAN, IMAGENET_STD


# ── Dataset ────────────────────────────────────────────────────────────


class FaceDataset(Dataset):
    def __init__(self, csv_path: Path, transform=None):
        self.samples = []
        self.transform = transform

        with open(csv_path) as f:
            reader = csv.DictReader(f)
            for row in reader:
                self.samples.append((row["path"], int(row["label"])))

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, label = self.samples[idx]
        img = Image.open(path).convert("RGB")
        if self.transform:
            img = self.transform(img)
        return img, torch.tensor(label, dtype=torch.float32)


# ── Transforms ─────────────────────────────────────────────────────────

train_transform = transforms.Compose([
    transforms.RandomRotation(10),
    transforms.ColorJitter(brightness=0.2, contrast=0.2, saturation=0.1, hue=0.05),
    transforms.RandomAffine(degrees=0, scale=(0.95, 1.05)),
    transforms.GaussianBlur(kernel_size=3, sigma=(0.1, 1.0)),
    transforms.Resize((IMAGE_SIZE, IMAGE_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
])

val_transform = transforms.Compose([
    transforms.Resize((IMAGE_SIZE, IMAGE_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
])


# ── Model ──────────────────────────────────────────────────────────────


def build_model(freeze_backbone: bool = True) -> nn.Module:
    """MobileNetV3-Small with binary classification head."""
    model = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.IMAGENET1K_V1)

    if freeze_backbone:
        for param in model.features.parameters():
            param.requires_grad = False

    # Replace classifier: original is Sequential(Linear(576, 1024), Hardswish, Dropout, Linear(1024, 1000))
    in_features = model.classifier[0].in_features
    model.classifier = nn.Sequential(
        nn.Linear(in_features, 1024),
        nn.Hardswish(inplace=True),
        nn.Dropout(p=0.2, inplace=True),
        nn.Linear(1024, 1),
    )

    return model


def unfreeze_backbone(model: nn.Module) -> None:
    """Unfreeze all backbone parameters for full fine-tuning."""
    for param in model.features.parameters():
        param.requires_grad = True
