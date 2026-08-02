# Smart Eyes

Two Xcode projects for "Smart Eyes," a smart-glasses + Gemini AI visual-inspection app, built for a Bachelor Thesis ("Smart Eyes: Building an AI visual assistant for real-world technical inspections"). Both pair with Meta smart glasses via the Meta Wearables Device Access Toolkit (DAT SDK), stream the wearer's point-of-view camera to an iPhone, and send captured photos to Google Gemini (via Firebase AI Logic) for spoken-question visual inspection of pipes, gauges, machinery, and workplace safety conditions.

## Folders

- **[`SmartEyesMVP/`](SmartEyesMVP)** — the current, client-facing build: a use-case-driven flow (Pipe Analysis, Gauge Reading, Anomaly Detection, Workplace Safety/SUVA), photo capture → tap-to-ask voice/text question → multi-turn Gemini conversation per photo, with a **Setup / Inspection / Chat Log** three-tab UI. Requires real hardware and a configured Firebase project — there is no simulator fallback.
- **[`SmartEyesV1-research/`](SmartEyesV1-research)** — the earlier research/testing-track prototype used for the thesis's empirical evaluation: a fixed Phase 1 / 2 / 3 framework (Baseline / Industrial / Stress Test), hands-free wake-word ("inspect") voice trigger, single-shot (non-multi-turn) analysis, and CSV telemetry export with accuracy ratings, in a **Inspection / Audit Log** two-tab UI. Includes a Simulator-only mock-camera fallback the MVP intentionally does not have, so it can be exercised without physical glasses.

Each folder is a self-contained Xcode project with a single `README.md` at its top level — what the app does, project structure, full Meta DAT SDK / Gemini integration detail, and how to test/run — and a `SETUP.md` (credentials you need to supply: Firebase, Meta Wearables Developer Center, Apple code signing, since none are included in this handoff).

## Full documentation

`Application_Documentation_Smart_Eyes.pdf` is the comprehensive architecture and setup reference for both apps — repository structure, full source listings for the key manager classes, the Meta DAT SDK integration walkthrough, data-flow diagrams, security/privacy notes, and a step-by-step reproduction guide (including glasses pairing and enabling Developer Mode in the Meta AI app).

## Before you build

Both projects need their own Firebase config, Meta Wearables app credentials, and Apple Developer Team before they'll compile — see each project's `SETUP.md` for exact steps, or the "Reproduction & Setup Guide" section of the full documentation above.
