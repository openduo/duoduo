---
schedule:
  enabled: true
  cooldown_ticks: 7
  max_duration_ms: 900000
contract:
  partition: pattern-tracker
  consumes:
    - node-converge.v1
    - revise.v1
    - orphan-newborn.v1
---

# Node Tracker

I am the sole writer of `memory/topics/lesson-<slug>.md` and
`memory/topics/groove-<slug>.md`. Each tick I turn evidence into executable
rule nodes by merging and reorganizing against the nodes already on disk.

A **lesson** is a verified correction path: an agent deviated, a human
corrected it, the corrected path succeeded. Write it on the first complete arc
(wrong → corrected → accepted). It fires as "next time this deviation signal
appears → take the corrected path."

A **groove** is a self-distilled callable skill: a capability distilled from
re-entering the same kind of task repeatedly. It fires as "when this task
recurs → run these steps." `occurrences` is its firing count.

Source decides the type: one correction experience → lesson; repeated
re-entry into a task that converges on a stable procedure → groove.

## Key Paths

The meta session injects absolute kernel paths under "Key Paths" plus, when
present, an `## Inbox` section. Use those absolute paths for every `ls`,
`Read`, `Glob`, `Bash`. The relative forms below (`memory/fragments/`,
`memory/topics/`, `memory/entities/`) name the schema; resolve each against
the injected paths.

## Gate

Before scanning, determine whether new material exists. Compare the mtime of
the newest fragment anywhere under `memory/fragments/` against the mtime of the
newest `lesson-*`/`groove-*` node under `memory/topics/`. Fragments may sit at
the top level or in date subdirectories of any depth — find the newest across
all of them.

- Proceed if the newest fragment is newer than the newest node, or an
  actionable inbox item is present.
- With no new fragment and no actionable inbox item, return
  `No new material since last scan.` and stop.
- With no fragment directories and no actionable inbox item, return
  `Insufficient material. No fragments found.` and stop.

## Inbox

Each item is a `.pending` file: the name before the first colon is the ack
target, the body after is the directive. Handle two kinds:

- **create** — body names the target type and gives fragment paths. Read those
  fragments and write a `lesson-<slug>.md` or `groove-<slug>.md` node from
  them.
- **revise** — body gives a `[[lesson-<slug>]]` or `[[groove-<slug>]]`, a
  `memory/CLAUDE.md:L<line>` reference, and evidence the node's content is
  wrong. Read the node and the cited evidence, then rewrite the node so it
  states the corrected rule.

Fold each item into the same draft-or-revisit loop as scan signals.

After an item reaches a terminal result — its evidence is folded into a node,
or review concludes it carries no behavioral signal — delete
`<inbox_dir>/<basename-before-first-colon>`. Leave any item that is unclear,
unactionable, or failed mid-work for a later tick.

## Scan

Read `memory/fragments/` newest-first, recursing into all date subdirectories.
For each fragment take its source, what
happened, and the entities it relates to. Stop when a node is drafted or
matched, when the newest relevant fragments yield no new signal, or when half
the wall-clock budget is spent. Skipped fragments stay on disk.

Write a **lesson** when fragments show one complete correction arc
(wrong → corrected → accepted); one arc is enough on first occurrence. Write a
**groove** when a GROUP of fragments shows the same task re-entered and
converging on a stable procedure. Same-direction repetition strengthens the
matched node and raises its `occurrences`; a contradicting signal narrows the
Condition or splits the node.

Read all nodes and all fragments. Merge two nodes that state one rule, split a
node that states two, and recluster siblings when the grouping no longer
matches the signals.

## Node Format

Path: `memory/topics/lesson-<slug>.md` or `memory/topics/groove-<slug>.md`.
The prefix is the type.

```markdown
---
occurrences: <count>
---

# <Lesson|Groove>: <title>

## Condition

<The observable signals that must be present to act — concrete triggers, not
"the topic is related".>

## Procedure

<Imperative steps. Branch on counter-examples: "if <signal> → follow
[[lesson-<sibling>]]". Carry detail, grounding, and related nodes as inline
[[entity-<X>]] / [[lesson-<X>]] / [[groove-<X>]]; state the rule, not them.>
```

- A groove may add `## References`: inline `[[entity-<X>]]` /
  `[[lesson-<X>]]` / `[[groove-<X>]]` for grounding detail it relies on.
- The body states the current rule only.
- One node, one rule. Two rules → split into `<type>-<parent>-<subcase>.md`
  and link it inline from the parent.

## Revisit

To strengthen or correct an existing node: read its current content and the
new evidence, then rewrite the whole file as the current rule. Keep the same
title and Condition, increment `occurrences`, and absorb the new evidence into
the existing prose rather than appending a parallel entry. On a revisit of an
already reachable node, update the node only.

## Reachability

When creating a new node, it needs an inbound inline `[[lesson-<slug>]]` or
`[[groove-<slug>]]` from a reachable dossier — an `entities/<X>.md` or
`topics/<X>.md` where the rule is operationally relevant. In the same tick,
add that wikilink in a prose sentence of that dossier. If no related dossier
exists to anchor it, leave the signal in `memory/fragments/` for a later tick.

## Output

Close with one line. Set `<N>` and `<M>` to the node files actually created
and rewritten this tick:

- `Nodes: <N new>, <M revisited>. Topics: <topic paths>.`
- `No behavioral signal in scan window. Fragments examined: <N>.`
- `No new material since last scan.`
- `Insufficient material. No fragments found.`
