# Subconscious Refresh

Use this reference when the user wants to pull a newer version of the
subconscious partition prompts into their running duoduo installation,
or roll back to a specific tagged version.

## Scope

This procedure **only** touches `<kernel>/subconscious/` files that
come from the public repo (partition prompts + `playlist.md` +
`subconscious/CLAUDE.md`). It does not touch `memory/`, user data
under `var/`, user-created partitions that never existed in the
public repo, or agent-installed skills.

The kernel directory is the aladuo kernel — typically `~/aladuo/`,
but confirm with `duoduo daemon config` since operators can override
it.

## When to Use

- The user asks to "refresh" / "update" / "升级" / "同步" their
  subconscious / partition prompts.
- A new duoduo version was released and release notes mention
  subconscious prompt changes.
- The user wants to inspect the diff between their current
  subconscious and the published version of a given tag.

Do not run this for:

- Upgrading the duoduo daemon or channel packages — that is
  `npm install -g @openduo/duoduo@<version>` plus
  `duoduo daemon restart`, covered in the main admin skills.
- Editing partition prompts locally — that is a normal text edit
  plus `git commit` inside the kernel; no skill needed.

## Preconditions

Before doing anything destructive:

1. Confirm the kernel path and current duoduo version:

   ```bash
   duoduo daemon config
   duoduo --version
   ```

2. Confirm the kernel is a clean git tree:

   ```bash
   git -C <kernel> status
   ```

   If the tree is dirty, stop and surface the pending changes to the
   user. Refreshing on a dirty tree risks mixing unrelated edits into
   the refresh commit.

3. Confirm the user's intended target tag (default: the tag matching
   their installed duoduo version, e.g. `v0.5.0`). The public repo
   is `openduo/duoduo`; valid tags are `v<X.Y.Z>`.

## Inspect Before Changing

Always show the diff before overwriting. Agents should not destroy
local state silently — `memory-committer` is the only subconscious
layer that commits without asking, and even it skips trivial changes.

Typical shell sequence:

```bash
# Fetch only the subconscious tree for the target tag into a tmp dir.
tmp=$(mktemp -d)
git clone --depth 1 --branch <target-tag> \
  https://github.com/openduo/duoduo.git "$tmp/upstream"

# Diff against the kernel's current subconscious.
diff -ruN <kernel>/subconscious "$tmp/upstream/subconscious" | head -200
```

Summarize the diff for the user:

- Which partition prompts changed (added / removed / modified)?
- Are any user-authored partitions (present locally, absent upstream)
  going to be preserved? They should be — overwrite only files that
  exist upstream.
- Are there local changes to upstream files (user edited a shipped
  partition's CLAUDE.md)? If yes, those will be lost on overwrite.
  Ask the user explicitly before proceeding.

## Executing the Refresh

Once the user has approved:

1. Overwrite only files that exist in the upstream tag. Leave
   user-authored partition directories alone.

   ```bash
   # Rough sketch — adapt to the actual upstream layout. Copy each
   # path that exists upstream; do not rm -rf the whole directory.
   for path in $(cd "$tmp/upstream/subconscious" && find . -type f); do
     mkdir -p "$(dirname <kernel>/subconscious/$path)"
     cp "$tmp/upstream/subconscious/$path" "<kernel>/subconscious/$path"
   done
   ```

2. Commit the result inside the kernel git repo:

   ```bash
   git -C <kernel> add subconscious/
   git -C <kernel> commit -m "subconscious: refresh to <target-tag>"
   ```

   This commit is the rollback point. The user can always
   `git revert` it if the refreshed prompts misbehave.

3. Clean up the temp clone:

   ```bash
   rm -rf "$tmp"
   ```

## After the Refresh

- Subconscious partitions reload their prompts from disk each tick.
  No daemon restart is required for prompt changes to take effect.
- The next cadence tick (up to one cadence interval away) will run
  the refreshed partitions. `duoduo daemon config` shows the
  current cadence interval.
- If the user regrets the refresh:

  ```bash
  git -C <kernel> revert <refresh-commit>
  ```

## Common Situations

**The user has edited an upstream partition's prompt.**
Their edit lives in the kernel git history. Refresh will overwrite
the current file. Offer two paths: (a) refresh now and the user
re-applies their edit in a follow-up commit; (b) skip the file (do
not copy it from upstream) and lose that file's upstream updates.
Most users want (a) — upstream wins, they port their edits forward.

**No network / git fetch fails.**
Surface the real error. Do not fall back to half-refreshed state.
Abort and leave the kernel untouched.

**Target tag does not exist.**
`git clone --branch` will fail cleanly. Ask the user for a valid
tag. Tags are listed at
<https://github.com/openduo/duoduo/releases>.

**Kernel path is inside a container.**
The refresh still works, but commands must run inside the container
shell (`duoduo container:shell` or equivalent). The host file
system's git and the container's kernel git are different repos.
