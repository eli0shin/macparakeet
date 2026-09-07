#!/usr/bin/env bash
# Shared packaging function. Source from app builders before signing.
# Caller supplies ROOT_DIR. Arguments: app bundle path, universal build (0/1).

bundle_meeting_echo_assets() {
  local APP_DIR="$1"
  local UNIVERSAL="${2:-0}"
  local FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
  local RESOURCES_DIR="$APP_DIR/Contents/Resources"
  local DEFAULT_MEETING_ECHO_ASSETS_DIR="$ROOT_DIR/.build/meeting-echo-assets"
  . "$ROOT_DIR/scripts/dist/meeting_echo_asset_defaults.sh"
  local should_bundle="${BUNDLE_MEETING_ECHO_ASSETS:-}"
  if [[ -z "$should_bundle" ]]; then
    if [[ "${REQUIRE_MEETING_ECHO_ASSETS:-0}" == "1" ||
          -n "${MACPARAKEET_MEETING_ECHO_LIBRARY:-}" ||
          -n "${MACPARAKEET_MEETING_ECHO_MODEL:-}" ]]; then
      should_bundle="1"
    else
      should_bundle="0"
    fi
  fi

  if [[ "$should_bundle" != "0" && "$should_bundle" != "1" ]]; then
    echo "Error: BUNDLE_MEETING_ECHO_ASSETS must be 0 or 1." >&2
    exit 1
  fi

  if [[ "$should_bundle" != "1" ]]; then
    if [[ "${REQUIRE_MEETING_ECHO_ASSETS:-0}" == "1" ]]; then
      echo "Error: REQUIRE_MEETING_ECHO_ASSETS=1 but BUNDLE_MEETING_ECHO_ASSETS=0." >&2
      exit 1
    fi
    echo "Skipping meeting echo-suppression assets (BUNDLE_MEETING_ECHO_ASSETS=0)"
    return 0
  fi

  local library_src="${MACPARAKEET_MEETING_ECHO_LIBRARY:-}"
  local model_src="${MACPARAKEET_MEETING_ECHO_MODEL:-}"
  local model_name="${MACPARAKEET_MEETING_ECHO_MODEL_NAME:-}"
  local expected_model_sha="${MACPARAKEET_MEETING_ECHO_MODEL_SHA256:-}"
  local dependent_dylib_dir="${MACPARAKEET_MEETING_ECHO_DYLIB_DIR:-}"

  if [[ -z "$library_src" && -z "$model_src" ]]; then
    if [[ "${MACPARAKEET_MEETING_ECHO_AUTO_PREPARE:-1}" != "1" ]]; then
      echo "Error: meeting echo asset paths are unset and MACPARAKEET_MEETING_ECHO_AUTO_PREPARE=0." >&2
      exit 1
    fi

    local prepared_assets_dir="${MACPARAKEET_MEETING_ECHO_ASSETS_DIR:-$DEFAULT_MEETING_ECHO_ASSETS_DIR}"
    local prepared_model_name="${model_name:-$DEFAULT_MEETING_ECHO_MODEL_NAME}"
    local prepared_model_sha="$expected_model_sha"
    if [[ "$prepared_model_name" == "$DEFAULT_MEETING_ECHO_MODEL_NAME" ]]; then
      prepared_model_sha="${prepared_model_sha:-$DEFAULT_MEETING_ECHO_MODEL_SHA256}"
    elif [[ -z "$prepared_model_sha" ]]; then
      echo "Error: custom auto-prepared meeting echo models require MACPARAKEET_MEETING_ECHO_MODEL_SHA256." >&2
      exit 1
    fi
    echo "Preparing bundled meeting echo assets in $prepared_assets_dir"
    MACPARAKEET_MEETING_ECHO_ASSETS_DIR="$prepared_assets_dir" \
      MACPARAKEET_MEETING_ECHO_MODEL_NAME="$prepared_model_name" \
      MACPARAKEET_MEETING_ECHO_MODEL_SHA256="$prepared_model_sha" \
      MACPARAKEET_MEETING_ECHO_UNIVERSAL="${MACPARAKEET_MEETING_ECHO_UNIVERSAL:-$UNIVERSAL}" \
      "$ROOT_DIR/scripts/dist/prepare_meeting_echo_assets.sh"

    library_src="$prepared_assets_dir/lib/liblocalvqe.dylib"
    model_src="$prepared_assets_dir/model/$prepared_model_name"
    model_name="$prepared_model_name"
    expected_model_sha="$prepared_model_sha"
    dependent_dylib_dir="${dependent_dylib_dir:-$prepared_assets_dir/lib}"
  elif [[ -z "$library_src" || -z "$model_src" ]]; then
    echo "Error: MACPARAKEET_MEETING_ECHO_LIBRARY and MACPARAKEET_MEETING_ECHO_MODEL must be set together." >&2
    exit 1
  fi

  if [[ -z "$library_src" || ! -f "$library_src" ]]; then
    echo "Error: MACPARAKEET_MEETING_ECHO_LIBRARY must point to a dylib when bundling echo assets." >&2
    exit 1
  fi
  if [[ -z "$model_src" || ! -f "$model_src" ]]; then
    echo "Error: MACPARAKEET_MEETING_ECHO_MODEL must point to a GGUF model when bundling echo assets." >&2
    exit 1
  fi

  model_name="${model_name:-$(basename "$model_src")}"
  local model_name_lc
  model_name_lc="$(printf '%s' "$model_name" | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$model_name" || "$model_name" == */* || "$model_name_lc" != *.gguf ]]; then
    echo "Error: MACPARAKEET_MEETING_ECHO_MODEL_NAME must be a GGUF filename, not a path." >&2
    exit 1
  fi
  if [[ -z "$expected_model_sha" && "$model_name" == "$DEFAULT_MEETING_ECHO_MODEL_NAME" ]]; then
    expected_model_sha="$DEFAULT_MEETING_ECHO_MODEL_SHA256"
  fi
  if [[ "${REQUIRE_MEETING_ECHO_ASSETS:-0}" == "1" && -z "$expected_model_sha" ]]; then
    echo "Error: REQUIRE_MEETING_ECHO_ASSETS=1 requires MACPARAKEET_MEETING_ECHO_MODEL_SHA256." >&2
    exit 1
  fi

  if [[ -n "$expected_model_sha" ]]; then
    local actual_sha
    local expected_sha_lc
    actual_sha="$(shasum -a 256 "$model_src" | awk '{print $1}')"
    expected_sha_lc="$(printf '%s' "$expected_model_sha" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    if [[ "$actual_sha" != "$expected_sha_lc" ]]; then
      echo "Error: meeting echo model SHA256 verification failed." >&2
      echo "  Expected: $expected_model_sha" >&2
      echo "  Actual:   $actual_sha" >&2
      exit 1
    fi
    echo "Meeting echo model SHA256 verified: $actual_sha"
  fi

  mkdir -p "$FRAMEWORKS_DIR" "$RESOURCES_DIR"
  if [[ -n "$dependent_dylib_dir" ]]; then
    if [[ ! -d "$dependent_dylib_dir" ]]; then
      echo "Error: MACPARAKEET_MEETING_ECHO_DYLIB_DIR is not a directory: $dependent_dylib_dir" >&2
      exit 1
    fi
    while IFS= read -r -d '' dylib; do
      install -m 0755 "$dylib" "$FRAMEWORKS_DIR/$(basename "$dylib")"
    done < <(find "$dependent_dylib_dir" -maxdepth 1 -type f -name '*.dylib' -print0)
  fi

  install -m 0755 "$library_src" "$FRAMEWORKS_DIR/liblocalvqe.dylib"
  if command -v install_name_tool >/dev/null 2>&1; then
    install_name_tool -id "@rpath/liblocalvqe.dylib" "$FRAMEWORKS_DIR/liblocalvqe.dylib"
  else
    echo "Warning: install_name_tool is not available; leaving meeting echo runtime install name unchanged." >&2
  fi
  # Dev bundles are reused. Remove old derived models so a model switch cannot
  # leave multiple GGUF files and make asset selection ambiguous.
  rm -rf "$RESOURCES_DIR/MeetingEchoSuppression"
  mkdir -p "$RESOURCES_DIR/MeetingEchoSuppression"
  install -m 0644 "$model_src" "$RESOURCES_DIR/MeetingEchoSuppression/$model_name"
  echo "Bundled meeting echo runtime: $FRAMEWORKS_DIR/liblocalvqe.dylib"
  echo "Bundled meeting echo model: $RESOURCES_DIR/MeetingEchoSuppression/$model_name"

  MACPARAKEET_MEETING_ECHO_MODEL_NAME="$model_name" \
    MACPARAKEET_MEETING_ECHO_MODEL_SHA256="$expected_model_sha" \
    "$ROOT_DIR/scripts/dist/verify_meeting_echo_assets.sh" "$APP_DIR"
}

