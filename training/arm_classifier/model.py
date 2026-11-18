"""1D-CNN arm-drift classifier (ML plan: 3 conv layers, 32/64/64 filters)."""

import torch
import torch.nn as nn

from config import FEATURE_NAMES, FEATURE_SCALE


class ArmDriftCNN(nn.Module):
    def __init__(self, channels: int = len(FEATURE_NAMES)):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv1d(channels, 32, kernel_size=5, padding=2),
            nn.BatchNorm1d(32),
            nn.ReLU(),
            nn.Conv1d(32, 64, kernel_size=5, padding=2, stride=2),
            nn.BatchNorm1d(64),
            nn.ReLU(),
            nn.Conv1d(64, 64, kernel_size=5, padding=2, stride=2),
            nn.BatchNorm1d(64),
            nn.ReLU(),
            nn.AdaptiveAvgPool1d(1),
        )
        self.head = nn.Sequential(nn.Flatten(), nn.Dropout(0.3), nn.Linear(64, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """x: (batch, channels, steps) already scaled. Returns raw logits (batch,)."""
        return self.head(self.features(x)).squeeze(-1)


class ScaledModel(nn.Module):
    """Takes raw features (as the app computes them) and applies FEATURE_SCALE."""

    def __init__(self, model: ArmDriftCNN):
        super().__init__()
        self.model = model
        self.register_buffer("scale", torch.tensor(FEATURE_SCALE).view(1, -1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.model(x / self.scale)


def scale(x: torch.Tensor) -> torch.Tensor:
    return x / torch.tensor(FEATURE_SCALE).view(1, -1, 1)
