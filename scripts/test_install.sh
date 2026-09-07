#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/macparakeet-install-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

pass_count=0
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() {
  pass_count=$((pass_count + 1))
  echo "PASS: $*"
}
assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"
}
assert_file_contains_once() {
  local count
  count="$(grep -Fxc "$2" "$1" || true)"
  [[ "$count" == "1" ]] || fail "expected one '$2' entry in $1, found $count"
}

EXPECTED_PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""

make_mocks() {
  local directory="$1"
  mkdir -p "$directory"

  cat >"$directory/uname" <<'MOCK'
#!/bin/bash
if [[ "$1" == "-s" ]]; then
  echo "${TEST_OS:-Darwin}"
else
  echo "${TEST_ARCH:-arm64}"
fi
MOCK

  cat >"$directory/curl" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG/curl"
if [[ "$*" == *"releases/latest/download/MacParakeet.dmg"* ]]; then
  while (($#)); do
    if [[ "$1" == "-o" ]]; then
      : >"$2"
      exit 0
    fi
    shift
  done
  exit 1
fi
printf 'https://github.com/eli0shin/macparakeet/releases/tag/v%s' "$TEST_LATEST_VERSION"
MOCK

  cat >"$directory/defaults" <<'MOCK'
#!/bin/bash
cat "${2}.test-version"
MOCK

  cat >"$directory/hdiutil" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG/hdiutil"
if [[ "$1" == "attach" ]]; then
  while (($#)); do
    if [[ "$1" == "-mountpoint" ]]; then
      mount_point="$2"
      break
    fi
    shift
  done
  app="$mount_point/MacParakeet.app"
  mkdir -p "$app/Contents/MacOS"
  printf '%s\n' "$TEST_LATEST_VERSION" >"$app/Contents/Info.test-version"
  printf '#!/bin/bash\n' >"$app/Contents/MacOS/macparakeet-cli"
  chmod +x "$app/Contents/MacOS/macparakeet-cli"
fi
MOCK

  cat >"$directory/ditto" <<'MOCK'
#!/bin/bash
cp -R "$1" "$2"
MOCK

  chmod +x "$directory"/*
}

new_case() {
  CASE_DIR="$(mktemp -d "$TEST_ROOT/case.XXXXXX")"
  HOME_DIR="$CASE_DIR/home"
  APPLICATIONS_DIR="$CASE_DIR/Applications"
  MOCK_DIR="$CASE_DIR/mocks"
  TEST_LOG="$CASE_DIR/log"
  mkdir -p "$HOME_DIR" "$APPLICATIONS_DIR" "$TEST_LOG"
  make_mocks "$MOCK_DIR"
}

seed_install() {
  local version="$1" marker="${2:-}"
  local app="$APPLICATIONS_DIR/MacParakeet.app"
  mkdir -p "$app/Contents/MacOS"
  printf '%s\n' "$version" >"$app/Contents/Info.test-version"
  printf '#!/bin/bash\n' >"$app/Contents/MacOS/macparakeet-cli"
  chmod +x "$app/Contents/MacOS/macparakeet-cli"
  if [[ -n "$marker" ]]; then
    printf '%s\n' "$marker" >"$app/$marker"
  fi
}

run_installer() {
  env \
    HOME="$HOME_DIR" \
    SHELL="${TEST_SHELL:-/bin/zsh}" \
    PATH="$MOCK_DIR:/usr/bin:/bin" \
    TEST_LOG="$TEST_LOG" \
    TEST_LATEST_VERSION="$TEST_LATEST_VERSION" \
    TEST_OS="${TEST_OS:-Darwin}" \
    TEST_ARCH="${TEST_ARCH:-arm64}" \
    MACPARAKEET_APPLICATIONS_DIR="$APPLICATIONS_DIR" \
    /bin/bash "$ROOT/install.sh" 2>&1
}

new_case
TEST_LATEST_VERSION="1.2.3"
output="$(run_installer)"
[[ "$(cat "$APPLICATIONS_DIR/MacParakeet.app/Contents/Info.test-version")" == "1.2.3" ]] || fail "absent app was not installed"
[[ "$(readlink "$HOME_DIR/.local/bin/macparakeet-cli")" == "$APPLICATIONS_DIR/MacParakeet.app/Contents/MacOS/macparakeet-cli" ]] || fail "CLI symlink has the wrong target"
assert_contains "$output" "MacParakeet is not installed"
pass "absent installation and CLI symlink setup"

new_case
TEST_LATEST_VERSION="2.0.0"
seed_install "1.9.9" "old-install"
output="$(run_installer)"
[[ ! -e "$APPLICATIONS_DIR/MacParakeet.app/old-install" ]] || fail "older app was not replaced"
assert_contains "$output" "Updating MacParakeet from 1.9.9 to 2.0.0"
pass "older installation update"

new_case
TEST_LATEST_VERSION="1.10.0"
seed_install "1.9.9" "old-install"
run_installer >/dev/null
[[ ! -e "$APPLICATIONS_DIR/MacParakeet.app/old-install" ]] || fail "numeric dotted update was compared lexically"
pass "dotted versions are compared numerically"

for installed in 1.10.0 2.0.0; do
  new_case
  TEST_LATEST_VERSION="1.10.0"
  seed_install "$installed" "preserve-me"
  output="$(run_installer)"
  [[ -e "$APPLICATIONS_DIR/MacParakeet.app/preserve-me" ]] || fail "$installed installation was replaced"
  assert_contains "$output" "is current or newer; skipping app installation"
done
pass "equal and newer installations are skipped"

new_case
TEST_LATEST_VERSION="3.0.0"
TEST_SHELL="/bin/zsh"
seed_install "3.0.0"
mkdir -p "$HOME_DIR/.local/bin"
ln -s /wrong/target "$HOME_DIR/.local/bin/macparakeet-cli"
printf '# %s\n' "$EXPECTED_PATH_LINE" >"$HOME_DIR/.zprofile"
run_installer >/dev/null
run_installer >/dev/null
assert_file_contains_once "$HOME_DIR/.zprofile" "$EXPECTED_PATH_LINE"
[[ "$(readlink "$HOME_DIR/.local/bin/macparakeet-cli")" == "$APPLICATIONS_DIR/MacParakeet.app/Contents/MacOS/macparakeet-cli" ]] || fail "existing CLI symlink was not repaired"
[[ ! -f "$TEST_LOG/hdiutil" ]] || fail "repeated current install mounted a DMG"
pass "repeated zsh setup is idempotent and repairs the CLI symlink"

equivalent_path_lines=(
  "export PATH=\"\$HOME/.local/bin:\${PATH}\""
  "export PATH=\"\${HOME}/.local/bin:\$PATH\""
  "export PATH=\"\${HOME}/.local/bin:\${PATH}\""
)
for path_line in "${equivalent_path_lines[@]}"; do
  new_case
  TEST_LATEST_VERSION="3.0.0"
  TEST_SHELL="/bin/zsh"
  seed_install "3.0.0"
  printf '%s\n' "$path_line" >"$HOME_DIR/.zprofile"
  run_installer >/dev/null
  run_installer >/dev/null
  [[ "$(cat "$HOME_DIR/.zprofile")" == "$path_line" ]] || fail "equivalent PATH entry was duplicated: $path_line"
done
pass "equivalent HOME and PATH forms remain idempotent"

new_case
TEST_LATEST_VERSION="3.0.0"
TEST_SHELL="/bin/bash"
seed_install "3.0.0"
run_installer >/dev/null
run_installer >/dev/null
assert_file_contains_once "$HOME_DIR/.bash_profile" "$EXPECTED_PATH_LINE"
pass "bash PATH setup is idempotent"

new_case
TEST_LATEST_VERSION="3.0.0"
TEST_SHELL="/bin/bash"
seed_install "3.0.0"
printf 'export EXISTING_SETTING=kept\n' >"$HOME_DIR/.profile"
run_installer >/dev/null
[[ ! -e "$HOME_DIR/.bash_profile" ]] || fail "installer masked an existing Bash profile"
assert_file_contains_once "$HOME_DIR/.profile" "$EXPECTED_PATH_LINE"
pass "bash setup preserves the existing login profile"

new_case
TEST_LATEST_VERSION="3.0.0"
TEST_SHELL="/bin/zsh"
seed_install "3.0.0"
mkdir -p "$HOME_DIR/.local/bin"
printf 'keep me\n' >"$HOME_DIR/.local/bin/macparakeet-cli"
if run_installer >/dev/null; then
  fail "installer replaced a non-symlink CLI file"
fi
[[ "$(cat "$HOME_DIR/.local/bin/macparakeet-cli")" == "keep me" ]] || fail "non-symlink CLI file changed"
pass "non-symlink CLI file is preserved"

for platform in "Linux arm64" "Darwin x86_64"; do
  new_case
  TEST_LATEST_VERSION="3.0.0"
  TEST_OS="${platform% *}"
  TEST_ARCH="${platform#* }"
  if output="$(run_installer)"; then
    fail "unsupported system $platform succeeded"
  fi
  assert_contains "$output" "requires Apple Silicon macOS"
done
pass "unsupported systems fail clearly"

echo "All $pass_count installer tests passed."
