# Host-Mode Map

Use this reference when the request is "explain duoduo to me" or when you need
to orient a user before changing anything.

## Core Surfaces

- `duoduo daemon status`: runtime health, pid, runtime mode
- `duoduo daemon config`: effective config and resolved paths
- `duoduo daemon restart`: replace the running background daemon with a freshly
  started process that picks up new code and env-backed settings
- `duoduo daemon logs`: daemon logs
- `duoduo channel list`: installed channels and running state
- `~/.config/duoduo/.env`: persistent host-mode env-backed settings

## Filesystem Model

- `kernel_dir/config/<kind>.md`
  Holds per-channel-kind defaults such as `new_session_workspace`,
  `prompt_mode`, tool allowlists, and the kind-level prompt body.
- `runtime_dir/var/channels/<channel_id>/descriptor.md`
  Holds per-channel-instance overrides such as `display_name`,
  `new_session_workspace`, `prompt_mode`, `stream`, tool lists, and the
  instance-level prompt body.
- `runtime_dir/var/channels/<channel_id>/`
  Holds per-channel runtime data such as inbox/outbox/session attachments.

Use `duoduo daemon config` to discover the actual `kernel_dir` and `runtime_dir`
instead of assuming `~/aladuo` or `~/.aladuo`.

## Mental Model

- `stdio` is the default direct operator surface after onboarding.
- In host mode, the daemon runs as a detached background process with PID
  tracking.
- `duoduo` from the same real directory re-attaches the same stdio session
  rather than creating an unrelated one.
- Channel plugins extend duoduo to external surfaces such as Feishu.
- Kind descriptors define defaults for all channels of one kind.
- Instance descriptors override one specific channel instance.
- Host-mode persistence lives in files; changing a file is often the actual
  control-plane action.

## Upgrade Flow

Update the CLI package:

```bash
npm install -g @openduo/duoduo@latest
```

Then restart the daemon:

```bash
duoduo daemon restart
```

Reason: the already-running background daemon keeps using the old code until it
is restarted.

## Restart Rule

- Editing `~/.config/duoduo/.env`: requires `duoduo daemon restart` for
  env-backed daemon settings to take effect.
- Editing `kernel/config/<kind>.md` or `descriptor.md`: takes effect on the next
  relevant turn or new session binding; channel process restart is only needed
  when credentials or plugin process env changed.
