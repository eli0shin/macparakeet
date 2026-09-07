#!/bin/bash
set -euo pipefail

REPO="eli0shin/macparakeet"
APPLICATIONS_DIR="${MACPARAKEET_APPLICATIONS_DIR:-/Applications}"
APP_PATH="${APPLICATIONS_DIR}/MacParakeet.app"
CLI_PATH="${APP_PATH}/Contents/MacOS/macparakeet-cli"
BIN_DIR="${HOME}/.local/bin"
CLI_LINK="${BIN_DIR}/macparakeet-cli"

OS="$(uname -s)"
ARCH="$(uname -m)"
if [[ "$OS" != "Darwin" || "$ARCH" != "arm64" ]]; then
  echo "Unsupported system: MacParakeet requires Apple Silicon macOS (found ${OS} ${ARCH})." >&2
  exit 1
fi

version_greater_than() {
  local left="${1#v}" right="${2#v}" index left_part right_part
  local -a left_parts right_parts

  [[ "$left" =~ ^[0-9]+(\.[0-9]+)*$ && "$right" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 2
  IFS=. read -r -a left_parts <<<"$left"
  IFS=. read -r -a right_parts <<<"$right"

  for ((index = 0; index < ${#left_parts[@]} || index < ${#right_parts[@]}; index++)); do
    left_part="${left_parts[index]:-0}"
    right_part="${right_parts[index]:-0}"
    if ((10#$left_part > 10#$right_part)); then
      return 0
    fi
    if ((10#$left_part < 10#$right_part)); then
      return 1
    fi
  done
  return 1
}

LATEST_URL="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
LATEST_VERSION="${LATEST_URL##*/}"
LATEST_VERSION="${LATEST_VERSION#v}"
if [[ ! "$LATEST_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "Could not resolve the latest MacParakeet release version." >&2
  exit 1
fi

INSTALL_APP=0
if [[ ! -d "$APP_PATH" ]]; then
  echo "MacParakeet is not installed. Installing ${LATEST_VERSION}."
  INSTALL_APP=1
else
  if ! INSTALLED_VERSION="$(defaults read "${APP_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null)"; then
    echo "Could not read the installed MacParakeet version." >&2
    exit 1
  fi
  if [[ ! "$INSTALLED_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "The installed MacParakeet version is not a dotted numeric version: ${INSTALLED_VERSION}" >&2
    exit 1
  fi
  if version_greater_than "$LATEST_VERSION" "$INSTALLED_VERSION"; then
    echo "Updating MacParakeet from ${INSTALLED_VERSION} to ${LATEST_VERSION}."
    INSTALL_APP=1
  else
    echo "MacParakeet ${INSTALLED_VERSION} is current or newer; skipping app installation."
  fi
fi

if ((INSTALL_APP)); then
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macparakeet-install.XXXXXX")"
  DMG_PATH="${TEMP_DIR}/MacParakeet.dmg"
  MOUNT_DIR="${TEMP_DIR}/mount"
  MOUNTED=0
  cleanup() {
    if ((MOUNTED)); then
      hdiutil detach "$MOUNT_DIR" -quiet || true
    fi
    rm -rf "$TEMP_DIR"
  }
  trap cleanup EXIT

  mkdir -p "$MOUNT_DIR"
  echo "Downloading MacParakeet.dmg."
  curl -fsSL "https://github.com/${REPO}/releases/latest/download/MacParakeet.dmg" -o "$DMG_PATH"
  hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
  MOUNTED=1

  SOURCE_APP="${MOUNT_DIR}/MacParakeet.app"
  if [[ ! -d "$SOURCE_APP" || ! -x "${SOURCE_APP}/Contents/MacOS/macparakeet-cli" ]]; then
    echo "The release disk image does not contain a complete MacParakeet app." >&2
    exit 1
  fi

  if [[ -w "$APPLICATIONS_DIR" ]]; then
    rm -rf "$APP_PATH"
    ditto "$SOURCE_APP" "$APP_PATH"
  else
    echo "Administrator access is required to install MacParakeet in /Applications."
    sudo rm -rf "$APP_PATH"
    sudo ditto "$SOURCE_APP" "$APP_PATH"
  fi
  echo "Installed MacParakeet ${LATEST_VERSION} at ${APP_PATH}."
fi

mkdir -p "$BIN_DIR"
if [[ -e "$CLI_LINK" && ! -L "$CLI_LINK" ]]; then
  echo "Cannot configure the CLI: ${CLI_LINK} exists and is not a symlink." >&2
  exit 1
fi
ln -sfn "$CLI_PATH" "$CLI_LINK"
echo "Configured ${CLI_LINK} -> ${CLI_PATH}."

case "${SHELL:-/bin/zsh}" in
  */bash)
    if [[ -f "${HOME}/.bash_profile" ]]; then
      PROFILE="${HOME}/.bash_profile"
    elif [[ -f "${HOME}/.bash_login" ]]; then
      PROFILE="${HOME}/.bash_login"
    elif [[ -f "${HOME}/.profile" ]]; then
      PROFILE="${HOME}/.profile"
    else
      PROFILE="${HOME}/.bash_profile"
    fi
    ;;
  *) PROFILE="${HOME}/.zprofile" ;;
esac
PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
path_is_configured() {
  [[ -f "$PROFILE" ]] && {
    grep -Fxq "export PATH=\"\$HOME/.local/bin:\$PATH\"" "$PROFILE" ||
      grep -Fxq "export PATH=\"\$HOME/.local/bin:\${PATH}\"" "$PROFILE" ||
      grep -Fxq "export PATH=\"\${HOME}/.local/bin:\$PATH\"" "$PROFILE" ||
      grep -Fxq "export PATH=\"\${HOME}/.local/bin:\${PATH}\"" "$PROFILE"
  }
}
if ! path_is_configured; then
  printf '\n%s\n' "$PATH_LINE" >>"$PROFILE"
  echo "Added ${BIN_DIR} to PATH in ${PROFILE}."
else
  echo "${BIN_DIR} is already configured in ${PROFILE}."
fi

export PATH="${BIN_DIR}:${PATH}"
echo "Run this in your current shell, then use macparakeet-cli:"
printf '  %s\n' "$PATH_LINE"
