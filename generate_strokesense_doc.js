// Generates StrokeSense.docx ("How Detection Works").
// Usage: npm install docx && node generate_strokesense_doc.js StrokeSense.docx
// Add arm/speech content by editing the rawChildren array.
const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow,
  TableCell, WidthType, ShadingType, BorderStyle, LevelFormat, Footer, PageNumber,
} = require("docx");

const FONT = "Arial";
const ACCENT = "C0392B";
const GRAY = "666666";

const p = (text, opts = {}) =>
  new Paragraph({ spacing: { after: 120 }, ...opts, children: runs(text) });

// Supports **bold** segments inside a string.
function runs(text) {
  return text.split(/(\*\*[^*]+\*\*)/).filter(Boolean).map((s) =>
    s.startsWith("**") ? new TextRun({ text: s.slice(2, -2), bold: true, font: FONT }) : new TextRun({ text: s, font: FONT })
  );
}

const h1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(t)] });
const h2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(t)] });
const h3 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun({ text: t, font: FONT })] });
const note = (t) => new Paragraph({ spacing: { after: 120 }, children: [new TextRun({ text: t, italics: true, color: GRAY, font: FONT })] });
const bullet = (t) => new Paragraph({ numbering: { reference: "bullets", level: 0 }, spacing: { after: 60 }, children: runs(t) });
let stepInstance = 1;
const newList = () => { stepInstance += 1; return null; };
const step = (t) => new Paragraph({ numbering: { reference: "steps" + stepInstance, level: 0 }, spacing: { after: 60 }, children: runs(t) });

const formula = (t) =>
  new Paragraph({
    spacing: { before: 60, after: 60 },
    indent: { left: 360 },
    shading: { type: ShadingType.CLEAR, fill: "F4F4F4", color: "auto" },
    children: [new TextRun({ text: t, font: "Courier New", size: 20 })],
  });

const border = { style: BorderStyle.SINGLE, size: 4, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };

function table(widths, header, rows) {
  const total = widths.reduce((a, b) => a + b, 0);
  const cell = (text, i, isHeader) =>
    new TableCell({
      width: { size: widths[i], type: WidthType.DXA },
      borders,
      shading: isHeader ? { type: ShadingType.CLEAR, fill: "F2D7D5", color: "auto" } : undefined,
      margins: { top: 60, bottom: 60, left: 100, right: 100 },
      children: [new Paragraph({ children: isHeader ? [new TextRun({ text, bold: true, font: FONT })] : runs(text) })],
    });
  return new Table({
    width: { size: total, type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      new TableRow({ tableHeader: true, children: header.map((t, i) => cell(t, i, true)) }),
      ...rows.map((r) => new TableRow({ children: r.map((t, i) => cell(t, i, false)) })),
    ],
  });
}

const spacer = () => new Paragraph({ spacing: { after: 120 }, children: [] });

const rawChildren = [
  new Paragraph({ heading: HeadingLevel.TITLE, children: [new TextRun({ text: "StrokeSense", font: FONT })] }),
  new Paragraph({
    spacing: { after: 60 },
    children: [new TextRun({ text: "How Detection Works", size: 32, color: GRAY, font: FONT })],
  }),
  new Paragraph({
    spacing: { after: 240 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: ACCENT, space: 4 } },
    children: [new TextRun({ text: "Congressional App Challenge 2026  ·  Last updated November 18, 2026", size: 20, color: GRAY, font: FONT })],
  }),

  h1("1. Overview"),
  p("StrokeSense guides the user through three quick checks based on the B.E. F.A.S.T. stroke warning signs: face droop, arm weakness and speech difficulty. Each check is compared against the user's own personal baseline, recorded on a normal day, so the app looks for a change in that person rather than comparing them with everyone else."),
  p("Every check produces a score from 0% to 100%, where higher always means better (more symmetric, steadier, clearer). Section 5 explains how the app compares those scores with the baseline and decides the overall result."),
  p("The app never diagnoses a stroke. It reports a change from the user's baseline and points them toward help. Anyone with sudden symptoms should call 911 whatever the app shows."),
  table([2400, 4560, 2400], ["Check", "What it looks for", "Status"], [
    ["Face Symmetry", "One side of the face drooping", "Section 2"],
    ["Arm Drift", "One arm drifting down or unsteady", "To be added"],
    ["Speech Clarity", "Slurred or unclear speech", "To be added"],
  ]),
  spacer(),

  h1("2. Face Symmetry Detection"),
  h2("2.1 Summary"),
  p("The face check looks for one side of the face drooping. The Face Symmetry score combines two independent measurements:"),
  bullet("**Geometry (80% of the score):** measured directly from face landmarks that Apple's Vision framework finds on the face: mouth corners, eyes and so on."),
  bullet("**AI model (20% of the score):** a small neural network we trained that looks at a picture of the face and estimates how asymmetric it looks."),
  p("Both are expressed as a symmetry score from 0% to 100%, where higher means more symmetric."),

  h2("2.2 From camera to measurements"),
  step("**Camera:** the front camera streams video using AVFoundation. Frames are rotated to portrait before analysis."),
  step("**Landmarks:** for every frame, Apple Vision runs VNDetectFaceLandmarksRequest, which returns the face's position and outlines of the lips and both eyes."),
  step("**Per-frame measurements:** from the landmarks, the app measures mouth-corner tilt and the openness of each eye (Section 2.3)."),
  step("**Smoothing:** the last 10 frames are kept in a rolling buffer. When the user taps Record, the app averages those frames, so a single blurry frame or blink can't decide the result."),
  step("**AI crop:** at the same moment, the face is cropped from the latest frame (with a 10% margin) and passed to the AI model (Section 2.4)."),
  step("**Saved metrics:** the result is stored as the baseline, during onboarding, or compared against the baseline, during a check."),

  h2("2.3 Geometry measurement"),
  h3("Mouth-corner tilt (75% of geometry)"),
  p("When one side of the face droops, that mouth corner sits lower than the other. The app measures this directly:"),
  newList(),
  step("Find the center of each eye. The line between them is the face's horizontal reference."),
  step("Rotate all the lip points so that eye line is perfectly level. That way a tilted head, or a phone held at an angle, doesn't count as asymmetry."),
  step("Take the two ends of the mouth along that level line: the left and right mouth corners."),
  step("Measure the vertical gap between the corners and divide it by the mouth width. That gives the tilt, a percentage that doesn't depend on how close the face is to the camera."),
  formula("tilt = |corner height difference| / mouth width"),
  formula("mouth symmetry = 1 − min(tilt / 0.12, 1)"),
  p("A tilt of 0% (level corners) scores 100%. A tilt of 12% or more scores 0%. The 12% cut-off was calibrated on a real iPhone. A relaxed face measured about 1% tilt, and a strong deliberate one-sided droop measured about 7%."),
  h3("Eye openness (25% of geometry)"),
  p("Facial droop can also make one eyelid sag. For each eye, the app computes an eye aspect ratio (eye height divided by eye width) and scales it to 0–100% openness. Then it compares the two eyes:"),
  formula("eye symmetry = 1 − min(|left openness − right openness| / 0.5, 1)"),
  h3("Geometry score"),
  formula("geometry = 0.75 × mouth symmetry + 0.25 × eye symmetry"),
  p("The mouth gets more weight because a drooping mouth corner is the most visible and reliable sign of facial weakness. The eye comparison adds a second, independent clue."),

  h2("2.4 AI model"),
  bullet("**Architecture:** MobileNetV3-Small, a compact image network designed for phones, fine-tuned with transfer learning."),
  bullet("**Input:** a 224 × 224 color crop of the face. ImageNet normalization is built into the model."),
  bullet("**Output:** one number, converted with a sigmoid into an asymmetry probability from 0 to 1. The app flips it into a symmetry score (1 − probability) so it uses the same direction as geometry."),
  bullet("**Training data:** frames of facial-palsy patients from the PalsyNet dataset (asymmetric class) and photos from the Celebrity-1000 dataset (normal class)."),
  bullet("**Runs on-device:** converted to Core ML and bundled in the app. No face images leave the phone. If the model fails to load, the app falls back to geometry only."),

  h2("2.5 How the weight is split: 80% geometry, 20% AI"),
  formula("face score = 0.8 × geometry + 0.2 × (1 − AI asymmetry probability)"),
  p("Both parts are measured the same way for the baseline and for the check, so the two face scores can be compared directly."),
  h3("Why geometry gets most of the weight"),
  p("We tested both parts on a real iPhone. The geometry measurement responded correctly to a deliberate droop. The AI model didn't. In an early test, it rated the tester's normal face as 42% asymmetric and their deliberately drooped face as 1%, which is backwards. In the later test (Section 2.6), it barely moved (100% → 99% symmetry)."),
  p("The most likely reason is the training data. All the asymmetric examples are frames from patient videos, and all the normal examples are polished celebrity photos. The model may have learned to tell the two image styles apart instead of learning what a droop looks like. It also judges a single frame, so its output can jump around."),
  table([2400, 3480, 3480], ["", "Geometry", "AI model"], [
    ["How it decides", "Measures mouth corners and eyes directly", "Learned pattern from training images"],
    ["Can we explain it?", "Yes, e.g. \"left corner 7% lower\"", "No, it only outputs a number"],
    ["Tested on iPhone", "Detected the deliberate droop", "Did not detect it"],
    ["Weight now", "**80%**", "**20%**"],
  ]),
  spacer(),
  p("The AI keeps a small 20% share so we can keep watching how it behaves on real phones. Its weight is a single setting in the code (geometryWeight = 0.8 in CheckResultsView.swift). We plan to raise it once a retrained model beats geometry on the same tests (Section 2.8)."),

  h2("2.6 Worked example (real iPhone test)"),
  p("These are the raw values from a test on November 18, 2026. The baseline was recorded with a relaxed face, then a check was done while deliberately pulling one corner of the mouth down."),
  table([3120, 3120, 3120], ["Raw measurement", "Baseline (relaxed)", "Check (deliberate droop)"], [
    ["Mouth-corner tilt", "1%", "7%"],
    ["Eye openness (L / R)", "71% / 73%", "74% / 71%"],
    ["AI symmetry (1 − asymmetry)", "100%", "99%"],
  ]),
  spacer(),
  h3("Step 1: Geometry"),
  formula("Baseline  mouth = 1 − 0.01/0.12 = 0.917    eye = 1 − 0.02/0.5 = 0.96"),
  formula("          geometry = 0.75 × 0.917 + 0.25 × 0.96 = 0.93  →  93%"),
  formula("Check     mouth = 1 − 0.07/0.12 = 0.417    eye = 1 − 0.03/0.5 = 0.94"),
  formula("          geometry = 0.75 × 0.417 + 0.25 × 0.94 = 0.55  →  55%"),
  h3("Step 2: Combine 80% geometry + 20% AI"),
  formula("Baseline  face = 0.8 × 0.93 + 0.2 × 1.00 = 0.94  →  94%"),
  formula("Check     face = 0.8 × 0.55 + 0.2 × 0.99 = 0.64  →  64%"),
  h3("Step 3: Compare with baseline (rules in Section 5)"),
  formula("drop = 94 − 64 = 30 points  →  Significant drop"),
  p("Result: the Face card shows a **Significant drop** and the overall header shows **Be Aware**. On the screen, the drop can read 30 or 31 points, because the raw values above are rounded."),
  h3("What the earlier version showed for the same face"),
  p("Before calibration (a 20% tilt cut-off and less weight on geometry), the same test produced only a 19-point Minor drop under a green \"Looking Good\" header. The AI model contributed almost nothing, which pulled the score toward \"no change\". This test is why geometry now carries 80% of the weight and the cut-off was tightened."),

  h2("2.7 Limitations"),
  bullet("Tested so far on one person with a deliberate, simulated droop. A real stroke droop may look different."),
  bullet("Lighting, glasses, beards and camera angle can affect landmark accuracy. Recording the baseline and the check in similar conditions gives the best comparison."),
  bullet("Small, natural changes in expression (for example, tilt moving from 1% to 3%) can produce a Minor drop. The 12% cut-off may need further tuning."),
  bullet("The AI model isn't reliable yet (Section 2.5), which is why its weight is limited to 20%."),

  h2("2.8 Next steps"),
  bullet("**Retrain the AI model** using PalsyNet patient frames against PalsyNet control frames, so both classes come from the same kind of video and the model has to learn the droop itself."),
  bullet("**Average the AI over several frames** instead of one, to reduce jumpy readings."),
  bullet("**Build a shared test set:** team members' relaxed faces, deliberate droops, and held-out patient frames. Score geometry and AI on the same set."),
  bullet("**Raise the AI weight** (for example to 50/50) only if the retrained model clearly beats geometry on that test set."),
  bullet("**Tune the cut-offs** (12% tilt, 10/25 point drops) using more test sessions."),

  h1("3. Arm Drift Detection"),
  note("To be added."),

  h1("4. Speech Clarity Detection"),
  note("To be added."),

  h1("5. Comparing against the baseline"),
  p("This applies to every check. The app measures the **drop** in each score from baseline to now, in points on a 0–100 scale:"),
  formula("drop = (baseline score − current score) × 100"),
  p("Two rules make this safer than a percentage change:"),
  bullet("**Points, not percent of baseline.** With percent change, a small baseline turns a small change into a huge-looking one. An early version showed a \"451% change\" for this reason."),
  bullet("**Only a decline counts.** Scoring better than baseline is never treated as a warning sign."),
  table([2400, 3480, 3480], ["Drop", "Result card shows", "Effect on overall result"], [
    ["Less than 10 points", "Normal (green)", "None"],
    ["10–24 points", "Minor drop (orange)", "Header shows at least \"Be Aware\""],
    ["25 points or more", "Significant drop (red)", "Counts as a flagged check"],
  ]),
  spacer(),
  p("Across all checks, the number of significant drops sets the overall result: 0 = Looking Good, 1 = Be Aware, 2 = Getting Serious, 3 or more = Seek Help Now. Nearby urgent care and the 911 countdown only appear for significant drops, so a minor change can never start an emergency on its own."),
];

const children = rawChildren.filter(Boolean);
const doc = new Document({
  creator: "StrokeSense team",
  title: "StrokeSense: How Detection Works",
  styles: {
    default: { document: { run: { font: FONT, size: 22 } } },
    paragraphStyles: [
      { id: "Title", name: "Title", basedOn: "Normal", next: "Normal",
        run: { font: FONT, size: 52, bold: true, color: ACCENT },
        paragraph: { spacing: { before: 0, after: 60 }, keepNext: true } },
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 30, bold: true, color: ACCENT },
        paragraph: { spacing: { before: 320, after: 120 }, keepNext: true, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 24, bold: true, color: "333333" },
        paragraph: { spacing: { before: 200, after: 80 }, keepNext: true, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 22, bold: true, color: GRAY },
        paragraph: { spacing: { before: 160, after: 60 }, keepNext: true, outlineLevel: 2 } },
    ],
  },
  numbering: {
    config: [
      { reference: "bullets", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      ...[1, 2].map((n) => ({ reference: "steps" + n, levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] })),
    ],
  },
  sections: [{
    properties: { page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } } },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: "StrokeSense · How Detection Works · Page ", size: 18, color: GRAY, font: FONT }),
                 new TextRun({ children: [PageNumber.CURRENT], size: 18, color: GRAY, font: FONT })] })] }) },
    children,
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(process.argv[2], buf);
  console.log("wrote", process.argv[2]);
});
