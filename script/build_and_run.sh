#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

MODE="${1:-run}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="${APP_NAME:-GHOrchestrator}"
SCHEME="${SCHEME:-$APP_NAME}"
BUNDLE_ID="${BUNDLE_ID:-com.ipavlidakis.GHOrchestrator}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/DerivedData}"
DESTINATION="${DESTINATION:-platform=macOS}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [run|--debug|--logs|--telemetry|--verify]

Builds the macOS app, stops any running instance, and launches the new build.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument: $MODE"
    ;;
esac

has_tuist_manifests() {
  [[ -f "$REPO_ROOT/Project.swift" ]] ||
    [[ -f "$REPO_ROOT/Workspace.swift" ]] ||
    [[ -f "$REPO_ROOT/Tuist/Project.swift" ]] ||
    [[ -f "$REPO_ROOT/Tuist/Workspace.swift" ]]
}

maybe_generate_workspace() {
  if [[ -n "${WORKSPACE_PATH:-}" || -n "${PROJECT_PATH:-}" ]]; then
    return
  fi

  if command -v tuist >/dev/null 2>&1 && has_tuist_manifests; then
    info "Generating Tuist workspace..."
    (
      cd "$REPO_ROOT"
      tuist generate --no-open
    )
  fi
}

resolve_build_container() {
  WORKSPACE_PATH="$(find "$REPO_ROOT" -maxdepth 1 -name '*.xcworkspace' -type d -print -quit || true)"
  PROJECT_PATH="$(find "$REPO_ROOT" -maxdepth 1 -name '*.xcodeproj' -type d -print -quit || true)"
}

collect_descendant_pids() {
  local parent_pid="$1"
  local child_pid

  while IFS= read -r child_pid; do
    [[ -n "$child_pid" ]] || continue
    collect_descendant_pids "$child_pid"
    printf '%s\n' "$child_pid"
  done < <(pgrep -P "$parent_pid" || true)
}

cleanup_stale_build_processes() {
  local build_target="${WORKSPACE_PATH:-${PROJECT_PATH:-}}"
  if [[ -z "$build_target" ]]; then
    return 0
  fi

  local stale_root_pids=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    stale_root_pids+=("${line%% *}")
  done < <(
    ps -ax -o pid=,command= | awk -v target="$build_target" '
      index($0, "xcodebuild") && index($0, target) { print $0 }
    '
  )

  if [[ "${#stale_root_pids[@]}" -eq 0 ]]; then
    return 0
  fi

  info "Stopping stale xcodebuild processes for $(basename "$build_target")..."

  local kill_pids=()
  local root_pid
  local child_pid
  for root_pid in "${stale_root_pids[@]}"; do
    [[ "$root_pid" == "$$" ]] && continue
    kill_pids+=("$root_pid")

    while IFS= read -r child_pid; do
      [[ -n "$child_pid" ]] || continue
      kill_pids+=("$child_pid")
    done < <(collect_descendant_pids "$root_pid")
  done

  if [[ "${#kill_pids[@]}" -gt 0 ]]; then
    kill "${kill_pids[@]}" 2>/dev/null || true
    sleep 1
  fi
}

kill_running_app() {
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    info "Stopping running $APP_NAME..."
    pkill -x "$APP_NAME" || true
    sleep 1
  fi
}

build_app() {
  maybe_generate_workspace
  resolve_build_container
  cleanup_stale_build_processes

  local build_args=()
  if [[ -n "${WORKSPACE_PATH:-}" ]]; then
    build_args+=(-workspace "$WORKSPACE_PATH")
  elif [[ -n "${PROJECT_PATH:-}" ]]; then
    build_args+=(-project "$PROJECT_PATH")
  else
    die "No .xcworkspace or .xcodeproj found. Generate the Tuist workspace first."
  fi

  info "Building $APP_NAME ($CONFIGURATION)..."
  xcodebuild \
    "${build_args[@]}" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build
}

find_app_bundle() {
  local direct_bundle="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
  if [[ -d "$direct_bundle" ]]; then
    printf '%s\n' "$direct_bundle"
    return 0
  fi

  find "$DERIVED_DATA_PATH/Build/Products" -maxdepth 4 -name "$APP_NAME.app" -type d -print -quit 2>/dev/null || true
}

open_app() {
  local app_bundle="$1"

  info "Launching $app_bundle..."
  /usr/bin/open -n "$app_bundle"
}

stream_logs() {
  /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
}

stream_telemetry() {
  /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
}

verify_process() {
  sleep 1
  if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    die "$APP_NAME did not appear after launch"
  fi

  info "Verification completed."
}

main() {
  command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is not available"

  kill_running_app
  build_app

  local app_bundle
  app_bundle="$(find_app_bundle)"
  [[ -n "$app_bundle" ]] || die "Built app bundle not found under $DERIVED_DATA_PATH"

  case "$MODE" in
    run)
      open_app "$app_bundle"
      ;;
    --debug|debug)
      info "Launching under LLDB..."
      lldb -- "$app_bundle/Contents/MacOS/$APP_NAME"
      ;;
    --logs|logs)
      open_app "$app_bundle"
      info "Streaming logs for $APP_NAME. Press Ctrl-C to stop."
      stream_logs
      ;;
    --telemetry|telemetry)
      open_app "$app_bundle"
      info "Streaming telemetry for $BUNDLE_ID. Press Ctrl-C to stop."
      stream_telemetry
      ;;
    --verify|verify)
      open_app "$app_bundle"
      verify_process
      ;;
  esac
}

main
