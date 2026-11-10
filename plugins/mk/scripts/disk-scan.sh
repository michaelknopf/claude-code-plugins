#!/usr/bin/env bash
# Read-only disk analysis for /mk:disk-cleanup. Deletes nothing.
set -uo pipefail

DATA_VOL=/System/Volumes/Data
PER_DIR_TIMEOUT=${PER_DIR_TIMEOUT:-300}
TIMEOUT_BIN=$(command -v timeout || command -v gtimeout || true)

section() { printf '\n## %s\n' "$1"; }

size_mb() {
  if [[ -n $TIMEOUT_BIN ]]; then "$TIMEOUT_BIN" "$PER_DIR_TIMEOUT" du -sxm "$1" 2>/dev/null
  else du -sxm "$1" 2>/dev/null; fi
}
export -f size_mb
export PER_DIR_TIMEOUT TIMEOUT_BIN

# du runs one process per directory, in parallel; a single du over ~ takes 10+ minutes.
parallel_sizes() {
  tr '\n' '\0' | xargs -0 -P 12 -I{} bash -c 'size_mb "$1"' _ {} | sort -rn
}

report_free() {
  section "Free space"
  df -h "$DATA_VOL" | tail -1 | awk '{print "Data volume: " $3 " used, " $4 " free (" $5 ")"}'
  diskutil info / | grep -E 'Container Free Space' | sed 's/^ *//'
  local snaps
  snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -vc '^Snapshots for' || true)
  echo "Time Machine local snapshots: $snaps"
}

report_top_level() {
  section "Largest top-level folders (MB)"
  {
    find "$HOME" -mindepth 1 -maxdepth 1 ! -name Library ! -name .Trash
    find "$HOME/Library" -mindepth 1 -maxdepth 1
    printf '%s\n' /Applications /Library /private/var /opt /usr/local
  } | parallel_sizes | head -30
}

report_second_level() {
  section "Inside the big Library folders and ~/.cache (MB, >500)"
  find "$HOME/Library/Caches" "$HOME/Library/Application Support" "$HOME/.cache" \
    -mindepth 1 -maxdepth 1 2>/dev/null | parallel_sizes | awk '$1 > 500'
}

report_known_caches() {
  section "Known regenerable caches (MB)"
  local p
  for p in \
    "$HOME/.terraform.d/plugin-cache" "$HOME/Library/pnpm" "$HOME/.npm" "$HOME/.cache/uv" \
    "$HOME/.cache/huggingface" "$HOME/.cache/pip" "$HOME/.gradle/caches" "$HOME/.m2/repository" \
    "$HOME/Library/Caches/ms-playwright" "$HOME/Library/Caches/ms-playwright-mcp" \
    "$HOME/Library/Caches/terragrunt" "$HOME/Library/Caches/org.swift.swiftpm" \
    "$HOME/Library/Caches/Homebrew" "$HOME/.cache/codex-runtimes" \
    "$HOME/Library/Developer/Xcode/DerivedData" "$HOME/Library/Developer/CoreSimulator"; do
    [[ -e $p ]] && echo "$p"
  done | parallel_sizes
}

report_docker() {
  section "Docker"
  if ! docker info >/dev/null 2>&1; then echo "Docker not running"; return; fi
  docker system df
  echo "Disk image: $(du -sh "$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw" 2>/dev/null | cut -f1)"
  echo "Unused named volumes (likely local dev databases):"
  docker volume ls -qf dangling=true | grep -vE '^[0-9a-f]{64}$' | sed 's/^/  /'
}

report_hf_orphans() {
  local hub=$HOME/.cache/huggingface/hub
  [[ -d $hub/blobs ]] || return
  section "Hugging Face blobs no model references (abandoned downloads)"
  local refd all
  refd=$(mktemp); all=$(mktemp)
  find "$hub"/models--* "$hub"/datasets--* -type l -exec readlink -f {} \; 2>/dev/null | sort -u >"$refd"
  find "$hub/blobs" -type f -size +1M | sort >"$all"
  comm -13 "$refd" "$all" | while read -r f; do
    printf '%6d MB  %s  <- %s\n' "$(( $(stat -f %z "$f") / 1048576 ))" "$f" \
      "$(cut -d/ -f1 "$f.refs" 2>/dev/null | sort -u | tr '\n' ' ')"
  done
  rm -f "$refd" "$all"
}

report_playwright() {
  section "Playwright MCP Chrome profiles"
  local in_use
  in_use=$(ps -Ao command= | grep -oE 'user-data-dir=[^ ]*mcp-chrome-[^ ]+' | sed 's/user-data-dir=//' | sort -u)
  echo "In use (keep): ${in_use:-none}"
  find "$HOME/Library/Caches/ms-playwright" "$HOME/Library/Caches/ms-playwright-mcp" \
    -mindepth 1 -maxdepth 1 -name 'mcp-chrome-*' 2>/dev/null | wc -l | sed 's/^ */Profiles: /'
  echo "Browser builds:"
  ls "$HOME/Library/Caches/ms-playwright" 2>/dev/null | grep -vE '^mcp-chrome-' | sed 's/^/  /'
}

report_lock_holders() {
  section "Running uv processes (block 'uv cache prune')"
  ps -Ao pid,etime,command | grep -E '[u]v (run|tool)|[u]vx ' | cut -c1-160
}

report_videos() {
  section "Video files over 100 MB"
  find "$HOME" \( -path "$HOME/code" -o -path "$HOME/Library/Containers" -o -path "$HOME/Library/Developer" -o -path "$HOME/.Trash" \) -prune \
    -o -type f -size +100M \( -iname '*.mov' -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mkv' -o -iname '*.webm' \) \
    -print0 2>/dev/null | xargs -0 stat -f '%z %Sm %N' -t '%Y-%m-%d' 2>/dev/null \
    | awk '{printf "%6d MB  %s  ", $1/1048576, $2; $1=$2=""; print substr($0,3)}' | sort -rn
}

report_apps() {
  section "Largest apps (MB)"
  find /Applications "$HOME/Applications" -mindepth 1 -maxdepth 1 -name '*.app' 2>/dev/null | parallel_sizes | head -25
}

report_free
report_docker
report_known_caches
report_hf_orphans
report_playwright
report_lock_holders
report_top_level
report_second_level
report_apps
report_videos
