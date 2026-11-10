# Claude Code Plugins

Opinionated Claude Code plugins built around explicit, written principles. Two plugins:

- **`dev`** — deep PR review, plan review, and the engineering principles they're grounded in. Needs nothing beyond Claude Code and `gh`.
- **`mk`** — personal extras: disk cleanup, Gmail filters, an artifact-structure skill, a statusline, and an orphaned-process reaper. Published as a reference rather than a recommendation.

## Installation from source (live-linked)

This is the recommended setup. Claude Code loads the plugins from symlinks into your clone, so a `git pull` or a local edit takes effect in the next session, with no version bump and no update step.

**1. Clone the repo.**

```bash
mkdir -p ~/code/github/michaelknopf
git clone https://github.com/michaelknopf/claude-code-plugins.git ~/code/github/michaelknopf/claude-code-plugins
```

**2. Create a local marketplace that points at the clone.** It hardcodes an absolute path, so it lives outside the repo and is never committed.

```bash
CLONE="$HOME/code/github/michaelknopf/claude-code-plugins"
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
      "description": "Deep PR review, plan review, and engineering principles"
    },
    {
      "name": "mk",
      "source": { "source": "command", "command": "echo $CLONE/plugins/mk", "mode": "link" },
      "description": "Personal commands"
    }
  ]
}
EOF
```

**3. Register it and install the plugins.** Run these **in your own terminal**, not inside a Claude Code session. A `command` source runs a shell command, so Claude Code makes you review and accept it interactively, and `--yes` is ignored in-session.

```bash
claude plugin marketplace add "$HOME/.claude/local-marketplaces/mk-live"
claude plugin install dev@mk-live
claude plugin install mk@mk-live   # optional
```

**4. Check that the link took.** Each top-level entry should be a symlink into your clone.

```bash
ls -la "$(claude plugin list --json | jq -r '.[] | select(.id=="dev@mk-live") | .installPath')"
```

To update on a machine, `git pull` in the clone. If a plugin is already installed from another marketplace (such as the cached `mk-plugins` install below), uninstall it first, because a plugin can only be installed from one marketplace.

### Alternative: cached install

```bash
claude plugin marketplace add michaelknopf/claude-code-plugins
claude plugin install dev@mk-plugins
```

This copies the plugin into a versioned cache. Claude Code only picks up changes when the `version` in `plugin.json` changes, so when changing `plugins/<name>/**`, bump `version` in both `plugins/<name>/.claude-plugin/plugin.json` and the matching entry in `.claude-plugin/marketplace.json`.

### Load the coding principles

`general-principles.md` and `python-principles.md` are meant to be imported into `~/.claude/CLAUDE.md`, so they're in every session. With the clone at the path above:

```markdown
@~/code/github/michaelknopf/claude-code-plugins/plugins/dev/docs/general-principles.md
@~/code/github/michaelknopf/claude-code-plugins/plugins/dev/docs/python-principles.md
```

`general-principles.md` tells Claude to make every change in a git worktree under `.worktrees/`. Ignore that directory everywhere with a global gitignore:

```bash
git config --global core.excludesFile ~/.gitignore_global
echo '.worktrees/' >> ~/.gitignore_global
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
