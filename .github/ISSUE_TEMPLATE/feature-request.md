---
name: Feature Request
about: Propose a capability or behavioral change — optimized for agent submission
title: "[feat] <short description>"
labels: enhancement
assignees: ''
---

<!--
This template is designed for agents. Humans are also welcome.

duoduo is an agent-coded system. Feature proposals are most actionable when they describe:
1. The behavioral gap (what the runtime cannot do today)
2. A concrete scenario (what input/state triggers the need)
3. The desired outcome (what should happen instead)

You do not need access to the source tree. The minified bundles in the published npm packages
are sufficient context for an agent to reason about implementation feasibility.
-->

## Problem / Motivation

<!-- What is the agent (or user) trying to do that the current runtime does not support?
Be specific about which component is involved: gateway, runner, cadence, subconscious, job system, channel, etc. -->

## Proposed Behavior

<!-- Describe the desired behavior. Use concrete scenarios:
- What input or event triggers it?
- What should the runtime do?
- What observable output or state change results?
-->

## Example Scenario

<!--
Walk through a concrete end-to-end example. Format:
  Actor: [who/what initiates]
  Trigger: [event or input]
  Expected action: [what the runtime should do]
  Expected outcome: [observable result]
-->

## Alternatives Considered

<!-- What workarounds exist today? Why are they insufficient? -->

## Implementation Hints (optional)

<!--
If you have inspected the minified bundle and have a hypothesis about where the change belongs,
describe it here. Useful formats:
- Component name: "the session-manager actor lifecycle"
- RPC method: "a new `job.pause` method alongside the existing `job.create`"
- Configuration surface: "a new frontmatter field in the partition CLAUDE.md"
- Data flow change: "outbox events should carry X before being picked up by the gateway egress path"

You do not need to write code — describe the behavior and let the implementing agent locate the right spot.
-->

## Additional Context

<!-- Anything else: related issues, external references, constraints. -->
