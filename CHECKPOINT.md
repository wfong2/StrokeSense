---
status: in-progress
branch: main
timestamp: 2026-09-27T17:44:25-07:00
session_duration_s: 7701
files_modified:
  - StrokeSense/Models/BaselineData.swift
  - StrokeSense/Services/BaselineManager.swift
  - StrokeSense/Views/HomeView.swift
  - StrokeSense/Views/Baseline/BaselineWelcomeView.swift
  - StrokeSense/Views/Baseline/BaselineFaceView.swift
  - StrokeSense/Views/Baseline/BaselineArmsView.swift
  - StrokeSense/Views/Baseline/BaselineSpeechView.swift
  - StrokeSense/Views/Baseline/BaselineCompleteView.swift
  - StrokeSense/ContentView.swift
---

## Working on: Baseline Onboarding Flow

### Summary

Implemented the first-launch personal baseline onboarding experience for StrokeSense. The app now captures face, arm, and speech baselines (stubbed with placeholders) before allowing access to the main home screen. Baseline data persists as a local JSON file so subsequent launches skip straight to the home screen.

### Decisions Made

- Used `@Observable` (Swift Observation framework) for `BaselineManager` instead of `ObservableObject` — cleaner syntax, modern SwiftUI pattern
- Baseline data stored as `baseline.json` in the app's documents directory using `Codable` with ISO-8601 date encoding
- Each baseline step (face, arms, speech) uses a "Record" button that flips local state, then reveals a "Next" navigation link — keeps the flow linear
- `ContentView` acts as the root router, switching between onboarding `NavigationStack` and `HomeView` based on `baselineManager.hasBaseline`
- `BaselineCompleteView` saves dummy placeholder metrics — real camera/vision/speech integration deferred to future work
- Back button hidden on the completion screen to prevent navigating back after baseline is saved

### Remaining Work

1. Integrate real face capture using Vision framework (ARKit/AVFoundation) in `BaselineFaceView`
2. Integrate real arm motion detection using CoreMotion or pose estimation in `BaselineArmsView`
3. Integrate real speech analysis using Speech framework in `BaselineSpeechView`
4. Build the stroke-check flow triggered by the "Check Me" button on `HomeView`
5. Add comparison logic between baseline and current measurements
6. Add ability to re-record baseline (settings screen with delete + re-onboard)
7. Add error handling for baseline save/load failures

### Notes

- Build verified: `xcodebuild` succeeds targeting iPhone 17 Pro Simulator (iOS 26.5)
- All new files use SwiftUI and target iOS 17+
- The `BaselineManager` uses a static URL computation in `init()` since stored properties aren't available before `self` is fully initialized
- No unit tests yet — data model is simple enough that integration tests during real capture implementation will be more valuable
