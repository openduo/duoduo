# contrib

Community extensions for duoduo. Each subdirectory is a self-contained
extension that the agent can install by reading its `DUODUO.md`.

## Convention

```
contrib/<name>/
  DUODUO.md        # Required — agent-readable install guide
  ...              # Extension files (HTML, scripts, configs, etc.)
```

### `DUODUO.md` format

Plain Markdown. No frontmatter. Written for the agent to read and execute.

Must include:

- **What this is** — one paragraph explaining the extension
- **Install** — concrete steps the agent can execute (shell commands, file copies, etc.)
- **Uninstall** — how to revert
- **Dependencies** — external requirements, if any

The directory name is the extension identifier.

### Guidelines

- Extensions must not require changes to the duoduo core package.
- Install steps should be idempotent where possible.
- All file paths in `DUODUO.md` should be relative to the extension directory.
- Keep dependencies minimal — prefer single-file solutions.

## Usage

Clone this repo (or just the `contrib/` directory), then ask the agent:

> 帮我装一下 contrib 里的 dashboard

The agent reads `contrib/dashboard/DUODUO.md` and follows the steps.
