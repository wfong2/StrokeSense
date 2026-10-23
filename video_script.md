# StrokeSense - Congressional App Challenge Video Script

**Target length:** ~3:00 minutes
**Format:** Slides with voiceover + live demo footage spliced in
**Demo footage:** 326.MP4 (app walkthrough on iPhone)

---

## SLIDE 1 — Title / Team (0:00-0:12)

**[ON SCREEN]** Title slide with team names and roles

**NARRATION:**
"Hi, we're the team behind StrokeSense, our submission for the Congressional App Challenge 2026-2027. I'm [Name], joined by Ray, William, Matthew, and Regina. We built an iOS app that could save someone's life."

---

## SLIDE 2 — The Problem (0:12-0:40)

**[ON SCREEN]** Problem slide with statistics

**NARRATION:**
"Stroke affects people we love — our grandparents, our parents, family friends. Most of us know someone who's had one. Every year, up to 170,000 people die from stroke in the United States. And every minute without treatment, 1.9 million neurons die.

But here's what most people don't realize: strokes don't always hit all at once. Early symptoms — a slight droop in the face, one arm feeling weaker, words coming out a little off — these can show up hours or even days before a major stroke. And most people miss them, or brush them off as tiredness.

That's the gap StrokeSense fills. This isn't for when someone collapses and you call 911. It's for catching those early warning signs before it gets to that point."

---

## SLIDE 3 — What Is StrokeSense? (0:40-1:05)

**[ON SCREEN]** Solution slide, then TRANSITION to demo footage showing the app home screen

**NARRATION:**
"StrokeSense is an iPhone app that lets anyone check themselves for early stroke symptoms — no medical training needed. It uses your phone's camera and microphone to test the three things doctors look for: face symmetry, arm strength, and speech clarity.

After the check, the app doesn't just give you a score. It uses a large language model to write a plain-English summary of what it found — what looked normal, what didn't, and what you should do next. If your results are concerning, it shows nearby urgent care locations so you can get checked out right away. And if it's serious, it can escalate all the way to calling 911 automatically.

The idea is to meet you where you are — maybe it's nothing and you get peace of mind, maybe you should go to urgent care, or maybe you need emergency help right now."

---

## SLIDE 4 — How It Works (1:05-1:45)

**[ON SCREEN]** Steps slide, then CUT TO demo footage for each step

**NARRATION:**
"Here's how it works. There are two phases: setting your baseline, and running a check.

**[CUT TO DEMO — baseline setup screen]**
First, the baseline. When you open the app for the first time, it captures your normal state — your face, each arm's strength, and how your speech sounds on a regular day. This takes about a minute, and you only do it once. The app needs to know what 'normal' looks like for you, so it can spot the difference later.

**[CUT TO DEMO — home screen, 'Check Me' button]**
Then whenever something feels off — maybe your face feels a little numb, or your arm feels heavy — you open the app and tap 'Check Me.'

**[CUT TO DEMO — face test, arm test, speech test]**
It walks you through three quick tests. Look at the camera so it can check your face. Hold up each arm one at a time so it can measure drift. And repeat a sentence so it can analyze your speech. The whole check takes under a minute.

**[CUT TO DEMO — results screen]**
Then it compares everything against your baseline, and shows you the results — the severity level, the LLM summary, and next steps."

---

## SLIDE 5 — Severity Assessment (1:45-2:10)

**[ON SCREEN]** Severity tiers slide, then CUT TO demo footage of results screen

**NARRATION:**
"The app gives you one of four results.

'Looking Good' — your check looks normal compared to your baseline. Nothing to worry about. You get peace of mind and move on with your day.

'Be Aware' — something small showed up. Maybe slight asymmetry, or one arm was a little weaker. The LLM summary explains what it noticed, and you can keep an eye on it.

'Getting Serious' — multiple signs were detected. The app recommends you see someone, and shows nearby urgent care locations so you don't have to search for one yourself.

'Seek Help Now' — strong indicators across multiple tests. At this point, the app starts a 911 countdown automatically, because the person may not be able to make that call on their own."

---

## SLIDE 6 — Technical Architecture (2:10-2:25)

**[ON SCREEN]** Tech stack slide

**NARRATION:**
"Under the hood, StrokeSense is built entirely in Swift. For the face test, we use Apple's Vision framework — it detects facial landmarks and measures asymmetry in real time. For the arm test, we use AVFoundation to track arm position through the camera and detect drift. And for the speech test, the Speech framework transcribes what you say so we can compare it against your baseline.

One thing we're proud of: everything runs on-device. No cloud. No internet connection needed. Your health data never leaves your phone. The only network calls are to the LLM for generating the summary and to Apple Maps for nearby urgent care — the actual detection is 100% local."

---

## SLIDE 7 (NEW) — Our Development Process (2:25-2:50)

**[ON SCREEN]** Photos of whiteboard wireframes, TestFlight screenshot, team working

**NARRATION:**
"We want to walk you through how we actually built this.

It started with brainstorming. We knew we wanted to build something that helps people, and stroke detection kept coming up — almost everyone on the team knew someone affected by it. We grabbed a whiteboard and started sketching. What screens does the user need? What's the simplest flow? How do we make it usable in a stressful moment?

From those wireframes, we moved into development. We used Claude Code as our AI coding assistant to build the iOS app in Swift — it helped us move fast while learning the Apple frameworks we needed, like Vision and AVFoundation.

We tested constantly. First in the Xcode simulator, then on our actual phones. There's a big difference between a demo on a simulator and someone holding a shaking phone trying to capture their face — we had to design for the real thing.

Once a feature was working, we published it through TestFlight so the whole team could try it. We collected feedback — what was confusing, what was slow, what didn't feel right — then went back to the whiteboard and the code, and iterated. We went through that loop multiple times until we were happy with the result."

---

## SLIDE 8 — Design & Impact (2:50-3:10)

**[ON SCREEN]** Design highlights + user scenarios

**NARRATION:**
"A lot of our design decisions came from one question: what if the person using this app is already having symptoms?

Their hand might be shaking, so the face capture is tolerant of movement. They might only have one good arm, so we test each arm separately. They might be confused or scared, so every screen has one clear action and large text. We didn't design for a healthy person in a demo. We designed for the real moment.

So who is this for? The grandparent who lives alone and feels something off but doesn't want to 'bother anyone' with a 911 call. The college student who gets a sudden headache and numbness but thinks they're just tired. Anyone who wouldn't recognize a stroke happening to them — which is most of us. StrokeSense gives them a way to check, a clear answer, and a path to help."

---

## SLIDE 9 — Future Development (3:10-3:25)

**[ON SCREEN]** Future roadmap slide

**NARRATION:**
"We're not done. The biggest thing on our roadmap is an Apple Watch companion — imagine passive monitoring that can tap your wrist and say 'something doesn't look right, run a check.' We also want to add emergency contact notifications, so if the app detects something serious, it can alert your family, not just 911. And we're exploring training a custom machine learning model on real clinical stroke data to make the detection even more accurate.

Long term — multi-language support and an Android version, so this isn't limited to English speakers with iPhones."

---

## SLIDE 10 — Closing (3:25-3:35)

**[ON SCREEN]** Closing slide + final shot of app on phone

**NARRATION:**
"We built StrokeSense because we believe catching a stroke early shouldn't require a medical degree. Just a phone and sixty seconds. StrokeSense — bringing stroke prevention to your pocket. Thank you."

---

## Production Notes

### Video Assembly Order
1. Record voiceover for each slide section (can be one continuous take or per-slide)
2. Screen-record or use 326.MP4 demo footage for slides 4-5
3. Layer slides as background with demo footage cut in during walkthrough sections
4. Add simple transitions (dissolve or cut) between slides and demo footage
5. If you have whiteboard photos or TestFlight screenshots, use them on slide 7

### Tips
- Keep energy conversational, not salesy — you're explaining something you built and care about
- When showing demo footage, let the app do the talking for 2-3 seconds before narrating over it
- The 911 countdown moment is the strongest visual — make sure it's in the video
- Slide 7 (dev process) is a good place for behind-the-scenes photos if you have them
- Total runtime is ~3:35 as written — trim pauses between slides to hit 3 minutes

### Demo Footage Mapping (from 326.MP4)
Review the video and identify timestamps for:
- [ ] App launch / home screen
- [ ] Baseline setup flow (face capture, arm test, speech recording)
- [ ] "Check Me" button press
- [ ] Face test in progress
- [ ] Arm test in progress
- [ ] Speech test in progress
- [ ] Results screen with severity level and LLM summary
- [ ] Nearby urgent care locations
- [ ] 911 countdown (if captured)
