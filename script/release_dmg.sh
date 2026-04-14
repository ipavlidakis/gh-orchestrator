#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="${APP_NAME:-GHOrchestrator}"
SCHEME="${SCHEME:-$APP_NAME}"
BUNDLE_ID="${BUNDLE_ID:-com.ipavlidakis.GHOrchestrator}"
WORKSPACE_PATH="${WORKSPACE_PATH:-$REPO_ROOT/GHOrchestrator.xcworkspace}"
REPOSITORY_DEFAULT="${GITHUB_REPOSITORY:-ipavlidakis/gh-orchestrator}"
DEFAULT_CONFIG_PATH="$REPO_ROOT/Config/Release.local.json"

VERSION=""
BUILD_NUMBER=""
RELEASE_TAG=""
RELEASE_NAME=""
RELEASE_NOTES_FILE=""
OUTPUT_DIR=""
REPOSITORY="$REPOSITORY_DEFAULT"
TARGET_COMMITISH="$(git -C "$REPO_ROOT" rev-parse HEAD)"
CONFIG_PATH="$DEFAULT_CONFIG_PATH"

APPLE_DEVELOPER_TEAM_ID="${APPLE_DEVELOPER_TEAM_ID:-}"
APPLE_DEVELOPER_ID_APPLICATION="${APPLE_DEVELOPER_ID_APPLICATION:-}"
APPLE_NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GH_ORCHESTRATOR_GITHUB_CLIENT_ID="${GH_ORCHESTRATOR_GITHUB_CLIENT_ID:-}"

CREATE_RELEASE=false
UPLOAD_RELEASE=false
DRAFT_RELEASE=false
PRERELEASE=false
SKIP_NOTARIZATION=false
DRY_RUN=false
ALLOW_DIRTY=false

usage() {
  cat <<'EOF'
Usage: release_dmg.sh [--config <json>] --version <version> --build <build>
                      [--tag <tag>] [--release-name <name>] [--release-notes-file <file>]
                      [--repo <owner/name>] [--output-dir <dir>]
                      [--upload] [--create-release] [--draft] [--prerelease]
                      [--skip-notarization] [--allow-dirty] [--dry-run]

If Config/Release.local.json exists, the script loads it automatically and
CLI flags override file values.

Environment:
  APPLE_DEVELOPER_TEAM_ID
  APPLE_DEVELOPER_ID_APPLICATION
  APPLE_NOTARY_PROFILE
  GH_ORCHESTRATOR_GITHUB_CLIENT_ID
  GITHUB_TOKEN                Required only with --upload
EOF
}

info() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

run() {
  printf '+'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'

  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi

  "$@"
}

run_capture() {
  if [[ "$DRY_RUN" == true ]]; then
    die "run_capture cannot be used in dry-run mode"
  fi

  "$@"
}

validate_gatekeeper_context() {
  local artifact_path="$1"
  local output_file
  local status

  output_file="$(make_temp_file)"

  if [[ "$DRY_RUN" == true ]]; then
    printf '+ %q %q %q %q\n' spctl -a -vv -t open "$artifact_path"
    return 0
  fi

  set +e
  spctl -a -vv -t open "$artifact_path" >"$output_file" 2>&1
  status=$?
  set -e

  cat "$output_file"

  if [[ $status -eq 0 ]]; then
    rm -f "$output_file"
    return 0
  fi

  if grep -q "source=Insufficient Context" "$output_file"; then
    info "warning: Gatekeeper returned 'Insufficient Context' for the local DMG path; continuing because notarization and stapler validation already succeeded."
    rm -f "$output_file"
    return 0
  fi

  rm -f "$output_file"
  return "$status"
}

urlencode() {
  /usr/bin/python3 - "$1" <<'PY'
import sys
from urllib.parse import quote

print(quote(sys.argv[1], safe=""))
PY
}

json_field() {
  /usr/bin/python3 - "$1" "$2" <<'PY'
import json
import sys

path = sys.argv[2].split(".")
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    value = json.load(handle)

for part in path:
    if isinstance(value, list):
        value = value[int(part)]
    else:
        value = value.get(part)
    if value is None:
        break

if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

json_bool_field() {
  local file_path="$1"
  local field_path="$2"
  local default_value="$3"
  local value

  value="$(json_field "$file_path" "$field_path")"
  if [[ -z "$value" ]]; then
    printf '%s\n' "$default_value"
    return 0
  fi

  case "$value" in
    true|false)
      printf '%s\n' "$value"
      ;;
    *)
      printf '%s\n' "$default_value"
      ;;
  esac
}

json_asset_id_by_name() {
  /usr/bin/python3 - "$1" "$2" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

name = sys.argv[2]
for asset in payload.get("assets", []):
    if asset.get("name") == name:
        print(asset["id"])
        break
else:
    print("")
PY
}

make_temp_file() {
  mktemp "${TMPDIR:-/tmp}/ghorchestrator-release.XXXXXX"
}

ensure_clean_worktree() {
  if [[ "$ALLOW_DIRTY" == true ]]; then
    return
  fi

  if [[ -n "$(git -C "$REPO_ROOT" status --short)" ]]; then
    die "worktree is dirty; commit or stash changes, or pass --allow-dirty"
  fi
}

ensure_workspace() {
  if [[ ! -d "$WORKSPACE_PATH" ]]; then
    run tuist generate --no-open
  else
    run tuist generate --no-open
  fi
}

load_config() {
  local config_path="$1"

  if [[ -z "$config_path" || ! -f "$config_path" ]]; then
    return
  fi

  info "Loading release config from $config_path"

  [[ -n "$RELEASE_NOTES_FILE" ]] || RELEASE_NOTES_FILE="$(json_field "$config_path" "releaseNotesFile")"
  [[ -n "$OUTPUT_DIR" ]] || OUTPUT_DIR="$(json_field "$config_path" "outputDir")"
  if [[ "$REPOSITORY" == "$REPOSITORY_DEFAULT" ]]; then
    local config_repo
    config_repo="$(json_field "$config_path" "repo")"
    [[ -n "$config_repo" ]] && REPOSITORY="$config_repo"
  fi

  local config_target_commitish
  config_target_commitish="$(json_field "$config_path" "targetCommitish")"
  if [[ -n "$config_target_commitish" && "$TARGET_COMMITISH" == "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]]; then
    TARGET_COMMITISH="$config_target_commitish"
  fi

  [[ -n "$APPLE_DEVELOPER_TEAM_ID" ]] || APPLE_DEVELOPER_TEAM_ID="$(json_field "$config_path" "appleDeveloperTeamID")"
  [[ -n "$APPLE_DEVELOPER_ID_APPLICATION" ]] || APPLE_DEVELOPER_ID_APPLICATION="$(json_field "$config_path" "appleDeveloperIDApplication")"
  [[ -n "$APPLE_NOTARY_PROFILE" ]] || APPLE_NOTARY_PROFILE="$(json_field "$config_path" "appleNotaryProfile")"
  [[ -n "$GH_ORCHESTRATOR_GITHUB_CLIENT_ID" ]] || GH_ORCHESTRATOR_GITHUB_CLIENT_ID="$(json_field "$config_path" "githubOAuthClientID")"
  [[ -n "$GITHUB_TOKEN" ]] || GITHUB_TOKEN="$(json_field "$config_path" "githubToken")"

  if [[ "$CREATE_RELEASE" == false ]]; then
    CREATE_RELEASE="$(json_bool_field "$config_path" "createRelease" "false")"
  fi
  if [[ "$UPLOAD_RELEASE" == false ]]; then
    UPLOAD_RELEASE="$(json_bool_field "$config_path" "upload" "false")"
  fi
  if [[ "$DRAFT_RELEASE" == false ]]; then
    DRAFT_RELEASE="$(json_bool_field "$config_path" "draft" "false")"
  fi
  if [[ "$PRERELEASE" == false ]]; then
    PRERELEASE="$(json_bool_field "$config_path" "prerelease" "false")"
  fi
  if [[ "$SKIP_NOTARIZATION" == false ]]; then
    SKIP_NOTARIZATION="$(json_bool_field "$config_path" "skipNotarization" "false")"
  fi
  if [[ "$ALLOW_DIRTY" == false ]]; then
    ALLOW_DIRTY="$(json_bool_field "$config_path" "allowDirty" "false")"
  fi
}

preflight() {
  [[ -n "$VERSION" ]] || die "--version is required"
  [[ -n "$BUILD_NUMBER" ]] || die "--build is required"
  [[ -n "$GH_ORCHESTRATOR_GITHUB_CLIENT_ID" ]] || die "GH_ORCHESTRATOR_GITHUB_CLIENT_ID must be set for shipped builds"

  [[ -n "$RELEASE_TAG" ]] || RELEASE_TAG="$VERSION"
  [[ -n "$RELEASE_NAME" ]] || RELEASE_NAME="$VERSION"

  if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$REPO_ROOT/build/release/${VERSION}-${BUILD_NUMBER}"
  fi

  if [[ "$UPLOAD_RELEASE" == true ]]; then
    [[ -n "$GITHUB_TOKEN" ]] || die "GITHUB_TOKEN must be set when --upload is used"
  fi

  if [[ -n "$RELEASE_NOTES_FILE" && ! -f "$RELEASE_NOTES_FILE" ]]; then
    die "release notes file not found: $RELEASE_NOTES_FILE"
  fi

  if [[ "$SKIP_NOTARIZATION" == false ]]; then
    [[ -n "$APPLE_NOTARY_PROFILE" ]] || die "APPLE_NOTARY_PROFILE must be set unless --skip-notarization is used"
  fi

  [[ -n "$APPLE_DEVELOPER_TEAM_ID" ]] || die "APPLE_DEVELOPER_TEAM_ID must be set"
  [[ -n "$APPLE_DEVELOPER_ID_APPLICATION" ]] || die "APPLE_DEVELOPER_ID_APPLICATION must be set"
}

create_release_payload() {
  local payload_file="$1"

  /usr/bin/python3 - "$payload_file" "$RELEASE_TAG" "$TARGET_COMMITISH" "$RELEASE_NAME" "$DRAFT_RELEASE" "$PRERELEASE" "$RELEASE_NOTES_FILE" <<'PY'
import json
import pathlib
import sys

payload_path = pathlib.Path(sys.argv[1])
tag = sys.argv[2]
target = sys.argv[3]
name = sys.argv[4]
draft = sys.argv[5] == "true"
prerelease = sys.argv[6] == "true"
notes_file = sys.argv[7]

body = ""
if notes_file:
    body = pathlib.Path(notes_file).read_text(encoding="utf-8")

payload = {
    "tag_name": tag,
    "target_commitish": target,
    "name": name or tag,
    "body": body,
    "draft": draft,
    "prerelease": prerelease,
}

payload_path.write_text(json.dumps(payload), encoding="utf-8")
PY
}

github_request() {
  local method="$1"
  local url="$2"
  local output_file="$3"
  local data_file="${4:-}"

  local curl_args=(
    curl
    --silent
    --show-error
    --location
    --request "$method"
    --header "Accept: application/vnd.github+json"
    --header "Authorization: Bearer $GITHUB_TOKEN"
    --header "X-GitHub-Api-Version: 2022-11-28"
    --output "$output_file"
    --write-out "%{http_code}"
  )

  if [[ -n "$data_file" ]]; then
    curl_args+=(
      --header "Content-Type: application/json"
      --data-binary "@$data_file"
    )
  fi

  curl_args+=("$url")

  run_capture "${curl_args[@]}"
}

github_release_response() {
  local response_file="$1"
  local status
  local payload_file=""

  status="$(github_request GET "https://api.github.com/repos/$REPOSITORY/releases/tags/$RELEASE_TAG" "$response_file")"
  if [[ "$status" == "200" ]]; then
    return 0
  fi

  if [[ "$status" != "404" ]]; then
    cat "$response_file" >&2
    die "unable to fetch GitHub release for tag $RELEASE_TAG (HTTP $status)"
  fi

  if [[ "$CREATE_RELEASE" != true ]]; then
    die "GitHub release $RELEASE_TAG does not exist; rerun with --create-release"
  fi

  payload_file="$(make_temp_file)"
  create_release_payload "$payload_file"
  status="$(github_request POST "https://api.github.com/repos/$REPOSITORY/releases" "$response_file" "$payload_file")"
  rm -f "$payload_file"

  if [[ "$status" != "201" ]]; then
    cat "$response_file" >&2
    die "unable to create GitHub release $RELEASE_TAG (HTTP $status)"
  fi
}

delete_existing_asset_if_needed() {
  local response_file="$1"
  local asset_name="$2"
  local asset_id
  local delete_file
  local status

  asset_id="$(json_asset_id_by_name "$response_file" "$asset_name")"
  if [[ -z "$asset_id" ]]; then
    return 0
  fi

  delete_file="$(make_temp_file)"
  status="$(github_request DELETE "https://api.github.com/repos/$REPOSITORY/releases/assets/$asset_id" "$delete_file")"
  rm -f "$delete_file"

  if [[ "$status" != "204" ]]; then
    die "unable to delete existing GitHub release asset $asset_name (HTTP $status)"
  fi
}

upload_asset() {
  local release_response="$1"
  local asset_path="$2"
  local content_type="$3"
  local asset_name
  local upload_url
  local upload_base
  local response_file
  local status

  asset_name="$(basename "$asset_path")"
  delete_existing_asset_if_needed "$release_response" "$asset_name"

  upload_url="$(json_field "$release_response" "upload_url")"
  [[ -n "$upload_url" ]] || die "GitHub release response did not include upload_url"
  upload_base="${upload_url%\{*}"

  response_file="$(make_temp_file)"
  status="$(
    run_capture curl \
      --silent \
      --show-error \
      --location \
      --request POST \
      --header "Accept: application/vnd.github+json" \
      --header "Authorization: Bearer $GITHUB_TOKEN" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      --header "Content-Type: $content_type" \
      --data-binary "@$asset_path" \
      --output "$response_file" \
      --write-out "%{http_code}" \
      "${upload_base}?name=$(urlencode "$asset_name")"
  )"

  if [[ "$status" != "201" ]]; then
    cat "$response_file" >&2
    rm -f "$response_file"
    die "unable to upload release asset $asset_name (HTTP $status)"
  fi

  info "Uploaded $(basename "$asset_path"): $(json_field "$response_file" "browser_download_url")"
  rm -f "$response_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --tag)
      RELEASE_TAG="$2"
      shift 2
      ;;
    --release-name)
      RELEASE_NAME="$2"
      shift 2
      ;;
    --release-notes-file)
      RELEASE_NOTES_FILE="$2"
      shift 2
      ;;
    --repo)
      REPOSITORY="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --upload)
      UPLOAD_RELEASE=true
      shift
      ;;
    --create-release)
      CREATE_RELEASE=true
      shift
      ;;
    --draft)
      DRAFT_RELEASE=true
      shift
      ;;
    --prerelease)
      PRERELEASE=true
      shift
      ;;
    --skip-notarization)
      SKIP_NOTARIZATION=true
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

load_config "$CONFIG_PATH"
preflight
ensure_clean_worktree
ensure_workspace

ARCHIVE_PATH="$OUTPUT_DIR/$APP_NAME.xcarchive"
STAGING_DIR="$OUTPUT_DIR/dmg-root"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256.txt"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
DMG_IDENTIFIER="${BUNDLE_ID}.dmg"

if [[ "$DRY_RUN" == false ]]; then
  rm -rf "$OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR"
fi

run xcodebuild \
  archive \
  -workspace "$WORKSPACE_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$APPLE_DEVELOPER_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$APPLE_DEVELOPER_ID_APPLICATION" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  GH_ORCHESTRATOR_GITHUB_CLIENT_ID="$GH_ORCHESTRATOR_GITHUB_CLIENT_ID"

if [[ "$DRY_RUN" == false && ! -d "$APP_PATH" ]]; then
  die "archived app bundle not found at $APP_PATH"
fi

run codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ "$DRY_RUN" == false ]]; then
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"
fi

run ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"

if [[ "$DRY_RUN" == false ]]; then
  ln -s /Applications "$STAGING_DIR/Applications"
fi

run hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

run codesign \
  --force \
  --sign "$APPLE_DEVELOPER_ID_APPLICATION" \
  --timestamp \
  -i "$DMG_IDENTIFIER" \
  "$DMG_PATH"

run codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$SKIP_NOTARIZATION" == false ]]; then
  run xcrun notarytool submit "$DMG_PATH" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
  run xcrun stapler staple "$DMG_PATH"
  run xcrun stapler validate "$DMG_PATH"
  validate_gatekeeper_context "$DMG_PATH"
else
  info "Skipping notarization and Gatekeeper validation."
fi

if [[ "$DRY_RUN" == false ]]; then
  shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"
else
  printf '+ shasum -a 256 %q > %q\n' "$DMG_PATH" "$CHECKSUM_PATH"
fi

info "DMG ready at $DMG_PATH"
info "Checksum ready at $CHECKSUM_PATH"

if [[ "$UPLOAD_RELEASE" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    info "Dry run: skipping GitHub Release upload."
  else
    release_response="$(make_temp_file)"
    github_release_response "$release_response"
    upload_asset "$release_response" "$DMG_PATH" "application/x-apple-diskimage"
    upload_asset "$release_response" "$CHECKSUM_PATH" "text/plain; charset=utf-8"
    rm -f "$release_response"
  fi
fi
