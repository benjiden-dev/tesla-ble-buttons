# Tesla Buttons

A self-signed iOS app that controls your Tesla **entirely over Bluetooth LE** — no internet, no Tesla account login, no cloud API, no subscription. Built on [`shoujiaxin/swift-tesla-ble`](https://github.com/shoujiaxin/swift-tesla-ble) (a pure-Swift implementation of Tesla's official signed [vehicle-command protocol](https://github.com/teslamotors/vehicle-command)).

**What you get:**

- 🎛️ **In-app button grid** — frunk, trunk, lock/unlock, climate, windows, charge port, honk, flash, wake
- 🗣️ **Siri & Action button** — "Open the frunk with Tesla Buttons"; bind any command to the iPhone Action button
- 🎚️ **Control Center / Lock Screen controls** (iOS 18+) — Frunk, Trunk, Climate, Lock buttons that work even when the app isn't running
- 🌡️ **Climate presets** — set-and-start at your preferred temperature

> ⚠️ **Scaffold status:** authored off-device against the library's documented API (v-main, April 2026). Expect the possibility of minor compile fixes on first build — the architecture and API usage follow the library's own example app. Validate every command against your actual car before relying on it.

---

## Prerequisites

- A Mac with **Xcode 16.4+ / Xcode 26** (the library requires a Swift 6.2 toolchain)
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)**: `brew install xcodegen`
- A **paid Apple Developer account** (personal signing = 1-year profiles; free accounts work but expire every 7 days)
- iPhone on **iOS 18+** (controls require 18; the library requires 17)
- Your Tesla **VIN** (Controls → Software in the car) and an **NFC key card**
- A vehicle on the signed command protocol (all Model 3/Y, 2021+ S/X, Cybertruck)

## Build & install

```bash
git clone <this repo>
cd tesla-ble-buttons
xcodegen generate
open TeslaButtons.xcodeproj
```

In Xcode:

1. Select the **TeslaButtons** target → *Signing & Capabilities* → pick your **Team** (repeat for **TeslaButtonsControls**). Or set `DEVELOPMENT_TEAM` once in `project.yml` and re-run `xcodegen`.
2. If the bundle id collides, change `bundleIdPrefix` in `project.yml` (currently `dev.benjiden`) — also update `AppConstants.bundleRoot` to match.
3. Plug in your iPhone, select it as the destination, **⌘R**.
4. First launch: allow **Bluetooth** when prompted.

## Pair with your car (one time)

1. **Sit in the car** with the phone; have your **NFC key card** ready.
2. Enter your 17-character VIN in the app → **Pair with Vehicle**.
3. **Tap the key card on the center console** when the app says so.
4. **Confirm** the new key on the car's screen.
5. Verify under **Controls → Locks** — rename the new key to "Tesla Buttons".

No pairing popup? Verify the VIN, make sure you're within a few meters of the car, and try again — the request is idempotent.

## Set up instant access

- **Action button:** Settings → Action Button → **Shortcut** → pick *Frunk*, *Trunk*, *Climate*, or *Lock*.
- **Siri:** works immediately — "Open the frunk with Tesla Buttons", "Precondition my Tesla with Tesla Buttons".
- **Control Center:** swipe down → **+** → *Add a Control* → find the **Tesla Buttons** controls.
- **Lock Screen:** long-press the Lock Screen → Customize → replace the flashlight/camera buttons with a Tesla control.
- **Shortcuts app:** the generic *Run Tesla Command* action exposes all 13 commands for automations (e.g., "when I arrive home → vent windows").

## How it works (the two tricks worth knowing)

**1. Everything is one process.** `VehicleService` is a process-wide actor owning a single `TeslaVehicleClient`. The UI, Siri, the Action button, and every control funnel through it, so BLE sessions (which carry anti-replay counters) are never contended. Sessions stay warm for 90 s after a background command — repeat presses are fast.

**2. Intents are forced into the app process.** Widget-extension processes can't do CoreBluetooth. Every intent here is target-membered into *both* the app and the extension, and conforms to `ForegroundContinuableIntent` **only in the app build** (`@available(iOSApplicationExtension, unavailable)`) — the documented pattern that makes the system background-launch the main app to execute the intent. `openAppWhenRun = false` keeps it invisible.
   *iOS 26+ note:* `ForegroundContinuableIntent` is deprecated (still functional) — migrate to `static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]` when you raise the deployment target.

**Expected latency** (validate on your car): warm session ≈ sub-second; cold background launch + scan + connect + dual-domain handshake ≈ 2–6 s. The car's BLE (VCSEC) listens even while the vehicle sleeps.

## Security notes

- The paired key is a **DRIVER-grade car key**. Enable **PIN to Drive** in the car.
- The P-256 private key lives in the **iOS Keychain**, device-only, no iCloud sync — the strongest key storage in this whole project space.
- Revoke anytime from the car: **Controls → Locks → Tesla Buttons → remove**.
- No Tesla account tokens are stored anywhere in this app.

## Troubleshooting

| Symptom | Check |
|---|---|
| Won't build | Xcode ≥ 16.4/26 (Swift 6.2 toolchain for the package); `xcodegen generate` after any `project.yml` edit |
| Pairing HMAC/auth error | VIN typo — it must match exactly |
| `scanTimeout` | Out of BLE range, or Bluetooth permission denied (Settings → Tesla Buttons) |
| Control does nothing when app closed | Confirm the intent files are members of **both** targets, and the `ForegroundContinuableIntent` extension is present |
| Command rejected | Vehicle asleep + command needs infotainment: send **Wake** first (the library auto-handshakes both domains on connect) |
| App expired after a year | Rebuild/reinstall — normal for personal signing |

## Ideas / next steps

- Apple Watch companion (see [`misakatao/TeslaBLEKeyKit`](https://github.com/misakatao/TeslaBLEKeyKit), watchOS 9+)
- Seat heaters (`.climate(.setSeatHeater(level:seat:))`) and HomeLink (`.actions(.triggerHomelink(latitude:longitude:))`) buttons
- Live vehicle state in-app via `client.fetch(.categories([.charge]))` (see the library's demo app)
- Configurable controls (`AppIntentControlValueProvider`) to pick the command per control slot

## License / credits

Personal-use scaffold. Libraries: [swift-tesla-ble](https://github.com/shoujiaxin/swift-tesla-ble) (MIT), protocol by [teslamotors/vehicle-command](https://github.com/teslamotors/vehicle-command) (Apache-2.0). Not affiliated with Tesla. You are responsible for anything your car does because you pressed a button you built.
