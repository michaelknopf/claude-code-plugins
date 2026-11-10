# TLDR

Two costs pull in opposite directions when deciding what a change should be, and both are real.

**We pay for correctness.** Doing something the right way is worth a slower, larger, more destabilizing change — worth widening scope, worth contradicting an established pattern that turned out to be wrong. We are building for the long term, so a corner cut to keep a diff small is a cost we pay later, repeatedly, with interest.

**We do not pay for speculation.** A change made against a hypothetical problem buys nothing and costs the same as one made against a real problem — plus the risk it introduces. Never risk a new bug to close a bug that was less likely than the fix that replaced it.

The two resolve cleanly, in order:

1. **Is the problem real?** Not "could this theoretically break" — does it actually break, on a path something actually reaches? If no, stop. There is nothing to weigh.
2. **Then fix it properly.** Once the problem is established, the size, scope, or awkwardness of the correct fix is not an argument against it.

Most bad calls come from applying these in the wrong order: rejecting a proper fix because it's big (skipping step 2), or accepting a big fix for a problem nobody established (skipping step 1).

**Large and risky are different properties.** Conflating them is what makes step 2 collapse — a change is not risky because it touches many lines, and a one-line change to a load-bearing path is not safe because it is small.

# Why both, and why they don't actually conflict

They look opposed because both are phrased as caution, but they guard different failures.

*Pay for correctness* guards **under-building**: the patch that leaves the bad abstraction in place, the special case bolted onto a design that should have changed, the fix at the call site because fixing the helper would touch twelve files. Each is cheap now and compounds forever, because the next change inherits the shape this one declined to fix.

*Don't pay for speculation* guards **over-building**: the defensive layer against an input that cannot arrive, the abstraction for a second implementation nobody has asked for, the validation shim for a threat model nobody holds. Each is also cheap now, and also compounds — every future reader must understand it, every future change must preserve it, and it was never load-bearing.

They only appear to collide when the realness of the problem is left unsettled. Settle that first and the tension dissolves: a real problem earns a proper fix however expensive; an unreal one earns nothing however cheap.

# Establishing that a problem is real

The bar is a path something actually reaches — not a story ending in "and then it breaks."

**Name the trigger.** Which caller, which input, which state. A concrete answer means the problem is real. An answer shaped like "if someone were to…" usually means it is not.

**Check what already covers it.** An upstream validation, an authentication boundary, a type signature, a database constraint. Adding a second guard behind an existing one buys defense-in-depth, which is occasionally worth it and usually just another thing to maintain.

**Assume a realistic adversary.** For security specifically, assume one who does *not* already have code execution, database write access, or the ability to edit deploy config. A finding that presupposes any of those describes a position from which we have already lost.

**Severity changes how much tracing is enough — it does not waive the requirement.** For a catastrophic outcome (data loss, auth bypass), naming the entry point without mapping the full route can be sufficient. It is never sufficient to name *no* entry point at all. A finding that cannot say where untrusted input enters has not established a problem, however severe the imagined consequence — and "the consequence would be terrible" is the most common way an unestablished finding survives this step.

When a problem cannot be established this way, the correct response is to leave it alone. Not a comment, not a guard, not a ticket-shaped hedge.

# Fixing it properly

Once the problem is real, cost stops being an argument against the correct fix. Specifically, none of these are reasons to do it wrong:

- **The right fix is bigger.** Diff size is not a design input.
- **The right fix is destabilizing.** Churn is a one-time cost; a wrong structure is a recurring one.
- **The right fix widens scope.** If the problem's actual root is one layer up, that layer is the scope.
- **The right fix contradicts an existing pattern.** An established pattern that is wrong is a reason to change the pattern, not to propagate it. Consistency with a mistake is not a virtue.

## Widening the fix is not widening the PR

One boundary the above does not license: **a real problem whose correct fix lies outside this change's scope earns a finding and a follow-up, not an in-place refactor.**

"If the problem's actual root is one layer up, that layer is the scope" governs *how to fix the thing this change broke* — it is not permission to rewrite the layer above because you noticed it was wrong while passing through. The test is whether the change under review introduced the problem. If it did, fix it at its root however far up that goes. If the problem predates the change and merely became visible during it, say so and leave it; a review that quietly triples a diff's blast radius is doing something other than reviewing.

This matters most where findings are implemented automatically. "Scope is not an objection" applies to the *shape* of a correct fix, never to annexing unrelated code.

## The one legitimate objection

The one thing that *is* a real argument: **the fix introduces more risk than the problem it removes.** That is a genuine trade and the reason step 1 comes first — you cannot weigh a remedy's risk against a problem you never established.

Read that narrowly. It means a fix whose risk is concretely larger — a rewrite of a critical path to close a minor edge case, a schema migration to fix a cosmetic inconsistency. It does not mean "this change is large, therefore risky." Large and risky are different properties.

# Applying this to review findings

A finding is a proposal to spend the cost of a change. Both criteria apply to the finding *and* to the remedy it recommends.

Before raising a finding, establish the problem is real per the tests above. If it is not, the finding does not exist — this is where most review noise comes from.

Once it is real, propose the correct fix rather than the small one. A finding that identifies a design problem and then recommends a local patch has diagnosed correctly and prescribed wrongly.

Then check the remedy against step 2's narrow exception: does the fix carry concretely more risk than the problem? If so, say that in the finding rather than proposing it anyway.

**The dangerous shape is a real observation attached to a disproportionate remedy** — the concern is technically true, so it survives scrutiny aimed at truth, and the fix adds a permanent defensive layer for a problem that did not warrant one. Scrutinize the remedy, not just the claim.

# Summary

1. **Settle whether the problem is real first.** Name the trigger path. Check what already covers it. Assume a realistic adversary. Nothing else can be weighed until this is answered.
2. **An unestablished problem earns no change at all** — not a guard, not a comment, not a hedge.
3. **A real problem earns the correct fix**, and its size, churn, scope, or conflict with an existing pattern are not arguments against it.
4. **Consistency with an established mistake is not a virtue.** Change the pattern.
5. **The one legitimate objection to a correct fix is concretely greater risk than the problem it removes.** Read it narrowly; large and risky are different properties.
6. **A real problem outside this change's scope earns a follow-up, not an in-place refactor.** Fix what this change broke, at its root; don't annex the code around it.
7. **Scrutinize the remedy as hard as the claim.** A true observation with a disproportionate fix is the most common way over-engineering enters a codebase.
