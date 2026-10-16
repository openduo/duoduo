# 多多随身 (DuoDuo Pocket): connecting and using the iPhone app

What the owner does on the phone, with the labels the app shows. Read it at `SKILL.md` step 6, or
when the owner asks about a screen or a banner. Source and design:
[openduo/pocket-ios](https://github.com/openduo/pocket-ios) (`README.md`, `SECURITY.md`,
`docs/design/native-app.md`). The app's UI is Simplified Chinese with an English localization; it
follows the phone's language. Labels below are given as zh / en.

Contents:

- What the app is
- Onboarding
- Using it
- Settings
- Banners and states
- Troubleshooting

## What the app is

- One app is one room: a chat with 多多, plus hold-to-talk voice notes, photos and files, and an
  ambient mode in which the phone listens to the room and speaks the answers.
- It embeds its own Tailscale node (tsnet, userspace). No VPN profile is installed, and the
  phone's system Tailscale app is not involved. The node appears in the tailnet as
  `duoduo-pocket`.
- Every connection dials out from the phone to the channel host; nothing listens on the phone.
- History comes from the channel and is cached on the phone for offline reading.

## Onboarding

First launch has three steps.

| Step | Screen (zh / en)                         | What the owner does                                                                                                                                  | Done when                  |
| ---- | ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| 1    | 先连上你的网络 / Connect to your network | 登录 Tailscale / Log In to Tailscale, sign in with the account of the tailnet this host is on, return to the app                                     | The node is running        |
| 2    | 配对这台手机 / Pair this phone           | Tap the pairing link from `device add`, 扫描二维码 / Scan QR code, or 粘贴配对链接 / Paste pairing link, then 配对 / Pair ([devices.md](devices.md)) | 已配对 · 房间「<room_id>」 |
| 3    | 添加 Passport / Add Passport             | Pair the Passport ([passport.md](passport.md)), or skip                                                                                              | Paired or skipped          |

Host, port, HTTPS and room all come from the link; the owner types nothing. A pairing link tapped
later (from Messages, Notes, the camera) opens the same sheet over whatever screen is showing.

Signing in with an account of another tailnet is the most common mistake: the phone then cannot
resolve the host. The node and the channel host must be in the same tailnet.

Permissions are asked when first needed: microphone on the first hold or ambient on, Bluetooth on
the Passport step, Photos and Camera on first use.

## Using it

| Action                                 | How                                                                                                                                                                           |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Type                                   | The composer at the bottom                                                                                                                                                    |
| Voice note                             | 按住说话 / Hold to Talk: hold, speak, release to send. The transcript appears, then the answer                                                                                |
| Photos and files                       | The attach menu in the composer. Over the channel's upload limit: 文件太大                                                                                                    |
| Ambient mode (环境模式 / Ambient mode) | The waveform button at the top right. While on, the phone listens to the room, holds its capture seat, and speaks answers. Tap again to open the call view; 关闭 turns it off |
| Passport                               | The device chip at the top right, beside the waveform button                                                                                                                  |

- Answers are spoken only while ambient mode is on. Otherwise they are shown (and on the
  Passport's screen).
- Only one device holds a room's capture seat. If another device has it, ambient mode shows
  另一台设备在听 / Another device is listening and 在这台手机上听 / Listen on this iPhone to take it.
- Ambient mode can keep listening with the app in the background or the phone locked: Settings,
  离开 App 后继续听 / Keep listening outside the app. Turn it off to stop when the app leaves.

## Settings

| Section (zh / en)  | Contents                                                                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 连接 / Connection  | 频道主机 / Channel Host and 房间 / Room (read-only, from pairing; 重新配对 / Pair Again replaces them), Tailscale (state, node name, IP, 退出登录 / Log Out) |
| 声音               | 离开 App 后继续听, hold-to-talk haptics, which microphone to use with AirPods, 环境模式的声音 / Ambient mode audio                                           |
| 配件 / Accessories | Passport                                                                                                                                                     |
| 诊断 / Diagnostics | Export logs (app, tsnet and Passport logs as one share sheet), `config_issues` from the channel, version                                                     |

Host, port, HTTPS and room are stored in UserDefaults and the device token in the Keychain;
nothing about the host is built into the app. Logs are under `Documents/logs`, visible in the Files app, so the owner can share them.

## Banners and states

| The app shows (zh / en)                                                   | Meaning                                         | Where to look                                      |
| ------------------------------------------------------------------------- | ----------------------------------------------- | -------------------------------------------------- |
| 在线 / Online                                                             | Connected                                       | —                                                  |
| 连接中… / Connecting…                                                     | Launching or reconnecting                       | —                                                  |
| 连不上 · 正在重试 / Offline · retrying, and a banner with the cached time | The channel cannot be reached; sends are queued | `SKILL.md` step 5 host checks; serve status        |
| 需要重新登录 Tailscale / Log in to Tailscale again                        | The phone's node needs login                    | The owner logs in again from the banner            |
| 需要重新配对 / Pair again                                                 | The device was revoked, or never paired         | Issue a link ([devices.md](devices.md))            |
| 多多暂时无法回复，消息会先记下                                            | `daemon_ok` is false                            | `duoduo daemon status`                             |
| 语音服务暂不可用 / Voice service unavailable                              | `cerebellum_ok` is false; typing still works    | [channel.md](channel.md), Troubleshooting          |
| 没听清，再说一次                                                          | The voice note transcribed empty                | Speak again                                        |
| 识别出错 · 轻点重试                                                       | Transcription failed on the cerebellum          | Retry; if it persists, whoever runs the cerebellum |

## Troubleshooting

| Symptom                                 | Cause and fix                                                                                                                                           |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pairing says Tailscale is not connected | The node is not logged in, or it is in another tailnet. Settings › Tailscale shows the state                                                            |
| Pairing cannot reach the host           | Wrong `--url` in `device add`; or serve is not running (`tailscale serve status`); or a tailnet ACL blocks the phone ([tailnet-acl.md](tailnet-acl.md)) |
| Pairing answers 403 host not allowed    | `AMBIENT_HTTP_HOSTS` does not hold the exact name in the link, or the channel was not restarted after adding it                                         |
| The link has expired or was used        | Issue a new one; each code works once                                                                                                                   |
| Two phones in one room                  | One room per phone. Create a second room for the second phone and pair it to that room                                                                  |
| The owner wants to start over           | Settings › Tailscale › 退出登录 / Log Out logs the node out; the next launch asks for the Tailscale login again                                         |
