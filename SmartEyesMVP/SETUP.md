# Setup

This copy of the project has had all developer-specific credentials removed. Before it will build and run, you need to supply your own in three places.

## 1. Firebase (Gemini API access)

The app uses Firebase AI Logic to talk to Gemini — there is no API key in the source code.

1. Go to the [Firebase console](https://console.firebase.google.com) → create/select a project → **AI Services → AI Logic → Get started** → choose **Gemini Developer API**.
2. Firebase console → **Project settings → Add app (iOS)**. Enter the app's bundle ID (see `SmartEyesMVP.xcodeproj` build settings).
3. Download the generated `GoogleService-Info.plist` and place it at `SmartEyesMVP/GoogleService-Info.plist` (next to `SmartEyesApp.swift`). This filename is already in `.gitignore`, so it will never be committed.
4. Make sure `FirebaseApp.configure()` is called at startup — it already is, in `SmartEyesApp.swift`.

## 2. Meta Wearables Developer Center (smart glasses pairing)

`Info.plist` has two placeholder values under the `MWDAT` key that must be replaced with your own app's credentials:

```
ClientToken = YOUR_META_CLIENT_TOKEN
MetaAppID   = YOUR_META_APP_ID
```

Register your own app at the [Meta Wearables Developer Center](https://developers.meta.com/horizon/wearables) to get these values, then paste them in.

You'll also need the Meta Wearables DAT SDK itself, which isn't included in this handoff (it's a large third-party package, not something we can redistribute):
- **File → Add Package Dependencies…** → `https://github.com/facebook/meta-wearables-dat-ios` → link `MWDATCore` and `MWDATCamera` to the app target.

## 3. Apple code signing

`project.pbxproj` has `DEVELOPMENT_TEAM = "";` (blank) in all 4 build configurations. In Xcode, select the project → target → **Signing & Capabilities** → choose your own Apple Developer Team. Xcode will fill in the team ID automatically.

---

Once all three are set, the project should build and run exactly as before.
