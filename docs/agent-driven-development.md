# Agent-driven development on Teststrip

Most of this codebase is built by AI agents working in a controller/subagent
pattern: one coordinating agent executes an implementation plan by dispatching
a fresh subagent per task, reviewing between tasks, and gating the whole branch
before merge. This document is the accumulated doctrine for doing that here —
what has actually gone wrong, and the rules that came out of it.

It is written for whoever runs the machine next, human or agent. The rules are
cheap to obey and each one was paid for.

## The shape of the work

- **A spec precedes a plan; a plan precedes code.** Design decisions get
  brainstormed with Jesse and written to `docs/superpowers/specs/`; the
  implementation plan goes to `docs/superpowers/plans/` with per-task file
  lists, interfaces, and verbatim code. Where plan and spec disagree, the spec
  governs and the conflict gets escalated rather than resolved silently.
- **A progress ledger is mandatory** for any multi-task push, kept outside the
  commit history (`.superpowers/sdd/<push-name>/progress.md`). It records one
  line per completed task (commits + review verdict), every ruling with its
  reasoning, and every open minor finding. Conversation memory does not
  survive compaction; the ledger does. After a context loss, trust the ledger
  and `git log` over recollection.
- **The ledger is gitignored and will not outlive the worktree.** Anything in
  it that matters beyond the push — follow-up work, durable lessons — must be
  lifted into issues or docs before the worktree is removed.

## Adversarial task splits

Semantic-core tasks are split into two agents with disjoint permissions:

- **NA (test author)** writes the failing tests and **may not touch
  `Sources/`**.
- **NB (implementer)** makes them pass and **may not touch `Tests/`**.

If an implementer believes a test is wrong, it reports BLOCKED — it does not
edit the test. Verify the split after each pair with `git log --stat`: NA
commits touch only `Tests/`, NB commits never do.

This is not ceremony. Every push that has used it has caught defects that a
single agent writing both sides would have papered over — most often a test
quietly weakened to match a convenient implementation.

## Red proofs and falsification

A test that has never failed proves nothing.

- Every NA task captures its genuine red output — a compile failure naming the
  missing symbol, or a real assertion failure — into its task report.
- **Any test that would pass immediately against existing behaviour must be
  proven sensitive by a named falsification break**: the exact file, the exact
  mutation, the expected failure, then `git checkout --` and a verification
  that `git diff --stat -- Sources/` is empty.
- **Falsification breaks run against committed code.** `git checkout --`
  reverts to HEAD, so running a break against uncommitted work destroys it.
- **The gold standard for a sensitivity fix**: show the new test goes red under
  the mutation *and* that the old test stayed green under the same mutation.
  Only the second half proves a strengthening rather than a restatement.
- **A break that fails to turn the test red is an escalation, not a shrug.**
  It usually means the test is vacuous or the code path is unreachable in the
  fixture.

### The toothless-test failure mode

The recurring defect in agent-written tests is an assertion that cannot fail:
asserting a count is zero against a fixture whose count is already zero;
seeding a scope so narrow the code path under test never executes; comparing a
field against itself. These pass, look like coverage, and defend nothing.

When an agent reports "the mutation didn't reproduce, so the assertion must be
fine," that is the signal to look harder, not to move on.

**Never weaken a failing assertion to reach green.** On this project, every
time an agent refused to do that, it surfaced a real bug — including a case
where a test the brief expected to pass revealed a guard that had never been
implemented at all.

## Model policy

Use the cheapest tier that fits the task, with one hard override:

- **Haiku-tier agents are banned from any task that writes or modifies test
  files.** Twice in one push, haiku implementers produced toothless results —
  a test that passed both before and after the fix it claimed to verify, and a
  fixer that claimed a red proof while committing a production change with no
  test at all. Both cost extra review rounds.
- **Sonnet is the floor** for test authors, for any fix touching tests, and for
  reviewers of small mechanical diffs.
- **The most capable available model** reviews the semantic cores (state
  models, data-model changes, migrations, anything touching invariants) and
  performs the final whole-branch review.
- Cheap tiers are appropriate for transcription: an implementer whose plan text
  already contains the complete code, or a single-file mechanical fix.

Turn count beats token price. The cheapest model routinely takes several times
the turns on multi-step work and costs more overall.

## Running agents safely

**Never re-dispatch an agent you believe is dead. Resume it by id.**

An agent between tool calls is indistinguishable from a dead one from outside:
a transcript that is not ticking, no visible child processes, even a harness
status of `failed`, have all been observed for agents that were alive and
mid-flight. Resuming by id is safe in both worlds — the message lands as a
mid-flight correction if alive, or restarts from the transcript if dead.
Re-dispatching is safe only if the agent is truly dead, which cannot be
established from outside.

Two incidents: a duplicate agent's in-flight work was destroyed by the
original's cleanup, and a near-miss where a "failed" agent had merely finished
a long build between tool calls.

Related rules:

- **One agent per worktree, always.**
- On suspected death, resume with the **observed** state spelled out (HEAD,
  diff stat, staged files) so an agent resuming from a truncated transcript
  does not trust its own recollection.
- **A gate run you intend to trust must not overlap a live agent.** CPU
  contention alone once produced a 276-second suite with nine phantom failures
  against a 60–95 second baseline; all of them passed in isolation. Either the
  worktree is quiet, or the number is provisional and must be labelled so.
- **Check `git diff --cached` before every commit.** A blocked implementer can
  leave files staged, and a later commit in the same worktree silently adopts
  them.
- **Wait on process exit and a total line when polling a test run**, not on the
  first "0 failures" you see — sub-suite output has produced false greens.
- Verify how agents can message the controller early; in some harnesses they
  cannot, and **report files are the only reliable channel**.

## Verify, don't assume

Plans and task briefs are written ahead of the code and drift from it. Real
findings from a single push:

- A brief asserted a property "keeps its other readers" when it had **zero**
  readers — deleting it removed an unscoped SQL query running on two load paths
  and every folder refresh.
- A plan named a new type whose name was already taken by an unrelated struct.
- A blast-radius checklist miscounted call sites (8 listed, 9 in the tree).
- Verbatim plan code that did not compile.
- Line-number citations stale by dozens of lines throughout.

Symbol names are the contract; line numbers are a hint. Instruct every
implementer to verify a brief's factual claims against the source before
relying on them, and treat a brief's assurance as a hypothesis.

**Plan silence reads as permission to skip.** When a ruling adds scope the plan
never mentioned, the brief must carry it explicitly.

## Reviews

- Review after every task, with two verdicts: spec compliance and code quality.
- Give the reviewer the diff as a file, not pasted text, and the same brief the
  implementer had.
- **Do not pre-judge findings for a reviewer.** Never instruct one to ignore an
  issue; let it raise the finding and adjudicate in the loop.
- A finding that conflicts with plan text is the human's decision — present the
  finding and the plan text, and ask which governs.
- **Do not accept an implementer's suite numbers for a gate decision.** The
  controller runs its own gates.
- When a reviewer's finding is answered one way in one task and the opposite
  way in another, resolve the tension explicitly rather than letting doctrine
  drift. (A coupling argument rejected as "incidental" in one task was
  legitimately accepted as "forced" in another — but only after the difference
  was articulated.)
- Resuming the original reviewer for a re-review preserves its first-pass
  context; it judges its own findings instead of re-deriving them from a diff.

## End-to-end verification is load-bearing

There is no SwiftUI view-inspection library in this project. A significant part
of any UI push's user-facing surface — control enablement, gating, hover
states, transient overlays — has **no verification path except a live run**.

Scenario cards driven in the VM are therefore a gate, not a formality. On the
unified-shell push they found two real defects that ~2,400 unit tests could
not: a sidebar disclosure that could never reach its children, and a dropped
"already in catalog" count that also corrupted a status message.

See `test/scenarios/README.md` for the harness, and treat "this behaviour has
no unit-testable surface" as a requirement to card it, not an excuse to skip
it.

## Escalation

Stop and ask the human when: a task is blocked after the standard remedies, a
reviewer finding conflicts with plan text, a product or design decision is
needed, an invariant looks violated, or a falsification break fails to produce
red. Write the ledger first so the work is resumable, then ask one question at
a time with a recommendation attached.

Everything else — naming, sequencing, engineering trade-offs, test design — is
the agent's to decide, and the decision belongs in the ledger with its
reasoning.

## Reporting honestly

- Report outcomes as they are: if tests fail, say so with the output; if a step
  was skipped, say that.
- Label a number provisional when the measurement was contaminated. "I do not
  yet have a verified result" beats a green you cannot defend.
- Retract a wrong claim as soon as you find it, including your own from earlier
  in the same session, and say why it was wrong.
- Volunteering a limitation in your own evidence is the behaviour to reward;
  it is how several real defects on this project surfaced.
