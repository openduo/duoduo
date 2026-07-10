#!/usr/bin/env python3
"""Scan .aladuo/var/channels/ and fetch group names from Feishu API.

Writes aladuo/config/channel-id-map.json with format:
  {"oc_short": {"long_id": "oc_full...", "name": "群名", "type": "group"}}

Usage:
    python3 scripts/refresh-channel-map.py
"""

import json
import os
import urllib.request

PROJECT = os.path.expanduser("~/ENG/openduo/openduo")
CHANNELS_DIR = os.path.join(PROJECT, ".aladuo/var/channels")
OUTPUT = os.path.join(PROJECT, "aladuo/config/channel-id-map.json")
ENV_FILE = os.path.join(PROJECT, ".env")


def load_env():
    env = {}
    with open(ENV_FILE) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def get_tenant_token(app_id, app_secret, domain):
    base = "https://open.larksuite.com" if domain == "lark" else "https://open.feishu.cn"
    url = f"{base}/open-apis/auth/v3/tenant_access_token/internal"
    data = json.dumps({"app_id": app_id, "app_secret": app_secret}).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.loads(resp.read())
    return body.get("tenant_access_token"), base


def get_chat_info(chat_id, token, base):
    url = f"{base}/open-apis/im/v1/chats/{chat_id}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read())
        data = body.get("data", {})
        return {
            "name": data.get("name", ""),
            "chat_type": data.get("chat_type", ""),  # "group" or "p2p"
        }
    except Exception as e:
        print(f"  [warn] {chat_id}: {e}")
        return {"name": "", "chat_type": ""}


def scan_channels():
    """Return list of long channel IDs from disk."""
    ids = []
    for name in sorted(os.listdir(CHANNELS_DIR)):
        if name.startswith("feishu-oc_") and os.path.isdir(os.path.join(CHANNELS_DIR, name)):
            ids.append(name.replace("feishu-", ""))
    return ids


def main():
    env = load_env()
    app_id = env.get("FEISHU_APP_ID", "")
    app_secret = env.get("FEISHU_APP_SECRET", "")
    domain = env.get("FEISHU_DOMAIN", "lark")

    if not app_id or not app_secret:
        print("[error] FEISHU_APP_ID or FEISHU_APP_SECRET not found in .env")
        return

    print("[refresh-channel-map] getting tenant token...")
    token, base = get_tenant_token(app_id, app_secret, domain)
    if not token:
        print("[error] failed to get tenant token")
        return

    long_ids = scan_channels()
    print(f"[refresh-channel-map] found {len(long_ids)} channels on disk")

    mapping = {}
    for long_id in long_ids:
        short_id = long_id[:11]  # oc_ + 8 hex
        print(f"  {short_id} -> {long_id}", end="")
        info = get_chat_info(long_id, token, base)
        mapping[short_id] = {
            "long_id": long_id,
            "name": info["name"],
            "type": info["chat_type"],
        }
        label = info["name"] or "(no name)"
        print(f"  [{info['chat_type']}] {label}")

    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(mapping, f, ensure_ascii=False, indent=2)

    groups = sum(1 for v in mapping.values() if v["type"] == "group")
    print(f"[refresh-channel-map] wrote {OUTPUT} ({groups} groups, {len(mapping) - groups} others)")


if __name__ == "__main__":
    main()
