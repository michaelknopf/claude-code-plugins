---
description: Multi-lens parallel PR review that discovers layered issues a single pass misses
argument-hint: "[--auto] [PR url|number ...] (nothing, to review the current branch)"
allowed-tools: Read, Edit, Glob, Grep, Write, Workflow, Bash, AskUserQuestion, Agent(*), SendMessage, Skill(*), Task(*)
---

# Multi-Lens PR Code Review

You are conducting a deep, multi-lens code review of one or more pull requests.

**You are the orchestrator.** You do not review any diff yourself and you do not edit any repo's files. You resolve each PR to its local checkout, launch one **review driver** sub-agent per PR, broker the judgment-call questions those drivers send back, and aggregate their results into a single report to the user. The drivers do the reviewing and the implementing.

This holds even when there is exactly one PR. One PR means one driver — not a review you run inline. Keeping a single path means the experience, the question flow, and the failure modes are identical whether you were given one PR or five.

## Why the pipeline is shaped this way

Two independent structures are at work; don't confuse them.

**Across PRs (this file's Phases A–D):** one driver per PR, running concurrently. Each owns its PR end to end.

**Within a PR (Phases 0.5–9, which each driver runs):** a single-pass review naturally focuses on the most prominent issues (the "top layer"), so deeper issues are easy to miss. Rather than discovering layers sequentially, each driver fans out several independent review agents **concurrently**, each assigned a distinct, non-overlapping *lens* (design, correctness/security, cross-file contracts, logic/intent). Diversity of coverage comes from the disjoint lenses, not from one reviewer re-reading with a hint — which means the lenses have no data dependency on each other and can run in parallel without sacrificing depth. A final consolidation step collapses overlap and re-derives cross-finding dependencies holistically.

Breadth is only half the job. A review that surfaces every conceivable concern isn't a good review — it becomes a source of over-engineering, since Phase 9 implements whatever survives to the report. So the pipeline is deliberately asymmetric: the lenses cast wide, and three successive filters (Phase 3 validation, Phase 4's skeptical critic, Phase 5's user calibration) lean toward dropping. The bar a finding should clear is being worth the complexity its fix would add, not merely being technically defensible.

Under `--auto` the third filter loses its human and the orchestrator applies *Weighing What a Change Costs* in their place. Note what that does and doesn't change: the filter still leans toward dropping **unestablished** problems, and just as firmly toward implementing established ones properly. Auto mode is not a more timid review — it is the same bar, applied without someone to ask.

The command does not stop at the report. Once a driver's report is written, it **implements every task in it, runs the checks, and commits & pushes** (Phase 9) — the report is the plan for that work, not the deliverable.

**Arguments:** `$ARGUMENTS` — zero or more GitHub PR URLs or numbers, space-separated, optionally preceded or followed by `--auto`. Each PR argument identifies a PR to review; **Phase A resolves each to its local checkout**. With no PR arguments, the review targets whatever branch is checked out in the current directory (the legacy single-PR behavior), still via one driver.

### `--auto` — unattended mode

`--auto` (alias: `--unattended`) runs the entire pipeline without ever putting a question to the user. Strip the flag from `$ARGUMENTS` before treating the rest as PR references, and set `AUTO_MODE = true` for the run.

**In auto mode you never call `AskUserQuestion`, for anything, at any phase.** Not for setup, not for findings, not for a case this file didn't anticipate. Every decision the interactive path would forward, you make yourself, reasoning from *Weighing What a Change Costs* below. The places this changes are marked **`--auto`:** inline throughout; where no marking exists, the interactive behavior already needed no human.

The user chose an unattended run knowing decisions would be made on their behalf. Making them is the job — a run that stalls waiting for input it was told not to seek has failed, and so has one that defers every hard call to avoid deciding. Your record of what you decided and why is the final summary (Phase D), which is where they audit the run after the fact.

## Resolved Plugin Root

!`echo "${CLAUDE_PLUGIN_ROOT}"`

That line is expanded when the slash command is invoked, so it is already the literal path by the time you read it. Use it wherever this file writes `<PLUGIN_ROOT>`. Do **not** try to recover it by running `echo "${CLAUDE_PLUGIN_ROOT}"` yourself — the variable is expanded by the harness in `!`-backtick directives and `allowed-tools`, but it is **not exported into the Bash tool's environment**, so it prints an empty string there.

---

## Code Review Principles

!`"${CLAUDE_PLUGIN_ROOT}/scripts/inline-doc.sh" "${CLAUDE_PLUGIN_ROOT}/docs/code-review.md"`

---

## Weighing What a Change Costs

!`"${CLAUDE_PLUGIN_ROOT}/scripts/inline-doc.sh" "${CLAUDE_PLUGIN_ROOT}/docs/change-cost.md"`

---

## Part I — Orchestration (you run this)

Phases A–D are yours. Phases 0.5–9 that follow them are the **driver's** instructions, not yours; you pass drivers the path to this file and they execute those phases themselves.

### Phase A: Resolve Every PR to Its Local Checkout

We do all of our work in **git worktrees**. In practice this command is almost always invoked from the *primary clone* of the repo (which is sitting on `main`), while the branch for a PR under review is checked out in a **worktree** elsewhere on disk. So the directory you start in is usually **not** where any PR's code lives.

Resolve **every** PR argument before launching **any** driver. Settling all the setup questions up front matters more here than it did when this command reviewed one PR: once drivers are running they will send back review questions, and you do not want a "which worktree?" prompt arriving in the middle of that stream.

For each `<arg>` in `$ARGUMENTS`:

**Step A1 — Resolve the PR to its head branch.**

```bash
gh pr view <arg> --json number,headRefName,headRepositoryOwner,headRepository,title,url
```

The `headRefName` field is the branch name you need to find locally.

**`gh` resolves the repo from the current directory.** A bare PR *number* therefore means "PR #N **in whatever repo you are standing in**" — so a bare number meant for another repo either 404s or, worse, silently resolves to a different real PR that happens to share the number. Full PR URLs carry their own repo and are safe from anywhere. Resolve bare numbers against the cwd's repo only; for PRs in other repos, expect full URLs or pass `--repo owner/name` explicitly.

**Step A2 — Find the worktree for that branch.**

```bash
git worktree list --porcelain
```

Each worktree appears as a `worktree <path>` line followed by a `branch refs/heads/<name>` line. Find the entry whose `<name>` equals the PR's `headRefName` and note its `<path>`.

`git worktree list` only knows the repo you run it in. If a PR belongs to a **different repo**, resolve that repo's local clone first (ask the user if you can't find it) and run the worktree lookup from there. Reviewing PRs across several repos in one run is fine — the drivers are independent — but each PR must be resolved against its own repo, and a `headRefName` that doesn't appear in *this* repo's worktree list is not evidence that no checkout exists.

**Step A3 — Record the resolution.** Build a table of `PR number → { url, branch, worktree path, repo, title }`. Identify the repo with `git -C <worktree path> rev-parse --git-common-dir` — worktrees of one repo share a `.git`, and that shared path is what tells you two PRs are siblings. You will pass each row to its driver, and you will use the PR number to label every question and result from here on.

**Note which PRs share a repo**, because their drivers are not independent:

- Review and analysis are read-only — launch all drivers concurrently regardless.
- **Serialize the Phase 9 tails within a repo group.** Resume one driver at a time there and wait for its Stage 2 result before resuming the next. Implementation, `just check`, and commits contend on the shared `.git` index and on build caches; running them concurrently in one repo is how you get lock errors and confusing check failures. Across different repos there is no contention — resume freely.
- Check whether same-repo PRs are **stacked** (one's `baseRefName` is another's `headRefName`). If so, resume the base PR's driver first so the dependent PR's fixes land on top rather than racing it, and say so in the final summary — a stacked pair the user didn't flag is worth surfacing.

**Handling the cases where no worktree matches:**

- **The current directory is already on the PR's branch.** `git rev-parse --abbrev-ref HEAD` already equals `headRefName` — use the current directory as that PR's checkout.
- **The branch exists locally but not in a worktree, or no local checkout exists at all.** Create one — `git worktree add .worktrees/<headRefName> <headRefName>` from that repo's primary clone (fetch the branch first if it's only on the remote), then use that path. Don't ask; a worktree is where the work belongs either way, and creating one is cheap and reversible. Note in the final summary which PRs you created worktrees for, so the user knows what appeared on disk.
- **`gh pr view` fails** (bad URL/number, no network, not authenticated, or the arg isn't a PR). Record that argument as **unresolved** with the actual error and move on to the others. Never fall back to reviewing whatever branch you happen to be on — a review of the wrong code is worse than no review.
- **One PR fails to resolve, others succeed.** Proceed with the rest; one bad argument doesn't sink the run. Every unresolved PR is reported in the final summary with the error that stopped it and what the user needs to do about it — the run continuing is not the same as the problem being handled, and they can only fix it if you say so plainly.
- **Every PR fails to resolve.** There is nothing to review. Report the errors and stop; don't launch a driver against the current branch as a consolation.

**No arguments at all:** there is one target — the current directory's branch. Resolve it with `git rev-parse --abbrev-ref HEAD` and `gh pr view` for its metadata (which may find no PR; that's allowed and Phase 9 handles it). One driver still runs it.

### Phase B: Launch One Driver per PR

Spawn one `dev:review-driver` sub-agent per resolved PR, using the `Agent` tool.

**Launch them all in a single message** so they run concurrently. **Capture every agent ID** — you resume each driver through its ID in Phase C, and losing one strands that PR's review along with everything it remembers.

Pass each driver:

- `PLUGIN_ROOT` — the literal path printed under **Resolved Plugin Root** near the top of this file. The driver is a sub-agent reading this file off disk; `${CLAUDE_PLUGIN_ROOT}` is not set in its environment (nor in yours), and several pipeline steps (the report directory, posting to the PR) are shell commands built from it. Every other path below is derived from this one — pass them resolved too, not as `${...}` strings.
- `COMMAND_PATH` — the absolute path to **this file**: `<PLUGIN_ROOT>/commands/deep-review-pr.md`. The driver reads it and executes Phases 0.5–9.
- `PRINCIPLES` — the **full text** of this file's own **Code Review Principles** and **Weighing What a Change Costs** sections, copied into the driver's prompt verbatim. You already have both: the `!`-backtick directives that produce them are expanded when the *slash command* is invoked, so what you are reading is the doc text itself. Do not re-run `inline-doc.sh` to get it; if a section did come through as a `[!WARNING]` block, `Read` the file it names under `<PLUGIN_ROOT>/docs/` and pass that text instead. Passing this is not optional: a driver `Read`s this file off disk and sees two literal backtick lines, so without it, it reviews and recommends with no principles at all.
- `PR_NUMBER`, `PR_URL`, `BRANCH`, `WORKTREE_PATH` — from your Phase A table.
- `FIX_SPEC`, `CI_FIX_SPEC`, `COMMIT_SPEC` — absolute paths to `<PLUGIN_ROOT>/docs/fix-loop.md`, `ci-fix-loop.md`, and `commit-loop.md`. Drivers read these and execute the loops inline.
- `AUTO_MODE` — `true` when the run was invoked with `--auto`, otherwise `false`. Drivers behave almost identically either way (they could never ask the user regardless), but this tells a driver that its questions will be answered by you rather than by a human, which changes how it writes them. Pass it explicitly; a driver that isn't told assumes `false`.
- Any metadata you gathered while resolving that PR.

Tell each driver to **skip Phase 0** — you already did that work.

Then **say what you launched** — one line per PR (number, title, branch) — so the user knows what is in flight. After that, end your turn. Results arrive as events.

### Phase C: Broker the Questions

Each driver reviews its PR, reaches Phase 5, and returns a **question batch**: the judgment-call findings where the right answer depends on context the driver doesn't have. Your job is to get every one of those decided — answering what you can, asking the user the rest — and then resume each driver.

**Batches arrive as events. Do not wait for them.** When a driver returns, its result is delivered to you automatically in a later turn. There is no file to poll, no task output to `stat`, no status to check. Do not write a `Bash` loop (`until [ ... ]`, `sleep`, `stat`, tailing a `.output` file) to "wait for the drivers" — any such loop blocks the very turn the result needs in order to reach you, and it will spin until it times out while the answers sit undelivered. **With several drivers in flight this is the single most likely way to break this command.** Yield the turn; the batches will land.

Work each batch as it arrives rather than holding out for all of them. A driver that has returned is idle until you resume it, so a PR whose questions you've already settled should be back at work while another PR is still reviewing.

#### Decide each question: answer it yourself, or ask the user

**Route on the question's `blocking_context` field.** The driver read the code and named what it was missing; that classification decides the route, so you are not re-litigating a judgment from a position of *less* context than the agent that raised it.

| `blocking_context` | Route (interactive) | Route (`--auto`) |
|---|---|---|
| `threat-model` | **Ask the user** — only they know what this system is exposed to | Decide it |
| `upstream-controls` | **Ask the user** | Decide it |
| `complexity-budget` | **Ask the user** | Decide it |
| `realistic-scale` | **Ask the user** | Decide it |
| `remediation-choice` | **Ask the user** | Decide it |
| `none` | **You may answer it** | Decide it |
| missing / unrecognized | **Ask the user** | Decide it |

`none` means the driver flagged something out of caution but could name no missing context. Those are yours to decide in either mode: check the recommendation against the criteria in *Weighing What a Change Costs*, and take it unless you can say concretely why an alternative is better.

Three rules on top of the routing, in **interactive** mode:

- **Never auto-answer a Security or Privacy finding**, whatever its `blocking_context`. That is the category where a review most often overreaches and where the user's threat model is the thing that settles it. Forward them.
- **Check against decisions you've already made** for other PRs in the same repo before answering. If two drivers propose incompatible changes to shared code, ask — auto-answering both independently is how they land as a conflict.
- **Your convenience is never a reason to answer.** Not the question count, not wanting an unattended run, not a batch that would be tedious to frame. Volume is an argument for batching related questions into fewer calls, never for deciding them yourself.

When a question doesn't fit the table — the field is absent, the value is unfamiliar, or the classification looks wrong for what the question actually asks — **ask**. Auto-answering something the user wanted to decide is the worse error: it is silent, and by the time they read your summary the driver has already implemented, committed, and pushed it.

The one rule that survives into auto mode is the middle one, in altered form: **cross-PR conflicts still need reconciling, you just reconcile them yourself.** Before deciding a question, check it against decisions already made for other PRs in the same repo. Two drivers proposing incompatible changes to shared code is a real problem that no longer has a human to catch it — pick one approach, apply it to both, and say so in each driver's resume message.

#### `--auto`: deciding every question yourself

There is no forwarding path. Every question gets an answer from you, and *Weighing What a Change Costs* is the instrument you decide with. Work each question in that document's order:

**1. Is the problem real?** Name the trigger — which caller, which input, which state. Check what already covers it: an upstream validation, an auth boundary, a type signature, a database constraint. For anything security-shaped, assume a realistic adversary, one who does not already hold code execution, database write access, or deploy config.

A question you cannot answer from the diff and the codebase resolves *against* the finding. `blocking_context` is the driver telling you it could not establish something; when you cannot establish it either, the problem is unestablished, and an unestablished problem earns no change at all — not a guard, not a comment, not a hedge. Defer it and record why.

**2. Then fix it properly.** Once the problem is real, cost stops being an argument against the correct fix. Its size, its churn, the scope it widens into, its conflict with an existing pattern in the codebase — none of those are grounds to pick the smaller wrong fix, and none are grounds to defer. **Bias toward action here.** An unattended run is not a reason to be timid about a real problem; it is a reason to be rigorous about step 1. Having done that rigorously, take the correct fix.

The one legitimate objection is the narrow one: the fix carries concretely more risk than the problem it removes. Read it as narrowly as the doc does — a rewrite of a critical path to close a minor edge case, a schema migration for a cosmetic inconsistency. "This change is large" is not that objection.

**3. Watch the remedy, not just the claim.** The dangerous shape is a real observation attached to a disproportionate fix: the concern survives scrutiny aimed at truth, and a permanent defensive layer lands for a problem that never warranted one. When the concern holds but the proposed remedy doesn't, don't choose between implementing it and dropping it — decide on a proportionate fix and say so in the resume message, so the driver updates the finding's **Suggestion** before implementing.

**4. Keep the fix inside this PR's scope.** A real problem whose root predates this change earns a finding and a follow-up, not an in-place refactor. This bites harder unattended: nobody is watching the blast radius. If the change under review introduced the problem, fix it at its root however far up that goes. If it merely became visible here, defer it with that reason.

**Security and privacy findings are decided too**, on these same tests rather than a category-level exception. Interactive mode forwards them because the user's threat model settles them; unattended, the realistic-adversary and reachability tests stand in for it. A security finding with a named entry point and a traceable path to attacker-controlled input is a real problem — fix it properly, and don't discount it for being large. A security finding that cannot name where untrusted input enters has not established a problem, however severe the imagined consequence, and severity is never a substitute for that. Both of those are decisions; neither is a deferral for its own sake.

**Record every decision as you make it** — PR, finding, the option chosen, the change-cost step that settled it, in one line. In interactive mode this log is a courtesy. Here it is the only account of the run's judgment that reaches the user, and Phase D depends on it.

**Do not post framing messages in auto mode.** There is nothing to frame; nobody is going to answer. Decide, resume the driver, and let the summary carry the record.

#### Asking the user

**`--auto`: skip this entire subsection.** You decided every question above; there is nothing to ask and nothing to frame. Resume the drivers.

Use the `AskUserQuestion` tool — literally, not a paraphrase or an inline prompt asking them to reply in chat.

**Frame before you ask.** The user has not seen any findings — no report exists yet. Post a brief conversation message covering, for each question you're about to put to them: what the finding is, why it matters, why it's a judgment call, and what the options mean. Keep it tight. Then go straight to the `AskUserQuestion` calls without waiting for acknowledgement.

**Label the PR everywhere.** With several reviews in flight, a question that doesn't name its PR is unanswerable. Put the PR number in the framing and in the question stem.

**Batch what reads naturally.** Several questions from one PR can share a call. Don't batch unrelated questions just to reduce call count.

**Batching across PRs is allowed but constrained.** The same pattern flagged in two reviews is worth deciding once. But `AskUserQuestion` returns one option per question, and you then have to apply that one answer to two findings in two codebases — so only batch across PRs when **every option is meaningful for every finding in the batch**. "Defer — file a follow-up ticket" may be fine for one PR and incoherent for another where the finding is the last thing blocking a merge. When you can't phrase options that fit both, ask separately; one extra prompt is cheap compared to applying an answer that didn't fit.

When you do batch across PRs, spell out the per-PR consequence in each driver's resume message. "The user chose *fix at the boundary*" means different code in each repo, and each driver only sees its own.

**Frame each question as "how should we address this?"** — not "what severity?". Options must commit to an action: fix now (optionally with a named alternative approach), or defer (with a path — follow-up ticket, code comment, or drop it). Severity adjustments can ride along with an option but are never its main content. Lead with the question; note your view if you have one, but don't lobby.

#### Resume the driver

Once every question in a PR's batch is decided, send that driver its decisions with `SendMessage`, addressed to the agent ID you captured in Phase B.

The driver resumes **with its full context intact** — its diff, findings, and reasoning are all still there. Send the decisions, not a recap of its own review.

For each question, state the outcome unambiguously: which option was chosen, any severity adjustment, and — where the user picked a specific alternative approach — what that approach is, so the driver updates the finding's **Suggestion** before implementing. Note which decisions were yours and which were the user's; a driver should not report a decision as the user's if you made it.

A batch with no questions still needs a resume message: send it an empty decision set so it proceeds to Phase 6.

#### When a driver returns something other than a clean batch

- **A batch with `from_phase: 1`.** The driver couldn't determine the PR's intent and has reviewed nothing yet. These are clarifying questions about what the change is *for*, not findings — frame them that way, and expect a Phase 5 batch from that driver later. This is rare; most drivers resolve intent themselves.

  **`--auto`:** you answer these too, from the PR description, the commits, the linked ticket, and the diff itself. Where the intent stays genuinely ambiguous, tell the driver to review against the **most conservative** reading — the one under which the change claims the least — and to note the ambiguity in its report. A review aimed at a narrower intent than the real one produces findings that are merely incomplete; one aimed at a wider guessed intent produces findings aimed at a change nobody made.
- **A second batch after you resumed it.** Allowed, and handled exactly like the first: decide, resume, continue. Expect at most two per driver in the normal case (an intent batch, then a findings batch), but a decision can legitimately open a follow-on question. Don't treat a repeat batch as an error or a loop. If a single PR is still asking after **three** rounds, stop resuming it — say so in the final summary with the open questions, and let the other PRs finish.

  **`--auto`:** the same three-round cap applies, and it matters more here. Interactive rounds terminate because a human eventually settles the question; unattended, both sides of the loop are you, so a driver that keeps asking is one you keep answering with the same information. On the third batch, decide every remaining question outright — apply the change-cost tests and send a final, binding decision set rather than a fourth resume. Say in the summary that the PR needed three rounds, since a driver that couldn't settle usually means the review found something genuinely ambiguous.
- **A malformed or partial batch** — missing recommendations, questions with no options, a result you can't parse. Don't guess at what it meant. Send it back one time via `SendMessage`, naming what was missing. If the second attempt is also unusable, record the PR as failed in the summary and move on.
- **A driver that errors out or returns nothing.** Record it as failed with whatever error you have and continue with the rest. One dead driver is not a reason to abandon the other PRs, and it is not a reason to review its PR yourself.
- **A Stage 2 result when you expected a batch.** The driver found no judgment calls and ran straight through. Nothing to resume — take the result.

Never resume a driver that has returned a Stage 2 result; it is finished.

**Keep a running log of every question you auto-answered** — PR, finding, the option you chose, and one line of why. It goes in the final summary.

When you are already posting a framing message for questions you're forwarding, add the ones you decided as a short bulleted list in the same message — one line each — noting the user can override any of them. This costs a few lines and turns a decision they'd otherwise read about after the code changed into one they can still catch. Don't post a message *solely* to announce auto-answers; fold them into the framing you're already writing, or leave them for the summary.

### Phase D: Aggregate and Report

Each resumed driver implements its tasks, drives `just check` green, pushes, and posts its report to its PR, then returns a Stage 2 result. These also arrive as events — the same no-polling rule applies.

Write the summary when every driver has either returned a Stage 2 result or been recorded as failed. A driver that died, errored, or produced nothing usable is *resolved* for this purpose — write the summary without it rather than holding the report open for a result that is not coming. Never review its PR yourself to fill the gap; report the gap.

Write **one** summary covering all of them. Per PR:

- PR number, title, and branch
- Tasks implemented, and any left unfinished with the reason
- `just check` status, whether the branch was pushed, whether the report was posted (and where it was saved)
- The **verdict at review time**, labeled as such — e.g. `Verdict at review time: NOT CONVERGED — 3 Urgent, 3 High`
- The driver's **recommendation**: merge, another deep review, or a targeted review with a named scope

Then, across all PRs:

- **Auto-answered decisions** — the log from Phase C, grouped by PR: the finding, the option chosen, and one line of why. This is where the user learns what you decided on their behalf.

  **`--auto`:** every decision was yours, so this section is the run's whole audit trail rather than a footnote — give it the space that implies. Per decision: the finding, what you chose, and which change-cost step settled it (the problem was unestablished; the fix was disproportionate; the root predates this PR; the correct fix was large and you took it anyway). Call out separately, at the top, the decisions the interactive path would have escalated — every security and privacy finding, and anything you deferred — since those are the ones the user is most likely to want to overturn. State plainly that these were made without their input and can be revisited.
- **Anything that failed** — a PR that wouldn't resolve, a driver that couldn't finish, a red check, a report that didn't post. Report these plainly with the actual error; a partial run is a normal outcome, and hiding the gap is not. Unresolved PR arguments belong here with what the user needs to do about each one.
- **Worktrees created** — any checkout Phase A created that wasn't there before, with its path.
- **Cross-PR observations**, only where they're real — the same finding pattern in several PRs, or a change in one that affects another. Don't manufacture these.

The per-PR recommendation is the driver's, made after its fixes landed, so it can legitimately differ from that PR's review-time verdict. A NOT CONVERGED report whose findings were all cleanly implemented should normally end in *merge*. Don't carry the old verdict forward as if it still held.

---

## Part II — The Review Pipeline (the driver runs this)

Everything below is the **driver's** instruction set. As orchestrator you do not execute these phases; you pass this file's path to each driver and it runs them against its own PR.

Where these phases say "you," they address the driver. Where they say to ask the user, the driver instead returns a question batch — it has no `AskUserQuestion` tool — and you handle it in Phase C.

Phase 0 below is superseded by Phase A: the orchestrator has already resolved the PR to its worktree and passes the path. Drivers start at Phase 0.5, from that directory.

### Phase 0: Locate the PR's Local Checkout — *superseded*

Phase A did this. The orchestrator passes you `WORKTREE_PATH`; start at Phase 0.5, which opens by confirming it.

### Phase 0.5: Gather Context (from the resolved checkout)

**First, confirm you are in the right place.** The orchestrator passed you `WORKTREE_PATH` and `BRANCH`:

```bash
cd <WORKTREE_PATH>
git rev-parse --abbrev-ref HEAD   # must equal BRANCH
```

If it doesn't match, stop and return that as an error rather than reviewing whichever branch you found — a mismatch means you would silently review the wrong code. Every remaining phase runs from this directory.

Then gather the review context and prior reports. Run each with `Bash` **from this directory** (do not let these run against `main` in the primary clone):

**Prior Review Reports (calibration anchors).** Existing reports for this branch establish the priority scale this review calibrates against, preventing priority inflation across successive reviews. The report directory is branch-derived, so it must be computed from the resolved checkout:

```bash
REPORT_DIR=$("<PLUGIN_ROOT>/scripts/branch-report-dir.sh")   # PLUGIN_ROOT: the resolved path the orchestrator passed you
if [ -d "$REPORT_DIR" ] && ls "$REPORT_DIR"/*.md >/dev/null 2>&1; then
  for f in $(ls -t "$REPORT_DIR"/*.md); do
    echo "=== Prior Report: $f ==="; cat "$f"; echo "=== End Prior Report ==="
  done
else
  echo "(No prior reports found for this branch — this is an uncalibrated first review.)"
fi
```

Remember the resolved `REPORT_DIR` — Phase 8 writes the report there.

**Current context** (branch, PR metadata, commits, diff shape):

```bash
git rev-parse --abbrev-ref HEAD                                  # Branch
gh pr view --json title,body,labels,url 2>/dev/null \
  || echo "No PR found - reviewing branch diff"                  # PR Details
git log main..HEAD --oneline                                     # Commit History
git diff main...HEAD --stat                                      # Diff Statistics
git diff main...HEAD --name-only                                 # Changed Files
```

Capture the PR metadata, commit history, diff statistics, and changed-file list — these feed Phase 1 and the lens fan-out in Phase 2.

### Phase 1: Understand Intent (Review Scout)

Spawn the `review-scout` agent (inherits the session model) to perform a fast first pass. Pass it:
- The PR metadata from the context above (title, description, labels, commit messages)
- The changed file list and diff statistics
- The changed files themselves (for structural scanning)

The agent will return:
- **Intent summary**: What this PR does and why
- **Structural overview**: Shape of the change at a high level
- **Context gaps**: Areas where intent is unclear

If the agent reports context gaps, first try to close them yourself from material you can reach: the PR description and linked issues, the commit messages, the branch's prior reports, and the surrounding code. Most gaps close this way.

For a gap that genuinely blocks the review — you cannot tell what the change is *for*, and reviewing without knowing would produce findings aimed at the wrong target — return a question batch (the Step 2 shape in Phase 5) with `stage: 1` and **`from_phase: 1`**, your questions describing what you need to know, then stop. `from_phase` matters: it tells the orchestrator you have not reviewed anything yet, so the questions are about intent rather than findings. The orchestrator resolves it and resumes you; continue at Phase 2 from there.

Use this sparingly. It stalls this PR's review until a human answers, which is worth it for genuinely unreadable intent and wasteful for a detail you could have inferred. A gap that leaves you unsure about one finding is not a blocker — review the rest and raise that finding as a Phase 5 judgment call instead.

**Do not proceed to Phase 2 until intent is clear.**

### Phase 2: Parallel Multi-Lens Deep Review (Workflow Fan-Out)

This phase fans out several `review-analyst` agents **concurrently**, each assigned a distinct, non-overlapping *lens*. Because the lenses are disjoint, the agents have no data dependency on each other — they run in parallel, and a barrier collects all findings before handing a single combined list back to the orchestrator for Phase 3.

Every lens is pointed at **code**. There is deliberately no synthesis step that reviews the *findings* rather than the diff: a reviewer whose only input is other reviewers' output has little concrete to check a hypothesis against, and its cheapest route to a non-empty result is inventing a cross-concern story. Cross-cutting concerns are real, but the lens mandates below overlap enough to catch most of them, and Phase 3 re-derives cross-finding relationships from the full set with the code in hand.

Drive the fan-out with the **`Workflow`** tool. Pass the lens definitions, diff, intent summary, and changed-file list through the workflow's `args`, and have the script spawn one `review-analyst` agent per lens via `parallel()`.

> **CRITICAL — pass the diff and other large/free-form text via `args`, never inline it into the `script`.**
> The workflow `script` is parsed as plain JavaScript. The git diff contains backticks, `${...}`, backslashes, and unbalanced quotes that will break the parse if pasted into a string literal — and the obvious "safe" workaround, writing `const DIFF = ${JSON.stringify(theDiff)}` in the script you author, is itself a syntax error (the script body may not contain author-time `${...}` interpolation; the runtime sees the literal `${` and fails at parse time). Workflow scripts also cannot read files from disk.
>
> The supported path is the `args` channel: put the diff, intent summary, changed-file list, lens definitions, and any other data into the **`args`** parameter of the `Workflow` tool call as a real JSON object (the tool serializes it for you), and reference it inside the script via the `args` global. The script stays a small, static, parse-clean orchestration program with **zero embedded PR content**.
>
> One catch: **`args` arrives inside the script as a JSON *string*, not a parsed object.** Always parse it at the top before use — `const a = typeof args === 'string' ? JSON.parse(args) : args`. Destructuring `args` directly (e.g. `const { diff } = args`) silently yields `undefined` fields, and the first `.map`/`.filter` then throws `undefined is not an object`.
>
> ```js
> // In the Workflow tool call:  args: { diff: "<full git diff>", intent: "...", files: [...], lenses: [...] }
> // Inside the script body — parse args first, then read everything off it:
> const a = typeof args === 'string' ? JSON.parse(args) : args
> const { diff, intent, files, lenses } = a
> phase('Lenses')
> const lensResults = await parallel(lenses.map(lens => () =>
>   agent(`${lens.mandate}\n\nINTENT:\n${intent}\n\nDIFF:\n${diff}`,
>         { label: `lens:${lens.key}`, phase: 'Lenses', schema: FINDINGS_SCHEMA, agentType: 'dev:review-analyst' })
>     .then(r => ({ lens: lens.key, findings: (r && r.findings) || [] }))))
> ```
>
> (The `${...}` above is fine — it runs at workflow *execution* time against the real `args` values. The rule is only that the script you *submit* must be valid JS with no author-time interpolation and no inlined diff.)

#### The Lenses

Each lens is the **same** `review-analyst` agent (opus) given the standard inputs (intent summary from Phase 1, full diff, changed file list, principles, project conventions) **plus** a lens-specific mandate appended to its prompt. The mandate both *focuses* the agent and *bounds* it — it reports findings in its lane and explicitly defers the others to avoid cross-lens duplication.

- **Lens A — Design & Architecture:** "Review **only** abstractions, responsibilities, architectural fit, API surface, extensibility, and coupling. Evaluate whether the change respects existing layering and separation of concerns. Defer correctness, security, edge-case logic, and intent/doc issues to other reviewers — do not report them."
- **Lens B — Correctness, Edge Cases & Security (adversarial):** "Take an adversarial perspective and review **only** correctness, realistic edge conditions, and security: bugs in state transitions, boundary conditions, concurrent access, and error paths; trust boundaries, input validation, injection vectors, secrets handling, authorization. What happens when dependencies return unexpected values? What invariants are assumed but never asserted? For an edge condition, **'realistic' is load-bearing** — try to name the caller or input that actually reaches it. An edge case nobody can reach usually isn't worth a finding, since guarding it costs a branch forever; use judgment when the consequence would be severe. **Try to ground each security finding in a reachable path.** Before reporting one, name where the untrusted input actually enters the system and how it reaches this code; if you can't trace that, it's more likely a hypothetical than a vulnerability, and usually better left out — though weigh the stakes, since a severe enough outcome can justify raising a concern you can only partly trace. Then sanity-check three things that tend to inflate security findings: whether an upstream control (authentication, validation, network boundary) already covers this, so an added check here would be defense-in-depth for its own sake; whether the attacker you're imagining is realistic for this system — generally assume one who does *not* already have code execution, database write access, or the ability to edit our deploy config, since a finding presupposing any of those describes a scenario we've already lost; and whether the data or exposure is genuinely as sensitive as the finding treats it. Those are illustrations rather than a complete list — use your judgment. Defer design, cross-file, and documentation issues to other reviewers."
- **Lens C — Cross-File Contracts & Integration:** "Review **only** cross-file interactions: implicit contracts between modules, error propagation across boundaries, assumptions in glue code connecting the changed components, and mismatches between a caller's expectations and a callee's behavior. Defer single-file design, security, edge-case logic, and intent/doc issues to other reviewers."
- **Lens D — Documentation (truth and worth):** "Review **only** the documentation layer this PR adds or changes — docstrings, inline comments, PR description, README sections — on two axes, plus misleading names where they genuinely confuse.

  **(1) Truth.** Documentation artifacts that contradict each other or the code: a comment stating a retired mechanism as live fact, a docstring naming a symbol or file that no longer exists, a pointer to something the reader cannot locate, a stated purpose the code has drifted from.

  **(2) Worth.** Comments that do not earn their place under the comment principles loaded in your agent definition. The test is whether you can name the specific mistake or misunderstanding a comment prevents. Apply it in this order: if you *can* name the mistake, the comment stays — say so and move on, even if it is long. Only when you cannot is there a finding. Expect this axis to fire on: deliberation published instead of the conclusion (a `WHY:` heading, enumerated reasons, a `Cost:` paragraph); prose written from the diff's position rather than the reader's (*previously*, *used to*, *this PR*, *is now*); restatement of what the code or a typed signature already says; an architecture essay in a module docstring that `docs/` should own; and the same fact explained in more than one place.

  **Bounds on axis (2), which matter because prose is often a large share of a diff.** Report specific comments, never a whole file — a finding names a `file:line` and proposes the compressed replacement, or says to delete it. There is no cap: report every comment that genuinely fails the test, and if that is a long list on a prose-heavy PR, that is the honest result. A comment that prevents a production incident, a security hole, or data loss is not a finding no matter its length. When you are unsure whether a comment earns its place, leave it alone — a false positive here trains the author to ignore this lens, which costs more than the comment does, so the filter is your confidence in each finding rather than a quota.

  Defer design, security, correctness, edge-case, and cross-file issues to other reviewers."

Every lens applies the analyst's standard discipline from its agent definition: high-confidence findings only, PR-introduced issues only (not pre-existing), category-first prioritization, concise one-line-per-finding output.

#### Workflow Output

The workflow returns the four lenses' combined raw findings. Note that the lenses do **not** tag downstream dependencies between findings (they can't — they run blind to each other). Re-deriving cross-finding dependencies is entirely Phase 3's job, which is the right place for it: consolidation already sees every finding at once and can reason about fix-ordering holistically.

Hand the combined findings list to Phase 3. Note the per-lens counts — they go in the report's methodology table, and your output reaches no one, so there is nothing to display.

### Phase 3: Consolidation and Absolute Reprioritization

After the workflow returns, consolidate all findings from all lenses:

1. **Deduplicate**: Because the lenses run blind to each other, the same concern can surface from more than one lens (e.g., a coupling issue caught by both Design and Cross-File). When multiple lenses found the same concern (same file + same issue), keep the version with the most detailed description and discard the rest. If findings describe the same pattern in different files, keep them as separate findings but note the shared pattern. Expect more raw overlap here than the old sequential design produced — dedup is doing real work, not a formality.

2. **Derive cross-finding dependencies**: The lenses ran independently and did **not** tag dependencies between findings, so you must derive them now from the full set. For each pair where fixing one finding would eliminate or fundamentally change another (a downstream consequence), decide:
   - **Keep both** if the downstream finding is a genuinely separate concern that would need its own fix even after the parent is resolved — record the dependency in the finding's **Dependencies** field so Phase 6 can set correct fix ordering.
   - **Drop the downstream finding** if fixing the parent would eliminate it entirely.
   - **Merge it** into the parent finding's description if it adds useful context about the parent's impact but isn't a separate fix.

   This is the right phase for dependency reasoning: you see every finding at once, which the per-lens agents could not.

3. **Reprioritize on an absolute scale**: Each lens assigned priorities relative to what it saw in its own lane. Now that you have the full picture, assign final priorities on an absolute scale:
   - **Urgent**: Bugs and security vulnerabilities that will cause harm in production
   - **High**: Design issues and intent contradictions with compounding cost
   - **Medium**: Logic gaps under realistic edge conditions
   - **Low**: Improvements (naming, style, simplification, performance)

   **If prior review reports were loaded above:**

   The prior reports define the priority scale for this PR. Use them to prevent priority
   inflation — where issues get promoted simply because worse issues have been fixed.

   Calibration protocol:
   a. Extract the findings from each prior report with their assigned priorities.
   b. For each finding in the current review, ask: "If this finding had appeared alongside
      the prior report's findings, what priority would it have received?" Assign that priority.
   c. If a finding from a prior report is still present (not fixed), retain its original priority.
   d. New findings should be calibrated against the prior scale by severity, not by their rank
      among current findings. A naming issue is still Low even if every Urgent/High issue is gone.
   e. The goal is convergence: if all prior Urgent/High issues are fixed and no equally severe
      issues are introduced, this review should show 0 Urgent/High findings. This is the desired
      outcome — do not promote Medium/Low findings to fill the gap.

4. **Validate each finding**: Read the relevant code yourself to confirm the finding is real. Drop anything you can't confirm. (Note: this is a low bar — the deeper skeptical filtering happens in Phase 4 below, run from a clean sub-agent context.)

5. **Apply the budget**: Keep all validated findings regardless of priority. If you'd be left with 0 findings, that's a valid outcome — say so.

### Phase 4: Skeptical Critique (Review Critic Sub-Agent)

Your context at this point has shepherded a multi-lens review and is invested in the findings — loss-aversion bias is real. The critique step deliberately runs in a fresh sub-agent context so it can be ruthlessly skeptical without sponsoring the findings it's evaluating.

In practice, deep reviews tend to drift in two directions, and this phase backstops both. The first is scope: spreading the work across disjoint lenses widens the net, so reviews often surface everything wrong with the touched code rather than only what the PR caused. The second, and usually the more expensive one, is proportion — findings whose *concern* is technically real but whose *fix* costs more complexity than the risk warrants. Since Phase 9 implements the tasks that reach the report, a disproportionate finding doesn't just add noise; it can add a defensive layer, an abstraction, or a validation shim to the codebase permanently. So the critic weighs the remedy and its reachability, not just whether the concern is true.

#### Spawn the `review-critic` agent

Spawn the `review-critic` sub-agent (opus, fresh context). Pass it:

- **The post-consolidation findings list** — each entry with `F<n>`, priority, file:line, category, and description
- **The full diff** — `git diff main...HEAD`
- **A note about prior reports** — which prior reports were loaded for calibration, so the critic preserves explicit carryovers (e.g., findings tagged `[Prior Report #7]`)
- The critic has `Bash` available and will use `git show main:<path>` / `git diff main...HEAD -- <path>` to determine whether each finding describes a condition that pre-existed this PR.

The critic returns a per-finding verdict (`keep` / `drop` / `downgrade`) with a one-line rationale, plus a summary line `Kept N, dropped M, downgraded K of T total.`

#### Apply the verdicts

1. **Drop** findings the critic flagged as drop.
2. **Downgrade** priorities where the critic recommended (apply the new priority verbatim).
3. **Keep** the rest unchanged.

#### Renumber surviving findings

After applying drops, renumber the surviving findings so `F1, F2, ...` is contiguous. This keeps downstream references in the Tasks section (Phase 6) sensible. Record the old → new number mapping internally so you can translate the critic's drop rationales for the audit trail.

#### Record the audit trail

Keep the dropped-findings list with rationales. This will be rendered in the Notes section of the final report (Phase 7) as a block titled "Dropped findings (skeptical critique)". The format is:

```
**Dropped findings (skeptical critique):**
- F2 (split ContextVar across two packages) — pre-existing in `main`; PR doesn't worsen.
- F4 (text-builder duplication) — pre-existing; extraction PR didn't touch this code.
- ...
```

Use the **original** finding numbers in the audit trail (the ones the critic saw), not the renumbered ones — readers comparing a prior report to this one need the original numbers to be traceable.

#### Empty-list outcome

If the critic recommends dropping all findings, that's a valid outcome. Proceed to Phase 5 with an empty findings list — Phase 7 will produce a "no findings" report and the Convergence Verdict will reflect this.

### Phase 5: User Calibration on Judgment-Call Findings

Some findings can't be resolved well without context the model doesn't have — the project's actual threat model, what other controls already exist, how much complexity the team is willing to spend on a given class of risk, whether a proposed remediation makes sense in this codebase. Earlier phases shouldn't guess at this; this phase hands those findings to the orchestrator, which resolves them — answering the clear-cut ones itself and putting the rest to the user.

**Under `--auto` the orchestrator answers all of them** against *Weighing What a Change Costs*, and no human sees them. This does not change what you flag here or how you flag it — see *What `AUTO_MODE` changes for you* in your agent definition. Flagging fewer findings because the answers will be automated would just move the same guess to a phase with less information.

Use your judgment to identify which findings are judgment calls. The general shape: a finding is a candidate when a reasonable engineer with full project context might keep it, drop it, or downgrade it — and you can't tell which without asking. Findings whose value is clear without project context (real bugs, intent contradictions, obvious design problems) should pass through unchanged.

To make this concrete: a finding might be a judgment call because the proposed fix only makes sense under assumptions you can't verify from the diff (e.g., the recommendation hardens against attacker-controlled input, but you can't tell whether the input is actually attacker-controlled in this system). Or because the *severity* of a real concern depends on project context (e.g., a PII or hardening gap that matters a lot in some products and not others). Or because the proposed remediation, even if the concern is real, might be in the wrong layer or might trade one risk for another — and only someone with the full picture can weigh that. Another flavor worth flagging: findings where the fix would add significant complexity (a new abstraction, defensive layer, or architectural change) to address a problem the team might reasonably choose to accept — the cost-vs-benefit only makes sense relative to how much the team cares about the underlying risk. Similarly, performance or scalability concerns at speculative load levels (e.g., "this is O(n²) and would be slow at large n," or "this wouldn't hold up under high concurrency") often depend on whether the projected scale actually applies to this system — the user knows the realistic operating range and the model usually doesn't. These are illustrative, not a checklist; the test is whether the user's context would meaningfully change the outcome.

A useful gut check alongside the analytical test: if you imagine the team seeing this finding land in their PR review, would they roll their eyes? Eye-roll-worthy findings are often the ones worth surfacing for user calibration — technically defensible, but missing something about how the team actually works.

**Security and privacy findings deserve a second look before they pass through.** Not because they're automatically judgment calls — a traced, reachable vulnerability is as clear-cut as any bug and can go straight into the tasks. But this is the category where a review is most likely to have overreached, so hold each one against the reachability and proportionality tests one more time. If it holds up, let it through. If you find yourself unsure — you can't quite trace how untrusted input arrives, you can't tell whether an upstream control already covers this, you're guessing at how sensitive the data really is, or the attack you're picturing is one you can't concretely construct — that's what this phase is for. Surface it and let the user's threat model settle it.

A review reaching this phase with no security findings to surface is a normal outcome, not a gap. So is one where every security finding was confident enough to pass through unasked.

#### Step 1: Identify candidates (sub-agent)

Spawn a fresh sub-agent (opus) with the findings that survived Phase 4, the full diff, and the PR intent summary from Phase 1. Ask it to flag findings where the right call depends on context only the user can supply, and to briefly note what that context is. Tell it to give security and privacy findings the extra scrutiny described above — re-checking reachability and proportionality, and flagging the ones where it can't fully substantiate the threat — while letting well-traced ones through unflagged. Findings that don't need user input shouldn't be flagged.

The sub-agent returns one line per candidate: `F<n> — <brief description of what makes this a judgment call and what context would resolve it>`. An empty list is a valid outcome and ends the phase.

#### Step 2: Return the question batch and stop

**You cannot ask the user anything.** `AskUserQuestion` is not in your tool set — it is removed from every sub-agent — so calling it fails rather than reaching anyone. The orchestrator asks on your behalf.

So instead of asking: package the candidates into a question batch, return it, and end your turn. Do not guess the answers, do not substitute your own judgment for the user's, and do not proceed to Phase 6 — the findings aren't settled yet.

Each question carries enough for someone who has not read your diff to put it to the user:

- **What the finding is**, concretely — file, location, and the actual concern
- **Why it's a judgment call** — the specific context you lack that would settle it
- **The options**, each committing to an *action*, not a severity: fix now (optionally with a named alternative approach), or defer with a path (follow-up ticket, code comment, or drop it). A severity adjustment can ride along with an option but is never its main content.
- **Your recommendation**, plus a line of rationale grounded in *Weighing What a Change Costs*: establish the problem is real, prefer the correct fix over the small one, and say so when a remedy carries concretely more risk than the problem it removes.

**Always recommend.** The orchestrator auto-answers questions whose recommendation is clearly right, and forwards the rest. A question with no recommendation gets forwarded by default — spending the user's attention on a call you were better positioned to make.

Return the Stage 1 shape from your agent definition. An empty `questions` array is a valid and common outcome; the orchestrator will resume you immediately.

#### Step 3: Resume when the decisions arrive

The orchestrator resolves every question — answering some itself, putting the rest to the user — and sends the decisions back via `SendMessage`. That message resumes you **with your full context intact**: your diff, findings, and critique verdicts are all still there. Don't re-derive any of it.

Continue at Step 4 below.

#### Step 4: Apply the user's decisions and record the audit trail

The decisions arrive together in the orchestrator's resume message, each marked as the user's or the orchestrator's. Both are binding — apply them the same way. For each finding decided, translate the chosen approach into one of the following outcomes:

- **Fix now (any variant)** — the finding stays in the surviving list. If a specific alternative approach was chosen, update the finding's **Suggestion** to reflect what was chosen so Phase 6 (task grouping) and Phase 9 (implementation) work from the right plan. Apply any severity adjustment that came with the option.
- **Defer (any path)** — drop the finding from the surviving list and record it in the audit trail with the deferral path chosen (ticket, comment, ignore) and the rationale. Filing the ticket or adding the comment is the user's follow-up; don't do either yourself unless the decision explicitly says to.

After applying decisions, renumber surviving findings contiguously and preserve the original numbers in the audit trail. Dropped findings (deferred, documented, or ignored) are itemized in the final report's Notes section under "Dropped findings (user calibration)" with the chosen approach and its rationale, noting where a decision was the orchestrator's rather than the user's.

If everything gets dropped, that's valid — Phase 7 will produce a "no findings" report.

### Phase 6: Consolidate Findings into Tasks

After Phase 5 (User Calibration on Judgment-Call Findings), but before compiling the report, group the surviving findings into **tasks**. Tasks are the unit of work you will implement in Phase 9. Do this yourself — do not delegate it to a subagent, because it requires a holistic view of all findings simultaneously.

#### Grouping Rules

Group findings into a single task when they share:

1. **Shared root cause**: Fixing one finding's underlying cause would naturally address the others.
2. **Tight code locality**: Multiple findings in the same function or tightly coupled block where editing one forces you to read/touch the others.
3. **Shared design concern**: Different perspectives (correctness, naming, edge cases) on the same abstraction, where addressing them piecemeal would produce awkward intermediate states.

**Do NOT group** findings that merely happen to be in the same file but address independent concerns. **Do NOT group** findings of vastly different priorities unless they share a root cause — a Low naming nit shouldn't ride along with an Urgent security bug, because it muddies the priority signal.

Default to *not grouping* when in doubt. Over-grouping forces unrelated changes into one task; under-grouping is recoverable.

#### Task Records

For each task, record:

- **Task number**: 1-indexed, ordered by priority (highest-first); within the same priority, order by fix-ordering dependency constraints
- **Title**: Short, action-oriented — "Fix X in Y" or "Refactor Z"
- **Priority**: Max priority across all member findings
- **Member finding IDs**: `F1`, `F4`, etc.
- **Dependencies**: Other task numbers that must complete first (derived from finding-level dependencies, translated to task numbers)
- **Grouping rationale**: Required only when the task groups more than one finding — explain *why* these findings belong together and *what* the consolidated task entails

### Phase 7: Compile Report

Generate a structured markdown report with the following section order:

```
# Title / Header
## Review Methodology
## Summary
## Checklist
## Tasks
## Findings by Priority
## Convergence Verdict
## Notes
```

#### Review Methodology

```
## Review Methodology

This report was generated using a parallel multi-lens review: four independent
reviewers ran concurrently, each on a disjoint lens.
[If prior reports were auto-discovered: "Priority calibration was applied using N prior report(s) from docs/local/reports/{BRANCH_SLUG}/ to maintain a consistent absolute scale across review iterations."]

| Lens | Findings | Focus |
|------|----------|-------|
| A — Design & Architecture | X | Abstractions, coupling, layering, API surface |
| B — Correctness, Edge Cases & Security | Y | Bugs, boundary conditions, edge conditions, trust boundaries, injection |
| C — Cross-File Contracts | Z | Inter-module contracts, error propagation, glue code |
| D — Documentation | W | Doc/code contradictions, comments that don't earn their place, naming |
| Total (after dedup) | T | — |
| Retained after skeptical critique | R | — |
| Retained after user calibration | P | — |
```

The **Retained after skeptical critique** row reports the count after Phase 4's `review-critic` sub-agent has filtered the consolidated list. The **Retained after user calibration** row reports the count after Phase 5, where the judgment-call findings were resolved — by the user, or by the orchestrator where the right call was unambiguous. If either filter dropped findings, the dropped items are itemized in the Notes section. If a filter kept everything, its dropped-findings block is omitted.

#### Summary Table

```
| Priority    | Design | Bug | Security | Logic | Intent | Improvement | Total |
|-------------|--------|-----|----------|-------|--------|-------------|-------|
| Urgent      | 0      | 0   | 0        | 0     | 0      | 0           | 0     |
| High        | 0      | 0   | 0        | 0     | 0      | 0           | 0     |
| Medium      | 0      | 0   | 0        | 0     | 0      | 0           | 0     |
| Low         | 0      | 0   | 0        | 0     | 0      | 0           | 0     |
| **Total**   | 0      | 0   | 0        | 0     | 0      | 0           | 0     |
```

The summary table counts **findings** (not tasks), matching the Findings by Priority section below.

#### Issue Categories

- **Design**: Wrong abstraction, tight coupling, separation of concerns violations, poor API surface, architectural misfit
- **Bug**: Logic errors, incorrect behavior, race conditions, boundary condition failures
- **Security**: Injection vulnerabilities, auth bypass, data exposure, missing validation at trust boundaries
- **Logic**: Works on happy path but fails under realistic edge conditions
- **Intent**: Contradictions between documentation/comments/PR description and actual code behavior
- **Improvement**: Naming, style, simplification, performance (only when genuinely impactful)

#### Checklist

Enumerate **tasks** (not raw findings). Each checklist item maps to a `### N. Title` section in the Tasks section below — the number + title must match the task heading exactly. Phase 9 works this checklist top to bottom and checks items off as it implements them.

```markdown
## Checklist

- [ ] 1. Brief task title (Urgent)
- [ ] 2. Brief task title (High)
- [ ] 3. Brief task title (Medium)
```

Drop `file:line` and `[Lens X]` from the checklist line — those details live in findings. Keep the priority tag in parentheses for at-a-glance scanning.

#### Tasks Section

The Tasks section contains one subsection per task, ordered by priority (highest-first). Each task subsection is what you implement from in Phase 9 — it must contain the `**Dependencies:**` field and enough context to execute.

**For a single-finding task:**

```markdown
### 1. Fix null check in user lookup

**Priority:** Urgent
**Findings:** F3

See finding [F3](#f3-srcauthpy45--bug-missing-null-check-lens-b) for full details.

**Dependencies:** (none)
```

**For a multi-finding task:**

```markdown
### 2. Refactor authentication middleware

**Priority:** High
**Findings:** F1, F4, F7

These findings all describe issues in the auth middleware's request validation: F1 is a missing null check, F4 flags inconsistent error handling in the same function, and F7 notes the tight coupling between validation and session lookup. They should be addressed together because fixing F7 (separating the concerns) naturally creates the right place to address F1 and F4.

See findings [F1](#f1-...), [F4](#f4-...), [F7](#f7-...) for individual details.

**Dependencies:** 1
```

Notes on task format:
- The grouping rationale blurb is required for multi-finding tasks and must explain *why* the findings belong together. Omit it for single-finding tasks.
- Anchor links to findings are a convenience for human readers; include them when practical.
- `**Dependencies:**` lists other task numbers (e.g., `1, 3`). Write `(none)` when there are no dependencies.

#### Findings by Priority

Group findings by priority (Urgent → High → Medium → Low). Findings are numbered with an `F` prefix (`F1`, `F2`, ...) to distinguish them from task numbers.

```markdown
## Findings by Priority

### Urgent

#### F1. `path/to/file.py:42` — [Bug] Brief one-line description [Lens B]

Detailed explanation of the issue, including why it's problematic and what scenarios would trigger it.

```python
# Problematic code snippet
```

**Suggestion:** Concrete, actionable fix with code example if applicable.

---

#### F2. `path/to/file.py:78` — [Security] Another finding [Lens B]

...

---
```

The `[Lens X]` attribution after each finding title indicates which review lens discovered it (A — Design, B — Correctness/Edge Cases/Security, C — Cross-File, or D — Documentation). Findings do **not** include a `**Dependencies:**` field — dependencies are managed at the task level.

#### Convergence Verdict

Compare the findings just compiled against the prior reports loaded at the start of this run. The goal is to tell the user whether further review rounds are worth running. This section goes in the saved report and in your Stage 2 return value, which is where the orchestrator picks it up.

Look at the trend across all reports in chronological order (oldest → newest, with this run at the end):

- **Total findings count** per report
- **Urgent + High count** per report (the "blocker" tier)
- **What kinds of findings remain** in this report

Apply this verdict rule:

- **CONVERGED** if **all** of these hold:
  - This report has 0 Urgent and 0 High findings
  - Any remaining Medium findings are realistic-edge-condition gaps, not latent bugs
  - No new substantive issues were introduced since the previous report (vacuously true on a first review)
  - Either: the total finding count has been trending down (or held flat at a low number) across the last 2+ reports, **or** this is the first review and it already meets the criteria above with a low total count — a clean first pass is a valid path to CONVERGED, signaling no further review rounds are needed.

- **ALMOST CONVERGED** — use your judgment here. The strict CONVERGED bar is hard to reach in practice, and the PR may be mergeable well before every last Medium is addressed. Declare ALMOST CONVERGED when, on balance, the remaining findings are not blockers and another full review round probably isn't worth the cost. Typical signals (not a checklist — weigh them):
  - 0 Urgent remaining, and any remaining High findings are debatable or low-impact
  - Remaining Medium/Low findings are genuine nitpicks, style preferences, or edge cases the author can reasonably defer
  - The trend is clearly downward even if the strict CONVERGED criteria aren't all met (or, on a first review, the findings are mostly minor but you wouldn't quite call it CONVERGED)
  - You would feel comfortable approving this PR if you were the reviewer
  You **must** include a 2-4 sentence explanation of *why* you chose this verdict — which findings you're treating as non-blocking and why.

- **NOT CONVERGED** otherwise. Specifically flag:
  - Any Urgent finding still present, or High findings that represent real risk
  - A finding count that went *up* since the previous report (regression — new issues introduced while fixing old ones)
  - Substantive new issues introduced since the previous report

- **BASELINE** only when this is the first review on the branch **and** it surfaced substantive findings that need addressing before a convergence judgment makes sense (i.e., the review would otherwise be NOT CONVERGED, but there's no prior trend to anchor that judgment against). If a first review is clean enough to meet the CONVERGED or ALMOST CONVERGED criteria, use those verdicts instead — BASELINE is reserved for "this is the starting point, expect more rounds."

Render this section in the report using exactly this structure:

```markdown
## Convergence Verdict: CONVERGED ✓

This branch has converged across N review rounds. No blockers remain.
You can stop running /dev:deep-review-pr on this branch unless the code changes substantially.

### Finding Trend
Total: 12 → 7 → 3 → 1
Urgent+High: 4 → 2 → 0 → 0
```

For a clean first review, phrase it as a one-shot convergence:

```markdown
## Convergence Verdict: CONVERGED ✓

This first review surfaced no blockers and only minor findings. No further
review rounds are needed unless the code changes substantially.

### Finding Trend
Total: 2
Urgent+High: 0
```

```markdown
## Convergence Verdict: ALMOST CONVERGED ≈

The remaining findings are not blockers. Another full review round is
probably not worth the cost — address what's actionable inline and ship.

### Finding Trend
Total: 12 → 7 → 3 → 2
Urgent+High: 4 → 2 → 1 → 0

### Reasoning
Finding #4 is a naming preference the author can take or leave, and #5 flags
an edge case that's gated behind a feature flag not yet enabled in production.
No Urgent or risky High findings remain, and the trend has been consistently downward.
```

```markdown
## Convergence Verdict: NOT CONVERGED

2 Urgent findings still present (see #1, #3 above).
Recommend: address the listed findings, then run /dev:deep-review-pr again.

### Finding Trend
Total: 12 → 7 → 5
Urgent+High: 4 → 2 → 2

### Reasoning
Findings #1 and #3 are real bugs that will cause incorrect behavior in production.
The total count has not meaningfully declined and no blockers have been resolved.
```

```markdown
## Convergence Verdict: BASELINE

First review on this branch, and it surfaced substantive findings — no prior
trend to compare against yet. Address the listed findings, then run
/dev:deep-review-pr again to begin tracking convergence.

### Finding Trend
Total: 12
Urgent+High: 3
```

Use BASELINE only when a first review has substantive findings (Urgent/High,
or a non-trivial count of Medium issues that would otherwise warrant
NOT CONVERGED). A clean first review should use CONVERGED or ALMOST CONVERGED
instead.

Formatting rules for the trend:
- Use the bare arrow form (`12 → 7 → 3 → 1`), one number per report in chronological order with this run's count last. Do **not** label entries with "Round 1", "Round 2", etc., and do **not** combine both numbers on a single line.
- Always include both `Total` and `Urgent+High` lines, even when there is only one prior report.
- For BASELINE, show a single number on each line.
- The Reasoning subsection is required for ALMOST CONVERGED and NOT CONVERGED; optional (or omit) for CONVERGED and BASELINE.

Place this section immediately after the Findings by Priority section and before the Notes Section.

#### Notes Section

Include:
- Overall assessment: is this PR well-designed? Does it accomplish its stated goal?
- Positive feedback on well-implemented aspects
- Broader observations about patterns across the PR
- Which lenses surfaced the most findings and what that says about the change's complexity (e.g., a security-heavy change lighting up Lens B, or a refactor concentrated in Lens A)
- If no issues found, say so explicitly — a clean review is a valid outcome
- **Dropped findings (skeptical critique)**: if Phase 4's `review-critic` sub-agent dropped any findings, list them here using their **original** finding numbers (not the renumbered ones). One bullet per dropped finding, with the critic's one-line rationale. Omit the block entirely if nothing was dropped.

  Example:

  ```
  **Dropped findings (skeptical critique):**
  - F2 (split ContextVar across two packages) — pre-existing in `main`; PR doesn't worsen.
  - F4 (text-builder duplication) — pre-existing; extraction PR didn't touch this code.
  - F9 (backtick sanitization scope) — pre-existing; no new exposure introduced by this PR.
  ```

- **Dropped findings (user calibration)**: if Phase 5 dropped any findings, list them here using the finding numbers as they appeared *after* Phase 4's renumbering (i.e., the numbers Phase 5 saw). One bullet per dropped finding with the rationale (or the option label chosen), noting where the decision was the orchestrator's rather than the user's. Omit the block entirely if nothing was dropped.

  Example:

  ```
  **Dropped findings (user calibration):**
  - F3 (validate UUID format from internal service) — user: input comes from a service we own; not worth the validation layer.
  - F6 (sanitize log fields for PII) — user: this log sink is internal-only and already scrubbed downstream.
  ```

### Phase 8: Output

1. **Determine output path:** `{REPORT_DIR}/deep-review-pr-{YYYY-MM-DD-HH-MM}.md`
   - `{REPORT_DIR}` = output of `<PLUGIN_ROOT>/scripts/branch-report-dir.sh` (already resolved in Phase 0.5 from the PR branch's checkout — write the report there, not under the primary clone)
   - Use today's date and time

2. **Save report:**
   - Create `{REPORT_DIR}/` directory if it doesn't exist
   - Write the full report (including the Convergence Verdict section compiled in Phase 7) to the output file
   - Confirm the file was written

   `docs/local/` is meant to be gitignored — the report is a local working artifact, and Step 9d posts it to the PR where it belongs. Never commit it. If the repo doesn't ignore `docs/local/` yet, mention once in the final summary that the user can add it to `.gitignore`.

3. **Do not print a summary to the conversation.** Your output does not reach the user — the orchestrator aggregates one report across all PRs at the end (Phase D). Keep the report file and your Stage 2 return value as the record, and proceed directly to Phase 9.

   Carry into that return value: the report path, the Convergence Verdict, the Urgent and High task list, and — if prior reports were found in the branch folder — that priority calibration was applied against N of them.

### Phase 9: Implement, Check, and Push

The report is a means, not the deliverable. Once it is written, **immediately implement every task in it** — do not stop to ask whether the user wants the work done. The user already made that decision by invoking this command; Phase 5 is where the judgment calls were settled, and every task that survived to the report is one they've effectively approved.

Run these steps from `WORKTREE_PATH`, not the primary clone.

**Implement inline, yourself. Do not delegate to further sub-agents.** You have just spent an entire review reading this diff — you know the code, the intent, why each finding was raised, and what was decided about the debatable ones in Phase 5. A fresh sub-agent has none of that and would have to rediscover it by re-reading the same files, which is slower and reconstructs the context worse than you already hold it. This is exactly why the orchestrator resumes *you* rather than handing your report to someone else. Write the fixes yourself with `Edit`/`Write`. Do not spawn `Task` agents, and do not hand the report off to another command to execute.

**Step 9a — Implement all tasks.** Work the Tasks section in order — it is already sorted highest-priority-first, with `**Dependencies:**` recording which tasks must land before which. Respect that ordering and otherwise just go top to bottom.

For each task: make the change, then check it off in the report's `## Checklist` (`- [x] <number>. <title>  *(completed: <brief summary>)*`) so the report reflects what was actually done.

Commit as you go, at whatever granularity is natural — one commit per task is a reasonable default, and grouping a few tightly related tasks into one commit is fine. Read `COMMIT_SPEC` and follow it, or commit directly.

If a task turns out to be unimplementable — the fix is wrong, or it conflicts with something you now understand better than the reviewing lens did — leave it unchecked, note why, and move on to the rest. One bad task does not block the others; surface it in `tasks_skipped`.

**Step 9b — Run the checks.** After all tasks are implemented, run the project's check suite and drive it green:

```bash
just check
```

If it fails, read `FIX_SPEC` and execute its loop against `just check` to diagnose and fix until it passes. Run the checks **once, after all tasks have landed** rather than after each one — this is what catches breakage that only appears when the fixes coexist, and it avoids paying for a full suite run per task.

If `just check` cannot be driven green after that loop exhausts its retries, stop before pushing and report the failure with the actual output in your Stage 2 result. Do not push a red branch — and name the commits left unpushed in the worktree so the user knows they are there.

**Step 9c — Commit and push.** The task work is already committed from Step 9a, so what typically remains uncommitted is just the fixes made in Step 9b. The report file is not among them — it lives under `docs/local/` and is meant to stay untracked. Commit whatever is outstanding (via `COMMIT_SPEC`, as in Step 9a), then push the branch:

```bash
git push
```

If the branch has no upstream, set it: `git push -u origin $(git rev-parse --abbrev-ref HEAD)`.

**Step 9d — Post the report to the PR.** The report is how the review reaches anyone who wasn't in this session, and it is gitignored, so the push in Step 9c did not carry it. Post it as a comment on the PR.

Use the `dev:github-pr-ops` skill (a Skill, not a slash command — you can invoke this one) and post the report file directly:

```bash
"<PLUGIN_ROOT>/skills/github-pr-ops/gh-pr.sh" post-comment --body-file {REPORT_PATH} --pr {PR_NUMBER}
```

Pass `--pr` explicitly using the `PR_NUMBER` the orchestrator gave you. The script can auto-detect the PR from the working directory, but you have the number for free and being explicit removes any chance of posting to the wrong PR.

- **Pass the file, never the content.** The report is full of backticks, tables, and code fences; interpolating it through the shell (`$(cat ...)`, a heredoc, `-f body=`) mangles all of it. `--body-file` is the only correct path — this is the skill's Escaping Rule, and the report is exactly the kind of content it exists for.
- **A general comment, not a review.** Use `post-comment`. Do **not** use `post-review`, inline threads, `REQUEST_CHANGES`, or `APPROVE` — the report is cross-cutting by construction, and this command never issues an approval signal.
- **No PR?** On the no-argument path there may be no PR — the orchestrator passes no `PR_NUMBER` when its Phase A found none. Skip posting, set `report_posted: false` with that reason, and say so in your Stage 2 result. Do not create a PR to have somewhere to post.
- **If the post fails**, carry the actual error into Step 9e. The report file and the pushed commits still stand — a failed comment does not undo the work.

**Step 9e — Return the Stage 2 result.** You are finished. Return the Stage 2 object from your agent definition — not a conversation summary, which would reach no one. The orchestrator folds it into the single report the user actually sees.

It must carry:

1. **What was done** — which tasks were implemented (and any left unfinished, with why), whether `just check` passed, whether the branch was pushed, and whether the report was posted to the PR (or why it wasn't). Report failures in the fields rather than omitting them; a partial result is more useful than a silent gap.

2. **The report's Convergence Verdict**, in `verdict_at_review_time` — e.g. `NOT CONVERGED — 3 Urgent, 3 High`. It is labeled *at review time* because it predates your fixes; that label is what stops the orchestrator from relaying it as a current assessment.

3. **A recommendation** — exactly one of:

   - **Merge** — the work is done. **This is the default.**
   - **Run another deep review** (`/dev:deep-review-pr`) — you have concrete reason to think a further round would surface significant problems.
   - **Run a targeted review of `<scope>`** — same bar, but the concern is confined to one area. **Naming the scope is mandatory**: which files, which change, which concern. "Run a targeted review" with no scope is not an acceptable answer — the scope is the entire content of the recommendation.

   **The goal is a merged PR, not a maximally reviewed one.** A review round costs real time and delays the change, so recommend one only when you can name what you expect it to find. The bar is a genuine, articulable concern that something *significant* remains — not the residual unease that always exists after touching code, and not a hedge against having missed something. You will essentially never be certain a diff is clean; that is not a reason to review it again.

   Do not soften a merge recommendation with a suggested review "just to be safe." Either you have a reason, in which case name it and recommend the review, or you do not, in which case recommend merge without qualification.

   This recommendation describes the state **after** the fixes, so it can legitimately differ from the review-time verdict — a NOT CONVERGED report whose findings were all cleanly implemented should normally end in *merge*, since the findings that drove the verdict are gone. That divergence is expected. Do not carry the old verdict forward as if it still held, and do not treat a severe review-time verdict as itself a reason for another round.

## Example Output (Orchestrator, Phase D)

The single summary the user sees after every driver has returned. Two PRs, one of which needed a decision:

```
# Deep Review Complete — 2 PRs

## PR #142 — Add auth middleware (`add-auth`)

All 8 tasks implemented across 5 commits. `just check` passed. Pushed;
report posted to the PR.
Report: `docs/local/reports/add-auth/deep-review-pr-2026-08-24-14-30.md`

**Verdict at review time:** NOT CONVERGED — 3 Urgent, 3 High.
**Recommendation: merge.** Every finding that drove that verdict is fixed,
and each fix was the narrow change the finding asked for.

## PR #147 — Batch import endpoint (`batch-import`)

5 of 6 tasks implemented across 3 commits. Task 4 (extract the pagination
helper) was left unimplemented — it conflicts with the fix for F2, noted in
the report. `just check` passed. Pushed; report posted to the PR.
Report: `docs/local/reports/batch-import/deep-review-pr-2026-08-24-14-31.md`

**Verdict at review time:** ALMOST CONVERGED — 0 Urgent, 1 High.
**Recommendation: run a targeted review of the pagination helper
(`src/api/batch.py`)** — task 4 was deferred mid-implementation and F2's fix
changed the surface it would have attached to.

## Decisions I made without asking

- **#142 / F3** — validate UUID from the internal callback → *fix at the
  boundary*. The trigger path is concrete and the fix is a two-line guard at
  the edge, well proportionate to the bug it closes.
- **#142 / F7** — drop the retry-count comment → *defer, no ticket*.
  Pre-existing; the PR doesn't worsen it.
- **#147 / F1** — widen the `except` in the importer → *fix now*. Establishes
  a real failure on a reachable path, and the correct fix is smaller than the
  workaround the finding contemplated.

## Asked you

- **#147 / F4** — whether the import endpoint is reachable by unauthenticated
  callers. You said it sits behind the gateway's auth, so the added check was
  dropped as defense-in-depth for its own sake.
```

When a run is partial, say so in the same place rather than burying it:

```
## PR #151 — not reviewed

`gh pr view 151` failed: no PR found with that number in this repo. Nothing
was reviewed for it; the other two PRs completed normally.
```

The example report file itself would contain (abbreviated):

```markdown
# PR Review: add-auth — 2026-01-23 14:30

## Review Methodology
...

## Summary
...

## Checklist

- [ ] 1. Fix SQL injection in user lookup (Urgent)
- [ ] 2. Fix uncaught exception and race condition in auth (Urgent)
- [ ] 3. Refactor processor service (High)
- [ ] 4. Correct module docstring for user.py (High)
- [ ] 5. Handle empty input in batch processor (Medium)
- [ ] 6. Handle missing config key gracefully (Medium)
- [ ] 7. Handle concurrent session expiry (Medium)
- [ ] 8. Rename get_data to fetch_user_profile (Low)

## Tasks

### 1. Fix SQL injection in user lookup

**Priority:** Urgent
**Findings:** F1

See finding [F1](#f1-srcapiAuthpy45--security-sql-injection-in-user-lookup-query-lens-b) for full details.

**Dependencies:** (none)

---

### 2. Fix uncaught exception and race condition in auth

**Priority:** Urgent
**Findings:** F2, F3

F2 is an uncaught exception when input is None in the processor, and F3 is a race condition in token validation in auth.py. These should be addressed together because both live in the request-handling path and the race condition (F3) is only reachable via the same code path that also fails to guard against None input (F2) — fixing them separately risks incomplete intermediate states where one issue is patched but the path remains broken.

See findings [F2](#f2-srcservicesprocessorpy123--bug-uncaught-exception-when-input-is-none-lens-b), [F3](#f3-srcapiAuthpy78--bug-race-condition-in-token-validation-lens-b) for individual details.

**Dependencies:** (none)

---

### 3. Refactor processor service

**Priority:** High
**Findings:** F4, F5

F4 flags that a single method in processor.py handles validation, transformation, and persistence. F5 notes that route handlers in routes.py contain business logic that belongs in the service layer. These share a root cause — the service boundary between routes and the processor is not respected — so fixing them together produces a coherent split rather than two awkward half-fixes.

See findings [F4](#f4-srcservicesprocessorpy30-80--design-single-method-handles-validation-transformation-and-persistence-lens-a), [F5](#f5-srcapiroutespy15-40--design-route-handler-contains-business-logic-lens-c) for individual details.

**Dependencies:** (none)

---

### 4. Correct module docstring for user.py

**Priority:** High
**Findings:** F6

See finding [F6](#f6-srcmodelsuserpy1-15--intent-module-docstring-describes-authentication-but-module-handles-profile-management-lens-d) for full details.

**Dependencies:** 3

---

...

## Findings by Priority

### Urgent

#### F1. `src/api/auth.py:45` — [Security] SQL injection in user lookup query [Lens B]

...

#### F2. `src/services/processor.py:123` — [Bug] Uncaught exception when input is None [Lens B]

...

#### F3. `src/api/auth.py:78` — [Bug] Race condition in token validation [Lens B]

...

### High

#### F4. `src/services/processor.py:30-80` — [Design] Single method handles validation, transformation, and persistence [Lens A]

...

#### F5. `src/api/routes.py:15-40` — [Design] Route handler contains business logic that belongs in service layer [Lens C]

...

#### F6. `src/models/user.py:1-15` — [Intent] Module docstring describes authentication but module handles profile management [Lens D]

...

## Convergence Verdict: NOT CONVERGED
...
```
