#!/usr/bin/env python3
"""Generate a brief StrokeSense ML Improvement Plan focused on face, arm, speech."""

from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT

doc = Document()

for section in doc.sections:
    section.top_margin = Cm(2.54)
    section.bottom_margin = Cm(2.54)
    section.left_margin = Cm(2.54)
    section.right_margin = Cm(2.54)

style = doc.styles["Normal"]
style.font.name = "Calibri"
style.font.size = Pt(11)
style.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
style.paragraph_format.space_after = Pt(6)
style.paragraph_format.line_spacing = 1.15


def add_heading(text, level=1):
    h = doc.add_heading(text, level=level)
    for run in h.runs:
        run.font.color.rgb = RGBColor(0x1A, 0x47, 0x7A)
    return h


def add_bold_para(bold_text, normal_text):
    p = doc.add_paragraph()
    p.add_run(bold_text).bold = True
    p.add_run(normal_text)
    return p


def add_bullet(text, bold_prefix=None):
    p = doc.add_paragraph(style="List Bullet")
    if bold_prefix:
        p.add_run(bold_prefix).bold = True
        p.add_run(text)
    else:
        p.add_run(text)
    return p


# ── Title ──
for _ in range(5):
    doc.add_paragraph()

title = doc.add_paragraph()
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = title.add_run("StrokeSense")
run.font.size = Pt(32)
run.font.color.rgb = RGBColor(0x1A, 0x47, 0x7A)
run.bold = True

subtitle = doc.add_paragraph()
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = subtitle.add_run("ML Improvement Plan")
run.font.size = Pt(20)
run.font.color.rgb = RGBColor(0x44, 0x44, 0x44)

doc.add_paragraph()
meta = doc.add_paragraph()
meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = meta.add_run("Congressional App Challenge 2026\nNovember 2026")
run.font.size = Pt(12)
run.font.color.rgb = RGBColor(0x66, 0x66, 0x66)

doc.add_page_break()

# ── Overview ──
add_heading("Overview", level=1)

doc.add_paragraph(
    "StrokeSense currently detects stroke symptoms using Apple's built-in Vision and "
    "Speech frameworks with geometric heuristic scoring. This plan describes how we will "
    "improve detection accuracy by training custom machine learning classifiers on real "
    "stroke patient data and deploying them as CoreML models for on-device inference."
)

doc.add_paragraph(
    "Each of the three FAST checks (Face, Arms, Speech) gets its own trained classifier "
    "that outputs a stroke-likelihood probability instead of relying on simple threshold "
    "comparisons."
)

# ── Face ──
add_heading("Face Symmetry", level=1)

add_heading("Current Approach", level=2)
doc.add_paragraph(
    "Uses Apple Vision face landmarks to compute eye aspect ratios and mouth width-to-height "
    "ratios. A rolling buffer of 10 frames smooths noise. Scores are geometric calculations "
    "that have never seen real stroke data."
)

add_heading("What Changes", level=2)
add_bold_para("Model: ", "MobileNetV3-Small CNN, fine-tuned via transfer learning.")
add_bold_para("Input: ", "224x224 RGB face crop from the existing Vision face detector.")
add_bold_para("Output: ", "Stroke-asymmetry probability [0.0 - 1.0].")

doc.add_paragraph(
    "We freeze MobileNetV3's pre-trained feature layers and replace the final classification "
    "head with a 2-class layer (normal vs. stroke-asymmetry). The model learns what "
    "stroke-related facial drooping actually looks like, rather than measuring generic "
    "geometric ratios."
)

add_heading("Training Data", level=2)
add_bullet(
    "32 video clips of 22 facial palsy patients, labeled by 3 clinicians for palsy region "
    "and severity (low/high). Frames extracted at 6 FPS.",
    "YouTube Facial Palsy (YFP) Dataset: "
)
doc.add_paragraph(
    "    Where to get it: GitHub repo at github.com/AvLab-CV/YouTube-Facial-Palsy-Database "
    "(fill out RequestForms.txt for access). Also on Kaggle at "
    "kaggle.com/datasets/dohaeid/yfp-dataset-updated (filtered version with 4 severity classes). "
    "Official site: sites.google.com/view/yfp-database/"
)
add_bullet(
    "200K+ celebrity face images for the normal/negative class. Available under non-commercial "
    "research license.",
    "CelebA Dataset: "
)
doc.add_paragraph(
    "    Where to get it: Official page at mmlab.ie.cuhk.edu.hk/projects/CelebA.html. "
    "Direct download via Google Drive at drive.google.com/drive/folders/0B7EVK8r0v71pWEZsZE9oNnFzTm8. "
    "Also available through TensorFlow Datasets (tfds.load('celeb_a'))."
)
add_bullet(
    "Curated dataset of 1,000 droopy/stroke faces plus images of facial paralysis patients "
    "(Bell's palsy, stroke, brain tumors).",
    "Kaggle Stroke Faces: "
)
doc.add_paragraph(
    "    Where to get it: Search Kaggle for 'stroke faces' and 'facial paralysis'. "
    "Also see jasir/palsynet-data on Hugging Face (CC-BY-4.0 license)."
)
add_bold_para("Target: ", "500-1,000 stroke-positive + 2,000-5,000 normal face images.")

add_heading("Expected Gain", level=2)
doc.add_paragraph(
    "Current heuristic accuracy is estimated at 60-70%. The CNN classifier targets "
    "85-92% accuracy based on published facial palsy detection research."
)

# ── Arms ──
add_heading("Arm Drift", level=1)

add_heading("Current Approach", level=2)
doc.add_paragraph(
    "Uses Apple Vision body pose estimation to track shoulder-wrist angles over a 5-second "
    "hold. Computes angle variance as a steadiness score. This catches instability but "
    "misses the directional pattern of stroke-related drift (gradual downward movement "
    "with pronation)."
)

add_heading("What Changes", level=2)
add_bold_para("Model: ", "1D-CNN (3 layers, filters 32/64/64) or 2-layer LSTM (64 hidden units).")
add_bold_para("Input: ", "Time series of angle + x/y wrist position at 30fps for 5 seconds (150 timesteps x 3 features).")
add_bold_para("Output: ", "Pathological-drift probability [0.0 - 1.0].")

doc.add_paragraph(
    "The model processes the full sequence of arm movement data and learns the temporal "
    "signature of pathological drift vs. normal tremor or fatigue. Delta features "
    "(frame-to-frame change) are added as extra input channels."
)

add_heading("Training Data", level=2)
add_bullet(
    "3,372 trials from 51 stroke-impaired and 20 healthy subjects. 9 IMUs recorded upper "
    "body motion (arms, forearms, hands) at 100 Hz with video at 60-100 fps. Contains "
    "120,891 annotated functional primitives.",
    "StrokeRehab Dataset: "
)
doc.add_paragraph(
    "    Where to get it: Hosted on SimTK at simtk.org/projects/primseq. "
    "Free to download with a SimTK account (free registration). "
    "Paper: 'StrokeRehab: A Benchmark Dataset for Sub-second Action Identification' (NeurIPS 2022)."
)
add_bullet(
    "Wearable sensor kinematic dataset from 120 post-stroke patients performing standardized "
    "rehabilitation tasks.",
    "Post-Stroke Kinematic Dataset (2026): "
)
doc.add_paragraph(
    "    Where to get it: Published in Nature Scientific Data. Access via the paper's "
    "data availability section at nature.com/articles/s41597-026-07802-2."
)
add_bullet(
    "Collect 100+ healthy volunteers performing the same 5-second arm-hold test in the "
    "StrokeSense app to build a normal-class dataset under real phone-camera conditions.",
    "Self-Collected Normal Data: "
)
add_bold_para("Target: ", "200-500 stroke-positive + 500-1,000 normal arm recordings.")

add_heading("Expected Gain", level=2)
doc.add_paragraph(
    "Current heuristic accuracy is estimated at 55-65%. The time-series classifier "
    "targets 80-88% accuracy by capturing directional drift patterns the variance "
    "calculation misses."
)

# ── Speech ──
add_heading("Speech Clarity", level=1)

add_heading("Current Approach", level=2)
doc.add_paragraph(
    "Uses Apple Speech Recognition to transcribe spoken words, then computes a clarity "
    "score based on word-overlap with the target phrase. This measures whether the right "
    "words were said, not how they sounded. Slurred speech that produces correct words "
    "gets a high score, so stroke-related dysarthria goes undetected."
)

add_heading("What Changes", level=2)
add_bold_para("Model: ", "Audio CNN on Mel-frequency spectrograms (4-layer CNN with 32/64/128/128 filters).")
add_bold_para("Input: ", "128-band Mel spectrogram computed from the recorded audio clip.")
add_bold_para("Output: ", "Dysarthria probability [0.0 - 1.0].")

doc.add_paragraph(
    "By analyzing the audio spectrogram directly, the model captures pronunciation quality "
    "-- the acoustic features of slurred, imprecise articulation -- rather than relying on "
    "word accuracy. This is the single biggest accuracy improvement across all three checks."
)

add_heading("Training Data", level=2)
add_bullet(
    "23 hours of English speech from 8 dysarthric speakers (cerebral palsy / ALS) and "
    "7 healthy controls. Includes acoustic recordings and 3D articulatory features. "
    "18 GB total.",
    "TORGO Database: "
)
doc.add_paragraph(
    "    Where to get it: Official download at cs.toronto.edu/~complingweb/data/TORGO/torgo.html. "
    "Also available via Linguistic Data Consortium (catalog.ldc.upenn.edu/LDC2012S02). "
    "Subset on Kaggle at kaggle.com/datasets/pranaykoppula/torgo-audio. "
    "Also on Hugging Face: huggingface.co/datasets/abnerh/TORGO-database."
)
add_bullet(
    "103 hours of speech from 16 dysarthric and 13 control speakers. Recordings of digits, "
    "letters, commands, and words with intelligibility ratings.",
    "UA-Speech Corpus: "
)
doc.add_paragraph(
    "    Where to get it: Email Mark Hasegawa-Johnson at the University of Illinois to request "
    "free download access. Official page: isle.illinois.edu/sst/data/UASpeech/. "
    "Provide your name, institution, and mailing address."
)
add_bullet(
    "32,584 hours of open speech data across 131 languages. Provides abundant normal "
    "speech examples with diverse accents and ages. CC0 license (free to use).",
    "Mozilla Common Voice: "
)
doc.add_paragraph(
    "    Where to get it: commonvoice.mozilla.org/en/datasets. Select English, provide "
    "an email address, and download. Also on Hugging Face: "
    "huggingface.co/datasets/mozilla-foundation/common_voice_17_0."
)
add_bullet(
    "Multimedia database of language samples from individuals with stroke-related aphasia. "
    "Includes audio, transcriptions, and clinical severity scores.",
    "AphasiaBank: "
)
doc.add_paragraph(
    "    Where to get it: aphasia.talkbank.org. Access requires registration as an "
    "established researcher. Email talkbank@andrew.cmu.edu to request access, verifying "
    "your institutional status. Data downloadable via the TalkBank browser or TalkBankDB "
    "(talkbank.org/DB) for Python/R access."
)
add_bold_para("Target: ", "300-800 dysarthric + 2,000-5,000 normal speech clips.")

add_heading("Expected Gain", level=2)
doc.add_paragraph(
    "Current heuristic accuracy is estimated at 50-60%. The spectrogram classifier "
    "targets 82-90% accuracy. This is the largest expected gain (+25-30%) because the "
    "current word-overlap method fundamentally cannot detect pronunciation problems."
)

# ── Deployment ──
add_heading("Deployment to iOS", level=1)

doc.add_paragraph(
    "All three models are trained in Python (PyTorch), then converted to CoreML format "
    "using Apple's coremltools library. The .mlpackage files ship inside the app bundle."
)

add_bullet(
    "Apple Vision still detects faces and body pose. The cropped face image, arm angle "
    "time series, and speech spectrogram are each passed to their CoreML classifier.",
    "Integration: "
)
add_bullet(
    "Final score = 70% ML probability + 30% heuristic score. Weights tuned via field testing.",
    "Hybrid Scoring: "
)
add_bullet(
    "If a CoreML model fails to load, the app falls back to the existing heuristic scoring.",
    "Fallback: "
)

# ── Summary table ──
add_heading("Summary", level=1)

table = doc.add_table(rows=4, cols=5)
table.style = "Light Grid Accent 1"
table.alignment = WD_TABLE_ALIGNMENT.CENTER
headers = ["Check", "Current Method", "New Model", "Data Needed", "Accuracy Gain"]
for i, h in enumerate(headers):
    cell = table.rows[0].cells[i]
    cell.text = h
    for p in cell.paragraphs:
        for r in p.runs:
            r.bold = True
            r.font.size = Pt(9)

rows = [
    ("Face", "Geometric ratios\n(60-70%)", "MobileNetV3 CNN\n(85-92%)", "500-1K stroke\n+ 2-5K normal", "+15-25%"),
    ("Arms", "Angle variance\n(55-65%)", "1D-CNN / LSTM\n(80-88%)", "200-500 stroke\n+ 500-1K normal", "+20-25%"),
    ("Speech", "Word overlap\n(50-60%)", "Audio CNN\n(82-90%)", "300-800 dysarthric\n+ 2-5K normal", "+25-30%"),
]
for i, row_data in enumerate(rows):
    for j, val in enumerate(row_data):
        cell = table.rows[i + 1].cells[j]
        cell.text = val
        for p in cell.paragraphs:
            for r in p.runs:
                r.font.size = Pt(9)

doc.add_paragraph()

# ── Save ──
output_path = "/Users/WAIFONG/Documents/My Projects/StrokeSense/StrokeSense_ML_Improvement_Plan.docx"
doc.save(output_path)
print(f"Document saved to: {output_path}")
