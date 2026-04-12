# Channel Config Model

Use this reference when the user asks to change channel prompts, workspaces, or
streaming behavior.

## Two Editable Layers

- Kind descriptor: `kernel_dir/config/<kind>.md`
- Instance descriptor: `runtime_dir/var/channels/<channel_id>/descriptor.md`

Resolve `kernel_dir` and `runtime_dir` with `duoduo daemon config`.

## When To Edit Which Layer

- Edit the kind descriptor when the user wants a default for all channels of one
  kind such as all `stdio` sessions or all `feishu` rooms.
- Edit the instance descriptor when the user wants to customize one specific
  chat, room, or channel surface.

## Common Frontmatter Keys

- `new_session_workspace`
- `prompt_mode`
- `time_gap_minutes`
- `stream`
- `allowedTools`
- `disallowedTools`
- `additionalDirectories`

## Prompt Assembly

- Kind prompt: Markdown body of `kernel_dir/config/<kind>.md`
- Instance prompt: Markdown body of `descriptor.md`

Effective behavior is:

1. identity prompt
2. kind prompt
3. instance prompt

Instance values replace kind values for the same key.

## Safe Editing Rule

Prefer edits that preserve:

- YAML comments in bootstrapped kind descriptors
- the existing Markdown body unless the user asked to rewrite the prompt
- unrelated keys already set by the operator
