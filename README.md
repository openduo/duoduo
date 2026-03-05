# duoduo

**A proactive, self-evolving agent runtime.**

duoduo is an open autonomous agent runtime built on Claude. It maintains persistent memory, runs background processes, and evolves its own behavior over time — not just a chat wrapper, but a living system.

[![npm](https://img.shields.io/npm/v/@openduo/duoduo)](https://www.npmjs.com/package/@openduo/duoduo)
[![Website](https://img.shields.io/badge/website-openduo.ai-blue)](https://openduo.ai)

## Quick Start

```bash
npx @openduo/duoduo
```

That's it. duoduo detects your environment, starts a local daemon if needed, and opens a chat session in your current directory.

## What Makes It Different

Most agent frameworks are stateless request/response wrappers. duoduo is a runtime:

- **Durable memory** — every conversation, observation, and decision is persisted. Restart anytime and pick up where you left off.
- **Subconscious background loops** — while you work, duoduo runs background partitions that consolidate memory, review context, and evolve its own behavior.
- **Self-programming** — the agent can modify its own prompts, create new background partitions, and curate its memory layer over time.
- **Filesystem-first** — all state lives in plain files. Git-auditable, inspectable, portable.

## Installation

```bash
# Run without installing
npx @openduo/duoduo

# Global install
npm install -g @openduo/duoduo
duoduo
```

## Commands

```bash
duoduo                          # Open chat in current directory
duoduo daemon start             # Start background daemon
duoduo daemon stop              # Stop daemon
duoduo daemon status            # Check daemon status
duoduo daemon logs              # View daemon logs
```

## Channel Plugins

Connect duoduo to external services:

```bash
# Feishu / Lark
npm install -g @openduo/channel-feishu
duoduo channel feishu start --gateway

# ACP (Agent Client Protocol)
npm install -g @openduo/channel-acp
duoduo channel acp start
```

## How It Works

```text
You ──► channel.ingress ──► Spine WAL ──► Mailbox ──► Runner (Claude SDK) ──► Response
                                                              │
                                          Cadence ──► Subconscious partitions ──► Memory
```

- **Spine WAL** — append-only event log. Source of truth.
- **Runner** — executes one SDK turn per mailbox drain, with full tool access.
- **Subconscious** — background partition system that runs on a cadence, consolidates memory, and can modify its own configuration.
- **Memory** — shared broadcast board (`memory/CLAUDE.md`) auto-loaded into every session.

## Runtime Layout

```text
~/.aladuo/          Runtime state (events, sessions, outbox)
~/aladuo/           Kernel — agent's persistent memory and subconscious
  memory/           Dossiers, broadcast board, entity/topic knowledge
  subconscious/     Background partition definitions and schedule
  config/           Per-channel kind configuration
```

## Configuration

```bash
ALADUO_DAEMON_URL=http://127.0.0.1:20233
ALADUO_LOG_LEVEL=info           # debug | info | warn | error
ALADUO_RUNTIME_MODE=yolo        # yolo (host) | container
```

## npm Packages

| Package | Description |
| ------- | ----------- |
| [`@openduo/duoduo`](https://www.npmjs.com/package/@openduo/duoduo) | Core runtime + CLI |
| [`@openduo/channel-feishu`](https://www.npmjs.com/package/@openduo/channel-feishu) | Feishu / Lark gateway |
| [`@openduo/channel-acp`](https://www.npmjs.com/package/@openduo/channel-acp) | ACP bridge |
| [`@openduo/protocol`](https://www.npmjs.com/package/@openduo/protocol) | Shared types + validators |

## Issues & Feedback

Found a bug? Have a feature request? [Open an issue](https://github.com/openduo/duoduo/issues/new/choose).

## License

Source-available. Free to use. See [openduo.ai](https://openduo.ai) for terms.
