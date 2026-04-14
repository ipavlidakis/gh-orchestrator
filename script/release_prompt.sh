#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

prompt_value() {
  local label="$1"
  local value="$2"

  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  local input=""
  if [[ -t 0 ]]; then
    read -r -p "$label: " input
  else
    if ! read -r input; then
      printf 'error: %s is required when stdin is not interactive\n' "$label" >&2
      exit 1
    fi
  fi

  if [[ -z "$input" ]]; then
    printf 'error: %s is required\n' "$label" >&2
    exit 1
  fi

  printf '%s\n' "$input"
}

VERSION=""
BUILD_NUMBER=""
FORWARDED_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    *)
      FORWARDED_ARGS+=("$1")
      shift
      ;;
  esac
done

VERSION="$(prompt_value "Version" "$VERSION")"
BUILD_NUMBER="$(prompt_value "Build" "$BUILD_NUMBER")"

if ((${#FORWARDED_ARGS[@]})); then
  exec "$REPO_ROOT/script/release_dmg.sh" --version "$VERSION" --build "$BUILD_NUMBER" "${FORWARDED_ARGS[@]}"
fi

exec "$REPO_ROOT/script/release_dmg.sh" --version "$VERSION" --build "$BUILD_NUMBER"
