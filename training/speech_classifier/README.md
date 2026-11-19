# Speech clarity (dysarthria) classifier

Audio CNN on 128-band log-Mel spectrograms, as in the ML plan. Trained on
TORGO; shown in the app as **info only** until it holds up on iPhone
recordings of our own team.

## Data

- **TORGO** (Hugging Face `abnerh/TORGO-database`, 1.5 GB, free for non-profit
  use): 15 speakers, 8 with dysarthria (cerebral palsy / ALS, mild to severe)
  and 7 healthy, 16,552 clips at 16 kHz. Both groups were recorded with the
  same microphones, so the model can't separate them by recording setup.
  ```bash
  mkdir -p data/torgo && for i in 0 1 2 3; do curl -L -o data/torgo/train-0000$i-of-00004.parquet \
    https://huggingface.co/datasets/abnerh/TORGO-database/resolve/main/data/train-0000$i-of-00004.parquet; done
  ```
- **App recordings:** with `DevFlags.dataCollection = true`, each speech test
  saves a .wav and a .json (participant, normal / simulated slurred) in
  Files › On My iPhone › StrokeSense › SpeechRecordings.

## Run

```bash
python3.12 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python 01_prepare_dataset.py   # 4 s clips → log-Mel spectrograms
.venv/bin/python 02_train_eval.py        # leave-speakers-out folds + final model
.venv/bin/python 03_export_coreml.py
cp -R exported/SpeechClarityClassifier.mlpackage ../../StrokeSense/
```

## Design notes

- The spectrogram front end (STFT as fixed convolutions, Mel filterbank, log,
  per-clip normalisation) is **inside** the Core ML model. The app only
  resamples to 16 kHz and centre-crops/pads to 4 s, so Swift and Python can't
  compute features differently.
- Per-clip normalisation removes loudness and much of the microphone
  difference between TORGO's lab mics and an iPhone.
- Evaluation holds out one dysarthric and one healthy speaker per fold; with
  only 15 speakers, a single split would mostly measure who was held out.

## Limits

- TORGO speakers have cerebral palsy or ALS, not stroke. Related slurring,
  not the same condition, and only 8 dysarthric people.
- Lab recordings of single words and sentences, not an iPhone saying
  "You can't teach an old dog new tricks".
