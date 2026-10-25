# FeelPath

**A haptic obstacle-detection aid for the white cane.**

FeelPath gives people with visual impairments early warning of obstacles and drop-offs through vibration patterns on the cane. The long-term goal is a self-contained cane module. This repository contains **Stage 1**: a functional prototype that uses an iPhone's LiDAR scanner and Taptic Engine to check the detection approach and the haptic vocabulary before any dedicated hardware is built.

[![CI](https://github.com/baaaaadr/FeelPath/actions/workflows/ci.yml/badge.svg)](https://github.com/baaaaadr/FeelPath/actions/workflows/ci.yml)

---

## 1. Motivation

A conventional white cane detects only what it touches: obstacles at ground level within about one metre. It gives no warning of objects at waist or chest height, such as table edges, open cabinet doors or vehicle mirrors. It also reports drop-offs (stairs, kerbs, platform edges) only when the tip is already over the edge. FeelPath adds a forward-looking depth sensor and turns what it sees into a small set of distinct vibration patterns, so the user's hearing stays free for the environment.

## 2. Stage 1 objectives

1. Show that a consumer LiDAR sensor can reliably detect (a) obstacles in the walking path and (b) downward steps, in real time.
2. Define and assess a minimal haptic vocabulary that users can tell apart without looking or listening.
3. Produce a tunable test bench (adjustable thresholds, live diagnostics) to support structured field testing.
4. Isolate the detection logic from the iOS platform so that it can be reused, unchanged, on Stage 2 hardware.

**Status:** the software is implemented, unit-tested and builds in CI. The app installs on an iPhone 17 Pro Max. Structured field testing (Section 8) has not yet been carried out.

## 3. Haptic vocabulary

The patterns differ in rhythm and duration rather than intensity alone, so that each one can be identified on its own.

![Haptic pattern design sketch](docs/haptic-patterns.png)

| Cue | Pattern | Default trigger |
|---|---|---|
| **Obstacle ahead** | Two medium pulses (120 ms, 250 ms apart), repeated every 1.0 s | Obstacle in the walking corridor within 2.0 m |
| **Very close** | Six short, sharp pulses (50 ms, 100 ms apart), repeated continuously | Obstacle within 0.8 m |
| **Stairs down** | One long, soft pulse (700 ms), repeated every 1.6 s | Floor ahead drops by 14 cm or more |

When several conditions apply, the most urgent cue wins: *very close* > *stairs down* > *obstacle ahead*. Only one cue plays at a time, and a change of cue interrupts the current pattern immediately.

## 4. System architecture

```
 ┌──────────────────────────────────────────────────────────────┐
 │ iOS app (Swift, SwiftUI)                                     │
 │                                                              │
 │  DepthSensor ── ARKit, LiDAR smoothed scene depth, ~15 Hz    │
 │      │  depth pixels → 3-D points (gravity-aligned)          │
 │      ▼                                                       │
 │  ┌────────────────────────────────────────────────────────┐  │
 │  │ FeelPathCore (platform-independent Swift package)      │  │
 │  │   SceneAnalyzer → floor height, obstacle distance,     │  │
 │  │                   floor-drop flag                      │  │
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

The floor height is the median of the lower half of point heights found **0.3–1.2 m ahead**. Using the lower half stops nearby objects from biasing the estimate upward. At least 15 points are required. Otherwise the floor is marked *unknown*: obstacle detection falls back to an assumed device height of 1 m, and stairs detection is turned off for that frame.

### 5.3 Obstacle detection

An obstacle point is any corridor point between **12 cm and 2 m above the floor**. If at least 12 such points exist, the reported distance is their **10th-percentile forward distance**. This is a conservative estimate of the nearest surface that is robust to isolated noise.

### 5.4 Drop-off (stairs down) detection

In the zone **0.8–2.5 m ahead**, the app takes the points at ground level or below and counts how many lie **more than 14 cm below the floor**. The 14 cm threshold is just below a standard stair riser of 15–18 cm. A frame reports a drop when at least 20 points are lowered **and** they make up at least 30 % of the ground points in that zone.

### 5.5 Temporal filtering

- **Hysteresis:** an active distance cue stays on until the obstacle is 15 cm beyond its threshold. This prevents the cue from flickering at the boundary.
- **Debouncing:** *stairs down* starts only after 3 consecutive drop frames (about 0.2 s) and stops after 5 consecutive frames without a drop.

All parameters are in `AnalyzerConfig` and `DeciderConfig` ([SceneAnalyzer.swift](ios/Core/Sources/FeelPathCore/SceneAnalyzer.swift), [AlertDecider.swift](ios/Core/Sources/FeelPathCore/AlertDecider.swift)).

## 6. Prototype application

The app is a single screen designed for testing rather than end use:

- **Status panel:** the current cue (colour-coded), the distance to the nearest obstacle, and a start/stop control.
- **Settings:** adjustable *obstacle* and *very close* distances, a switch to turn stairs detection on or off, haptic mute, and VoiceOver announcements of cue changes.
- **Pattern preview:** plays each haptic pattern on demand, for user familiarisation.
- **Diagnostics:** tracking state, processing rate, corridor point count, estimated floor height and the drop flag.

While sensing is running, the screen does not lock. Sensing stops when the app goes into the background, so the user is never left relying on a cue that has silently stopped.

## 7. Verification

| Level | Scope | Status |
|---|---|---|
| Unit tests | Floor estimation, obstacle detection inside and outside the corridor, step-down versus shallow-dip discrimination, hysteresis, stairs debouncing, cue priority, pattern timing | Passing (13 tests) |
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
| Blind identification of the three patterns | Whether the haptic vocabulary can be told apart |

Measures: detection rate, false-alarm rate, warning distance, and cue identification accuracy.

## 9. Known limitations

- **Device pitch:** stairs detection requires the floor 0.3–1.2 m ahead to be in view, which means a downward pitch of roughly 30°. Held level, the drop cue is disabled.
- **No direction information:** the system reports *that* something is ahead, not on which side.
- **Unseen drop-offs:** a drop with no returning LiDAR signal (very dark, specular, or out of range) is not reported as a drop.
- **Sensor physics:** transparent and reflective surfaces, and strong sunlight, reduce LiDAR reliability.
- **Not detected yet:** obstacles above 2 m, and stairs going up.
- **Foreground only:** sensing requires the app to stay open in the foreground.

## 10. Roadmap

1. **Stage 1 completion:** run the field evaluation, tune the thresholds, and refine the patterns based on user feedback.
2. **Stage 1 extensions:** a left/right clearance cue, an upward-stairs cue, and detection of obstacles at head height.
3. **Stage 2:** a dedicated cane module (time-of-flight depth sensor, microcontroller, vibration motor in the grip) running a port of FeelPathCore.

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
