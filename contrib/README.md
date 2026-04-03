# contrib

Community extensions for duoduo. Each subdirectory is a self-contained
extension that the agent can install by reading its `DUODUO.md`.

## Convention

```
contrib/<name>/
  DUODUO.md        # Required — frontmatter + agent-readable install guide
  ...              # Extension files (HTML, scripts, configs, etc.)
```

### `DUODUO.md` format

YAML frontmatter followed by Markdown body.

#### Frontmatter (required)

```yaml
---
name: my-extension            # Machine ID, must match directory name
type: dashboard               # Category: dashboard | channel | tool | workflow
version: 0.1.0                # Semver
author: github-username        # Maintainer
description: One-line summary  # For listing and discovery
requires:                      # Optional — prerequisites
  - python3
  - feishu-credentials
---
```

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | yes | Machine identifier, matches directory name |
| `type` | yes | Extension category for filtering |
| `version` | yes | Semver, for future compatibility checks |
| `author` | yes | GitHub username of maintainer |
| `description` | yes | One-line summary for `contrib list` |
| `requires` | no | External prerequisites the agent checks before installing |

Keep frontmatter minimal — installation details belong in the Markdown body.

#### Markdown body

Must include:

- **What this is** — one paragraph explaining the extension
- **Install** — concrete steps the agent can execute
- **Uninstall** — how to revert
- **Dependencies** — external requirements, if any

### Runtime path discovery

Extensions must **never hardcode** runtime paths. Scripts and dashboards
should discover paths via the `system.runtime.info` RPC:

```bash
curl -s http://localhost:20233/rpc \
  -d '{"jsonrpc":"2.0","id":1,"method":"system.runtime.info"}' \
  | jq '.result'
```

Returns `runtime_dir` (state/data) and `kernel_dir` (config/memory).
Derive sub-paths from these roots (e.g. `${runtime_dir}/var/channels`,
`${kernel_dir}/config`).

### Guidelines

- Extensions must not require changes to the duoduo core package.
- Install steps should be idempotent where possible.
- File paths in scripts must use RPC-discovered paths, not hardcoded values.
- Keep dependencies minimal — prefer single-file solutions.

## Usage

Clone this repo (or just the `contrib/` directory), then ask the agent:

> 帮我装一下 contrib 里的 dashboard

The agent reads `contrib/dashboard/DUODUO.md` and follows the steps.
