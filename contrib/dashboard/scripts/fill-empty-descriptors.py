#!/usr/bin/env python3
"""Fill empty channel descriptors from sample-descriptor.md template.

Scans .aladuo/var/channels/ for descriptors that only have frontmatter
(no <channel-meta> rules) and fills them from the template.

Usage:
    python3 scripts/fill-empty-descriptors.py
"""

import json
import os
import shutil
import tempfile

PROJECT = os.path.expanduser("~/ENG/openduo/openduo")
TEMPLATE = os.path.join(PROJECT, "aladuo/config/sample-descriptor.md")
CHANNELS_DIR = os.path.join(PROJECT, ".aladuo/var/channels")
ID_MAP = os.path.join(PROJECT, "aladuo/config/channel-id-map.json")


def main():
    with open(TEMPLATE) as f:
        tmpl = f.read()
    with open(ID_MAP) as f:
        chmap = json.load(f)

    filled = 0
    for short_id, info in sorted(chmap.items()):
        if not info.get("name") or not info.get("type"):
            continue
        long_id = info["long_id"]
        desc_path = os.path.join(CHANNELS_DIR, f"feishu-{long_id}", "descriptor.md")

        if not os.path.exists(desc_path):
            print(f"  skip: {info['name']} ({short_id}) — no channel dir")
            continue

        with open(desc_path) as f:
            content = f.read()

        if "<channel-meta>" in content:
            print(f"  ok:   {info['name']} ({short_id})")
            continue

        new_content = (
            tmpl.replace("{{CHANNEL_ID}}", long_id).replace(
                "{{CHANNEL_NAME}}", info["name"]
            )
        )

        # Write via temp file + sudo to handle uid 1001 ownership
        fd, tmp = tempfile.mkstemp(suffix=".md")
        with os.fdopen(fd, "w") as f:
            f.write(new_content)
        os.system(f'sudo cp "{tmp}" "{desc_path}"')
        os.system(f'sudo chown 1001:1001 "{desc_path}"')
        os.unlink(tmp)
        print(f"  FILL: {info['name']} ({short_id})")
        filled += 1

    print(f"\nDone. Filled {filled} descriptor(s).")


if __name__ == "__main__":
    main()
