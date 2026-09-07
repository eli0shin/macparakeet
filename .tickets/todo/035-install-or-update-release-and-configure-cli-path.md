---
Assigned-To:
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

# Install or update MacParakeet and configure the CLI path

## Goal

Add a simple repository-root `install.sh`, shaped like `../repos/install.sh`, that users run with:

```bash
curl -fsSL https://raw.githubusercontent.com/eli0shin/macparakeet/main/install.sh | bash
```

The script installs or updates `MacParakeet.app` from this repository's latest GitHub Release and makes the CLI available on `PATH`.

## Required behavior

- Run on Apple Silicon macOS and fail clearly on unsupported systems.
- Resolve the latest release version from `eli0shin/macparakeet`.
- Read the currently installed version from `/Applications/MacParakeet.app` when it exists.
- Download and install `MacParakeet.dmg` when the app is not installed.
- Download and install it when the latest release version is greater than the installed version.
- Do not replace the app when the installed version is equal to or greater than the latest release version.
- Compare dotted versions numerically, not lexically.
- Install the app at `/Applications/MacParakeet.app`.
- Do not launch the app automatically.
- Always configure or repair CLI access, including when the app install is skipped.

## CLI path setup

- The CLI remains inside the app at `/Applications/MacParakeet.app/Contents/MacOS/macparakeet-cli`.
- Create `$HOME/.local/bin` when needed.
- Create or update `$HOME/.local/bin/macparakeet-cli` as a symlink to the bundled CLI.
- Do not replace a non-symlink file at that location.
- Add `$HOME/.local/bin` to the user's zsh or bash PATH when needed.
- Do not add duplicate PATH entries on repeated runs.
- Print what was installed or skipped and how to use `macparakeet-cli` in the current shell.

## Constraints

- The script must be self-contained because it runs from stdin without a checkout.
- Keep the implementation small and direct, like `../repos/install.sh`.
- Do not require Homebrew, `jq`, repository build tools, or a cloned checkout.
- Repeated runs must be idempotent.
- Do not add unrelated installation features or refactor existing packaging and release workflows.

## Verification

- Add focused tests for absent installation, older-version update, equal/newer-version skip, dotted numeric version comparison, CLI symlink setup, PATH setup, repeated execution, and unsupported systems.
- Tests must use isolated temporary paths and must not modify the real `/Applications` or home directory.
- Update the primary installation documentation with the exact `curl -fsSL ... | bash` command.

## Acceptance criteria

- [ ] The exact `curl | bash` command works without a checkout.
- [ ] An absent app is installed from the latest GitHub Release.
- [ ] An older app is updated, while an equal or newer app is left unchanged.
- [ ] `$HOME/.local/bin/macparakeet-cli` points to the CLI in the installed app.
- [ ] zsh and bash PATH setup is idempotent.
- [ ] The script remains small, self-contained, and consistent with `../repos/install.sh`.
- [ ] Focused isolated tests pass.
- [ ] The README contains the supported install command.
