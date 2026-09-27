# StrokeSense - Project Context

## One-Sentence Pitch

If you suddenly do not feel right, StrokeSense uses a guided face, arm, and speech check to help identify possible stroke warning signs and move you quickly toward emergency help.

## What Is StrokeSense?

StrokeSense is an iPhone app being built for the **Congressional App Challenge (CAC) 2026** (deadline: October 26, 2026). It guides a user through a short stroke-warning check using the phone's camera and microphone, looking for possible warning signs based on the B.E. F.A.S.T. protocol: facial asymmetry, arm drift, and speech difficulty. If concerning signs are detected, it clearly tells the user to call 911.

**StrokeSense does not diagnose stroke.** It is a warning-and-escalation tool.

## The Problem

Stroke is time-sensitive. A person experiencing a possible stroke may be scared, confused, alone, or unsure whether what they are feeling is serious. The app reduces friction: open it, follow a few simple steps, see an urgent warning if concerning changes are found, and reach emergency help quickly.

## User Flow

1. **Start** - Large button: "I do not feel right - Check Me"
2. **Face Check** - Front camera asks user to look forward and smile; measures left/right facial landmark differences
3. **Arm Check** - User holds both arms out for ~10 seconds; tracks whether one arm drifts downward
4. **Speech Check** - User repeats a short sentence; confirms phrase completion, optionally compares timing/clarity
5. **Quick Symptom Questions** - Large yes/no buttons for sudden vision change, severe headache, numbness/weakness, confusion, balance trouble
6. **Result** - If any concerning sign is present: "Possible stroke warning signs detected. Call 911 now."
7. **Emergency Action** - Large CALL 911 button + approximate symptom start time for emergency personnel

## MVP Scope

| Module | Description |
|--------|-------------|
| Face | Live camera + Vision face landmarks. User smiles. Calculate symmetry metrics from lips, mouth corners, face centerline, head pose. |
| Arm | Live camera + Vision body pose. Track wrists, elbows, shoulders over ~10 seconds. Detect meaningful one-sided downward drift. |
| Speech | Prompt a fixed sentence, use speech recognition to confirm user attempted the phrase. Advanced speech classification is a stretch goal. |
| Symptom Questions | Large yes/no questions for balance, vision, weakness/numbness, confusion, severe headache. |
| Decision Logic | Conservative "possible warning signs" result. No diagnosis or probability output. |
| Emergency Screen | One-tap call 911; display symptom start time and summary of concerning checks. |

## Technical Architecture

| Layer | Technology | Purpose |
|-------|-----------|---------|
| UI | SwiftUI | Simple screens, large buttons, progress indicator, emergency result |
| Camera | AVFoundation | Capture front-camera frames for face and upper-body checks |
| Face Vision | Apple Vision | Face landmarks: lips, eyes, nose, contour, face pose |
| Body Vision | Apple Vision | Shoulder, elbow, wrist positions for arm-drift measurement |
| Speech | Speech / AVFoundation | Capture prompted sentence, basic recognition/audio processing |
| Logic | Swift service layer | Combine measurements, confidence checks, symptom answers, safety rules |
| Storage | Local device | Store baseline and recent test results locally; no cloud health data for MVP |

## Core Algorithms

### A. Face Asymmetry
- Detect face landmarks from each camera frame
- Reject frames with poor angle, low confidence, blur, or face turned too far
- Use face centerline/nose as reference, compare left vs. right lip/mouth positions
- Average several frames instead of deciding from one picture
- If personal baseline exists, compare current measurements with that person's normal smile

### B. Arm Drift
- Track both shoulders, elbows, wrists repeatedly during a 10-second hold
- Normalize coordinates by shoulder width/body size (camera distance independence)
- Measure each wrist's vertical change over time relative to corresponding shoulder
- Flag concern only when one side shows sustained downward drift with good pose confidence

### C. Decision Logic
- Each module provides evidence, not a diagnosis
- Quality gates: if camera can't see both arms, say "Test could not be completed" rather than guessing
- If user reports a major stroke warning sign, don't reassure them just because camera test looks normal
- MVP rule: if FaceCheck is concerning OR ArmCheck is concerning OR user reports a major sudden warning sign, show emergency result

## Differentiating Feature: Personal Baseline

Users can optionally record a normal baseline on a healthy day:
- Normal smile geometry vs. current smile geometry
- Normal arm hold vs. current arm hold
- Normal phrase sample vs. current phrase sample

This lets the app compare a person with their own normal pattern rather than just running a generic checklist.

## Safety and Medical Boundaries

- Never say "You are having a stroke"
- Never say "You are safe" or "No stroke detected" after a negative test
- Use: "This app cannot diagnose stroke. If you have sudden stroke symptoms, call 911."
- Don't delay emergency screen if user reports obvious major warning sign
- Don't silently place emergency calls based on algorithm alone
- If image quality is poor, body not fully visible, speech recognition fails, or confidence is low: say the check cannot be completed and remind user that sudden symptoms require emergency care

## UX Principles

- **Large controls** - user may have weakness, impaired vision, confusion, poor coordination
- **One instruction per screen** - e.g., "Look at the camera and smile"
- **Audio + text** - read instructions aloud while showing on screen
- **Progress indicator** - Face -> Arms -> Speech -> Result
- **Fast escape to help** - "Call 911" always accessible
- **No scary percentages** - avoid "72% chance of stroke"
- **Accessibility** - high contrast, large font, simple language, minimal typing

## 5-Week Build Plan

| Week | Deliverable |
|------|-------------|
| 1 | SwiftUI flow, camera permissions, camera preview, emergency screen, symptom-start timer |
| 2 | Face landmark overlay and basic asymmetry measurement; quality checks for face angle/visibility |
| 3 | Arm-pose overlay and 10-second arm-drift measurement; test with intentional lowered-arm movements |
| 4 | Speech prompt/recognition, symptom questions, decision logic, local result summary, baseline recording if time allows |
| 5 | Testing, bug fixing, accessibility polish, screenshots, README/technical explanation, CAC demo video |

## Priority List

| Priority | Feature |
|----------|---------|
| MUST | Face landmark check |
| MUST | Arm drift check |
| MUST | Emergency result / Call 911 path |
| MUST | Simple symptom questions |
| SHOULD | Speech prompt / recognition |
| SHOULD | Personal baseline |
| COULD | Voice-quality ML classifier |
| DO NOT | Screen-pressure grip test |
| DO NOT | Automatic medical diagnosis |

## Key References

- [CDC - Signs and Symptoms of Stroke](https://www.cdc.gov/stroke/signs-symptoms/index.html)
- [Apple Vision - Detecting Human Body Poses](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images)
- [Apple Vision - Face Landmarks / DetectFaceLandmarksRequest](https://developer.apple.com/documentation/vision/detectfacelandmarksrequest)
- [Congressional App Challenge - 2026 Rules (PDF)](https://www.congressionalappchallenge.us/wp-content/uploads/2026/05/2026-CAC-Rules.pdf)
- [Congressional App Challenge - Student Rules](https://www.congressionalappchallenge.us/students/rules/)
