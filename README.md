# FeelPath

A cane that tells you, through vibration, what is in front of you.

**Stage 1 (this repo):** a prototype that uses only an iPhone with a LiDAR scanner (iPhone 12 Pro and later; developed on an iPhone 17 Pro Max). You strap the phone to a cane, or hold it pointing ahead. The phone reads the LiDAR depth map and plays one of three vibration patterns.

![Haptic pattern sketch](docs/haptic-patterns.png)

| Situation | Pattern | Default trigger |
|---|---|---|
| **Obstacle ahead** | 2 medium pulses, repeated every second | something in your path within 2.0 m |
| **Very close** | fast short pulses, continuous | something within 0.8 m |
| **Stairs down** | 1 long pulse, repeated every 1.6 s | the floor ahead drops ≥ 14 cm |

Priority: very close > stairs down > obstacle ahead. You can change the distances in the app, and test each pattern on its own with the "Feel the patterns" buttons.

## How it works

```
ARKit LiDAR depth (256×192, ~15 Hz)
   │  every 4th pixel, medium+ confidence
   ▼
DepthSensor ── unprojects each pixel with the camera pose → points as
   │           (forward, lateral, height) relative to the phone, gravity-aligned
   ▼
SceneAnalyzer (FeelPathCore)
   │  • floor height = robust median of points 0.3–1.2 m ahead
   │  • obstacle    = 10th-percentile forward distance of points in a 70 cm-wide
   │                  corridor that stand ≥ 12 cm above the floor
   │  • floor drop  = ≥ 30 % of ground points 0.8–2.5 m ahead are ≥ 14 cm below the floor
   ▼
AlertDecider (FeelPathCore) ── hysteresis + 3-frame confirmation for stairs
   ▼
HapticRenderer ── Core Haptics, loops the pattern for the current alert
```

Because the points are projected into world space, the phone's tilt doesn't matter, which is what makes stairs detection possible. Inspired by [OpenCane](https://github.com/aritroBh/OpenCane/), which uses the same ARKit `sceneDepth` + Core Haptics approach.

## Repo layout

```
ios/
  project.yml            XcodeGen spec (the .xcodeproj is generated, not committed)
  Core/                  FeelPathCore: pure Swift logic + unit tests (no iOS frameworks)
  FeelPath/
    App/                 FeelPathApp, AppModel (glue)
    Depth/DepthSensor    ARKit session → points → SceneReading
    Haptics/             Core Haptics renderer
    UI/ContentView       status, start/stop, settings, pattern tester, debug
docs/
```

## Running it on your iPhone

### From Windows (no Mac needed)

GitHub Actions compiles the app on a cloud Mac. You sign and install it from Windows with a free Apple ID.

**One-time setup**
1. Install **[iLoader](https://github.com/nab138/iloader)**.
2. On the iPhone, the *Developer Mode* switch (Settings → Privacy & Security) shows up only after the first install. You'll turn it on during step 4 below.

**Each install**
1. Push to `main`, or start the workflow by hand (*Actions → CI → Run workflow*).
2. When the run turns green, open it and download the **FeelPath-unsigned-ipa** artifact. Unzip it to get `FeelPath-unsigned.ipa`.
3. Plug in the iPhone, open iLoader, sign in with your Apple ID, and install `FeelPath-unsigned.ipa` with it.
4. On the iPhone, open Settings → General → VPN & Device Management, then trust your Apple ID. Turn on Developer Mode if asked, and let the phone restart.
5. Open FeelPath and allow camera access.

With a free Apple ID the app expires after **7 days**. Re-run step 3 to refresh it. (A paid Apple Developer account, $99/yr, would allow TestFlight installs that last 90 days.)

### From a Mac (if you ever have one)

```bash
brew install xcodegen
cd ios && xcodegen && open FeelPath.xcodeproj
```

Choose your team under *Signing & Capabilities*, select the iPhone, and press ▶︎.

The simulator can build the app but has no LiDAR or Taptic Engine, so all real testing is on the device.

## Tests

The logic is in `ios/Core` and runs on macOS, Linux, or Docker:

```bash
cd ios/Core && swift test
```

On Windows with Docker Desktop running:

```bash
docker run --rm -v "$PWD/ios/Core:/src" -w /src swift:6.1 swift test
```

CI (GitHub Actions) runs these tests on Linux, builds the app for the simulator, and produces an unsigned `.ipa` for sideloading on every push.

## Field-testing checklist

- [ ] Wall at 3 m → 2 m → 0.5 m: the cue goes clear → obstacle → very close
- [ ] Narrow pole (lamp post), chair, table edge at hip height
- [ ] Top of a staircase, kerb, single step down
- [ ] Phone angles: pointing level, 30° down, 60° down
- [ ] Bright sun outdoors (LiDAR range drops), darkness indoors
- [ ] Glass doors and mirrors (LiDAR may see through them: a known limitation)

## Next steps

- Tune the thresholds from field tests (all of them are in `AnalyzerConfig` / `DeciderConfig`)
- Stairs **up** / overhanging obstacles at head height (separate cue)
- Left/right hints (which side is clear)
- Stage 2: dedicated hardware (ToF sensor + vibration motor in the cane grip)
