# Smart Eyes: Meta Glasses & Gemini Integration Prototype

This folder contains the core Swift and SwiftUI source for "Smart Eyes" — an iOS app that pairs with Meta smart glasses, streams the wearer's point-of-view camera to the phone, and sends captured photos to Gemini (via Firebase AI Logic) for spoken-question visual inspection. Originally built for the Bachelor Thesis *"Smart Eyes: Building an AI visual assistant for real-world technical inspections"*, this folder is the restructured, use-case-driven MVP build (see [`../SmartEyesV1-research`](../../SmartEyesV1-research) for the earlier research/testing-track prototype this evolved from).

---

## Setup

This copy has had all developer-specific credentials removed. Before it will build, you need to supply your own Firebase project, Meta Wearables Developer Center credentials, and Apple Developer Team — see [`../SETUP.md`](../SETUP.md) for exact steps.

---

## Project Structure

| File | Purpose |
|---|---|
| `SmartEyesApp.swift` | App entry point. Calls `FirebaseApp.configure()` and `Wearables.configure()` at launch, and routes the Meta AI companion app's registration callback URL to `WearableManager`. |
| `WearableManager.swift` | Wraps the Meta Wearables Device Access Toolkit (DAT) SDK — registration, device discovery, session lifecycle, camera streaming, and photo capture. See below for how this works. |
| `GeminiManager.swift` | Wraps Firebase AI Logic (Gemini) — defines the four inspection use cases, runs multi-turn analysis conversations, and tracks token telemetry. See below for how this works. |
| `ContentView.swift` | Main SwiftUI dashboard — three tabs: Setup, Inspection, Audit Log. |
| `VoiceQuestionManager.swift` | Tap-to-ask speech-to-text: captures a spoken follow-up question after a photo is taken. |
| `SpeechManager.swift` | Local text-to-speech playback of analysis results. |
| `TelemetryManager.swift` | Logs every analysis trial locally and exports it as CSV/JSON; backs the Audit Log tab's feedback (thumbs up/down, star rating). |
| `Info.plist` | iOS background modes, custom URL scheme, and the `MWDAT` SDK configuration block. |

---

## How the Meta Wearables (DAT) Integration Works

The glasses integration is built on Meta's [Wearables Device Access Toolkit for iOS](https://github.com/facebook/meta-wearables-dat-ios) (added via Swift Package Manager, `MWDATCore` + `MWDATCamera`). `WearableManager.swift` follows the SDK's documented lifecycle end to end:

1. **Configure** — `Wearables.configure()` runs once at app launch (`SmartEyesApp.swift`).
2. **Register** — the user taps a "Register Glasses" action, which calls `startRegistration()` and hands off to the Meta AI companion app; when it calls back into `smarteyesmvp://`, `SmartEyesApp.swift`'s `.onOpenURL` hands the URL to `WearableManager.handleCallbackURL`, which passes it to the SDK via `handleUrl(_:)`. Registration and paired-device state are observed continuously through `registrationStateStream()` and `devicesStream()`.
3. **Session** — `startStream()` waits for a device to be discovered, then opens a `DeviceSession` for that specific device (`SpecificDeviceSelector`) and waits for it to reach the `.started` state before proceeding.
4. **Stream** — a camera stream is added to the session with a `StreamConfiguration`. This app deliberately requests the lowest bandwidth profile the SDK offers (`resolution: .low` / 360×640, `frameRate: 2`) — smart glasses only have Bluetooth Classic bandwidth to work with, and pushing more than that starves the higher-priority high-res photo capture. Frame, state, and error callbacks are wired via `videoFramePublisher`, `statePublisher`, and `errorPublisher`.
5. **Capture** — `capturePhoto(format: .jpeg)` triggers an out-of-band high-resolution JPEG capture over the stream's `photoDataPublisher`, independent of the low-res live preview.

**Simulator fallback (not part of Meta's SDK):** when running in the iOS Simulator, `WearableManager` skips the SDK entirely and drives a self-contained mock mode instead — a timer-generated placeholder frame stream and a `capturePhoto()` that just returns the current mock frame. This lets the rest of the app (Gemini analysis, telemetry, UI) be developed and demoed without physical glasses.

**A few things worth knowing before extending this:**
- Publishing to the App Store isn't supported today — the SDK relies on Apple's `ExternalAccessory` framework (see `UISupportedExternalAccessoryProtocols` in `Info.plist`), which requires MFi certification Meta hasn't completed yet.
- Delivered stream frames are adaptively compressed to fit available Bluetooth bandwidth; if image quality looks worse than expected, lowering resolution/frame rate further (rather than raising them) can actually help.
- The SDK ships a Mock Device Kit for testing without physical hardware, separate from this app's own simulator fallback above.

Full API reference, permission flows, session-state details, and the official sample app are in [Meta's iOS integration guide](https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/) and the [`meta-wearables-dat-ios` repo](https://github.com/facebook/meta-wearables-dat-ios).

---

## How the Gemini AI Integration Works

`GeminiManager.swift` talks to Gemini through **Firebase AI Logic**, not a raw API key — `FirebaseApp.app() != nil` is the only "do we have a key" check in the app; the actual credential lives in `GoogleService-Info.plist` and never touches app code. (This app previously used the deprecated `generative-ai-swift` package with an in-app API key field; it was migrated to Firebase AI Logic specifically to close the risk of a key being extracted from a compiled `.ipa`.)

- **Use cases** (`UseCase` in `GeminiManager.swift`): four selectable "lenses" — Pipe Analysis, Gauge Reading, Anomaly Detection, and Workplace Safety (SUVA) — each with its own system prompt. Adding a new use case means appending to `UseCase.all`; nothing else needs to change.
- **Grounding**: the Workplace Safety use case attaches Gemini's Google Search tool (`Tool.googleSearch()`) so it can cite real, current SUVA (Swiss workplace safety) guidance instead of relying only on the model's training data; when it does, the response appends the source links, per Gemini's grounding usage terms.
- **Multi-turn conversation**: the first question against a photo opens a `Chat` and sends the image + prompt together; follow-up questions about the *same* photo reuse that `Chat` (`isFollowUp: true`) so the image doesn't need to be re-sent. Retaking the photo or switching use case calls `startNewConversation()` to reset it.
- **Retry logic**: only genuinely transient backend errors (HTTP 500/503, "model overloaded") get retried, up to 3 attempts with backoff — a 404 (retired model) or 429 (quota exhausted) fails immediately instead of hammering a dead endpoint.
- **Token telemetry**: every response's `usageMetadata` (text/image input tokens, output tokens, thinking tokens, total) is captured and handed to `TelemetryManager`.
- **Simulation fallback**: if Firebase isn't configured, `analyzeFrame` returns a randomized, clearly-labeled `(SIMULATION)` response per use case instead of failing — useful for UI development without live credentials.

The anti-hallucination guideline (`UseCase.safeFailureGuideline`) is appended to every use case's system prompt: the model is instructed to say *why* it can't answer (out of frame, too dark, obstructed, etc.) rather than guess.

---

## Voice Control

`VoiceQuestionManager.swift` implements tap-to-ask: after taking a photo, the technician taps the mic, speaks their question, taps stop, and can review/edit the transcript before sending it to Gemini. There's no wake word in this build — see [`../SmartEyesV1-research`](../../SmartEyesV1-research) for the earlier hands-free "wake word" approach this was simplified from.

---

## Telemetry & Audit Log

Every analysis is logged locally by `TelemetryManager` (`ContentView.swift` calls `logTrial` right after each Gemini response) — timestamp, use case, capture source (live device vs. simulator), latency, prompt/response text, parsed severity, model name, and the full token breakdown. The Audit Log tab lets the technician mark a result correct/incorrect and give it a 1-5 star rating (`submitFeedback`), and can export the whole log as CSV or JSON, or purge it.

One known rough edge: the CSV export always writes a `test_case` column as the literal string `"Please enter test case"` — it's wired for a structured field that was never populated. Harmless (every other column is real data), just not actionable as-is.

---

## How to Test and Run

1. **Register the glasses**: turn them on, open the Meta AI companion app, ensure Developer Mode is on, then run this app and tap Register — you'll be bounced to the Meta AI app to grant Camera/Microphone permissions and back again.
2. **Inspection tab**: once connected, the live low-res preview appears; pick a use case (Pipe Analysis, Gauge Reading, Anomaly Detection, or Workplace Safety), then capture a frame.
3. Ask a question by voice (tap-to-ask) or type one; Gemini's response streams into the chat, and follow-ups about the same photo stay in context.
4. **Audit Log tab**: review past trials, rate accuracy, export telemetry.
5. **Setup tab**: switch the target Gemini model (Gemini 3.5 Flash by default, plus other Gemini/Gemma variants), toggle voice output, manage device registration.

---

## Third-Party SDK Terms

Using the Meta Wearables DAT SDK means this app is subject to Meta's [Wearables Developer Terms](https://wearables.developer.meta.com/terms) and [Acceptable Use Policy](https://wearables.developer.meta.com/acceptable-use-policy); Meta may collect some data about how the app communicates with users' devices per their [Privacy Policy](https://www.meta.com/legal/privacy-policy/). This project has already opted out of that analytics collection (`MWDAT.Analytics.OptOut = true` in `Info.plist`) — see the [SDK repo's README](https://github.com/facebook/meta-wearables-dat-ios#opting-out-of-data-collection) if you need to change that.

---

## References

- [Meta Wearables DAT — iOS integration guide](https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/)
- [`facebook/meta-wearables-dat-ios`](https://github.com/facebook/meta-wearables-dat-ios) (SDK source, license, changelog)
- [Firebase AI Logic docs](https://firebase.google.com/docs/ai-logic)
