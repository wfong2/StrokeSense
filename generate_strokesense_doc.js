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
    ["Arm Drift", "One arm sinking, turning or sagging", "Section 3"],
    ["Speech Clarity", "Slurred or unclear speech", "To be added"],
  ]),
  spacer(),
  p("**A principle across both checks:** measurements we can explain and test (rules) make the decision. AI models are trained alongside them and only get weight once tested on real phones. The face AI failed those tests and is shown for information only; the arm AI passed them so far and has a 20% share."),

  // ── FACE ───────────────────────────────────────────────────────────
  h1("2. Face Symmetry Detection"),
  h2("2.1 Summary"),
  p("The face check looks for one side of the face drooping. Two measurements are taken:"),
  bullet("**Geometry (100% of the score):** measured directly from face landmarks that Apple's Vision framework finds on the face: mouth corners and eyes."),
  bullet("**AI model (shown, not scored):** a neural network we trained that looks at a picture of the face and estimates how asymmetric it looks. It started with a 20% share and was set to 0% after iPhone testing (Section 2.5)."),
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
  p("A tilt of 0% (level corners) scores 100%. A tilt of 12% or more scores 0%. The 12% cut-off was calibrated on a real iPhone: relaxed faces measured 1–2% tilt, deliberate one-sided droops 5–7%."),
  h3("Eye openness (25% of geometry)"),
  p("Facial droop can also make one eyelid sag. For each eye, the app computes an eye aspect ratio (eye height divided by eye width) and scales it to 0–100% openness. Then it compares the two eyes:"),
  formula("eye symmetry = 1 − min(|left openness − right openness| / 0.5, 1)"),
  h3("Geometry score"),
  formula("geometry = 0.75 × mouth symmetry + 0.25 × eye symmetry"),
  p("The mouth gets more weight because a drooping mouth corner is the most visible and reliable sign of facial weakness. The eye comparison adds a second, independent clue."),

  h2("2.4 AI model"),
  bullet("**Architecture:** MobileNetV3-Small, a compact image network designed for phones, fine-tuned with transfer learning."),
  bullet("**Input:** a 224 × 224 color crop of the face. ImageNet normalization is built into the model."),
  bullet("**Output:** one number, converted with a sigmoid into an asymmetry probability from 0 to 1. The app shows it as a symmetry score (1 − probability), the same direction as geometry."),
  bullet("**Training data:** frames of facial-palsy patients from the PalsyNet dataset (asymmetric class) and photos from the Celebrity-1000 dataset (normal class)."),
  bullet("**Runs on-device:** converted to Core ML and bundled in the app. No face images leave the phone."),

  h2("2.5 How the weight is split: 100% geometry, AI shown for information"),
  formula("face score = geometry"),
  p("We first combined the two as 80% geometry + 20% AI. Testing on a real iPhone showed the AI was unreliable: its reading swung by 60–90 points between photos of the same face, often in the wrong direction. Even at a 20% share, those swings outweighed the geometry. So the AI's weight was set to 0%. Its reading is still shown under the Face card so we can keep comparing."),
  h3("What 20% AI would have done to our real tests"),
  p("Every row is a real test on November 18, 2026. Geometry got every one right. The last column shows what the result would have been with the AI at 20%."),
  table([1500, 1500, 2300, 2030, 2030], ["Test", "Geometry drop", "AI symmetry (baseline → now)", "Result, AI 0% (now)", "Result if AI were 20%"], [
    ["Relaxed face", "5 pts", "100% → 17%", "**Normal** ✓", "Minor drop ✗ (false alarm)"],
    ["Deliberate droop", "25 pts", "36% → 98%", "**Significant** ✓", "Normal ✗ (missed)"],
    ["Deliberate droop", "26 pts", "1% → 93%", "**Significant** ✓", "Normal ✗ (missed)"],
    ["Deliberate droop", "21 pts", "1% → 97%", "**Minor** ✓", "Normal ✗ (missed)"],
    ["Relaxed face", "8 pts", "1% → 47%", "**Normal** ✓", "Normal ✓"],
  ]),
  spacer(),
  p("At 20%, the AI would have hidden all three deliberate droops and raised one false alarm. In the droop tests it rated the drooped face as **more** symmetric than the relaxed one."),
  h3("Why the AI fails"),
  p("The most likely reason is the training data. All the asymmetric examples are frames from patient videos, and all the normal examples are polished celebrity photos. The model may have learned to tell the two image styles apart instead of learning what a droop looks like. It also judges a single frame, so its output can jump around."),
  table([2400, 3480, 3480], ["", "Geometry", "AI model"], [
    ["How it decides", "Measures mouth corners and eyes directly", "Learned pattern from training images"],
    ["Can we explain it?", "Yes, e.g. \"left corner 6% lower\"", "No, it only outputs a number"],
    ["Tested on iPhone", "Correct in all 5 tests", "Wrong direction in 4 of 5 tests"],
    ["Weight now", "**100%**", "**0% (shown only)**"],
  ]),
  spacer(),
  p("The weight is one setting in the code (geometryWeight = 1.0 in CheckResultsView.swift). It will only be lowered if a retrained model beats geometry on the same tests (Section 2.8)."),

  h2("2.6 Worked example (real iPhone test)"),
  p("Raw values from a test on November 18, 2026: baseline with a relaxed face, then a check while deliberately pulling one corner of the mouth down."),
  table([3120, 3120, 3120], ["Raw measurement", "Baseline (relaxed)", "Check (deliberate droop)"], [
    ["Mouth-corner tilt", "1%", "7%"],
    ["Eye openness (L / R)", "71% / 73%", "74% / 71%"],
  ]),
  spacer(),
  h3("Step 1: Geometry"),
  formula("Baseline  mouth = 1 − 0.01/0.12 = 0.917    eye = 1 − 0.02/0.5 = 0.96"),
  formula("          geometry = 0.75 × 0.917 + 0.25 × 0.96 = 0.93  →  93%"),
  formula("Check     mouth = 1 − 0.07/0.12 = 0.417    eye = 1 − 0.03/0.5 = 0.94"),
  formula("          geometry = 0.75 × 0.417 + 0.25 × 0.94 = 0.55  →  55%"),
  h3("Step 2: Compare with baseline (rules in Section 5)"),
  formula("drop = 93 − 55 = 38 points  →  Significant drop"),
  p("Result: the Face card shows a **Significant drop** and the overall header shows **Be Aware**."),
  h3("How the scoring got here"),
  p("The very first version measured \"smile size\" instead of left-right difference, and gave this same droop a 19-point Minor drop under a green \"Looking Good\" header. Measuring corner tilt along the eye line, calibrating the 12% cut-off on a real phone, and removing the AI's share fixed that."),

  h2("2.7 Limitations"),
  bullet("Tested on one person with deliberate, simulated droops. A real stroke droop may look different."),
  bullet("Lighting, glasses, beards and camera angle can affect landmark accuracy. Recording the baseline and the check in similar conditions gives the best comparison."),
  bullet("Small, natural changes in expression (tilt moving from 1% to 3%) can produce a Minor drop. The 12% cut-off may need further tuning."),
  bullet("The AI model isn't reliable yet (Section 2.5), so it doesn't count toward the score."),

  h2("2.8 Next steps"),
  bullet("**Retrain the AI model** using PalsyNet patient frames against PalsyNet control frames, so both classes come from the same kind of video and the model has to learn the droop itself."),
  bullet("**Average the AI over several frames** instead of one, to reduce jumpy readings."),
  bullet("**Build a shared test set:** team members' relaxed faces, deliberate droops, and held-out patient frames. Score geometry and AI on the same set."),
  bullet("**Give the AI weight again** only if the retrained model beats geometry on that test set."),

  // ── ARM ────────────────────────────────────────────────────────────
  h1("3. Arm Drift Detection"),
  h2("3.1 Summary"),
  p("The arm check looks for the classic sign of arm weakness: when a person holds both arms out with their eyes closed, a weak arm slowly **sinks** and the palm **turns** inward. StrokeSense tests one arm at a time with the phone held in that hand, and reads the phone's motion sensors."),
  bullet("**Rules (80% of the score):** drift, turn and shake during the hold, plus how much lower the arm is than at baseline (sag)."),
  bullet("**AI model (20% of the score):** a small network trained on the sensor recordings. It passed our iPhone tests so far, unlike the face AI."),
  bullet("**The weaker arm decides.** One-sided weakness is the warning sign; averaging both arms would halve it."),

  h2("3.2 Why the phone's motion sensors, not the camera"),
  p("The first version used the front camera and Apple Vision body pose, like the face check. On a real iPhone it failed: with the phone in one hand at arm's length, the camera only sees about 25 cm either side of the body's center, so an arm held out to the side is out of view. Three of four holds captured 0–1 frames."),
  p("Holding the phone **in the hand being tested** solves this. The phone tilts exactly as the hand does, the sensors record 50 readings a second, and it works in any lighting. It also matches published research: the iPronator study (stroke patients vs healthy controls) used handheld devices' sensors on the forearms, and the NeuFun-TS study used a phone's accelerometer for the same test."),

  h2("3.3 How the test works"),
  newList(),
  step("The screen says which arm (right first). The user holds the phone **upright in that hand, screen facing them**. Flat on the palm, screen up, also works."),
  step("They tap **Start**. The phone says \"Stretch your arm straight out in front of you\" and counts down 3 seconds."),
  step("A **vibration** and \"Close your eyes and hold still\" mark the start. The phone records for **8 seconds**."),
  step("A vibration and \"Done\" mark the end. Then the same for the other arm."),
  step("If a hold didn't record enough readings, or the phone was on its side, the phone says so and **repeats that arm**. The app never continues with an arm it couldn't measure."),
  p("Every step is spoken and marked with a vibration, because the user can't watch the screen with their arm stretched out and eyes closed."),

  h2("3.4 Measurements"),
  p("The first second of each hold is skipped while the arm settles. All angles come from the direction of gravity as seen by the phone, which is the same whether the phone is held upright or flat."),
  table([1900, 4160, 3300], ["Measure", "What it is", "Score"], [
    ["**Drift**", "How much the arm sank from the first second of the hold to the last (downward only)", "20° or more = 0"],
    ["**Turn**", "How much the forearm rotated (palm turning) during the hold", "30° or more = 0"],
    ["**Shake**", "Wobble around the arm's overall trend line", "3° or more = 0"],
    ["**Sag vs baseline**", "How much lower the arm is held than the same arm at baseline", "First 8° free, then 0 at 28°"],
  ]),
  spacer(),
  formula("hold score = 0.60 × drift + 0.25 × turn + 0.15 × shake"),
  formula("rules = the lower of (hold score, sag score)"),
  p("**Why sag counts on its own:** a real patient may not reach a level arm at all. If the arm is already low and shaky when the recording starts, and then stays low, drift during the hold is near 0°. Comparing against the user's own baseline catches it. Taking the lower of the two scores means a steady but sagging arm can't hide behind a good drift score."),
  p("**Why 8° is allowed:** the phone tilts with the wrist as well as the arm. In our steady checks, the arm's angle differed from baseline by up to 7° from wrist position alone. An earlier \"Arm Position\" card that scored the raw angle was removed for this reason."),

  h2("3.5 AI model"),
  bullet("**Architecture:** a 1D convolutional network (three layers with 32, 64 and 64 filters, about 37,000 parameters), as specified in our ML improvement plan."),
  bullet("**Input:** 5 signals over the 7-second hold, resampled to 140 steps: sink and turn relative to the start, tilt rate, total rotation speed and movement acceleration."),
  bullet("**Output:** drift probability. The app uses 1 − probability so higher means \"stayed put\"."),
  bullet("**Training data so far:** 480 synthetic holds that we generated, modelled on the iPronator study's published numbers. **No real patient data.**"),
  bullet("**Pipeline:** training/arm_classifier generates data, splits it by participant, trains, evaluates the AI against the rules on people it hasn't seen, and exports to Core ML. We verified the app computes exactly the same inputs as the Python training code (identical on 12 recordings)."),
  bullet("**Data collection:** a data-collection mode in the app tags each hold with a participant code and a \"normal\" or \"simulated drift\" label, and saves the raw sensor data. Every test our team runs becomes training data."),

  h2("3.6 How the weight is split: 80% rules, 20% AI"),
  formula("arm score (per arm) = 0.8 × rules + 0.2 × (1 − AI drift probability)"),
  formula("Arm Drift card = the lower of left and right"),
  p("Unlike the face AI, the arm AI stayed steady between baseline and steady checks (within about 5 points) and dropped clearly when the arm sank. So it keeps a 20% share. It isn't given more, because it was trained on synthetic data and can't see the baseline, so it can't detect sag. In our \"arm already low\" test it barely moved. With 80% AI weight, that test would have shown only a Minor drop instead of Significant:"),
  table([2600, 2250, 2250, 2260], ["Weight", "Rules part (40-pt drop)", "AI part (~7-pt drop)", "Card result"], [
    ["80% rules / 20% AI (now)", "32", "1", "**~33 → Significant** ✓"],
    ["20% rules / 80% AI", "8", "6", "~14 → Minor ✗"],
  ]),
  spacer(),

  h2("3.7 Real iPhone tests (November 18, 2026)"),
  table([2300, 2600, 2230, 2230], ["Test", "Measured", "Rules / AI (baseline → now)", "Result"], [
    ["Steady hold", "Drift 0°, turn 1–4°, shake 0.2°", "Rules 95/99 → 96/98; AI 87/85 → 87/86", "**Normal** ✓"],
    ["Arm sinks after the buzz", "Drift 9° and 8°, smooth sink from 2.5 s", "Rules 99/95 → 68/74; AI 87/90 → 51/50", "**Significant (30 pts)** ✓"],
    ["Arm already low when recording starts", "Drift 1°, but 14° and 17° below baseline", "Rules drop 3 pts before the sag rule, 40 pts after", "**Significant** ✓ (missed before sag was added)"],
  ]),
  spacer(),
  h3("What testing taught us"),
  bullet("**Phone in the wrong hand:** holding the phone in the other hand measures the arm that isn't moving. Instructions now say \"in your right hand\" for the right arm."),
  bullet("**Sinking during the countdown:** if the arm sinks before the recording starts, drift misses it. This led to the sag-vs-baseline rule."),
  bullet("**Two motion managers:** one baseline hold recorded 0 readings. The app now uses a single shared sensor manager and makes the user repeat any hold that didn't record."),

  h2("3.8 Comparison with published stroke data"),
  p("No public dataset of stroke patients doing this test with a phone was available to train on. The iPronator study (10 acute stroke patients with mild arm weakness vs 10 healthy controls, devices on the forearms) published the averages that separated the two groups:"),
  table([2600, 2250, 2250, 2260], ["", "Stroke patients", "Healthy controls", "Our steady holds"], [
    ["Average turn (pronation)", "28.9°", "3.8°", "1–4°"],
    ["Average drift", "26.8°", "−1.7°", "0–2°"],
  ]),
  spacer(),
  p("Our steady holds look like the healthy controls, and our cut-offs (20° drift, 30° turn) sit near the patients' averages."),

  h2("3.9 Limitations"),
  bullet("The phone measures tilt, not height. If the wrist bends to keep the phone level while the arm sinks, drift reads low. Holding the phone firmly, wrist straight, matters."),
  bullet("Sag depends on a good baseline: a baseline recorded with a low, lazy arm makes later sag harder to see."),
  bullet("Tested on one person with simulated drift. Real stroke weakness may look different."),
  bullet("The AI is trained on synthetic data and doesn't see the baseline."),

  h2("3.10 Next steps"),
  bullet("**Collect team data:** about 10 normal and 10 simulated-drift holds per arm per person, using data-collection mode."),
  bullet("**Retrain the AI on real recordings,** and give it the baseline hold as a second input so it can learn sag."),
  bullet("**Raise the AI weight only if it beats the rules** on people it hasn't seen (04_evaluate.py), in small steps."),
  bullet("**Seek real stroke data:** the NeuFun-TS authors (smartphone arm-hold data) and the StrokeRehab dataset."),

  // ── SPEECH ─────────────────────────────────────────────────────────
  h1("4. Speech Clarity Detection"),
  note("To be added."),

  // ── SHARED ─────────────────────────────────────────────────────────
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
  p("**Incomplete checks:** if a check couldn't be measured, its card says \"Could not be completed\" and the header never shows \"Looking Good\". It shows \"Check Incomplete\" with a reminder to call 911 for sudden symptoms. The app never fills in a missing measurement with a made-up score."),
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
      ...[1, 2, 3].map((n) => ({ reference: "steps" + n, levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
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
