---
description: Adversarially review the current plan's design by arguing it out with a critic sub-agent
allowed-tools: Task(*), Agent(*), SendMessage, Read, Edit, Write, Grep, Glob, Bash(git:*), AskUserQuestion
---

# /dev:plan-review — argue the plan out before building it

You have a plan. Before it becomes code, you are going to defend it to a skeptical reviewer and revise it where the reviewer is right.

This is **a dialogue, not a review pass.** You spawn the `dev:plan-critic` agent, it reviews the plan, you push back on what it got wrong, it responds, and you continue until the design is settled. Both sides retain the full thread, so points stay settled once settled.

The user is not part of this loop. They invoked the command once; they see the result when you converge. Do not ask them to relay messages, and do not stop between rounds to check in.

## Why the argument matters

The value here is not the critic's first review — it is what survives your pushback.

You hold context the critic does not: the codebase, the conversation that produced the plan, the constraints that were considered and discarded. The critic reads a plan cold. That makes it good at spotting what the plan assumes without saying, and prone to confident findings resting on things it could not know.

So neither reflex is right. Accepting every finding produces a plan shaped by a reviewer with half the context. Rejecting every finding wastes the round trip. Argue each point on its merits and let the disagreements resolve.

## Phase 1 — Find the plan

**A formal plan file**, if one exists: its path appears in the system prompt under "Plan File Info". Read it.

**Otherwise, the plan in this conversation** — the approach you laid out in prose. Reconstruct it, including decisions made across several messages and any revisions the user asked for. What you assemble here is the plan under review.

Pass the plan to the critic **inline and in full.** It starts cold; a file path is not something it can be counted on to resolve, and a summary hides exactly the details worth reviewing.

If you cannot find a plan in either place, say so and stop. Do not review a plan you invented.

## Phase 2 — Spawn the critic

Use the `Agent` tool with `subagent_type: "dev:plan-critic"`.

**Capture the agent ID it returns.** Every later round addresses that same ID — lose it and you lose the dialogue, along with everything the critic remembers.

The spawn prompt carries:

- The full plan text.
- The **goal and constraints the plan itself omits** — what the user is trying to accomplish, what was ruled out and why, relevant facts about the codebase. Plans are written for readers who sat through the conversation; the critic did not.
- The instruction to **reply via `SendMessage` with `to: "main"`**, which is how its review reaches you.

## Phase 3 — The dialogue

Per round:

**1. Read the findings and judge each one.** Sort them into: right and worth changing the plan for; wrong, or built on something the critic could not know; or outside the design mandate. Where a finding is right, work out what the plan actually becomes — a finding you accept in the abstract but cannot turn into a concrete revision is not yet resolved.

**2. Reply via `SendMessage`** to the critic's agent ID. Per point, state **accepted** (and how the plan changes), **rejected** (and the specific reason), or **needs clarification** (and what you are asking).

Rejecting well is the skill this command depends on. "The plan already handles this in the migration step" is a rebuttal. "I don't think that's a concern" is not — it gives the critic nothing to update on, and it will either fold for the wrong reason or repeat itself. When you reject, say what the critic missed.

**3. End your turn and let the reply come to you.** After `SendMessage`, the critic's response is **delivered to you automatically** as a `<agent-message>` — it arrives on its own, in a later turn, with no action from you. So once you have sent your rebuttal, simply stop; the next round begins when the message lands.

**Do not wait for it.** There is no file to poll, no task output to `stat`, no status to check. Do not write a `Bash` loop (`until [ ... ]`, `sleep`, `stat`, tailing a `.output` file) to "wait for the critic" — the reply is an event, not a file, so any such loop blocks the very turn the reply needs in order to reach you, and it will spin until it times out while the answer sits undelivered. The single most common way to break this command is to invent a wait step. There is nothing to wait on; yield the turn.

### When you are done

Converge when **both sides have nothing substantive left** — the critic says so, and you have no open questions of your own.

Two ways this goes wrong, both worth watching for:

- **You capitulate to end the loop.** If you find yourself accepting points you were arguing against a round ago, without the critic having said anything new, you are ending the conversation rather than finishing it. Convergence means the disagreements resolved.
- **The critic folds instantly on everything.** A reviewer that concedes every point the moment you push is not reviewing. Your rebuttals were probably too deferential, or you asserted rather than argued. Push once more on a point you believe is genuinely open before accepting a clean sweep.

### The cap

Around **four rounds** without convergence, stop. Use `AskUserQuestion` to put the *specific* open disagreement to the user, with the tradeoff stated both ways.

This is an escape hatch for real design disputes, not a routine step — most plans converge in two or three rounds. A dispute that survives four rounds of good-faith argument is usually a genuine judgment call about priorities, which is the user's to make, not yours.

## Phase 4 — Apply the outcome

**If a plan file exists:** edit it to fold in the agreed revisions. Revise the affected sections rather than appending a changelog — the plan should read as though it was written correctly the first time, since it is about to be handed to an implementer who was not part of this conversation. (This works in plan mode, where the plan file is the one file you may write.)

**If there is no plan file:** restate the converged plan in the conversation. Do not create a file that did not exist.

## Phase 5 — Report

Keep it short:

- **What changed** in the plan, and why.
- **What you rejected** — the critic's findings you argued down, and on what grounds.
- **What is still open**, if anything.

The rejected section is not optional. You are the only party to this conversation the user did not hear from directly, and you both argued the case and judged when it was over. Showing what you pushed back on is what lets the user see whether the plan was tested or merely approved — and it is where they will catch a review that rolled over.
