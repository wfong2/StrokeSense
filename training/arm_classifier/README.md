# Arm-drift classifier

1D-CNN that reads the phone's motion sensors during the arm-hold test and
outputs a drift probability. Shown in the app as **info only** until it is
trained on real data and beats the rule-based score on the same test set.

## Collect data (iPhone)

1. Make sure `DevFlags.armDataCollection = true` (StrokeSense/DevFlags.swift).
2. On the arm screen, type a participant code (e.g. initials) and pick a label:
   - **Normal hold**: arm straight out, hold still.
   - **Simulated drift**: let the arm sink slowly and turn the palm down.
3. Aim for ~10 of each label per arm per person.
4. Copy the files from **Files › On My iPhone › StrokeSense › ArmRecordings**
   (AirDrop to the Mac) into `data/recordings/`.

## Train

```bash
python3.12 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python 01_make_synthetic.py          # optional: synthetic holds
.venv/bin/python 02_prepare_dataset.py          # add --real-only once there's enough real data
.venv/bin/python 03_train.py
.venv/bin/python 04_evaluate.py                 # AI vs the app's rule, on unseen participants
.venv/bin/python 05_export_coreml.py
cp -R exported/ArmDriftClassifier.mlpackage ../../StrokeSense/
```

## Features

`features.py` is the single definition; the app mirrors it in
`ArmRecording.modelInput` (BaselineData.swift). If you change one, change both.
5 channels × 140 steps (20 Hz over the 7 s hold after a 1 s settle):
sink and forearm turn relative to the first second (deg), pitch rate and total
rotation speed (deg/s), movement acceleration (g).

## Limits

- Synthetic "drift" is modelled on published numbers (iPronator: stroke
  patients ~27° drift / ~29° pronation, controls ~−2° / ~4°). It is not
  patient data, and the synthetic task is easy (test F1 1.00 vs 0.96 for the rule).
- Team-simulated drift teaches the model what *simulated* drift looks like.
  Real stroke recordings are needed before the AI should count toward the score.
