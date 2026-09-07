#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${GITHUB_REPOSITORY:-eli0shin/macparakeet}"
TARGET_SHA="${TARGET_SHA:-}"

if [[ -z "$TARGET_SHA" ]]; then
  echo "error: TARGET_SHA is required." >&2
  exit 1
fi

latest_tag=""
while IFS= read -r candidate; do
  if [[ "$candidate" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    latest_tag="$candidate"
    break
  fi
done < <(git tag --merged "$TARGET_SHA" --sort=-version:refname)

[[ -n "$latest_tag" ]] || exit 0

release_response=""
release_status=0
release_response="$(
  gh api --include "repos/$REPOSITORY/releases/tags/$latest_tag" 2>&1
)" || release_status=$?

if [[ "$release_status" -eq 0 ]]; then
  exit 0
fi
if ! grep -Eq '(HTTP/[^ ]+ 404|HTTP 404)' <<<"$release_response"; then
  printf '%s\n' "$release_response" >&2
  exit "$release_status"
fi

tag_type="$(git cat-file -t "$latest_tag")"
annotation="$(git tag -l "$latest_tag" --format='%(contents)')"
if [[ "$tag_type" != "tag" || \
      "$annotation" != "MacParakeet automated release $latest_tag" ]]; then
  echo "Preserving version tag without a GitHub Release: $latest_tag"
  exit 0
fi

draft_id="$(
  gh api --paginate "repos/$REPOSITORY/releases?per_page=100" \
    --jq ".[] | select(.tag_name == \"$latest_tag\" and .draft == true) | .id" | \
    head -1
)"
if [[ -n "$draft_id" ]]; then
  gh api --method DELETE "repos/$REPOSITORY/releases/$draft_id"
fi
git push origin ":refs/tags/$latest_tag"
git tag -d "$latest_tag"
echo "Removed interrupted automated release tag: $latest_tag"
