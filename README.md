# FeelPath

**A haptic obstacle-detection aid for the white cane.**

FeelPath gives people with visual impairments early warning of obstacles and drop-offs through vibration patterns on the cane. The long-term goal is a self-contained cane module. This repository contains **Stage 1**: a functional prototype that uses an iPhone's LiDAR scanner and Taptic Engine to check the detection approach and the haptic vocabulary before any dedicated hardware is built.

[![CI](https://github.com/baaaaadr/FeelPath/actions/workflows/ci.yml/badge.svg)](https://github.com/baaaaadr/FeelPath/actions/workflows/ci.yml)

---

## 1. Motivation

A conventional white cane detects only what it touches: obstacles at ground level within about one metre. It gives no warning of objects at chest or head height with free space beneath them, such as open cabinet doors, low branches, signs or vehicle mirrors. It also reports drop-offs (stairs, kerbs, platform edges) only when the tip is already over the edge. FeelPath adds a forward-looking depth sensor and turns what it sees into a small set of distinct vibration patterns, so the user's hearing stays free for the environment.

## 2. Stage 1 objectives

1. Show that a consumer LiDAR sensor can reliably detect (a) obstacles in the walking path and (b) downward steps, in real time.
2. Define and assess a minimal haptic vocabulary that users can tell apart without looking or listening.
3. Produce a tunable test bench (adjustable thresholds, live diagnostics) to support structured field testing.
4. Isolate the detection logic from the iOS platform so that it can be reused, unchanged, on Stage 2 hardware.

**Status:** the software is implemented, unit-tested and builds in CI. The app installs on an iPhone 17 Pro Max. Structured field testing (Section 8) has not yet been carried out.

## 3. Haptic vocabulary

The patterns differ in rhythm and duration rather than intensity alone, so that each one can be identified on its own.

![Haptic pattern design sketch](docs/haptic-patterns.png)

*The design sketch covers the first three cues; the head-height cue was added afterwards.*

| Cue | Pattern | Default trigger |
|---|---|---|
| **Obstacle ahead** | Two medium pulses (120 ms, 250 ms apart), repeated every 1.0 s | Obstacle in the walking corridor within 2.0 m |
| **Very close** | Six short, sharp pulses (50 ms, 100 ms apart), repeated continuously | Obstacle within 0.8 m |
| **Stairs down** | One long, soft pulse (700 ms), repeated every 1.6 s | Floor ahead drops by 14 cm or more |
| **Head height** | Three hard, crisp knocks (40 ms, 120 ms apart), repeated every 0.9 s | Overhanging obstacle within 2.0 m (Section 5.5) |

When several conditions apply, the most urgent cue wins: *very close* > *head height* > *stairs down* > *obstacle ahead*. *Head height* ranks above the other warnings because the cane gives no tactile backup for an overhang. *Very close* ranks above it because stopping is the safe response to any imminent contact. Only one cue plays at a time, and a change of cue interrupts the current pattern immediately.

## 4. System architecture

```
 ┌──────────────────────────────────────────────────────────────┐
 │ iOS app (Swift, SwiftUI)                                     │
 │                                                              │
 │  DepthSensor ── ARKit, LiDAR smoothed scene depth, ~15 Hz    │
 │      │  depth pixels → 3-D points (gravity-aligned)          │
 │      │  + tracked floor plane (floor memory)                 │
 │      ▼                                                       │
 │  ┌────────────────────────────────────────────────────────┐  │
 │  │ FeelPathCore (platform-independent Swift package)      │  │
 │  │   SceneAnalyzer → floor height, obstacle distance,     │  │
 │  │                   overhang distance, floor-drop flag   │  │
 │  │   AlertDecider  → current cue (hysteresis, debounce)   │  │
 │  │   HapticPattern → pulse timings for each cue           │  │
 │  └────────────────────────────────────────────────────────┘  │
 │      ▼                                                       │
 │  HapticRenderer ── Core Haptics (Taptic Engine)              │
 │  ContentView    ── status, controls, diagnostics             │
 └──────────────────────────────────────────────────────────────┘
```

All detection and decision logic is in **FeelPathCore**, which has no dependency on Apple frameworks. It is unit-tested on Linux, and the intent is to port it directly to the Stage 2 embedded platform.

## 5. Detection method

### 5.1 Point-cloud construction

Each frame, the LiDAR depth map (256 × 192) is sampled every fourth pixel. Only pixels with medium or high confidence are kept. Each pixel is back-projected into 3-D using the camera intrinsics and the device pose from ARKit, and is then expressed in a **gravity-aligned walking frame** centred on the phone:

- *forward*: horizontal distance in the direction the phone faces
- *lateral*: horizontal offset to the left or right
- *height*: vertical offset from the phone

Because this frame does not depend on the phone's tilt, the analysis stays valid while the cane swings and pitches. This is what makes reliable drop detection possible.

Only points inside a **70 cm-wide corridor**, at most **4 m** ahead, are analysed.

### 5.2 Floor estimation

The floor height is resolved from three sources, in order of preference:

1. **Measured:** the median of the lower half of point heights found **0.3–1.2 m ahead** (at least 15 points). Using the lower half stops nearby objects from biasing the estimate upward.
2. **Remembered:** when the near floor is out of view, for example because the phone is pitched up, the height of the floor plane that ARKit detected earlier and is still tracking. Of the planes classified as *floor* that lie 0.3–2.5 m below the phone, the highest one is used, so a lower floor seen down a staircase is ignored.
3. **Assumed:** otherwise, a device height of 1 m. With an assumed floor, obstacle detection continues, but stairs and overhang detection are turned off for that frame.

### 5.3 Obstacle detection

An obstacle point is any corridor point between **12 cm above the floor and the user's height plus 10 cm**. The user's height is a setting in the app (default 1.75 m), so objects the user can walk under are not reported. If at least 12 such points exist, the reported distance is their **10th-percentile forward distance**. This is a conservative estimate of the nearest surface that is robust to isolated noise.

### 5.4 Drop-off (stairs down) detection

In the zone **0.8–2.5 m ahead**, the app takes the points at ground level or below and counts how many lie **more than 14 cm below the floor**. The 14 cm threshold is just below a standard stair riser of 15–18 cm. A frame reports a drop when at least 20 points are lowered **and** they make up at least 30 % of the ground points in that zone.

### 5.5 Overhang (head height) detection

An overhang is an obstacle at chest or head height with free space beneath it, which a cane sweeping the ground will not touch. The corridor is divided into 10 cm slices by forward distance. A slice contains an overhang when:

- at least 8 points lie **1.0 m or more above the floor** (up to the user's height plus 10 cm), **and**
- at most 3 points lie in the **gap band (12–60 cm above the floor)** in that slice and the two next to it, **and**
- at least 10 floor points are visible from 20 cm before the slice to 1 m beyond it.

The third condition is the important one. An empty gap only means *free space* if the sensor can actually see the floor through it. Otherwise it may simply be out of view. A wall fails the second condition, and a table top (about 75 cm high) lies between the two bands, so it remains an ordinary obstacle. The reported distance is that of the nearest such slice.

### 5.6 Temporal filtering

- **Hysteresis:** an active distance cue stays on until the obstacle is 15 cm beyond its threshold. This prevents the cue from flickering at the boundary.
- **Debouncing:** *stairs down* starts only after 3 consecutive drop frames (about 0.2 s) and stops after 5 consecutive frames without a drop. *Head height* starts after 2 consecutive overhang frames.

All parameters are in `AnalyzerConfig` and `DeciderConfig` ([SceneAnalyzer.swift](ios/Core/Sources/FeelPathCore/SceneAnalyzer.swift), [AlertDecider.swift](ios/Core/Sources/FeelPathCore/AlertDecider.swift)).

## 6. Prototype application

The app is a single screen designed for testing rather than end use:

- **Status panel:** the current cue (colour-coded), the distance to the nearest obstacle, and a start/stop control.
- **Settings:** adjustable *obstacle* and *very close* distances, the user's height (saved between launches), switches to turn stairs and head-height detection on or off, haptic mute, and VoiceOver announcements of cue changes.
- **Pattern preview:** plays each haptic pattern on demand, for user familiarisation.
- **Diagnostics:** tracking state, processing rate, corridor point count, floor height and its source (measured, remembered or assumed), overhang distance and the drop flag.

While sensing is running, the screen does not lock. Sensing stops when the app goes into the background, so the user is never left relying on a cue that has silently stopped.

## 7. Verification

| Level | Scope | Status |
|---|---|---|
| Unit tests | Floor estimation and floor memory, obstacle detection inside and outside the corridor, user-height limit, step-down versus shallow-dip discrimination, overhang versus wall versus table classification, hysteresis, debouncing, cue priority, pattern timing | Passing (24 tests) |
| Continuous integration | Unit tests on Linux; iOS simulator build; unsigned device build packaged as an `.ipa` | Passing on every push |
| On-device | Installation and launch on iPhone 17 Pro Max | Done |
| Field evaluation | See Section 8 | Not started |

## 8. Evaluation plan

| Scenario | Purpose |
|---|---|
| Approach a wall from 3 m to 0.5 m | Check cue transitions and distance accuracy |
| Narrow pole, chair, table edge at hip height | Detection of thin and elevated obstacles |
| Staircase top edge, kerb, single step down | Drop detection rate and warning distance |
| Device pitch: level, 30° down, 60° down | Sensitivity to how the cane is held |
| Bright sunlight; low light indoors | Limits of the LiDAR sensor |
| Glass doors, mirrors | Known failure mode of the sensor |
| Open cabinet door, low branch, sign at head height | Overhang detection rate; false alarms on walls and tables |
| Pitch up, then walk on with the floor out of view | Floor memory keeps heights correct (diagnostics show *remembered*) |
| Blind identification of the three patterns | Whether the haptic vocabulary can be told apart |

Measures: detection rate, false-alarm rate, warning distance, and cue identification accuracy.

## 9. Known limitations

- **Conflicting pitch requirements:** stairs detection needs the floor 0.3–1.2 m ahead in view (a downward pitch of roughly 30°), whereas head-height obstacles are only in view when the phone is held close to level. Floor memory keeps heights correct when the phone pitches up, but one sensor cannot see both regions at once. The best compromise pitch is to be determined in field tests.
- **No direction information:** the system reports *that* something is ahead, not on which side.
- **Unseen drop-offs:** a drop with no returning LiDAR signal (very dark, specular, or out of range) is not reported as a drop.
- **Sensor physics:** transparent and reflective surfaces, and strong sunlight, reduce LiDAR reliability.
- **Not detected yet:** stairs going up.
- **Foreground only:** sensing requires the app to stay open in the foreground.

## 10. Roadmap

1. **Stage 1 completion:** run the field evaluation, tune the thresholds, and refine the patterns based on user feedback.
2. **Stage 1 extensions:** a left/right clearance cue and an upward-stairs cue.
3. **Stage 2:** a dedicated cane module (time-of-flight depth sensors, microcontroller, vibration motor in the grip) running a port of FeelPathCore. It would use a second, upward-angled sensor dedicated to head height, which removes the pitch conflict described in Section 9.

## 11. Building and installing

The iOS app is compiled by GitHub Actions on a macOS runner, so no local Mac is needed.

**Installing on an iPhone (from Windows, free Apple ID):**
1. Open the latest successful run under **Actions → CI** and download the `FeelPath-unsigned-ipa` artifact.
2. Install the `.ipa` with [iLoader](https://github.com/nab138/iloader), signing in with an Apple ID.
3. On the iPhone, trust the developer profile (Settings → General → VPN & Device Management) and turn on Developer Mode when prompted.

Apps signed with a free Apple ID expire after 7 days and must be reinstalled. Distribution through TestFlight would require a paid Apple Developer account.

**Building locally on macOS (optional):**

```bash
brew install xcodegen
cd ios && xcodegen && open FeelPath.xcodeproj
```

**Running the logic tests** (macOS, Linux, or Docker):

```bash
cd ios/Core && swift test
```

A LiDAR-equipped iPhone (Pro models from iPhone 12 Pro onward) is required to run the app. The simulator has neither a LiDAR sensor nor a Taptic Engine.

## 12. Repository structure

```
ios/
  project.yml                 XcodeGen project specification
  Core/                       FeelPathCore: detection and decision logic, unit tests
  FeelPath/
    App/                      Application entry point and state model
    Depth/                    ARKit depth capture and point-cloud construction
    Haptics/                  Core Haptics rendering
    UI/                       User interface
docs/                         Design material
.github/workflows/ci.yml      Continuous integration
```

## Acknowledgements

The sensing approach (ARKit scene depth combined with Core Haptics) was informed by the open-source [OpenCane](https://github.com/aritroBh/OpenCane/) project.
