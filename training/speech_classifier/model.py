"""Log-Mel front end + audio CNN (ML plan: 4 conv layers, 32/64/128/128).

The front end is part of the exported Core ML model, so the app only passes
16 kHz audio and can't compute the spectrogram differently from training.
"""

import math

import torch
import torch.nn as nn
import torchaudio

from config import F_MAX, F_MIN, HOP, N_FFT, N_MELS, SAMPLE_RATE


class LogMel(nn.Module):
    """STFT as fixed convolutions (converts cleanly to Core ML), then Mel
    filterbank, log, and per-clip normalisation. Normalising each clip removes
    loudness and much of the microphone difference between TORGO and an iPhone."""

    def __init__(self):
        super().__init__()
        bins = N_FFT // 2 + 1
        n = torch.arange(N_FFT, dtype=torch.float32)
        k = torch.arange(bins, dtype=torch.float32)[:, None]
        window = torch.hann_window(N_FFT, periodic=True)
        angle = 2 * math.pi * k * n / N_FFT
        self.real = nn.Conv1d(1, bins, N_FFT, stride=HOP, bias=False)
        self.imag = nn.Conv1d(1, bins, N_FFT, stride=HOP, bias=False)
        self.real.weight.data = (torch.cos(angle) * window)[:, None, :]
        self.imag.weight.data = (-torch.sin(angle) * window)[:, None, :]
        for p in self.parameters():
            p.requires_grad = False
        fb = torchaudio.functional.melscale_fbanks(bins, F_MIN, F_MAX, N_MELS, SAMPLE_RATE, norm=None, mel_scale="htk")
        self.register_buffer("mel_fb", fb.T.contiguous())  # (mels, bins)

    def forward(self, wave: torch.Tensor) -> torch.Tensor:
        """wave: (batch, samples) at 16 kHz → (batch, 1, mels, frames)."""
        x = nn.functional.pad(wave[:, None, :], (N_FFT // 2, N_FFT // 2))
        power = self.real(x) ** 2 + self.imag(x) ** 2           # (B, bins, T)
        mel = torch.matmul(self.mel_fb, power)                  # (B, mels, T)
        logmel = torch.log(mel + 1e-6)
        mean = logmel.mean(dim=(1, 2), keepdim=True)
        std = logmel.std(dim=(1, 2), keepdim=True)
        return ((logmel - mean) / (std + 1e-5))[:, None]


def block(cin: int, cout: int) -> nn.Sequential:
    return nn.Sequential(
        nn.Conv2d(cin, cout, 3, padding=1), nn.BatchNorm2d(cout), nn.ReLU(), nn.MaxPool2d(2)
    )


class SpeechCNN(nn.Module):
    """Classifies a normalised log-Mel spectrogram; returns raw logits (batch,)."""

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(block(1, 32), block(32, 64), block(64, 128), block(128, 128),
                                      nn.AdaptiveAvgPool2d(1))
        self.head = nn.Sequential(nn.Flatten(), nn.Dropout(0.3), nn.Linear(128, 1))

    def forward(self, spec: torch.Tensor) -> torch.Tensor:
        return self.head(self.features(spec)).squeeze(-1)


class WaveformModel(nn.Module):
    """What ships in the app: 16 kHz audio in, dysarthria logit out."""

    def __init__(self, cnn: SpeechCNN):
        super().__init__()
        self.frontend = LogMel()
        self.cnn = cnn

    def forward(self, wave: torch.Tensor) -> torch.Tensor:
        return self.cnn(self.frontend(wave))
