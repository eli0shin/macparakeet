# Development builds

MacParakeet publishes an owner-only development build from successful `main` and manual CI runs.

1. Open the completed CI run in GitHub Actions.
2. Download `MacParakeet-owner-development-build`.
3. Expand the GitHub ZIP with Archive Utility.
4. Open the DMG and drag `MacParakeet.app` to Applications.
5. Remove quarantine from this development build:

```bash
xattr -dr com.apple.quarantine /Applications/MacParakeet.app
```

6. Open the app:

```bash
open /Applications/MacParakeet.app
```

This artifact has a valid ad-hoc signature, but it is not Developer ID signed or Apple-notarized. Use the quarantine-removal command only for a development artifact downloaded from this repository's expected GitHub Actions run. Do not distribute this build to other users.

The separate `MacParakeet-signed-notarized-ci-test` workflow validates the protected Developer ID and notarization path. Official release steps remain in [`distribution.md`](distribution.md).
