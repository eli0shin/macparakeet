#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRUSTED_DMG="$ROOT_DIR/dist/MacParakeet-signed-notarized-ci-test.dmg"
NOTARYTOOL_PROFILE="macparakeet-ci-${GITHUB_RUN_ID:-local}-$$"
KEYCHAIN_PATH="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/macparakeet-signing-${GITHUB_RUN_ID:-local}-$$.keychain-db"
CERTIFICATE_PATH="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/macparakeet-developer-id-${GITHUB_RUN_ID:-local}-$$.p12"
KEYCHAIN_PASSWORD=""

fail() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  rm -f "$CERTIFICATE_PATH"
  if [[ -n "$KEYCHAIN_PASSWORD" ]]; then
    security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  fi
  rm -f "$KEYCHAIN_PATH"
}
trap cleanup EXIT INT TERM

required_variables=(
  SIGNED_ARTIFACT_VERSION
  SIGNED_ARTIFACT_BUILD_NUMBER
  DEVELOPMENT_ID_CERTIFICATE_BASE64
  DEVELOPMENT_ID_CERTIFICATE_PASSWORD
  DEVELOPER_ID_APPLICATION_IDENTITY
  APPLE_TEAM_ID
  NOTARY_APPLE_ID
  NOTARY_APP_SPECIFIC_PASSWORD
)
for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    fail "Required signing input $variable_name is missing. Configure it in the signed-ci-artifact GitHub environment."
  fi
done

if ! [[ "$SIGNED_ARTIFACT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$SIGNED_ARTIFACT_VERSION" == "0.0.0" ]]; then
  fail "SIGNED_ARTIFACT_VERSION must be an explicit non-sentinel X.Y.Z version."
fi
if ! [[ "$SIGNED_ARTIFACT_BUILD_NUMBER" =~ ^[0-9]{14}$ ]]; then
  fail "SIGNED_ARTIFACT_BUILD_NUMBER must be a 14-digit UTC timestamp."
fi
if [[ "$APPLE_TEAM_ID" != "FYAF2ZD7RM" ]]; then
  fail "APPLE_TEAM_ID must be the MacParakeet distribution team FYAF2ZD7RM."
fi
if [[ "$DEVELOPER_ID_APPLICATION_IDENTITY" != "Developer ID Application: "*" ($APPLE_TEAM_ID)" ]]; then
  fail "DEVELOPER_ID_APPLICATION_IDENTITY must be a Developer ID Application identity for APPLE_TEAM_ID."
fi

rm -f "$TRUSTED_DMG" "$KEYCHAIN_PATH" "$CERTIFICATE_PATH"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 7200 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

if ! printf '%s' "$DEVELOPMENT_ID_CERTIFICATE_BASE64" | base64 --decode >"$CERTIFICATE_PATH"; then
  fail "DEVELOPMENT_ID_CERTIFICATE_BASE64 is not valid base64."
fi
security import "$CERTIFICATE_PATH" -k "$KEYCHAIN_PATH" \
  -P "$DEVELOPMENT_ID_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
rm -f "$CERTIFICATE_PATH"
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null

identity_output="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH")"
if ! grep -Fq "\"$DEVELOPER_ID_APPLICATION_IDENTITY\"" <<<"$identity_output"; then
  echo "$identity_output" >&2
  fail "The imported certificate does not contain the configured Developer ID Application identity."
fi

xcrun notarytool store-credentials "$NOTARYTOOL_PROFILE" \
  --apple-id "$NOTARY_APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$NOTARY_APP_SPECIFIC_PASSWORD" \
  --keychain "$KEYCHAIN_PATH"
xcrun notarytool history \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --keychain "$KEYCHAIN_PATH" >/dev/null

cd "$ROOT_DIR"
VERSION="$SIGNED_ARTIFACT_VERSION" \
BUILD_NUMBER="$SIGNED_ARTIFACT_BUILD_NUMBER" \
BUILD_SOURCE="github-actions-signed-notarized-ci-test" \
BUILD_SYSTEM=swiftpm \
REQUIRE_MEETING_ECHO_ASSETS=1 \
  bash scripts/dist/build_app_bundle.sh

SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION_IDENTITY" \
SIGN_KEYCHAIN="$KEYCHAIN_PATH" \
NOTARYTOOL_PROFILE="$NOTARYTOOL_PROFILE" \
NOTARYTOOL_KEYCHAIN="$KEYCHAIN_PATH" \
EXPECTED_TEAM_ID="$APPLE_TEAM_ID" \
EXPECTED_AUTHORITY="$DEVELOPER_ID_APPLICATION_IDENTITY" \
  bash scripts/dist/sign_notarize.sh

EXPECTED_TEAM_ID="$APPLE_TEAM_ID" \
EXPECTED_AUTHORITY="$DEVELOPER_ID_APPLICATION_IDENTITY" \
  bash scripts/ci/verify_signed_dmg.sh dist/MacParakeet.dmg

mv dist/MacParakeet.dmg "$TRUSTED_DMG"
echo "Protected signed CI test artifact is ready: $TRUSTED_DMG"
