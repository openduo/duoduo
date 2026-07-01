# duoduo 项目深度架构分析

> 分析对象：`openduo/duoduo`（GitHub 仓库）/ `@openduo/duoduo` v0.5.8（npm 运行时）
> 分析日期：2026-07-01
> 分析方式：仓库文档审读 + 本机实际部署、运行与运行时探测（host 模式，Claude Code 本地认证）
> 本文所有架构主张均标注了「文档来源」与「本次部署的实测证据」。
>
> **姊妹篇**：本文是**系统级/部署级**架构分析；如需 **agent 内部认知与运行逻辑**（提示词装配、drain 循环、事件溯源、session actor、cadence/潜意识引擎、记忆系统、runtime 抽象——均从 minified 运行时逆向 + 对抗验证）见 [`AGENT_INTERNALS_ANALYSIS.md`](./AGENT_INTERNALS_ANALYSIS.md)。

---

## 0. 一句话定位

> **duoduo 是一个"会自我编程"的长驻自治 Agent 运行时——它把智能做成可持久、可崩溃恢复的进程，而不是一次性的请求/响应包装器。**

它的核心反差在于：绝大多数 Agent 栈是无状态的（prompt 进、answer 出、状态丢失），而 duoduo 把**文件系统当数据库、事件日志当真理之源、进程默认无状态**，并在前台对话之外常驻一个"潜意识"后台循环。

---

## 1. 一个反直觉的前提：这不是传统意义的"开源项目"

部署前必须澄清一个关键事实，否则会走错路：

- **GitHub 仓库本身不包含运行时源码。** 仓库里只有：`README.md`、`CHANGELOG.md`、`skills/`（运维技能）、`subconscious/`（潜意识分区提示词）、`contrib/`（社区扩展）、`assets/`（截图）。
- **真正的运行时以"压缩后的 JavaScript"形式发布在 npm**（`@openduo/duoduo`）。作者明确说明：这套代码"不是写给人读的"——Agent 能直接读懂、修改 minified 代码，压缩只是为了节省带宽、保持上下文窗口精简。
- 因此 **"部署"= `npm install -g @openduo/duoduo` 并运行 daemon**，而非"克隆源码 + 构建"。
- License 标注为 `Private. All rights reserved.`，名称 "**open**duo" 是一句自嘲式玩笑（README 原文："we are called openduo and we don't publish source either. Respect to OpenAI."）。

> 实践意义：分析架构靠的是**官方文档 + 运行时可观测行为（文件系统、WAL、RPC、CLI）**，而不是阅读源码。本文正是这样做的。

---

## 2. 六大核心创新（文档主张 → 实测印证）

README 提出六项核心创新。下表把每一项与本次部署中**实际观测到的证据**对应起来：

| # | 创新 | 文档主张 | 本次部署的实测证据 |
|---|------|----------|---------------------|
| 1 | **文件系统优先、事件溯源运行时** | 所有状态（会话、输出、任务、记忆）都在持久化文件里；文件系统就是数据库 | `~/.aladuo/var/` 下存在 `events/`、`sessions/`、`ingress/`、`outbox/`、`usage/`、`telemetry/` 等目录；一次对话即在 `var/events/2026-06-30.jsonl` 落了 3 条事件 |
| 2 | **网关边界 WAL-before-execute** | 每条入站消息先写规范事件到 append-only 日志，再入队，再执行 | 实测 WAL 事件序列严格为：`channel.attached` → `channel.message` → `agent.result`，消息事件先于结果落盘 |
| 3 | **一个外部身份、多个内部会话** | 对外是单一 Agent 身份；对内编排多个并发 session actor，租约锁控制生命周期与并发 | `duoduo session list` 显示按 `kind`（channel/job/subconscious）+`plane`（work/...）分类的路由表；config 中 `max_concurrent_channel=10`、`max_concurrent_job=6` |
| 4 | **双环认知：Cortex + 潜意识** | 前台响应实时消息；后台按节奏常驻运行，巩固记忆、反思、维护知识广播板 | `daemon status` 显示 cadence 心跳（`every 37min`）与 `subconscious: 0/0 partitions done`；4 个分区已加载并各有 cooldown/timeout |
| 5 | **自编程认知拓扑** | 潜意识行为由文件定义；分区可改自己的提示词、新建分区、调整调度 | `subconscious/CLAUDE.md` 明确列出"我能改自己的 CLAUDE.md / 新建分区 / 改 playlist"，但禁止改 spine 数据、锁文件、`contract:` frontmatter |
| 6 | **薄运行时、重模型委派** | 应用层代码刻意做薄；推理/工具编排/规划全部委派给基础模型和 SDK | `claude-runtime.md` 证实运行时内嵌 Claude Code SDK，"runtime 只拥有模型无法可靠拥有的东西：持久化、生命周期、调度、并发边界" |

---

## 3. 进程与文件系统模型

### 3.1 两个根目录（注意区分）

| 目录 | 角色 | 内容 |
|------|------|------|
| `~/aladuo`（**kernel_dir**） | 内核 / "内在世界" | `CLAUDE.md`（内核引导）、`claude-runtime.md`、`codex-runtime.md`、`config/<kind>.md`（按通道种类的默认值与提示词）、`.git`（内核自身受 git 版本管理——这也是"自编程回滚点"的基础） |
| `~/.aladuo`（**runtime_dir**） | 运行时可变状态 | `run/`（PID、锁）、`var/`（全部事件溯源数据，见下） |

> 易混点：**带点的 `~/.aladuo` 是运行时数据**，**不带点的 `~/aladuo` 是内核**。可用 `duoduo daemon config` 查询实际路径，切勿假设。

### 3.2 `runtime_dir/var/` 的事件溯源结构（实测）

```
~/.aladuo/var/
├── events/                 # 规范事件日志（WAL，真理之源）
│   ├── 2026-06-30.jsonl    #   按天分片；单文件可达 10-30MB
│   └── index/              #   by_session / by_id 索引
├── sessions/<hash>/        # 每会话状态 + mailbox/notes.jsonl
├── ingress/<hash>/         # 入站快照
├── outbox/                 # 出站投递（stdio/、replay/、index/、.pending_queue.jsonl）
├── usage/<session>.jsonl   # 成本/token 账本（append-only，无自动保留）
├── telemetry/<day>.jsonl   # 遥测
├── cadence/inbox/          # 节奏（cron）投递箱
├── jobs/{active,archive}/  # 一次性/周期任务
├── subconscious/           # 潜意识运行数据
├── channels/<id>/          # 每通道运行数据
├── registry/dedup.jsonl    # 去重水位线
└── meta/partitions/        # 分区元数据
```

### 3.3 持久化的配置面

| 文件 | 作用 | 变更后是否需重启 daemon |
|------|------|------------------------|
| `~/.config/duoduo/.env` | host 模式持久化的环境变量（如 `ALADUO_*`、`DUODUO_NODE_BIN`） | **需要** `duoduo daemon restart`（daemon 是分离的后台进程，不热加载） |
| `~/.config/duoduo/config.json` | onboard 向导写入的选择（认证来源等） | — |
| `kernel/config/<kind>.md` | 按通道种类的默认值与种类级提示词 | 下一回合/新会话绑定时生效 |
| `var/channels/<id>/descriptor.md` | 单个通道实例的覆盖与实例级提示词 | 同上；仅当凭证/进程 env 变化才需重启通道 |

---

## 4. 数据流：一条消息的完整生命周期（实测验证）

```
                          ┌─────────────────────────── duoduo daemon (host 进程) ───────────────────────────┐
  外部通道                │                                                                                  │
 (stdio / Feishu / ACP)   │   ① 写 WAL          ② 入队           ③ 执行(drain)          ④ 出站              │
        │                 │  spine.append  →  session mailbox  →  SDK query()  →  outbox  →  replay/index   │
        │  channel.message │  (canonical      (per-session       (Claude/Codex   (落盘)                      │
        └────────────────▶│   event 先落盘)    actor + 租约锁)    runtime adapter)                           │
                          │        │                                   │                                     │
                          │   var/events/*.jsonl                 var/usage/*.jsonl  ← 成本/token 账本        │
                          └──────────────────────────────────────────────────────────────────────────────┘
```

**本次实测的事件序列**（向 stdio 发送一条 "6×7" 测试消息）：

1. `channel.attached` —— stdio 通道绑定到会话 `stdio:default:28d3ca682f86`
2. `channel.message` —— 入站消息**先写入 WAL**（WAL-before-execute 合约）
3. `agent.result` —— 模型经 Claude Code 本地认证产出回复 `DUODUO_OK_42`（正确：6×7=42）

`usage.get` RPC 同时记录了这次 drain 的账本：`total_drains=1`、`cost_usd≈0.239`、`input_tokens=2806`、`output_tokens=12`、`cache_creation_tokens=22445`。

> 这条链路完整跑通，证明 **stdio → spine WAL → mailbox → SDK drain → outbox** 的全栈可用。

---

## 5. 崩溃恢复与"进程无状态"（实测验证）

README 主张："进程中途死亡，系统从文件 rehydrate，恰好从中断处续上。"

**本次实测**：执行 `duoduo daemon restart` 后——

- 进程 PID 从 `3128489` 变为 `3129393`（确实是全新进程），
- 但 **`runtime_id` 保持 `rt_b3b7599e9317` 不变**（运行时身份跨进程持久化），
- 会话从文件重建：`session list` 仍显示同一 `stdio:default:28d3ca682f86`、同一 `LAST_EVENT` 时间戳，
- WAL 3 条事件完好无损，
- 认证来源从 `.env` 重新加载（`claude_auth_source: claude_code_local`）。

> 结论：**进程是可丢弃的，状态在文件里**。这是"文件系统即数据库"主张的硬证据。

---

## 6. 双环认知：Cortex（前台）+ Subconscious（潜意识）

### 6.1 前台（Cortex）
响应实时通道消息。会话跨重启持久化并精确恢复历史。每个对话通道、后台任务会话、潜意识分区各是一个 **session actor**，由租约锁（lease lock）强制生命周期与并发边界。

### 6.2 后台（Subconscious）
按节奏（cadence，本机默认 **每 37 分钟**一次心跳）运行，**与前台是否活跃无关**。它做的是"不该需要刻意思考的事"：记忆巩固、自我健康监控、维护队列处理，并维护一个**自动注入到未来每个会话上下文的知识广播板**。

潜意识的组织（来自 `subconscious/CLAUDE.md`）：

```text
subconscious/
├── CLAUDE.md          # 潜意识总览
├── inbox/             # 待拾取的 .pending / .json 通知
├── playlist.md        # round-robin 调度表（谁下一个跑）
└── <partition>/
    └── CLAUDE.md      # 该分区的目的 + YAML frontmatter(schedule/contract)
```

**调度模型**："每个 tick 唤醒潜意识的一块，做完工作就回去睡——无状态，除了写进文件的东西，不记得上次。" `playlist.md` 是 round-robin，每 tick 取下一个未勾选项，一轮跑完就用所有 enabled 分区重建。

### 6.3 本机加载的 4 个分区（实测 `daemon config`）

| 分区 | cooldown | timeout | 职责（合约） |
|------|----------|---------|--------------|
| `cadence-executor` | 1 tick | 10min | 执行节奏/cron 投递 |
| `memory-committer` | 3 ticks | 30min | 提交记忆 |
| `memory-weaver` | 5 ticks | 35min | 记忆编织：`entity-converge.v1`、`merge.v1`、`orphan-islands.v1`、`orphan-newborn.v1`、`scan-gap.v1`、`sink.v1` |
| `pattern-tracker` | 7 ticks | 15min | 模式追踪：`node-converge.v1`、`orphan-newborn.v1`、`revise.v1` |

`memory-weaver` 内部还通过 `.claude/agents/*.md` 定义子 Agent（`spine-scanner`、`entity-crystallizer`、`intuition-updater`），由 Claude SDK 自动加载并暴露给 `Agent` 工具——形成"分区协调器 → 专职子 Agent"的两级结构。

---

## 7. 自编程认知拓扑（第 5 项创新的机理）

分区行为由文件定义，且**分区可以改写自身**。`subconscious/CLAUDE.md` 明确划定了自编程的边界：

**允许自改：**
- 自己分区的 `CLAUDE.md`（精炼工作方式）
- 新建分区目录（生长新能力）
- `playlist.md`（调整节奏）
- `memory/CLAUDE.md`（塑造全局"直觉层"——写进这里的东西成为所有会话思考方式的一部分）
- `subconscious/inbox/`（给其他分区留便条）

**禁止触碰：**
- Spine 事件数据（"不可更改的历史"）
- 锁文件（属于运行时）
- 其他分区的 `CLAUDE.md`（须经 inbox 协调，不可直接改）
- 任何分区的 `contract:` frontmatter（机器读取的消费者声明，由运行时拥有、从上游刷新）

> 设计哲学：**运行时只发一份脚手架，长期行为越来越多由 Agent 自己撰写**，系统随时间自我扩展。内核 `~/aladuo` 受 git 管理，每次自改前 git 提交即"回滚点"。

> ⚠️ 版本耦合风险：`npm install` 升级**不会覆盖**已存在内核的分区提示词（只合并缺失文件，刻意保留 Agent 自编程与本地改动）。因此升级 duoduo 后，分区提示词需按目标 tag **显式刷新**（见 `duoduo-runtime-admin` 技能的 subconscious-refresh 流程），否则旧分区会误解析新版 lint 信号。

---

## 8. 模型运行时：Claude 与 Codex 互为对等

- duoduo 内嵌 **Anthropic Claude Code SDK**，并把原生平台二进制作为 npm 可选依赖随包安装。
- 自 v0.5.3 起，**Claude 与 Codex 是对等运行时**；daemon 启动时探测两者，按可用情况适配。
- **Claude 是保守的默认回退**：除非 actor 显式声明 `runtime: codex`（在 descriptor / job frontmatter / 分区 frontmatter 中），或设置 `ALADUO_DEFAULT_RUNTIME=codex`，否则一律落到 Claude。
- 三种认证来源（onboard 时三选一）：
  - `claude_code_local`——本机已 `claude login`（**本次部署采用**）
  - `anthropic_api_key`——设置 `ANTHROPIC_API_KEY`
  - `compatible_endpoint`——OpenAI 兼容端点（sglang、vLLM 等），需 `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`
- Claude 侧用**单一进程内适配器**：streaming 通道会话、任务、潜意识分区共享一个 in-process adapter，**不像 Codex 每回合 spawn 外部 CLI**。
- 逃生舱：`CLAUDE_CODE_EXECUTABLE` 可指向非 SDK 的本地 `claude` 二进制（当可选原生二进制没装上时）。

---

## 9. 通道（Channel）插件体系

通道把 duoduo 连接到外部消息平台，以 npm 包形式安装：

```bash
duoduo channel install @openduo/channel-feishu
duoduo channel feishu start
```

- 当前官方可用：`@openduo/channel-feishu`（飞书 / Lark）。
- 配置走两级：`kernel/config/<kind>.md`（种类级默认）→ `var/channels/<id>/descriptor.md`（实例级覆盖）。
- 通道安装器只接受 **npm 包名**（无 flag）或**本地 `.tgz` 包**（须 `--from-path`），**不能**把裸 git 仓库当通道装。
- 包结构：`@openduo/duoduo`（核心运行时+CLI）、`@openduo/channel-feishu`（飞书适配器）、`@openduo/protocol`（零依赖共享 RPC 类型）。

---

## 10. 可观测性：ATC 监控面板 + RPC API（实测）

### 10.1 Dashboard
- 地址 `http://localhost:20233/dashboard`（本次实测 **HTTP 200**）。
- **单文件、零依赖** HTML，由 daemon 直接服务，无构建步骤、无额外端口、无框架。
- 三大区：**Header**（累计成本/token/工具调用数/健康灯）、**Signal Bar**（每个活跃实体的形状+颜色状态：● 前台会话 / ■ cron 任务 / ◆ 一次性任务 / ✓· 潜意识分区）、**Event Stream**（实时 Spine WAL 事件，富渲染 + 可展开 JSON）。

### 10.2 RPC 接口
Dashboard 通过 **`POST /rpc`（JSON-RPC 2.0）** 与 daemon 通信。实测可用方法包括：

| 方法 | 用途 | 实测结果 |
|------|------|----------|
| `spine.tail` | 拉取最近 WAL 事件 | 返回本会话 3 条事件 |
| `usage.get` | 成本/token 账本 | 返回 drain/cost/token 明细 |
| `job.list` | 任务列表 | （dashboard 使用） |
| `document.get` | 文档读取 | （dashboard 使用） |

> 注意：没有 REST 风格的 `/api/events`（实测 404）。Dashboard 另有 `127.0.0.1:20234/save` 用于本地保存类操作。

### 10.3 CLI 诊断命令
`duoduo daemon status|config|logs`、`duoduo session list|alias|notify|compact|archive`、`duoduo channel ... status|logs|doctor`、`duoduo memory check|...`、`duoduo prompts`。

---

## 11. 技能（Skills）体系

仓库以 [skills.sh](https://skills.sh/) 安装器形式发布 host 模式运维技能（供任意 Agent 使用，**不依赖** `$skill-name` 之类的 agent 专有语法，用自然语言触发）：

| 技能 | 范围 |
|------|------|
| `duoduo-admin` | host 模式总入口：解释机理、查看配置、升级（含 v0.5 跨大版本 playbook）、归档/恢复会话 |
| `duoduo-runtime-admin` | daemon 级设置/诊断、Claude/Codex 运行时、日志/遥测/节奏、潜意识刷新、usage 账本维护、`duoduo session` 跨会话编排 |
| `duoduo-channel-admin` | 通道安装/生命周期、飞书设置、通道提示词/workspace |
| `duoduo-pipeline` | 流水线类工作 |
| `duoduo-loop` | 循环/重复任务（命名提示词注册表） |

---

## 12. 本次部署记录（可复现）

**环境**：Linux x86_64，无 node/npm（自行安装），Docker 可用，无 passwordless sudo。

```bash
# 1) 安装 Node 22 LTS 到用户目录（无 sudo）
curl -fsSL -o node.tar.xz https://nodejs.org/dist/v22.17.0/node-v22.17.0-linux-x64.tar.xz
tar -xf node.tar.xz -C ~/.local
export PATH="$HOME/.local/node-v22.17.0-linux-x64/bin:$PATH"   # 已写入 ~/.bashrc

# 2) 安装 duoduo 运行时（250 包，~34s）
npm install -g @openduo/duoduo            # → v0.5.8

# 3) 非交互式 onboard（host 模式 + 本机 Claude Code 认证）
export DUODUO_NODE_BIN="$HOME/.local/node-v22.17.0-linux-x64/bin/node"
export ALADUO_RUNTIME_MODE=host
export ALADUO_CLAUDE_AUTH_SOURCE=claude_code_local   # 依赖本机已 claude login
export DUODUO_ONBOARD_YES=1
duoduo onboard

# 4) 持久化关键 env（保证重启后仍生效）
#    ~/.config/duoduo/.env:
#      DUODUO_NODE_BIN=/home/.../node
#      ALADUO_CLAUDE_AUTH_SOURCE=claude_code_local

# 5) 启动并验证
duoduo daemon start          # → healthy, pid, runtime_mode=host, v0.5.8
duoduo daemon status         # → 4 个潜意识分区已加载
curl -s http://localhost:20233/dashboard   # → HTTP 200
printf 'Reply ...\n' | duoduo chat         # → 模型正确回复（端到端通路）
```

**两个部署要点（坑）**：
1. **无交互 TTY** → 必须用 `duoduo onboard` + 环境变量（`ALADUO_RUNTIME_MODE`、`ALADUO_CLAUDE_AUTH_SOURCE`、`DUODUO_ONBOARD_YES=1`），缺失时 onboard 以 code 2 退出并打印完整 env 配方。
2. **daemon 是分离后台进程，且 PATH 可能被重置** → 用 `DUODUO_NODE_BIN` 指向 node 绝对路径，并把认证来源写进 `~/.config/duoduo/.env`，否则重启后丢配置。

**验证清单（全部 ✅）**：

| 验证项 | 结果 |
|--------|------|
| daemon 健康 | ✅ `healthy: yes`，v0.5.8，host 模式 |
| 端到端对话 | ✅ stdio 发消息→模型正确回复 `DUODUO_OK_42` |
| WAL 事件溯源 | ✅ `channel.attached→channel.message→agent.result` 落盘 |
| Dashboard | ✅ `http://localhost:20233/dashboard` HTTP 200 |
| RPC API | ✅ `spine.tail`/`usage.get` 正常返回 |
| 成本账本 | ✅ usage.get 记录 cost/token |
| 崩溃恢复/重启 | ✅ 重启后 runtime_id 不变、会话与 WAL 从文件重建 |
| 潜意识分区 | ✅ 4 分区加载，cadence 心跳 every 37min |

---

## 13. 架构评价：取舍与亮点

**亮点**
1. **正确的持久化边界**：把"模型擅长的"（推理/编排/规划）全交给 SDK，运行时只守"模型守不住的"（持久化、生命周期、调度、并发）。模型升级即系统升级，无需改代码。
2. **WAL-before-execute** 一个排序换三个属性：可重放、可审计、确定性崩溃恢复——实测重启后状态无损，是真功夫。
3. **双环认知**让 Agent 在"没人说话时"也能巩固记忆、自我维护，把广播板自动注入未来上下文——这是把"长期记忆"工程化的务实做法。
4. **自编程拓扑 + git 内核**：分区可改自身、内核 git 化即回滚点，在"可演化"与"可控"之间取得平衡（用 `contract:` 不可改、其他分区须经 inbox 协调来设防）。
5. **零依赖单文件 Dashboard + JSON-RPC**：运维可观测性开箱即用，无构建链。

**取舍 / 注意点**
- **闭源 + minified 发布**：对人类不可读，调试/审计严重依赖官方 issue 流程和运行时可观测面。把"代码给 Agent 读"作为产品立场，是激进但自洽的赌注。
- **后台持续消耗 token**：潜意识即使无人对话也按 cadence 烧钱（onboard 明确告警）。生产部署需关注成本，可调 `ALADUO_CADENCE_INTERVAL_MS`。
- **升级有版本耦合**：分区提示词不随 npm 升级自动更新，需显式刷新，否则 lint 信号会被旧分区误解析。
- **usage 账本无自动保留**：长驻主机会累积数百 MB，需手动归档。

---

## 附录 A：关键路径与命令速查

| 项 | 值 |
|----|----|
| 内核目录 kernel_dir | `~/aladuo`（git 管理） |
| 运行时目录 runtime_dir | `~/.aladuo`（`var/` 事件溯源数据） |
| 持久化 env | `~/.config/duoduo/.env` |
| onboard 选择 | `~/.config/duoduo/config.json` |
| Dashboard | `http://localhost:20233/dashboard` |
| RPC | `POST http://localhost:20233/rpc`（JSON-RPC 2.0） |
| 默认端口 | 20233（daemon），20234（dashboard save-api） |
| 默认 cadence | 37 min |
| 升级 | `npm i -g @openduo/duoduo@latest && duoduo daemon restart` |

## 附录 B：WAL 事件结构（实测）

每条事件含字段：`type, source, session_key, payload, routing_hint?, id, ts`。
按天分片存于 `~/.aladuo/var/events/YYYY-MM-DD.jsonl`（单文件 10-30MB，潜意识守则规定**只能用 shell `grep`/`tail` 读，禁用 Read/Grep 工具**）。
