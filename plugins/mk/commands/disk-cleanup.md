---
description: Analyze what's filling the Mac's disk and clean it up, row by row with approval
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/disk-scan.sh:*), Bash, Read, AskUserQuestion
---

# /mk:disk-cleanup — find and reclaim disk space

Find what is filling the Mac's Data volume and free up space. First run the scan script. Then show the user one table with a delete, keep, or ask decision for every large item. Get the user's approval of that table, delete only the items they approved, and report how much free space there was before and after.

Never delete anything the user hasn't approved. Every deletion in this command is destructive.

## 1. Scan

Before you start, tell the user the scan takes several minutes. Then run it in the background:

`${CLAUDE_PLUGIN_ROOT}/scripts/disk-scan.sh`

The script only reads. It deletes nothing. It prints these sections:

- Free space: the Data volume, free space in the APFS container, and the number of Time Machine local snapshots
- Docker: `docker system df`, the size of `Docker.raw`, and unused named volumes
- Known caches that regenerate on demand, with their sizes
- Hugging Face blobs that no model references, with the model name taken from each blob's `.refs` file
- Playwright MCP Chrome profiles: how many there are, which one a running Chrome is using, and the browser builds
- Running uv processes that hold the uv cache lock
- The largest top-level folders
- Folders over 500 MB inside `~/Library/Caches`, `~/Library/Application Support` and `~/.cache`
- The largest apps
- Video files over 100 MB

If a section is missing or looks wrong, look into it yourself by running `du -sxm` on each directory, in parallel. Never run a single `du` over all of `~`. It takes more than 10 minutes and shows no progress, so the user is left waiting with no idea when it will end.

## 2. Propose

Show the user one table with these columns:

1. Item
2. Size
3. Decision: **delete**, **keep** or **ask**
4. What deleting costs, such as a re-download, a rebuild, or lost data

Make a decision on every row. Don't just list options for the user to choose from. Use **ask** only when the decision depends on something only the user knows, such as whether they still want a particular model.

Then ask the user once to approve the whole table. Don't ask row by row.

### Standing decisions

The user has already made these decisions. Apply them without asking again.

- **Keep** iOS simulators (`CoreSimulator`), Xcode DerivedData, Android Studio, and the Android SDK and emulators.
- **Keep** app bundles unless the user names them. When the user said "delete the iMovie stuff," they meant large movies and iMovie libraries, not `iMovie.app`. A previous session misread this and tried to delete the app.
- **Keep** data that is in use or managed by the system:
  - The Chrome profile
  - Claude desktop's `vm_bundles`
  - `/private/var`

### Usually safe to delete

These items regenerate on demand, so deleting them usually costs only a re-download or rebuild. Still put each one in the table for approval.

- **Unused Docker images, build cache and stopped containers.** Run:
  - `docker image prune -a -f`
  - `docker builder prune -a -f`
  - `docker container prune -f`
- **Unused Docker volumes.** Run `docker volume prune -a -f`.
  - Volumes with hash names are leftover Postgres and emulator data from test runs.
  - Volumes named `*-local_*` (for example `api-local`) are local dev databases. List each one by name in the table, because deleting one resets that stack to an empty database.
- **Terraform plugin cache.** Run `rm -rf ~/.terraform.d/plugin-cache && mkdir ~/.terraform.d/plugin-cache`. It was 23.6 GB last time. `terraform init` downloads the plugins again when they're needed.
- **Hugging Face blobs that no model references.** Delete the blob, the `.lock` and `.refs` files next to it, and `hub/.locks/<model>`. The `.refs` file names the model, so confirm the user doesn't want that model before deleting.
- **Playwright `mcp-chrome-*` profiles.** Delete all of them except the one a running Chrome is using. The scan names that profile.
- **Old Playwright browser builds.** Keep the highest-numbered `chromium-*` and the highest-numbered `chromium_headless_shell-*`. Delete the rest.
- **uv cache.** Run `uv cache prune --force`.
  - If the scan shows running `uv run` jobs, wait for them to finish first. Poll for them in the background.
  - You need `--force` even when no jobs are running, because long-lived `uvx` MCP servers hold the cache lock permanently. Without `--force`, uv waits 300 seconds and then fails with an error.
- **pnpm store.** Run `pnpm store prune`.

## 3. Act and report

1. Note the free space the scan reported. This is the "before" figure.
2. Run the deletions the user approved, and nothing else.
3. For personal files, such as videos, iMovie libraries and documents, use `mv` to move them to `~/.Trash` instead of deleting them with `rm`. That way the user can still recover them.
4. Check free space again with `df`. If you pruned Docker, wait a few minutes before you check, because Docker releases the space late (see below).
5. Report free space before and after.
6. If you moved anything to `~/.Trash`, tell the user to empty the Trash themselves. macOS doesn't let this session read or empty `~/.Trash`, so the space isn't freed until they do.

## Things that mislead

- **`du` overcounts the uv and pnpm caches.** Each `.venv` is an APFS clone of the uv cache, and `node_modules` folders are hard links into the pnpm store. So `du` makes `~/code` and the worktrees look much bigger than the space they really use. Pruning those caches or deleting worktrees frees much less than `du` suggests. For example, one `uv cache prune` removed 5.1 GiB of files but freed almost nothing on disk. Set size expectations in the table accordingly.
- **Docker releases space late.** `Docker.raw` shrinks a few minutes after a prune. Check `df` again before concluding that a prune freed nothing.
- **Root-owned App Store apps, such as `iMovie.app`, can't be removed.** Removing them needs `sudo`, which this session can't run. `rm -rf` on them fails partway through, so don't try.
- **`gdu` on this machine is GNU `du` from coreutils.** It is not the interactive disk usage analyzer of the same name.
