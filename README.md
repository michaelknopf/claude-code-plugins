# Claude Code Plugins

Opinionated Claude Code plugins built around explicit, written principles. Two plugins:

- **`dev`** — deep PR review, plan review, and the engineering principles they're grounded in. Needs nothing beyond Claude Code and `gh`.
- **`mk`** — personal extras: disk cleanup, Gmail filters, an artifact-structure skill, a statusline, and an orphaned-process reaper. Published as a reference rather than a recommendation.

## Installation

```bash
git clone https://github.com/michaelknopf/claude-code-plugins.git
claude plugin marketplace add ./claude-code-plugins
claude plugin install dev@mk-plugins
claude plugin install mk@mk-plugins   # optional
```

Plugins install with `user` scope by default. Use `--scope project` to limit one to the current project.

Installing this way copies the plugin into a versioned cache, and Claude Code only picks up changes when the `version` in `plugin.json` changes. If you're editing the plugins, use the live-linked setup below instead.

### Editing the plugins: install live-linked

If you're changing commands, skills, or principle docs, install from a local marketplace that symlinks your working tree instead of copying it. Edits then take effect on the next session — no version bump, no update step.

Create a marketplace manifest outside the repo (it hardcodes an absolute path, so it must not be committed):

```bash
CLONE="$(pwd)"                       # run from your clone's root
LIVE="$HOME/.claude/local-marketplaces/mk-live"
mkdir -p "$LIVE/.claude-plugin"
cat > "$LIVE/.claude-plugin/marketplace.json" <<EOF
{
  "name": "mk-live",
  "owner": { "name": "Michael Knopf" },
  "description": "Local-only live-linked view of the plugins working tree.",
  "plugins": [
    {
      "name": "dev",
      "source": { "source": "command", "command": "echo $CLONE/plugins/dev", "mode": "link" },
      "description": "Core development commands",
      "author": { "name": "Michael Knopf" }
    },
    {
      "name": "mk",
      "source": { "source": "command", "command": "echo $CLONE/plugins/mk", "mode": "link" },
      "description": "Personal commands",
      "author": { "name": "Michael Knopf" }
    }
  ]
}
EOF
```

Then register it and swap your installs:

```bash
claude plugin marketplace add "$LIVE"

# Remove the cached copies first — a plugin can only be installed from one marketplace.
claude plugin uninstall dev@mk-plugins
claude plugin uninstall mk@mk-plugins

claude plugin install dev@mk-live
claude plugin install mk@mk-live
```

Run the two `install` commands **in your own terminal**, not inside a Claude Code session. A `command` source executes a shell command, so Claude Code requires you to review and accept it interactively; `--yes` is ignored in-session by design.

Verify the link took — each top-level entry should be a symlink into your clone:

```bash
ls -la "$(claude plugin list --json | jq -r '.[] | select(.id=="dev@mk-live") | .installPath')"
```

To go back to the cached install, uninstall the `@mk-live` plugins and reinstall from `@mk-plugins`.

### Releasing a change

Because consumers install from the cached `mk-plugins` marketplace, **a change is not delivered until the version is bumped**. When landing a PR that touches `plugins/<name>/**`, bump `version` in both `plugins/<name>/.claude-plugin/plugin.json` and the matching entry in `.claude-plugin/marketplace.json` — `claude plugin tag` validates that the two agree.

### Load the coding principles

`plugins/dev/docs/general-principles.md` and `python-principles.md` are meant to be imported into `~/.claude/CLAUDE.md`:

```markdown
@/path/to/claude-code-plugins/plugins/dev/docs/general-principles.md
@/path/to/claude-code-plugins/plugins/dev/docs/python-principles.md
```

The other docs are loaded on demand by the skills and agents that need them.

## Dependencies

- **`gh`** — GitHub CLI, for PR operations and CI logs. `brew install gh`, then `gh auth login`.
- **`jq`** — used for GitHub API payloads and the statusline. `brew install jq`.

## The `dev` plugin

Every analysis agent loads a principles doc from `plugins/dev/docs/` before it starts, and each finding cites the principle it applies. A finding you disagree with can be argued with, or fixed at the principle. `code-review.md` sets the tone: review feedback is a scarce resource, so these tools surface fewer findings than you might expect, and a clean review is a valid outcome.

| Piece | What it does |
|---|---|
| `/dev:deep-review-pr` | Sonnet scout establishes intent, then an Opus analyst reviews over up to four passes, re-validates findings, and writes a report to `docs/local/reports/`. `--auto` runs it unattended. Fixes are driven green with `docs/fix-loop.md` and `docs/ci-fix-loop.md`. |
| `/dev:plan-review` | Argues the current plan out with an adversarial critic sub-agent. |
| Agents | `review-scout`, `review-analyst`, `review-critic`, `review-driver`, `plan-critic`, `fix-diagnostician`, `type-fix-planner`. |
| Skills | `python-principles`, `type-safety-principles`, `smoke`, `ux-design-principles`, `diagrams`, `github-pr-ops`. |
| Docs | `general-principles`, `python-principles`, `type-safety`, `code-review`, `change-cost`, `comment-principles`, `voice-principles`, `smoke-tests`, `ux-design`, plus the fix, CI-fix and commit loops. |

## The `mk` plugin

- `/mk:gmail-filters` finds high-volume automated senders no filter covers and, after a dry run you approve, creates label filters via the `gws` CLI.
- `/mk:disk-cleanup` analyzes what's filling a Mac's disk and cleans it up, row by row with approval.
- The `artifacts` skill sets how multi-part HTML artifacts and mock-ups are structured.
- `install.sh` installs a launchd job that reaps orphaned `claude` processes (see `plugins/mk/README.md`).

### Statusline

The `mk` plugin ships a statusline script that shows model, cost, context window usage, and rate limit consumption as color-coded mini progress bars with countdown timers to quota reset:

```
Opus · $1.23 · ctx ████░░░░ 42% · 5h ██░░░░░░ 23% 3h30m · 7d ███░░░░░ 41% 5d12h
```

Colors shift from green to yellow to red as values approach their thresholds. Context and rate limit sections are omitted when unavailable (early in a session, or on plans that don't expose rate limit data).

To enable it, add a `statusLine` entry to `~/.claude/settings.json` pointing at the script in your local clone:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/claude-code-plugins/plugins/mk/scripts/statusline.sh"
  }
}
```

To preview the output without starting a session, run the script with `--test`:

```bash
plugins/mk/scripts/statusline.sh --test
```
