# Channel lifecycle (cross-kind conventions)

This reference holds conventions that apply to **every** channel
plugin. Kind-specific behavior (Feishu setup card, WeChat QR, ACP
init) is in that kind's reference file.

## Installer conventions

`duoduo channel install` accepts:

1. An npm package spec: `@openduo/channel-<kind>` (preferred for
   published plugins).
2. A local `.tgz` tarball path: `./openduo-channel-<kind>-*.tgz`
   (used for pre-release / host-mode deploy).

Do NOT advertise `duoduo channel install https://github.com/...` unless
the runtime version actually supports it. If a user asks for a build
from source, that's only appropriate when the package is unpublished,
a dev build is required, or they have a local unreleased tarball.

### Install is pure write-to-disk (v0.5+)

`duoduo channel install` writes the new package to disk and atomically
swaps it in. It does **not** stop, restart, or otherwise touch any
running plugin process. POSIX file semantics keep the running process
mapped to the previous code via its open inode until it exits on its
own terms.

This means:

- After `install`, the channel keeps serving on the OLD code. You will
  see `duoduo channel <kind> status` show the new package version but
  the same `pid` as before — that is correct.
- The new code only takes effect after an explicit `stop && start`.
- Operators who want to refresh the running version must issue:
  ```bash
  duoduo channel <kind> stop
  duoduo channel <kind> start
  ```
- Pre-v0.5 behavior was different: install used to terminate the
  running plugin and leave it stopped. Any automation written against
  the old behavior should be updated to issue an explicit stop+start
  when a version swap is desired.

## Lifecycle subcommands

All channel plugins expose:

```bash
duoduo channel <kind> start
duoduo channel <kind> status
duoduo channel <kind> stop
duoduo channel <kind> logs
```

There is no `restart` subcommand. When a full cycle is required
(after reset, after env change), use `stop && start`.

## `doctor` subcommand (v0.5+)

Optional per-plugin self-diagnosis. Not every plugin exposes it — run
`duoduo channel <kind> doctor` and if it's unrecognized, fall back to
manual log inspection.

`doctor` typically refuses to run on a live plugin (it needs stdin or
credentials that the running process holds). When the plugin exposes
it, the required sequence is:

```bash
duoduo channel <kind> stop
duoduo channel <kind> doctor
# apply any fixes the doctor recommends
duoduo channel <kind> start
```

## Env credential hygiene

Channel credentials live in `~/.config/duoduo/.env`. After editing
that file:

- Channel-scoped keys (FEISHU_*, WECHAT_*, …) → restart only the
  affected channel plugin.
- Daemon-scoped keys (ALADUO_*) → `duoduo daemon restart`; channel
  plugins may or may not need a restart depending on whether they
  cache the resolved value at startup.

## After install, verify

`install` only writes to disk (see "Install is pure write-to-disk"
above), so a fresh install of a not-yet-running plugin leaves it
`stopped`. To bring it up:

```bash
duoduo channel list              # confirms the new plugin is registered
duoduo channel <kind> start      # actually launches the process
duoduo channel <kind> status     # confirms it started cleanly
duoduo channel <kind> logs       # first few lines should show handshake
```

If you are upgrading an already-running plugin to a new version, the
sequence is:

```bash
duoduo channel install <new.tgz>     # disk only, old process keeps serving
duoduo channel <kind> stop           # release the old version
duoduo channel <kind> start          # boot the new version
```

If `logs` is quiet or `status` reports a crash loop, the handshake
with the daemon failed — check `duoduo daemon logs` for the
counterpart.
