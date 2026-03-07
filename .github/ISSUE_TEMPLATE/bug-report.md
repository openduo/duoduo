---
name: Bug Report
about: Report a bug — optimized for agent submission
title: "[bug] <short description>"
labels: bug
assignees: ''
---

<!--
This issue template is designed for agents. Humans are also welcome to file bugs using this format.

Context: The published duoduo packages contain minified JavaScript. You do not need the original source tree.
- Locate the relevant code in `node_modules/@openduo/duoduo/dist/` or the installed global package.
- Use minified function/variable names or byte offsets to reference specific locations.
- Include a minimal reproduction — ideally a shell sequence or a concrete filesystem state that triggers the bug.
-->

## Environment

- duoduo version: <!-- e.g. 0.2.4 — run `duoduo --version` -->
- Node.js version:
- OS / platform:
- Runtime mode: <!-- container | host -->
- Channel (if relevant): <!-- feishu | acp | stdio | none -->

## What happened

<!-- Describe the observed behavior. Be concrete: what command was run, what input was sent, what output or error was produced. -->

## What was expected

<!-- Describe the correct behavior. -->

## Reproduction

<!-- Minimal steps to reproduce. Prefer a shell sequence or filesystem state description over prose. -->

```sh
# Example
duoduo daemon start
# send message via channel / trigger condition
```

## Relevant output or error

```
# Paste log output, stack traces, or error messages here.
# Run with ALADUO_LOG_LEVEL=debug for verbose output.
```

## Code location (if identified)

<!--
If you have identified the relevant code in the minified bundle, reference it here.
Useful formats for agents:
- File path + approximate byte range: `dist/daemon.js` bytes 14200-14350
- Minified symbol name if recognizable: function `Xe` in `dist/daemon.js`
- RPC method or runtime component: `channel.ingress` handler in the gateway layer
- Behavioral description if exact location is unclear: "the session lock acquisition path in the runner"

You do not need to paste the minified code — just enough to locate it.
-->

## Additional context

<!-- Anything else relevant: config files (redact secrets), filesystem layout anomalies, timing conditions, etc. -->
