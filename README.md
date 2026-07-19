# Smart Eyes

Two Xcode projects for the Smart Eyes smart-glasses + Gemini AI visual-inspection prototype.

## Folders

- **[`SmartEyesMVP/`](SmartEyesMVP)** — the current build: a use-case-driven flow (Pipe Analysis, Gauge Reading, Anomaly Detection, Workplace Safety/SUVA), photo capture → voice/text question → Gemini multi-turn conversation, with a Setup / Inspection / Audit Log UI.
- **[`SmartEyesV1-research/`](SmartEyesV1-research)** — the earlier research/testing-track prototype used for empirical evaluation (Phase 1-3 prompt framework, CSV/JSON telemetry export with accuracy ratings). Included for reference on how the current build's design choices were validated.

Each folder is a self-contained Xcode project with its own `README.md` (what the app does, project structure, how to test/run) and `SETUP.md` (credentials you need to supply — Firebase, Meta Wearables Developer Center, Apple code signing — since none are included in this handoff).

## Before you build

Both projects need their own Firebase config, Meta Wearables app credentials, and Apple Developer Team before they'll compile — see each project's `SETUP.md` for exact steps.
