# Issue Reporting

Use this reference when the user wants to report a duoduo bug, regression,
paper cut, or documentation gap to the public repo `openduo/duoduo`.

## First Confirm It Is Worth Filing

Before opening an issue:

1. Confirm the runtime mode and current effective config.
2. Capture the exact user-visible symptom.
3. Gather the smallest reproducible sequence or the clearest failure pattern.
4. Distinguish product bug from local setup mistake whenever possible.

Useful commands:

```bash
duoduo daemon status
duoduo daemon config
duoduo daemon logs
duoduo channel list
duoduo channel <type> status
duoduo channel <type> logs
```

## Public Repo Rule

Issues go to:

```bash
gh issue create --repo openduo/duoduo
```

or:

```bash
gh issue comment --repo openduo/duoduo ...
```

## Do Not Leak Private Source

Public issues must not include:

- private repo file paths
- private line numbers
- private function or class names unless they are already public API surface
- pasted private source code

Describe behavior, reproduction, impact, and fix direction in product terms.

## Good Issue Shape

Include:

- what the user was trying to do
- what actually happened
- what they expected
- exact commands or steps if they are public-safe
- runtime mode, channel kind, and version if known
- impact or severity

## Practical Flow

1. Write a short title in user-visible terms.
2. Draft a concise repro.
3. Include only public-safe details.
4. Create the issue in `openduo/duoduo`.

If the user only wants a draft, prepare the title and body without posting it.
