#!/usr/bin/env bash
#
# install.sh — install the mk plugin's launchd job (macOS):
#   com.mk.kill-orphaned  every 60s: reap orphaned `claude` processes
#   (re-parented to PID 1 when a terminal closes abruptly). See README.md.
#
# Usage:
#   install.sh              Install everything (idempotent; safe to re-run)
#   install.sh --uninstall  Unload and remove the launchd jobs
#
# launchd is macOS-only. On other platforms the launchd steps are skipped with
# instructions to schedule the script yourself (cron/systemd).

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$PLUGIN_DIR/scripts"
TEMPLATES="$PLUGIN_DIR/templates"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

log()  { echo "install: $*" >&2; }
die()  { log "$*"; exit 1; }
is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

# The launchd jobs this plugin manages: "label|script".
JOBS=(
  "com.mk.kill-orphaned|$SCRIPTS/kill-orphaned-claude.sh"
)

# Render <template> substituting the job's script path, write to LaunchAgents,
# and load it (unloading any prior copy first, so a changed path takes effect).
install_job() {
    local label="$1" script="$2"
    local template="$TEMPLATES/$label.plist.template"
    local plist="$LAUNCH_AGENTS/$label.plist"
    [[ -f "$script" ]]   || die "script not found: $script"
    [[ -f "$template" ]] || die "template not found: $template"

    local content; content="$(cat "$template")"
    printf '%s\n' "${content//__SCRIPT__/$script}" > "$plist"
    launchctl unload "$plist" 2>/dev/null || true
    launchctl load "$plist"
    log "installed $label"
}

uninstall_job() {
    local label="$1"
    local plist="$LAUNCH_AGENTS/$label.plist"
    if [[ -f "$plist" ]]; then
        launchctl unload "$plist" 2>/dev/null || true
        rm -f "$plist"
        log "removed $label"
    fi
}

install_all() {
    if ! is_macos; then
        log "Not macOS — no launchd. Schedule this yourself:"
        log "    every 60s:  $SCRIPTS/kill-orphaned-claude.sh"
        exit 0
    fi
    mkdir -p "$LAUNCH_AGENTS"
    local job label script
    for job in "${JOBS[@]}"; do
        IFS='|' read -r label script <<<"$job"
        install_job "$label" "$script"
    done
    log "Done. Log: /tmp/claude-kill-orphaned.log"
}

uninstall_all() {
    if ! is_macos; then log "nothing to uninstall (no launchd)"; exit 0; fi
    local job label rest
    for job in "${JOBS[@]}"; do
        IFS='|' read -r label rest <<<"$job"
        uninstall_job "$label"
    done
    log "done"
}

case "${1:-}" in
    ""|--install) install_all ;;
    --uninstall)  uninstall_all ;;
    -h|--help) echo "Usage: install.sh [--install|--uninstall]" >&2; exit 0 ;;
    *) die "unknown argument: $1" ;;
esac
