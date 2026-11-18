---
status: in-progress
branch: main
timestamp: 2026-11-18T12:34:16-06:00
files_modified: []
---

## Working on: Face symmetry scoring and detection doc

### Summary

Wired the trained CoreML face model into the iOS app, then found on-device that both the AI model and the old geometry heuristic failed to detect a deliberate droop. Rebuilt face scoring as 80% landmark geometry + 20% AI, switched baseline comparison to directional point drops, calibrated on an iPhone test, and wrote `StrokeSense.docx` explaining it. All work is committed and pushed to `origin/main` (7d6f4fb code, 050e27e doc, plus the checkpoint commit that follows this file).

### Decisions Made

- **Face score = 0.8 × geometry + 0.2 × (1 − AI asymmetry prob)** (`CheckResultsView.swift`, `geometryWeight = 0.8`). The AI model rated a normal face 42% asymmetric and a deliberate droop 1% (backwards); later 100%→99% symmetry (no signal). Likely shortcut learning: positives are PalsyNet video frames, negatives are Celebrity-1000 photos. User chose 80/20 over info-only.
- **Old geometry heuristic was broken**: `mouthSmile` measured corners relative to their own midpoint, so averaging left+right cancelled asymmetry. Replaced with `mouthCornerTilt` (FaceDetectionService.swift): rotate lip points into the eye-line frame (removes head roll), take extreme-x points as corners, tilt = |Δy| / mouth width. Corners are picked AFTER rotation (picking before broke on rotated frames).
- **Geometry = 0.75 × mouth symmetry + 0.25 × eye symmetry** (`FaceMetrics.geometrySymmetry` in BaselineData.swift). mouth = 1 − min(tilt/0.12, 1); eye = 1 − min(|L−R|/0.5, 1). Raw tilt is stored, scale applied at compute time, so changing the 0.12 cut-off does not require re-recording the baseline. `mouthCornerTilt` is optional; old baselines fall back to legacy smile average.
- **Calibration (iPhone test, Nov 18):** relaxed tilt ~1%, strong deliberate droop ~7%. With 0.12 scale: baseline face 94%, droop 64%, drop 30 pts → Significant, header Be Aware. Old settings (0.20 scale, 70/30 AI) gave only a 19-pt Minor drop under "Looking Good".
- **Baseline comparison is now drop in points, decline only** (`dropPoints`): minor ≥ 10, significant ≥ 25. Was abs(% of baseline), which showed "451%" and flagged improvements (could even drive the 911 countdown).
- **Header rule:** any minor drop → at least "Be Aware" (`severityLevel`). Urgent care + 911 countdown still keyed on `flaggedCount` (significant drops only).
- Baseline capture now runs the AI too (`captureSnapshotWithML` in BaselineFaceView), so baseline and check are scored the same way.
- LLM prompt + `MetricPair.dropPoints` updated to the new metric.
- `DevFlags.faceOnly = true` (StrokeSense/DevFlags.swift) skips arm + speech in baseline and check; arm/speech cards use placeholder values. **Committed as true.**
- Results screen shows a debug breakdown under the Face card: Geometry/AI/Raw (tilt, eyes) lines.

### Remaining Work

1. **Relaxed-face test** with the 0.12 scale: confirm a normal check shows Normal / Looking Good. If everyday wobble (tilt 1%→3%) trips a Minor drop, loosen the scale slightly (e.g. 0.14–0.15) and update the doc.
2. **Arm drift**: write the "3. Arm Drift Detection" section of StrokeSense.docx; consider the ML plan's 1D-CNN/LSTM classifier. Re-enable via `DevFlags.faceOnly = false`.
3. **Speech clarity**: write "4. Speech Clarity Detection" section; the current word-overlap metric cannot detect slurring (ML plan: audio CNN on Mel spectrograms).
4. **Retrain the face AI** using PalsyNet affected vs PalsyNet control frames (`PALSYNET_CONTROL_DIR` already in training/face_classifier/config.py); average AI over several frames instead of the single latest frame. Raise AI weight only if it beats geometry on a shared test set.
5. Before demo/TestFlight: set `DevFlags.faceOnly = false` (or delete DevFlags.swift); consider hiding the debug breakdown lines.
6. Add a baseline re-record option (currently must delete the app to re-onboard).
7. Pre-existing issues noticed, not addressed: video_script.md claims automatic 911 calling and "peace of mind" messaging, which conflicts with CONTEXT.md safety rules; README.md is empty; CONTEXT.md lists the Oct 26 CAC deadline (already passed).

### Notes

- **Xcode is on the external volume**: `/Volumes/<spaces>/Applications/Xcode.app`. `xcode-select` still points at CommandLineTools, so CLI builds need `DEVELOPER_DIR=".../Xcode.app/Contents/Developer"`. Builds must use default DerivedData (a `/tmp` derivedDataPath fails CoreML compile with a weight.bin permission error from Xcode's build sandbox).
- `StrokeSense/APIKeys.swift` is gitignored; a placeholder with an empty OpenAI key was created on this Mac. Paste the real key for the LLM summary to work. Each new machine needs this file.
- Project uses Xcode 16+ synchronized folders: new files under `StrokeSense/` are added to the target automatically; no manual "add to project" step.
- `python3` is killed (exit 137) on this Mac; use node/Edit instead for scripts.
- Doc generator: `generate_strokesense_doc.js` at repo root (needs `npm install docx`), outputs `StrokeSense.docx`. Edit the `rawChildren` array to add arm/speech sections.
- Git push: remote switched to SSH `git@github.com:wfong2/StrokeSense.git`; `~/.ssh/config` maps github.com to `~/.ssh/github_ed25519` (new Ed25519 key added to GitHub; the old 2048-bit `github_rsa` was rejected by GitHub as too short). known_hosts updated to GitHub's post-2023 RSA key.
- Context saved on one machine lives in `~/.gstack` only; the repo `CHECKPOINT.md` mirrors this file so it reaches other machines via git pull.
