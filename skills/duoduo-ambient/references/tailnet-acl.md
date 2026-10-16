# Limiting the phone to the channel: a tailnet ACL draft

The channel admits only paired devices ([devices.md](devices.md)), but a pairing link or a token
is a bearer credential: whoever holds one and can reach this host's port 443 is in. On a tailnet
with the default allow-all policy that is every device and every user in it, so the policy decides
how far a leaked link reaches. Read this when the owner asks
who can reach the room, shares the tailnet with other people, or wants the phone limited to the
channel.

You draft; the owner applies. Never edit the tailnet policy yourself, even with console access:
the policy also governs devices and routes you cannot see (`SKILL.md` policy 2).

Contents:

- What the app gives the policy to match
- Draft A: tag the phone
- Draft B: match the phone by address
- Applying it safely
- What is verified

## What the app gives the policy to match

- The app joins as an ordinary device of the user who logged in, named `duoduo-pocket`. It
  advertises no tag.
- So a rule can name the phone either by a tag the owner assigns in the admin console (Draft A) or
  by its tailnet address (Draft B). A rule on the owner's user alone would also cover every other
  device of that user.
- What the phone needs: TCP 443 on the channel host. Nothing listens on the phone, so nothing needs
  to reach it.

Two goals, and the owner picks:

| Goal                                                           | Change                                                                       |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| The phone reaches only the channel                             | Rules that let the phone's identity reach anything else are narrowed         |
| Only the phone (and the owner's own devices) reach the channel | Rules that let other users or tags reach the channel host's 443 are narrowed |

Both mean narrowing an existing rule if the tailnet is on allow-all (`"src": ["*"]`,
`"dst": ["*:*"]`), because a broad rule also matches the tagged phone and the channel host.

## Draft A: tag the phone

The owner creates `tag:pocket`, then in the admin console, Machines, opens `duoduo-pocket` and
sets its tag to `tag:pocket` (Edit ACL tags). A tagged device stops being the user's device for
policy purposes: rules on `autogroup:member` or the owner's user no longer match it.

```jsonc
{
  "tagOwners": {
    "tag:pocket": ["autogroup:admin"]
  },
  "hosts": {
    "duoduo-channel": "<channel host tailnet IP>"
  },
  "acls": [
    // The phone reaches the channel's HTTPS port and nothing else.
    {
      "action": "accept",
      "src": ["tag:pocket"],
      "dst": ["duoduo-channel:443"]
    }
    // Every other existing rule stays. A rule whose src is "*" also matches tag:pocket:
    // replace that "*" with what it is meant to cover (autogroup:member, the existing tags).
  ],
  "tests": [
    {
      "src": "tag:pocket",
      "accept": ["duoduo-channel:443"],
      "deny": ["duoduo-channel:22"]
    },
    // Plus one accept per kind of destination the owner reaches today (see below).
    { "src": "<owner>@<domain>", "accept": ["duoduo-channel:22"] }
  ]
}
```

If the channel host is itself tagged, use its tag (`tag:<x>:443`) instead of the `hosts` entry.

## Draft B: match the phone by address

No tag; the phone stays the owner's device. Read its address from the admin console or from
`tailscale status` on this host (the line for `duoduo-pocket`).

```jsonc
{
  "hosts": {
    "duoduo-pocket": "<phone node tailnet IP>",
    "duoduo-channel": "<channel host tailnet IP>"
  },
  "acls": [
    {
      "action": "accept",
      "src": ["duoduo-pocket"],
      "dst": ["duoduo-channel:443"]
    }
    // Rules that match the owner's user (autogroup:member, "*", the user) also match the phone.
    // Keep the phone limited only if those rules are narrowed for it, which a user-based rule
    // cannot express. Prefer Draft A when the goal is "the phone reaches only the channel".
  ],
  "tests": [{ "src": "duoduo-pocket", "accept": ["duoduo-channel:443"] }]
}
```

Draft B is mainly useful for the second goal: letting the phone in while other users' devices are
kept off the channel host. If the app logs out and in again, the node may get a new address; check
the `hosts` entry after any re-login.

## Applying it safely

The owner applies the change in the admin console, Access controls. Before they save, give them:

1. **A backup.** They copy the current policy text somewhere first.
2. **What every broad rule covers today.** List from the admin console: the owner's devices, other
   users' devices, tags in use, subnet routes, exit nodes, devices shared in. Never replace `*`
   with a shorter list without that enumeration: a careless narrowing cuts the owner off from
   subnet routes and shared devices.
3. **The exact diff**, with a `tests` block that asserts the owner still reaches one device of each
   kind above. Tailscale refuses to save a policy whose tests fail, which guards against a lockout.

After they save, check:

```bash
tailscale ping <an existing peer>          # still answers from this host
```

and the owner reopens the app: it must show 在线 / Online and answer a typed message.
For Draft A, the owner also checks that from the phone nothing else is reachable that was before
(for example a NAS page), if they want the first goal proven.

Record in the handoff note: which draft, the tag or address, where the backup is, and how to roll
back (restore the backup, or remove the added rule, tag and `hosts` entries).

## What is verified

| Fact                                                             | Status                                                                         |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| The app's node is named `duoduo-pocket` and advertises no tag    | Verified in the app's source                                                   |
| The channel admits paired devices only; tokens are bearer tokens | Verified in the channel's source and deploy docs                               |
| Tailscale policy syntax (`tagOwners`, `hosts`, `acls`, `tests`)  | Tailscale's documented policy format; check the console's validator            |
| Draft A and Draft B on a real tailnet with the app               | Not measured. The owner's console validator and the checks above are the proof |
| A tagged device no longer matches user-based rules               | Tailscale's documented behaviour; not measured here                            |
