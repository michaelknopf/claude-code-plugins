# CI fix loop: debug and fix CI failures

**Target:** <TARGET> (defaults to current branch's PR if empty)

## Phase 1: Identify the Failing Workflow(s)

1. **Determine the PR/branch:**
   - If `<TARGET>` is empty: get current branch with `git rev-parse --abbrev-ref HEAD`, then find its open PR
   - If `<TARGET>` is a number: treat as PR number
   - If `<TARGET>` is a URL: extract PR number from it
   - If `<TARGET>` looks like a branch name: use that branch
   - If `<TARGET>` is numeric and large (8+ digits): treat as workflow run ID

2. **Fetch workflow runs for the target:**
   ```bash
   gh run list --branch <branch> --limit 10 --json databaseId,name,status,conclusion,event,headBranch,workflowName
   ```

3. **Identify failing runs and check for workflow chains:**
   - Look for runs with `conclusion: "failure"`
   - Check `event` field for `workflow_run` (indicates this was triggered by another workflow)
   - If chained workflows exist, trace back to find the root trigger
   - Ignore checks about failed test coverage thresholds.
   - Build a chain: [root workflow] → [triggered workflow] → [failing workflow]
   - **Remember this chain** - you'll need to verify the entire chain passes after fixes

4. **Present chain to user:**
   - If multiple workflows are involved in the chain, show the full chain
   - Use AskUserQuestion to ask which workflow(s) to debug
   - If only one failing workflow, proceed with that one
   - **Keep track of the original failing workflow** - after fixes, you must verify this same workflow succeeds when re-triggered

5. **If the PR carries a deploy label** (`deploy`, or a variant like `deploy-<target>`), a green run is not sufficient — check the deploy/smoke jobs `success` rather than `skipped`:
   ```bash
   gh run view <run-id> --json jobs \
     --jq '.jobs[] | select(.name|test("Deploy|Smoke";"i")) | "\(.conclusion)\t\(.name)"'
   ```
   A skipped job does not fail its run. Deploy jobs read the labels from the payload of the run **as it was triggered**, and labeling fires no run, so a run started before the label was added skips them forever. Force a fresh run with an empty commit (it squashes away at merge; don't amend, which rewrites the SHA under existing reviews):
   ```bash
   git commit --allow-empty -m "chore: re-trigger CI with deploy label"
   git push
   ```
   Don't add a deploy label yourself unless the user asked for one.

## Phase 2: Analyze Failures

1. **For the selected failing workflow(s):**
   - Download logs: `gh run view <run-id> --log-failed`
   - Identify the failing job and step
   - Parse error messages and stack traces

2. **Categorize the failure:**
   - Build/test issue (can likely reproduce locally)
   - Workflow config issue (need to fix `.github/workflows/*.yml`)
   - Environment/secrets issue (may need user input)
   - Dependency issue (package versions, missing tools, etc.)

## Phase 3: Local Validation

**Before pushing any fix, validate locally when possible:**

1. **Discover local tooling:**
   ```bash
   just -l
   ```
   - Check for nested justfiles in sub-projects (`cd <dir> && just -l`)
   - Note which recipes correspond to CI steps

2. **Run equivalent local commands:**
   - Prefer `just <recipe>` over constructing raw commands
   - Match CI steps to local recipes
   - Examples:
     - CI runs `npm test` → run `just test`
     - CI runs `pytest` → run the recipe that wraps it

3. **Only proceed to push when:**
   - Local validation passes, OR
   - The failure is environment-specific and can't be reproduced locally

## Phase 4: Fix and Push Loop

You orchestrate an autonomous Opus→Sonnet loop to diagnose and fix CI failures until all workflows pass. Each iteration is visible to the user so they can follow along.

### Fix Loop (max 10 attempts)

For each attempt (1 through 10):

#### A. Diagnose with Opus (with agent selection)

**Detect if this is a type error:**

Check the CI error output for patterns indicating type errors:
- Workflow name or step contains: `mypy`, `pyright`, `typecheck`, `type-check`
- Error output contains: `error:` with type-related messages like `Incompatible`, `has no attribute`, `Missing return`, `Argument of type`

**Select the appropriate diagnostician:**

| Error Type | Agent                    | Why |
|------------|--------------------------|-----|
| Type errors (mypy, pyright) | `dev:type-fix-planner`  | Applies type safety principles |
| All other errors | `dev:fix-diagnostician` | General-purpose debugging |

Spawn the selected agent (opus) with:
- Target command: `gh run view <run-id> --log` (the workflow that failed)
- Error output: Full CI logs from the failed workflow
- Attempt number: Current iteration (1-indexed)
- Attempt history: Summary of previous attempts and what was tried

Both agents return a structured plan with these sections:
- `### Root Cause` (type-fix-planner also includes `### Principles Applied`)
- `### Fix Plan`
- `### Status` — either `CONTINUE` or `BLOCKED: <reason>`
- `### Blockers` (if any)

**CRITICAL: Output the full diagnosis plan verbatim.** After receiving the Task result, you MUST include the complete plan text in your next response message — this is how the user sees it. Do not summarize, truncate, or skip any part of the plan. Format it as:

```
---
## Attempt {N} / 10: Diagnosis

{full opus plan output}
---
```

#### B. Check for Blockers

Parse the `### Status` section from the opus plan:
- If `BLOCKED: <reason>` → stop the loop, report the blocker to the user
- If `CONTINUE` → proceed to implementation

#### C. Implement Fixes with Sonnet

Spawn a sonnet implementation agent (use `Task` tool with `subagent_type: "general-purpose"`, `model: "sonnet"`) with the full opus plan. The agent should:
- Read the relevant files
- Apply the changes described in the `### Fix Plan` section
- Not commit or push (you'll do that next)

#### D. Local Validation (when possible)

Before pushing, validate locally if the failure can be reproduced:
- Use `just` recipes to test fixes locally (see Phase 3)
- Only skip if the failure is environment-specific (secrets, CI-only setup, etc.)
- If local validation fails → record this in attempt history and loop back to (A) for re-diagnosis

#### E. Commit and Push

```bash
git add <changed-files>
git commit -m "ci: <brief description of fix>"
git push
```

#### F. Poll for Workflow Completion

Wait for the new workflow run to complete:
```bash
gh run list --branch <branch> --limit 5 --json status,conclusion,name,databaseId,event,workflowName
```

Wait until `status: "completed"`, then check `conclusion`.

#### G. Follow the Chain Forward (CRITICAL)

After the immediate workflow completes:

1. **Check if it triggers downstream workflows:**
   - Look for new workflow runs with `event: "workflow_run"`
   - Look for runs triggered by tags/pushes if this workflow pushed code
   - Match by timestamp (created shortly after completion)

2. **Wait for all downstream workflows to complete:**
   - Poll each downstream workflow until `status: "completed"`
   - Check their `conclusion` fields

3. **Verify the entire chain passes:**
   - If **any** workflow in the chain fails → treat as failure, continue loop
   - If **all** workflows succeed → success! Break out of loop.

Example chain:
- You fix "Release" workflow → it succeeds
- → It pushes a tag, triggering "Build" workflow
- → **You must wait for Build workflow too**
- → If Build fails, loop continues with Build's error logs

#### H. Track Attempt

Record:
- Attempt number
- What was diagnosed (root cause summary)
- What was changed (brief summary of fixes applied)
- Which workflows ran and their outcomes
- New error output (if any workflow still failing)

If you've reached 10 attempts, stop.

### Stop Conditions

- **Success:** All workflows in the chain pass (`conclusion: "success"`) — **and, on a deployable repo, its deploy + smoke jobs are `success` rather than `skipped`** (Phase 1, step 5). A skipped deploy job leaves the run green, so this is a distinct condition, not a restatement: exiting on it means merging something that was never deployed or smoke-tested.
- **Blocked:** Opus returns `BLOCKED: <reason>` status
- **Max attempts:** Reached 10 iterations without success

### Report Summary

After the loop completes, report:

**On Success:**
- Number of attempts needed
- Summary of all fixes applied across all attempts
- Which workflows were verified
- Any follow-up recommendations

**On Blocked:**
- Why it's blocked (from opus diagnosis)
- What needs to happen to unblock (secrets, permissions, etc.)
- Summary of what was tried

**On Max Attempts:**
- Final error output from last workflow run
- Summary of all attempts and what was tried
- Highest-leverage next steps to investigate

## Workflow Chain Navigation

**When a workflow triggers another workflow:**
- Event type `workflow_run` indicates a chained workflow
- Use `gh run view <id> --json event,workflowName,triggeredBy` to trace relationships
- Example chain:
  - "Release" workflow (pushes a tag)
  - → "Build" workflow (triggered on: push tags)
  - → "Deploy" workflow (triggered by build completion)
- The fix may need to be in the triggering workflow, not the failing one
- **Always show the chain and ask user which to debug**

## Notes

- **Prefer local debugging:** CI minutes cost money, local iteration is free and fast
- **Keep fixes minimal:** Don't refactor, clean up, or "improve" unrelated code
- **Track attempts:** Maintain a running log of what was tried and what changed
- **Bounded retries:** If you're cycling through the same 2-3 errors without progress, stop and report
