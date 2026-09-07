# Distribution (Developer ID + Notarization)

> Status: **ACTIVE** - Build, sign, notarize, and manually publish to GitHub Releases

This repo is SwiftPM-based, so we assemble a `.app` bundle manually for Developer ID distribution.
The packaged app product must be built through Xcode. Plain `swift build`
generates command-line resource accessors that check the app root and then an
absolute checkout path. The Xcode package integration generates app-aware
accessors that check `Contents/Resources`, where macOS code signing can seal the
resource bundles. The bundled CLI continues to use `swift build`.

## 1) Build the app bundle

From the repo root:

```bash
scripts/dist/build_app_bundle.sh
```

This creates `dist/MacParakeet.app` and bundles:
- `Assets/AppIcon.icns` into `Contents/Resources/AppIcon.icns` (app icon for Dock, Finder, DMG)
- `macparakeet-cli` into `Contents/MacOS/macparakeet-cli`
- SwiftPM-generated `.bundle` directories into `Contents/Resources`, which is
  `Bundle.main.resourceURL` and is the first app location used by Xcode's
  generated package-resource accessors
- Standalone helper binaries (FFmpeg, yt-dlp helper seed, and optional Node runtime) into `Contents/Resources/` when configured by the build scripts
- No Python runtime or `uv` bootstrap is bundled (FluidAudio/CoreML STT is native Swift)

`build_app_bundle.sh` automatically downloads a **statically-linked FFmpeg** from [ffmpeg.martin-riedl.de](https://ffmpeg.martin-riedl.de/) (macOS arm64, SHA256-verified). No Homebrew dependency. To use a custom binary instead, set `FFMPEG_PATH`:

```bash
FFMPEG_PATH=/absolute/path/to/static-ffmpeg scripts/dist/build_app_bundle.sh
```

The script verifies the bundled binary has no non-system dylib dependencies (portability check via `otool -L`).

`yt-dlp` is bundled as a signed helper seed. At runtime, the app/CLI copies it
to `~/Library/Application Support/MacParakeet/bin/yt-dlp` before first YouTube
transcription so future helper updates never mutate the signed app bundle. To
use a pre-fetched helper in release builds, set `YTDLP_PATH`; set
`BUNDLE_YTDLP=0` only for diagnostic builds.

Meeting echo suppression assets are optional for local/dev bundles, but
AEC-ready release builds should require them. With
`REQUIRE_MEETING_ECHO_ASSETS=1`, the bundle script builds the pinned LocalVQE
runtime from source and downloads the selected v1.4 echo-only GGUF into
`.build/meeting-echo-assets/` when explicit asset paths are not supplied:

```bash
export REQUIRE_MEETING_ECHO_ASSETS=1
VERSION=X.Y.Z scripts/dist/build_app_bundle.sh
```

The default model is `localvqe-v1.4-aec-200K-f32.gguf`
(`SHA256=b6e43138588a83bfe903ab5e143b4020b91c1e1629f5a575ac5855ff0003c731`).
It is roughly 2.9 MB before compression. The source-built runtime is copied to
`Contents/Frameworks/liblocalvqe.dylib`, and the selected model is copied under
`Contents/Resources/MeetingEchoSuppression/`. Release bundles must contain
exactly one GGUF model so asset verification and runtime model resolution cannot
drift.

The native CMake build uses host parallelism by default; if that build fails,
the script cleans the build directory and retries once with `-j1`. If an
interrupted prior build leaves a Git index lock in the default generated
LocalVQE source checkout under `.build/`, the prep script discards that generated
checkout and clones it again. Custom `LOCALVQE_SOURCE_DIR` checkouts are left in
place and require manual cleanup on lock errors.

For a deliberately serialized release build, set:

```bash
export LOCALVQE_CMAKE_BUILD_JOBS=1
export REQUIRE_MEETING_ECHO_ASSETS=1
VERSION=X.Y.Z scripts/dist/build_app_bundle.sh
```

To use prebuilt assets instead of the pinned auto-prep path, set both source
paths explicitly:

```bash
export MACPARAKEET_MEETING_ECHO_LIBRARY=/absolute/path/to/liblocalvqe.dylib
export MACPARAKEET_MEETING_ECHO_MODEL=/absolute/path/to/localvqe-v1.4-aec-200K-f32.gguf
export MACPARAKEET_MEETING_ECHO_MODEL_SHA256=b6e43138588a83bfe903ab5e143b4020b91c1e1629f5a575ac5855ff0003c731
export REQUIRE_MEETING_ECHO_ASSETS=1
VERSION=X.Y.Z scripts/dist/build_app_bundle.sh
```

`build_app_bundle.sh` preserves the source GGUF filename by default; override
with `MACPARAKEET_MEETING_ECHO_MODEL_NAME=<filename>.gguf` only when the source
path is not the intended bundled name. Set
`MACPARAKEET_MEETING_ECHO_AUTO_PREPARE=0` to force explicit prebuilt paths and
fail if they are absent.

`scripts/dist/verify_meeting_echo_assets.sh dist/MacParakeet.app` is the release
gate. With `REQUIRE_MEETING_ECHO_ASSETS=1`, it fails if either asset is missing,
if the model checksum does not match, if `liblocalvqe.dylib` is not executable,
if required LocalVQE C symbols are not exported, or if `otool -L` shows
non-portable dylib references outside `@rpath`, `@loader_path`, `/System/Library`,
or `/usr/lib`. Without `REQUIRE_MEETING_ECHO_ASSETS=1`, missing assets are
accepted and the app intentionally runs the meeting echo path as passthrough.

Retained purchase activation config (normally unset in current free builds):

```bash
export MACPARAKEET_CHECKOUT_URL="https://..."
export MACPARAKEET_LS_VARIANT_ID="12345"
scripts/dist/build_app_bundle.sh
```

Current public MacParakeet builds are free/GPL-3.0 and
`EntitlementsService.currentState()` returns unlocked. These variables are
retained for future GPL-compatible official paid distribution/support and are
not required for current free production builds. When set, they are embedded
into `Info.plist` as:
- `MacParakeetCheckoutURL`
- `MacParakeetLemonSqueezyVariantID`

### Owner-only development CI artifact

Successful `main` pushes and manual CI runs publish the three-day artifact
`MacParakeet-owner-development-build`. It contains exactly one Finder-mountable
`MacParakeet-owner-development-build.dmg`. The DMG contains the complete app,
including FFmpeg, yt-dlp, Node, the bundled CLI, SwiftPM
resource bundles, and an Applications shortcut. CI verifies helper execution,
relative bundle symlinks, and the app plus nested code with
`codesign --verify --deep --strict`. It also copies the packaged app outside the
checkout, removes quarantine metadata from that copy, launches its bundled
executable, and requires it to remain alive past startup before upload. This
path does not access release certificates or notary credentials.

This is an **owner-testing development build**. Its signatures are ad-hoc and
provide bundle structure only. It is not Developer ID signed, Apple-notarized,
Gatekeeper-ready or an official release. Do not distribute it to users or
publish it to GitHub Releases.

To install it for owner testing:

1. Download `MacParakeet-owner-development-build` from the workflow run's
   **Artifacts** section.
2. Expand GitHub's artifact ZIP with Archive Utility. Open the one DMG inside.
3. Drag `MacParakeet.app` onto the Applications shortcut.
4. If macOS blocks this known development build because it has quarantine
   metadata, run this exact command, then open the installed app:

   ```bash
   xattr -dr com.apple.quarantine /Applications/MacParakeet.app
   ```

Removing quarantine bypasses a macOS safety check. Use this command only for an
owner build downloaded from the expected repository workflow. Normal users must
install the official notarized DMG instead.

### Signed and notarized CI test artifact

CI can publish a Developer ID signed and Apple-notarized test DMG through one
explicit, protected manual path. It does not publish an app from pull requests,
main pushes, or ordinary manual validation runs. The protected run uses the
same bundle, nested-helper entitlements, privacy checks, release-version gate,
notarization, stapling, and Gatekeeper checks as distribution. It also executes
the signed FFmpeg, yt-dlp seed, and Node version checks from the mounted DMG.

The artifact is named `MacParakeet-signed-notarized-ci-test` and contains one
`MacParakeet-signed-notarized-ci-test.dmg`. GitHub wraps that DMG in its normal
artifact ZIP. Retention is seven days.

This is a **CI test artifact**, not a release. It proves the signing and
notarization path works; it does not create a tag or a GitHub Release. Use the
manual procedure in section 3 to publish a release.

#### One-time repository-owner setup

1. In the Apple Developer portal, create or use a **Developer ID Application**
   certificate for this fork owner's team, `GY6L5GL2Z7`. Import the certificate
   and private key on a trusted Mac, then export both from Keychain Access as a
   password-protected `.p12`. Do not export an Apple Development certificate.
2. Create an Apple ID app-specific password for the Apple ID that can submit
   notarization requests for the same team.
3. In GitHub, open **Settings -> Environments**, create
   `signed-ci-artifact`, require an owner as a reviewer, and limit deployment
   branches to `main`.
4. Add these environment secrets (not repository variables):

   | Secret | Exact value |
   |---|---|
   | `DEVELOPMENT_ID_CERTIFICATE_BASE64` | Base64 of the complete Developer ID `.p12` |
   | `DEVELOPMENT_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
   | `DEVELOPER_ID_APPLICATION_IDENTITY` | Full identity, for example `Developer ID Application: Elimelech Oshinsky (GY6L5GL2Z7)` |
   | `APPLE_TEAM_ID` | `GY6L5GL2Z7` |
   | `NOTARY_APPLE_ID` | Apple ID email used for notarization |
   | `NOTARY_APP_SPECIFIC_PASSWORD` | Apple ID app-specific password |

   Encode and provision the certificate without writing it into the repository:

   ```bash
   base64 -i /secure/path/DeveloperIDApplication.p12 | \
     gh secret set DEVELOPMENT_ID_CERTIFICATE_BASE64 --env signed-ci-artifact
   gh secret set DEVELOPMENT_ID_CERTIFICATE_PASSWORD --env signed-ci-artifact
   gh secret set DEVELOPER_ID_APPLICATION_IDENTITY --env signed-ci-artifact
   gh secret set APPLE_TEAM_ID --env signed-ci-artifact
   gh secret set NOTARY_APPLE_ID --env signed-ci-artifact
   gh secret set NOTARY_APP_SPECIFIC_PASSWORD --env signed-ci-artifact
   ```

   The last five commands prompt for the value. Do not put secret values on the
   command line. Delete the exported `.p12` after provisioning it.

The job creates a random temporary keychain, imports the certificate, stores the
notary profile in that keychain, and deletes the certificate and keychain on
success, failure, interruption, or timeout. A missing secret, wrong certificate,
wrong team, invalid version, failed notarization, or failed verification stops
the job before the trusted DMG name exists. The artifact upload also fails if
that exact DMG is absent.

#### Publish and download

1. Open **Actions -> CI -> Run workflow** on `main`.
2. Enable **Publish the protected signed and notarized CI test DMG**.
3. Enter an explicit `X.Y.Z` test version. `0.0.0` and other sentinel values are
   rejected. The job generates an increasing UTC timestamp build number.
4. Approve the `signed-ci-artifact` environment deployment.
5. After the run succeeds, download `MacParakeet-signed-notarized-ci-test` from
   **Artifacts**, expand the GitHub ZIP, open the DMG, and drag the app to
   Applications.

For an independent landing check, run:

```bash
xcrun stapler validate MacParakeet-signed-notarized-ci-test.dmg
hdiutil attach MacParakeet-signed-notarized-ci-test.dmg
codesign --verify --deep --strict /Volumes/MacParakeet/MacParakeet.app
codesign -dv --verbose=4 /Volumes/MacParakeet/MacParakeet.app
spctl --assess --type execute --verbose=4 /Volumes/MacParakeet/MacParakeet.app
xcrun stapler validate /Volumes/MacParakeet/MacParakeet.app
hdiutil detach /Volumes/MacParakeet
```

The signature details must show `TeamIdentifier=GY6L5GL2Z7`, and Gatekeeper must
report a notarized Developer ID source. Then complete the Finder launch check on
a normal Mac.

## 2) Sign + notarize (recommended)

Prereqs:
- A **Developer ID Application** certificate in Keychain.
- `notarytool` credentials stored in Keychain under the profile `AC_PASSWORD` (shared with Oatmeal):

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "developer@example.com" \
  --team-id "GY6L5GL2Z7" \
  --password "app-specific-password"
```

Verify credentials work:

```bash
xcrun notarytool history --keychain-profile "AC_PASSWORD"
```

Then:

```bash
scripts/dist/sign_notarize.sh
```

The script defaults `NOTARYTOOL_PROFILE` to `AC_PASSWORD`. Override with `NOTARYTOOL_PROFILE="other" scripts/dist/sign_notarize.sh` if needed.

Outputs:
- `dist/MacParakeet.app` (signed + stapled)
- `dist/MacParakeet.dmg` (signed + stapled)

## 3) Publish

GitHub Releases on `eli0shin/macparakeet` is the only distribution channel.
Publishing is manual. The release owner builds, signs, notarizes, and verifies
the DMG, then creates a tag and GitHub Release with `MacParakeet.dmg` attached.
Users download from
<https://github.com/eli0shin/macparakeet/releases/latest>.

## Release procedure

### Pre-flight

Before building, verify the codebase is ready:

```bash
# All tests must pass
swift test

# Fresh SwiftPM checkouts must be able to update package submodules. The bundle
# script automatically lends xcodebuild the shell Git helper path when needed.
{ test -n "${GIT_EXEC_PATH:-}" && test -x "$GIT_EXEC_PATH/git-submodule"; } || \
  test -x "$(xcrun git --exec-path)/git-submodule" || \
  test -x "$(env -u GIT_EXEC_PATH git --exec-path)/git-submodule"

# Distribution privacy/entitlement guard runs after signing, but this source
# file is the expected entitlement surface for the final app.
plutil -p scripts/dist/MacParakeet.entitlements

# Check the currently published version
gh release view --repo eli0shin/macparakeet --json tagName -q .tagName
```

### Version

Choose the next semantic version after the latest published tag. The script
accepts `VERSION` and `BUILD_NUMBER` environment variables:

```bash
VERSION=0.1.1 scripts/dist/build_app_bundle.sh   # set version explicitly
scripts/dist/build_app_bundle.sh                   # local/dev only: VERSION defaults to 0.0.0
```

- **Build number**: auto-generated UTC timestamp, always increasing.
- The script's default `0.0.0` is intentionally non-release metadata, and
  `verify_release_version.sh` rejects it during signing so a local bundle
  cannot be mistaken for a release.

### Step 1: Build

```bash
VERSION=X.Y.Z scripts/dist/build_app_bundle.sh
```

For AEC-ready releases, look for `Meeting echo assets verified`; the explicit post-build check is:

```bash
REQUIRE_MEETING_ECHO_ASSETS=1 scripts/dist/verify_meeting_echo_assets.sh dist/MacParakeet.app
```

The script exits with an error if required echo assets fail verification.

### Step 2: Sign + notarize

```bash
scripts/dist/sign_notarize.sh
```

The script defaults `NOTARYTOOL_PROFILE` to `AC_PASSWORD`. It first refuses dev/sentinel bundle versions such as `0.0.0`, `dev`, or `*pdx*`; rebuild with `VERSION=X.Y.Z` before signing. For explicit local diagnostic signing only, set `MACPARAKEET_ALLOW_DEV_VERSION_SIGNING=1`. Both app and DMG are signed, notarized, and stapled. The script submits and polls for completion — **never use `notarytool submit --wait`** (it crashes with a bus error; see gotcha #1 below).

Verify:
```bash
spctl --assess --type execute --verbose=4 dist/MacParakeet.app
# Expected: "accepted / source=Notarized Developer ID"

dist/MacParakeet.app/Contents/Resources/yt-dlp --version
# Expected: prints a yt-dlp version, not a [PYI:ERROR] Python shared library failure

scripts/dev/release_demo_smoke.sh \
  --cli dist/MacParakeet.app/Contents/MacOS/macparakeet-cli \
  --output-dir ".codex/release-demo-smoke/release-X.Y.Z"
# Expected: local health, transcription, and export smoke passes with evidence
```

### Step 3: Verify the DMG

```bash
EXPECTED_TEAM_ID=GY6L5GL2Z7 \
EXPECTED_AUTHORITY="Developer ID Application: Elimelech Oshinsky (GY6L5GL2Z7)" \
  bash scripts/ci/verify_signed_dmg.sh dist/MacParakeet.dmg
```

Then mount it and check the payload:

```bash
hdiutil attach dist/MacParakeet.dmg
bash scripts/ci/verify_downloadable_app.sh /Volumes/MacParakeet/MacParakeet.app
bash scripts/ci/verify_packaged_app_launch.sh /Volumes/MacParakeet/MacParakeet.app
hdiutil detach /Volumes/MacParakeet
```

### Step 4: Create the tag and GitHub Release

Prepare release notes in a file, then publish the exact verified DMG:

```bash
git status --short                       # must be clean
git tag -a vX.Y.Z -m "MacParakeet X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z dist/MacParakeet.dmg \
  --repo eli0shin/macparakeet \
  --verify-tag \
  --title "MacParakeet X.Y.Z" \
  --notes-file /path/to/release-notes.md
```

Confirm that the release asset is present at
<https://github.com/eli0shin/macparakeet/releases/latest> and that its name is
exactly `MacParakeet.dmg`.

### Quick reference (copy-paste)

```bash
# Local verification build — run from macparakeet repo root
swift test                                         # pre-flight: all tests must pass
VERSION=X.Y.Z scripts/dist/build_app_bundle.sh     # set version explicitly
scripts/dist/sign_notarize.sh
EXPECTED_TEAM_ID=GY6L5GL2Z7 \
EXPECTED_AUTHORITY="Developer ID Application: Elimelech Oshinsky (GY6L5GL2Z7)" \
  bash scripts/ci/verify_signed_dmg.sh dist/MacParakeet.dmg
git tag -a vX.Y.Z -m "MacParakeet X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z dist/MacParakeet.dmg --repo eli0shin/macparakeet \
  --verify-tag --title "MacParakeet X.Y.Z" --notes-file /path/to/release-notes.md
```

### Common pitfalls

| Problem | Cause | Fix |
|---------|-------|-----|
| GitHub Release creation fails | The tag is missing, the asset path is wrong, or GitHub authentication is unavailable | Confirm the pushed tag, the verified `dist/MacParakeet.dmg`, and `gh auth status`, then retry `gh release create` |
| `notarytool` auth failure | Keychain profile missing | Run `xcrun notarytool store-credentials "AC_PASSWORD"` (see Step 2 above) |
| Fresh SwiftPM dependency checkout fails with `git: 'submodule' is not a git command` | Xcode's Apple Git cannot find `git-submodule`, even though the shell Git may have it | Re-run `build_app_bundle.sh`; it now detects this mismatch and lends xcodebuild the shell Git helper path. If neither Git has the helper, repair Xcode/Command Line Tools or export `GIT_EXEC_PATH` to a directory containing `git-submodule`. |
| `notarytool` bus error / crash | Using `--wait` flag | **Never use `xcrun notarytool submit --wait`.** Submit without `--wait`, then poll with `xcrun notarytool info <submission-id>`. See gotcha #1 below. |
| `notarytool` stays `In Progress` beyond the normal window | Apple accepted upload but the submission is likely stale/stuck | Stop local pollers, discard release artifacts, rebuild/sign from scratch, and submit a fresh archive. Do not continue from orphaned `In Progress` submissions. See gotcha #1a below. |
| TCC permissions silently fail | User ran app from DMG volume instead of /Applications | DMG must include Applications symlink. See gotcha #3 below. |
| YouTube transcription fails with `[PYI:ERROR] Failed to load Python shared library ... different Team IDs` | Bundled `yt-dlp_macos` was re-signed with hardened runtime but without disabling library validation | Sign `yt-dlp` with `com.apple.security.cs.disable-library-validation=true`, smoke-test `Contents/Resources/yt-dlp --version`, and repair any bad managed copy in Application Support |

### Known gotchas (hard-won lessons)

These are bugs and edge cases discovered during actual releases. Read before your first release.

#### 1. `notarytool --wait` crashes with bus error

**Never use the `--wait` flag** with `xcrun notarytool submit`. It crashes with a bus error (EXC_BAD_ACCESS) on some macOS versions. This is an Apple bug that has persisted across multiple Xcode releases.

**Instead:** Submit without `--wait` and poll for completion:

```bash
# Submit (returns a submission ID)
xcrun notarytool submit dist/MacParakeet.dmg --keychain-profile "AC_PASSWORD"
# Note the submission ID from the output

# Poll until status is "Accepted" or "Invalid"
xcrun notarytool info <SUBMISSION_ID> --keychain-profile "AC_PASSWORD"
```

The `sign_notarize.sh` script already handles this correctly — it submits and polls in a loop. If you're running notarization manually, never add `--wait`.

#### 1a. Restart from clean artifacts if notarization stalls

Normal notarization usually returns `Accepted` in roughly 2-5 minutes. If a
fresh app or DMG submission stays `In Progress` well beyond that window, treat
the submission as stale instead of waiting indefinitely. This can happen even
when `notarytool submit` produced a valid submission ID.

For a clean restart:

```bash
# Stop any local release pollers first.
ps -axo pid,ppid,etime,command | rg 'notarytool|sign_notarize|build_app_bundle|hdiutil'

# Then discard generated release artifacts and rebuild/sign fresh.
rm -rf dist/MacParakeet.app dist/MacParakeet.app.zip \
  dist/MacParakeet.dmg dist/MacParakeet-rw.dmg dist/.dmg-staging
VERSION=X.Y.Z scripts/dist/build_app_bundle.sh
SKIP_NOTARIZE=1 CREATE_DMG=0 scripts/dist/sign_notarize.sh
```

Submit the newly-created archive and poll that exact fresh submission ID. Only staple, package, or publish after a clean `Accepted` response for the
artifact you are actually shipping.

#### 2. DMG must include Applications symlink

Without `ln -s /Applications` in the DMG staging folder, users run the app from `/Volumes/MacParakeet/` instead of `/Applications/`. macOS TCC will not register apps running from a mounted DMG volume — microphone permission requests silently fail, and the app never appears in System Settings > Privacy & Security > Microphone.

The `sign_notarize.sh` script creates this symlink during DMG creation. If building a DMG manually, always include it:

```bash
ln -s /Applications dist/dmg-staging/Applications
```

#### 3. `yt-dlp_macos` is PyInstaller and needs a special signing entitlement

MacParakeet bundles `yt-dlp` as a helper seed. Fresh installs copy that seed
from `Contents/Resources/yt-dlp` into
`~/Library/Application Support/MacParakeet/bin/yt-dlp` before first YouTube
transcription. Existing users may already have a working managed helper, so a
bad bundled seed can appear as a fresh-install-only bug.

The official `yt-dlp_macos` asset is a PyInstaller binary. If the release script
re-signs it with Developer ID + hardened runtime but does not include
`com.apple.security.cs.disable-library-validation=true`, macOS library
validation blocks PyInstaller's extracted embedded `Python.framework` at runtime:

```text
[PYI:ERROR] Failed to load Python shared library ... different Team IDs
```

This fails when a user starts YouTube transcription or opens the YouTube video
playback stream extraction path. It does not affect dictation, local file
transcription, meeting recording, or STT model loading.

Release requirements:
- Sign bundled `yt-dlp` with hardened runtime plus `com.apple.security.cs.disable-library-validation=true`, or do not apply hardened runtime to that helper.
- Smoke-test after signing: `dist/MacParakeet.app/Contents/Resources/yt-dlp --version`.
- If a bad build shipped, repair existing users by replacing
  `~/Library/Application Support/MacParakeet/bin/yt-dlp`; a fixed bundled seed
  alone will not help users who already copied the bad managed helper.

## Privacy Strings and Entitlements

Permission prompts require both the appropriate `Info.plist` usage string and
the matching signed app entitlement when macOS gates access through TCC. The
release signing script runs `scripts/dist/verify_app_privacy_surface.sh` after
codesigning to catch drift before notarization.

| Capability | Info.plist key | Entitlement |
|------------|----------------|-------------|
| Microphone input | `NSMicrophoneUsageDescription` | `com.apple.security.device.audio-input` |
| System audio capture | `NSAudioCaptureUsageDescription` | macOS TCC prompt, no app entitlement |
| Calendar event read access | `NSCalendarsFullAccessUsageDescription` | `com.apple.security.personal-information.calendars` |

Microphone-only meeting capture uses only the Microphone permission and never
triggers the System Audio (Screen Recording) prompt; system audio is requested
only for source modes that capture it.

## Notes

- The scripts default to a single-arch Release build. For a universal binary:

```bash
UNIVERSAL=1 scripts/dist/build_app_bundle.sh
```

- `MacParakeet` requests microphone permission. The app bundle `Info.plist` includes `NSMicrophoneUsageDescription`.
- **Users must install to /Applications before launching.** Running directly from a mounted DMG (`/Volumes/MacParakeet/`) will not register with macOS TCC — the app won't appear in System Settings > Privacy & Security > Microphone, and permission requests will silently fail. The DMG includes an Applications symlink for drag-to-install.
- If a user's microphone permission gets stuck as "Denied", reset it with: `tccutil reset Microphone com.macparakeet.MacParakeet`
