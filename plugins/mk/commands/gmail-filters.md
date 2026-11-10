---
description: Analyze a Gmail mailbox and create label-applying filters for high-volume senders
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/gmail-filters.py:*), Bash(gws:*), Read, Write, AskUserQuestion, ToolSearch
---

# /mk:gmail-filters — organize a Gmail inbox with filters + labels

Find the high-volume senders flooding the user's Gmail, propose Gmail filters that apply labels to them, and (on approval) create those filters and backfill the labels onto existing mail.

Gmail access is split by what each tool can do:

- **Reading and labeling mail** goes through the **Gmail connector** (an MCP server whose tools include `search_threads`, `list_labels`, `get_message` and `update_message_labels`; its tool names carry a server prefix, so find them with ToolSearch). It needs no local login.
- **Creating and deleting filters** goes through the `gws` CLI, via the backing script's `apply`. The connector has no filter tools. This is the only step that needs a current `gws auth login`.

**The backing script is:**

!`echo "${CLAUDE_PLUGIN_ROOT}/scripts/gmail-filters.py"`

That path is expanded when the slash command is invoked, so it is already literal by the time you read it. Every command below writes `<SCRIPT>` — substitute that path. Do **not** type `${CLAUDE_PLUGIN_ROOT}` into a Bash call: the harness expands it in `!`-backtick directives and `allowed-tools`, but it is not exported into the Bash tool's environment, so it resolves to an empty string there.

Read the script's module docstring once for the config format and subcommand flags. The declared plan lives in a persistent, multi-account YAML config (default `~/.config/gmail-filters.yaml`). Confirm the connector is signed in to the account whose stanza you are editing before labeling anything.

**Core principles:**
- **Never mutate without showing a dry run first.** For `apply`, that is its default dry run. For connector writes, show the per-filter match counts first. Only write after the user approves the concrete plan.
- **One filter → one or more labels, and prefer 1:1** unless the user asks otherwise, so archive decisions can be made per-label later without side effects.
- **Do not auto-label or archive person-to-person mail.** Filter automated senders and mailing lists, not human colleagues.

## Phase 1: Analyze

Sample the mail slipping past your filters with the connector's `search_threads`, paging 50 threads at a time through roughly the 500 most recent matches of:

```
in:inbox OR (has:nouserlabels newer_than:90d -in:sent -in:chats)
```

That is everything in the inbox, plus recent mail no filter labeled, including mail that got archived without a label. Aggregate by sender, then by subject template within each high-volume sender (normalize away numbers, dates and ids).

Coverage comes from the config, not from Gmail: read `~/.config/gmail-filters.yaml` and skip senders and templates an existing filter already matches. Call `list_labels` so proposals reuse existing labels.

The connector does not return `List-Id`. When a sender looks like a mailing list, confirm with a `list:(<id>)` search, or read one message with `messageFormat: RAW` and take the header from there.

## Phase 2: Propose a plan

Group the uncovered high-volume senders into a coherent scheme. Guidance:

- **Label recurring *templates*, not bare senders.** A `from:X → label` filter adds little value: the user can already type `from:X` into search and get the same set instantly. The label earns its keep only when it captures a specific recurring email *type* that a sender emits — a template you cannot cheaply reconstruct with a one-off search. So a good filter is almost always **sender + a subject (or body) pattern** that identifies one template, e.g. `firebase-noreply@google.com` + `subject:("Missing dSYM")`, or `cloudplatform-noreply@google.com` + `subject:("[Action Advised]")`. Before proposing filters for a sender, sample its actual subjects and cluster them (normalize away numbers/dates/ids) to find the distinct recurring templates; make one filter per template. A high-volume sender whose mail is all *one-off* content (e.g. marketing blasts with no repeating template) usually deserves no label at all — labeling it is no better than a search.
- **Prefer mailing-list criteria over From.** When a sender carries a `List-Id`, filter on `{"query": "list:(<list-id>)"}` — it is far more stable than a From address and cleanly separates a distribution list from a person who also mails you directly. GitHub per-repo notifications, in particular, each carry a distinct `List-Id` and should become nested `GitHub/<repo>` labels so noisy repos can be archived independently later. (A `List-Id` identifies a distribution *channel*, which is itself a durable pattern — that is why it is the exception to the "not bare senders" rule above.)
- **Reuse existing labels** where one fits (e.g. an existing `infra alerts` or `billing`); only create new labels for genuinely new buckets.
- **Distinguish humans from automation.** Mail from a person (no `List-Id`, a real name) should not be auto-filtered. Automated addresses (`no-reply@`, `notifications@`, `*-noreply@`) and lists are fair game.

Use AskUserQuestion to settle anything that changes the plan's shape — label scheme (by-category vs by-source), and whether any categories should also **archive** (skip inbox) or **mark read**. Default to **label-only** unless the user opts in.

The plan lives in a persistent config file — by default `~/.config/gmail-filters.yaml` (overridable via `$GMAIL_FILTERS_CONFIG` or an explicit path arg to the script). This is the durable source of truth, not a throwaway: **edit the existing file, adding to the current account's stanza**, rather than starting fresh. The config is **multi-account** — a top-level `accounts` map keyed by managed email address; `apply` uses only the stanza for the account `gws` is signed in as. Add your new filters under the stanza matching the account you are managing (create the stanza if this account is new).

Each filter is `{criteria, labels, archive?, markRead?}`. Format (YAML; JSON is also accepted):

```yaml
accounts:
  you@example.com:
    filters:
      - criteria: { query: "list:(<my-repo.my-org.github.com>)" }
        labels: [GitHub/my-repo]
      - criteria: { from: firebase-noreply@google.com, subject: "Missing dSYM" }
        labels: [Firebase/Missing dSYM]
        archive: true
```

Read the current config first (so you extend it rather than clobber it), then add the new entries. If the file does not exist yet, create it with the structure above. Labels referenced by filters are auto-created on apply; an explicit top-level `labels:` list under the stanza is optional (for labels you want to exist even without a filter).

## Phase 3: Apply (dry run → confirm → execute)

This is the only phase that needs `gws`. Check its login first:

```
<SCRIPT> preflight
```

If it fails, ask the user to run `gws auth login` and **select `gmail.settings.basic` in the scope picker** (the picker does not remember it). Everything else in this command works without it.

Dry-run the apply so the user sees exactly which labels and filters will be created. Existing labels are detected and skipped; existing filters are matched by criteria — an identical filter is skipped (`exists`), so re-running an unchanged config is a safe no-op. Run it against the default config (or pass an explicit path if the user keeps it elsewhere):

```
<SCRIPT> apply
```

**If you edited a filter that was already applied**, the dry run prints a `DIFFERS` line instead of `exists`: the criteria still matches an installed filter, but its action (labels / archive / mark-read) has drifted from the rules file. Gmail filters are immutable, so `apply` cannot reconcile this on its own — it will not silently overwrite. To apply the edit, delete the installed filter by its id and re-run, using `gws` directly:

```
gws gmail users settings filters delete --params '{"userId":"me","id":"<filter-id-from-DIFFERS-line>"}'
```

Then re-run `apply` so the corrected filter is created fresh. Confirm the delete with the user first.

Present the dry-run output. On approval, re-run the same command with `--apply` appended to execute.

Filters only ever *add* labels (plus optional archive/mark-read); they never delete mail.

## Phase 4: Backfill (optional)

Gmail filters apply only to **incoming** mail. Offer to backfill: apply each new filter's labels to existing matching messages. Get each filter's equivalent search from the config:

```
<SCRIPT> queries
```

For each new filter, run its `query` through `search_threads` and report the match count. On approval, call `update_message_labels` per message: add the label ids (from `list_labels`), and remove `INBOX` when the filter archives, or `UNREAD` when it marks read. Refuse any filter that archives without a label.

The connector modifies one message per call, so ask before backfilling more than a few hundred messages.

## Phase 5: Delayed archive (optional)

A Gmail filter may carry only **one user label** — attempting a second fails with `Too many user labels in filter`. So a filter that already stamps `Receipt` cannot also stamp a "queued for archive" marker, and filters have no notion of message age (they run once, at delivery, when the message is zero days old). Both limits mean a *delayed* archive is impossible with filters alone.

A Google Apps Script does it via the API, which has no one-label limit. Every hour it marks matching inbox mail with a delay label, then archives whatever already carries that label and has aged past the window, skipping starred mail. The delay is the point: it keeps mail visible long enough for an external consumer to ingest it before it leaves the inbox. Ramp's receipt scraper is the motivating case — it replies to receipt mail it has processed, so archiving a receipt on arrival risks it never being seen. Configure per account alongside `filters:`:

```yaml
    sweep:
      label: Delayed Archive
      days: 7
      queries:
        - from:receipts@example.com
        - label:Receipt
```

Marking and archiving happen in the same run, so mail already older than the window is archived on the first run after a query is added.

The script fetches the `sweep` stanza from a URL on every run, so it is pasted once and never regenerated for config edits; a stanza change takes effect on the next run after it is published there (for a config in a public dotfiles repo, merged to the default branch). Render it with that URL:

```
<SCRIPT> apps-script --config-url https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>/gmail-filters.yaml > Code.gs
```

The user pastes it into a project at script.google.com, adds the Gmail advanced service (Services → + → Gmail API), and runs `installTrigger` once (hourly by default; `--every-hours` changes it). Running `sweep` from the editor applies the published stanza immediately. The script reads the stanza with a small line parser, not full YAML, so `apply` and `apps-script` refuse a stanza it would misread: keep it to `label:`, `days:`, and a `queries:` list of one-line scalars.

## Phase 6: Summary

Report concisely: labels created, filters created, and (if run) messages backfilled. Note that filters apply going forward and — if the user declined backfill — that existing mail was left unlabeled. The config file is the durable record; remind the user it lives in version control (e.g. their dotfiles) so the plan is re-runnable and reviewable.

## Important constraints

- **Dry run before every write.** Never pass `--apply`, or label mail through the connector, until the user approves that specific dry-run output.
- **Label templates, not bare senders.** A `from:X` filter is barely better than a search; filter on sender + a subject/body pattern that identifies a recurring email type. Bare `List-Id` list filters are the exception (a list is itself a durable channel).
- **Never filter person-to-person mail** into an auto-archive.
- **Prefer `List-Id` criteria** over From for anything that is a mailing list.
- **Reuse existing labels/filters;** don't create duplicates or parallel schemes.
- Filters and backfill only add labels (and optionally archive/mark-read). Nothing is ever deleted.
- **One user label per filter.** Gmail rejects a second with `Too many user labels in filter`. A message can hold many labels, but each filter contributes at most one — so a "queued for archive" marker alongside a semantic label needs the sweep, not a filter.
- **Filters cannot act on message age.** They run once at delivery and never re-evaluate, so `older_than:` in filter criteria matches nothing. Anything time-based belongs in the sweep.
