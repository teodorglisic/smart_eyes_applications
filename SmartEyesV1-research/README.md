# SmartEyesV1-research

The original bachelor-thesis research and testing-track build of Smart Eyes — an iOS app that pairs with Meta smart glasses, streams the wearer's point-of-view camera to the phone, and sends captured photos to Gemini (via Firebase AI Logic) for spoken-question visual inspection. This build carries the empirical Phase 1-3 evaluation framework and structured telemetry export used to validate the approach, ahead of it being restructured into the use-case-driven MVP (see [`../SmartEyesMVP`](../SmartEyesMVP), and the root [`README.md`](../README.md) for how the two projects relate).

---

## Setup

This copy has had all developer-specific credentials removed. Before it will build, you need to supply your own Firebase project, Meta Wearables Developer Center credentials, and Apple Developer Team — see [`SETUP.md`](SETUP.md) for exact steps. Firebase is optional for Simulator/mock-mode testing (see below), but required for real Gemini answers. Live-hardware testing also requires pairing the glasses with the Meta AI companion app and enabling **Developer Mode** there first (Section 11.4 of `Application_Documentation_Smart_Eyes.pdf` has the exact steps) — without it, an unpublished Xcode build can't register against the glasses at all.

---

## Project Structure

```
SmartEyesV1-research/                 (this folder)
├── README.md                         — you are here
├── SETUP.md                          — credentials you need to supply
├── SmartEyesPrototypeV1.xcodeproj
└── SmartEyesPrototypeV1/              — Swift source
    ├── App/, Managers/, Models/, Views/, Support/
    └── Info.plist
```

| File | Purpose |
|---|---|
| `SmartEyesApp.swift` | App entry point. Calls `FirebaseApp.configure()` and `Wearables.configure()` at launch, and routes the Meta AI companion app's registration callback URL to `WearableManager`. |
| `WearableManager.swift` | Wraps the Meta Wearables Device Access Toolkit (DAT) SDK — registration, device discovery, session lifecycle, camera streaming, and photo capture — plus a Simulator-only mock camera fallback. See below for how this works. |
| `GeminiManager.swift` | Wraps Firebase AI Logic (Gemini) — the Phase 1-3 research prompt framework (read from `PhaseCatalog.swift`) and single-shot analysis calls, with token telemetry. See below for how this works. |
| `ContentView.swift` | Main SwiftUI dashboard — two tabs: Inspection, Audit Log (model/settings are a sheet reached from the header gear icon, not a separate tab). |
| `VoiceTriggerManager.swift` | Hands-free wake-word listener — says "inspect" to trigger analysis without touching the phone. |
| `SpeechManager.swift` | Local text-to-speech playback of analysis results. |
| `TelemetryManager.swift` | Logs every analysis trial locally and exports it as CSV; backs the Audit Log tab's feedback (thumbs up/down, star rating). |
| `PhaseCatalog.swift` | The three empirical-evaluation phases (Baseline, Industrial, Stress Test), each with its own system prompt and canned simulator-mode responses. |
| `GeminiModelCatalog.swift` | The list of selectable Gemini/Gemma models shown in Settings. |
| `ChatLogStore.swift` | The shared chat/audit transcript. |
| `Info.plist` | iOS background modes, custom URL scheme, and the `MWDAT` SDK configuration block. |

---

## How the Meta Wearables (DAT) Integration Works

The glasses integration is built on Meta's [Wearables Device Access Toolkit for iOS](https://github.com/facebook/meta-wearables-dat-ios) (added via Swift Package Manager, `MWDATCore` + `MWDATCamera`, pinned to version 0.8.0). `WearableManager.swift` follows the SDK's documented lifecycle end to end:

1. **Configure** — `Wearables.configure()` runs once at app launch (`SmartEyesApp.swift`).
2. **Register** — the user taps a "Register Glasses" action, which calls `startRegistration()` and hands off to the Meta AI companion app; when it calls back into `smarteyesapp://`, `SmartEyesApp.swift`'s `.onOpenURL` hands the URL to `WearableManager.handleCallbackURL`, which passes it to the SDK via `handleUrl(_:)`. Registration and paired-device state are observed continuously through `registrationStateStream()` and `devicesStream()`.
3. **Session** — `startStream()` waits for a device to be discovered, then opens a `DeviceSession` for that specific device (`SpecificDeviceSelector`) and waits for it to reach the `.started` state before proceeding.
4. **Stream** — a camera stream is added to the session with a `StreamConfiguration`. This app deliberately requests the lowest bandwidth profile the SDK offers (`resolution: .low` / 360×640, `frameRate: 2`) — smart glasses only have Bluetooth Classic bandwidth to work with, and pushing more than that starves the higher-priority high-res photo capture. Frame, state, and error callbacks are wired via `videoFramePublisher`, `statePublisher`, and `errorPublisher`.
5. **Capture** — `capturePhoto(format: .jpeg)` triggers an out-of-band high-resolution JPEG capture over the stream's `photoDataPublisher`, independent of the low-res live preview.

> **Why 2 FPS?** This wasn't the starting point — it's a downgrade. Earlier iterations ran the live preview at a higher frame rate/resolution, but that had to be scaled back specifically so the separate high-resolution photo capture (1080×1440) could be enforced reliably. The Bluetooth link only has so much bandwidth to share between the continuous live preview and the on-demand high-res capture; a richer live preview left too little headroom for the high-res capture to complete before the SDK's watchdog timeout fired, so captures would silently fail or come back corrupted. Starving the live preview down to the minimum useful frame rate fixed it — a choppier live view in service of every capture reliably returning a usable high-res image.

**Simulator fallback (not part of Meta's SDK):** when running in the iOS Simulator, `WearableManager` skips the SDK entirely and drives a self-contained mock mode instead — a timer-generated placeholder frame (grid overlay, rotating crosshair, live clock) and a `capturePhoto()` that just returns the current mock frame. This lets the rest of the app (Gemini analysis, telemetry, UI) be developed and demoed without physical glasses. A "Switch to Simulation" / "Switch to Live Device" toggle on the Audit Log tab also lets you flip mock mode on/off manually, e.g. when running on a physical iPhone.

**A few things worth knowing before extending this:**
- Publishing to the App Store isn't supported today — the SDK relies on Apple's `ExternalAccessory` framework (see `UISupportedExternalAccessoryProtocols` in `Info.plist`), which requires MFi certification Meta hasn't completed yet.
- Delivered stream frames are adaptively compressed to fit available Bluetooth bandwidth; if image quality looks worse than expected, lowering resolution/frame rate further (rather than raising them) can actually help.
- The SDK ships its own separate Mock Device Kit (`MWDATMockDevice`/`MWDATMockDeviceTestClient`) for testing without physical hardware, distinct from this app's own hand-rolled simulator fallback above and not currently linked into this target.

Full API reference, permission flows, session-state details, and the official sample app are in [Meta's iOS integration guide](https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/) and the [`meta-wearables-dat-ios` repo](https://github.com/facebook/meta-wearables-dat-ios).

---

## How the Gemini AI Integration Works

`GeminiManager.swift` talks to Gemini through **Firebase AI Logic**, not a raw API key — `FirebaseApp.app() != nil` is the only "do we have a key" check in the app; the actual credential lives in `GoogleService-Info.plist` and never touches app code, and no Keychain storage is used anywhere. (This app previously used the deprecated `generative-ai-swift` package with an in-app API key field; it was migrated to Firebase AI Logic specifically to close the risk of a key being extracted from a compiled `.ipa`. `ApiKeySettingsView.swift`, despite its name, now only lets you pick a target model, not enter a key.)

This build's analysis is organized around the thesis's three-phase empirical testing track (the `Phase` struct in `PhaseCatalog.swift`), each with its own system prompt tuned for that phase's test conditions:

- **Phase 1 — Baseline**: fast, low-context identification of everyday objects and generic components under varying lighting, kept to 1-2 sentences.
- **Phase 2 — Industrial**: high-precision inspection of machinery/piping/gauges/valves, with structured `OBJECT DETECTED` / `STATE-VALUE` / `DETECTED ANOMALY` / `SEVERITY` / `SUGGESTED ACTION` reporting.
- **Phase 3 — Stress Test**: analysis under degraded conditions — perspective distortion, glare, partial obstruction, motion blur — with explicit confidence/limitation reporting.

Each `analyzeFrame` call is a single-shot `generateContent`, not a multi-turn chat (unlike the MVP build, there's no follow-up-in-context flow here — every question re-sends the photo). Every response's `usageMetadata` (text/image input tokens, output tokens, thinking tokens, total) is captured and handed to `TelemetryManager`. If Firebase isn't configured, `analyzeFrame` returns a randomized, clearly-labeled `(SIMULATION)` response drawn from that phase's canned `mockResponses` instead of failing — useful for UI development without live credentials.

---

## Voice Control

`VoiceTriggerManager.swift` implements hands-free wake-word activation: it listens continuously and fires an analysis trigger when it hears "inspect" (with a 4-second cooldown to avoid re-triggering on the same utterance, and automatic recognition-session restart on non-fatal errors). This is the earlier, fully hands-free approach — the MVP build simplified this to explicit tap-to-ask (see [`../SmartEyesMVP`](../SmartEyesMVP)).

**Known instability:** this was included specifically to try a hands-free interaction model, but it turned out to be unreliable — the always-open microphone/audio session needed to catch the wake word competes for the same Bluetooth radio the DAT SDK uses to stay connected to the glasses, which throttles the live feed and can destabilize the connection while listening is active. This is the real reason the MVP build replaced it with tap-to-ask rather than trying to fix the wake word directly; it's kept here as-is because it's part of the empirical record the thesis evaluated, not because it's production-ready.

---

## Telemetry & Audit Log

Every analysis is logged locally by `TelemetryManager` (`InspectionView.swift` calls `logTrial` right after each Gemini response) — timestamp, phase, capture source (live device vs. simulator), latency, prompt/response text, parsed severity, model name, and the full token breakdown. This is the core research instrumentation for the thesis's empirical evaluation: the Audit Log tab lets you mark a result correct/incorrect and give it a 1-5 star rating (`submitFeedback`), and export the whole log as CSV for analysis, or purge it between test sessions.

One known rough edge: the CSV export always writes a `test_case` column as the literal string `"Please enter test case"` — it's wired for a structured field that was never populated. Harmless (every other column is real data), just not actionable as-is.

---

## How to Test and Run

1. **Register the glasses**: turn them on, open the Meta AI companion app, ensure Developer Mode is on, then run this app and tap Register — you'll be bounced to the Meta AI app to grant Camera/Microphone permissions and back again. (Or skip this entirely in the iOS Simulator, where mock mode activates automatically.)
2. **Inspection tab**: once connected, the live low-res preview appears; pick a phase (Baseline / Industrial / Stress Test), then capture a frame — by button, or hands-free by saying "inspect".
3. Gemini's response appears in the chat log along with the captured frame.
4. **Audit Log tab**: review past trials, rate accuracy, export telemetry for analysis, toggle Live Device/Simulation mode.
5. **Settings (gear icon)**: switch the target Gemini model (Gemini 3.5 Flash by default, plus other Gemini/Gemma variants).

---

## Third-Party SDK Terms

Using the Meta Wearables DAT SDK means this app is subject to Meta's [Wearables Developer Terms](https://wearables.developer.meta.com/terms) and [Acceptable Use Policy](https://wearables.developer.meta.com/acceptable-use-policy); Meta may collect some data about how the app communicates with users' devices per their [Privacy Policy](https://www.meta.com/legal/privacy-policy/). Like the MVP build, this project has opted out of that analytics collection (`MWDAT.Analytics.OptOut = true` in `Info.plist`) — see the [SDK repo's README](https://github.com/facebook/meta-wearables-dat-ios#opting-out-of-data-collection) if you want to change that.

This app's own source code (this folder) is MIT-licensed — see [`../LICENSE`](../LICENSE) and the "License" section of the [root README](../README.md) for the full breakdown of what that covers vs. the third-party SDKs above.

---

## More documentation

`Application_Documentation_Smart_Eyes.pdf` is the comprehensive documentation covering both apps: full source listings, architecture diagrams, ADRs, security/privacy notes, and a complete reproduction/setup guide (including glasses pairing and Developer Mode).

## References

- [Meta Wearables DAT — Setup (glasses pairing, Developer Mode)](https://wearables.developer.meta.com/docs/develop/dat/getting-started-toolkit)
- [Meta Wearables DAT — iOS integration guide](https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/)
- [`facebook/meta-wearables-dat-ios`](https://github.com/facebook/meta-wearables-dat-ios) (SDK source, license, changelog)
- [Firebase AI Logic docs](https://firebase.google.com/docs/ai-logic)
