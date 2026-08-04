# Smart Eyes

Two Xcode projects for "Smart Eyes," a smart-glasses + Gemini AI visual-inspection app, built for a Bachelor Thesis ("Smart Eyes: Building an AI visual assistant for real-world technical inspections"). Both pair with Meta smart glasses via the Meta Wearables Device Access Toolkit (DAT SDK), stream the wearer's point-of-view camera to an iPhone, and send captured photos to Google Gemini (via Firebase AI Logic) for spoken-question visual inspection of pipes, gauges, machinery, and workplace safety conditions.

## Folders

- **[`SmartEyesMVP/`](SmartEyesMVP)** — the current, client-facing build: a use-case-driven flow (Pipe Analysis, Gauge Reading, Anomaly Detection, Workplace Safety/SUVA), photo capture → tap-to-ask voice/text question → multi-turn Gemini conversation per photo, with a **Setup / Inspection / Chat Log** three-tab UI. Requires real hardware and a configured Firebase project — there is no simulator fallback.
- **[`SmartEyesV1-research/`](SmartEyesV1-research)** — the earlier research/testing-track prototype used for the thesis's empirical evaluation: a fixed Phase 1 / 2 / 3 framework (Baseline / Industrial / Stress Test), hands-free wake-word ("inspect") voice trigger, single-shot (non-multi-turn) analysis, and CSV telemetry export with accuracy ratings, in a **Inspection / Audit Log** two-tab UI. Includes a Simulator-only mock-camera fallback the MVP intentionally does not have, so it can be exercised without physical glasses.

Each folder is a self-contained Xcode project with a single `README.md` at its top level — what the app does, project structure, full Meta DAT SDK / Gemini integration detail, and how to test/run — and a `SETUP.md` (credentials you need to supply: Firebase, Meta Wearables Developer Center, Apple code signing, since none are included in this handoff).

## Full documentation

Each project has its own comprehensive technical documentation PDF — architecture and setup reference, repository structure, full source listings for the key manager classes, the Meta DAT SDK integration walkthrough, data-flow diagrams, security/privacy notes, and a step-by-step reproduction guide (including glasses pairing and enabling Developer Mode in the Meta AI app): [`SmartEyesMVP/FHNW_SmartEyes_MVP_Technical_Documentation.pdf`](SmartEyesMVP/FHNW_SmartEyes_MVP_Technical_Documentation.pdf) and [`SmartEyesV1-research/FHNW_SmartEyes_V1_Research_Technical_Documentation.pdf`](SmartEyesV1-research/FHNW_SmartEyes_V1_Research_Technical_Documentation.pdf).

## Before you build

Both projects need their own Firebase config, Meta Wearables app credentials, and Apple Developer Team before they'll compile — see each project's `SETUP.md` for exact steps, or the "Step-by-Step Replication Guide" section of that project's documentation PDF above.

## License

The original source code in this repository (both apps' Swift/SwiftUI code, documentation, and configuration) is © Teodor Glisic and licensed under the [MIT License](LICENSE) — see the `LICENSE` file at the repo root.

This repo does **not** vendor any third-party SDK source — the Meta Wearables DAT SDK and the Firebase iOS SDK are both pulled in at build time via Swift Package Manager (see each project's `SETUP.md`), not committed here. They remain under their own, separate terms:

- **Meta Wearables Device Access Toolkit (DAT SDK)** — a proprietary license under the [Meta Wearables Developer Terms](https://wearables.developer.meta.com/terms) and [Acceptable Use Policy](https://wearables.developer.meta.com/acceptable-use-policy), not open source. Notably, its terms prohibit redistributing the SDK itself, or using/redistributing it in any way that would subject it (or Meta) to an open-source license — this repo complies by only referencing it via SPM, never vendoring or modifying its source.
- **Firebase iOS SDK** (`FirebaseAILogic`, `FirebaseCore`) — [Apache License 2.0](https://github.com/firebase/firebase-ios-sdk/blob/master/LICENSE), permissive.
- **Google Gemini API** — accessed through Firebase AI Logic; usage is governed by Google's own Gemini API terms, separate from this repo's license.

This project was originally built as part of a Bachelor Thesis at FHNW, in a client-adjacent context; the client has confirmed the repository can be made public, and no client data or proprietary client material is included here.
