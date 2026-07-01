# duoduo Agent 内部框架与运行逻辑

## 一句话结论

**duoduo 是一个"薄运行时 + 基础模型"的自治 agent：运行时只握模型握不住的那部分可确定骨架——以文件事件日志为唯一真理之源的持久化、一 key 一 actor 的生命周期与并发、以及"是否动用模型 / 改不改内容"的边界闸门——把一切推理与裁决诚实地委派给模型。正是这条"代码守骨架、模型做裁决"的边界，让它在单进程内同时做到低延迟前台、崩溃可重放、后台自治。**

这句话贯穿全文八个子系统。它可以拆成四条并列的支撑论点（本文的四个部分）：

| 部分 | 关键句（运行时在哪一面守骨架） | 子系统 |
|------|------------------------------|--------|
| **一 · 前台交互** | **一次前台交互 = 可确定的上下文装配 + 单一长驻会话的受控执行。** 运行时决定"拼什么上下文、何时发一次 query、如何合并/steering/抢占"，模型只在这段上下文上推理。 | §1 认知装配 · §2 Turn/Drain |
| **二 · 会话编排** | **会话是被编排与路由的有状态对象。** 用"一 key 一 actor + 两层锁 + 双有界可让出池"把一外部身份扩成多内部会话，并在 claude/codex 两值枚举上把每个会话诚实路由到对应后端。 | §3 Session Actor · §8 运行时抽象 |
| **三 · 可信之源** | **可信来自一条铁律：先落日志，再执行 / 入队。** Spine 的 append-before-execute 把所有状态变成可从"日志 + 指针"精确重建的派生视图；Gateway 的 WAL-before-enqueue 把入站边界做成"既可重放、又决定是否动用模型"的闸门。 | §4 Spine · §5 Gateway |
| **四 · 后台自治** | **无人对话时，运行时靠心跳自我维护而绝不越权。** 潜意识引擎经活动门节流后唤起无状态一次性 LLM 分区会话做维护，记忆系统只做只读测量与软删 GC，一切内容改写交回模型；机器真正强制的只剩契约门。 | §6 Subconscious · §7 记忆系统 |

> 阅读建议：先读 **§0 端到端流程**（把四条论点拍成一条时间线），再按 Part I→IV 顺序读。每节都是"结论先行"——开头一句是该子系统的领起结论，其后才是代码/运行时证据。

---

## 材料与方法

duoduo 故意以 minified JS 发布（作者立场："代码是给 agent 读的，压缩只为省带宽"）。本文用三种方法交叉取证并经对抗验证，逆向其真实实现：

1. **静态代码 + 调用链追踪**：用 esbuild 反混淆 + js-beautify 把 `dist/release/{daemon,cli,stdio}.js` 展开为可读代码（daemon 7.9 万行）。字符串字面量（事件名/RPC 方法/env/日志）在 minify 后完整保留，是证据锚；关键机制**沿真实函数调用链追踪**（跟进被调用的下游函数确认控制流真的这样串联），而非仅凭单个字符串推断。
2. **可读提示词**：`bootstrap/` 下 `meta-prompt.md`（agent 身份/记忆纪律的"宪法"）、`config/*.md`、`subconscious/**` 定义 agent 认知，本身人类可读。
3. **活体运行时调用链**：本机运行的 daemon，用 `duoduo` CLI + `/rpc`（`spine.tail` 事件序列 / `usage.get` drain record / `daemon status`）印证动态行为——动态证据优先于静态推断。

**可信度纪律**：8 个子系统各由独立 agent 逆向，再由对抗验证器沿调用链逐条证伪；每条机制主张标注 `file:line` / 字面量 / RPC / CLI 供复核，置信分 `confirmed` / `未证实推测`。所有行号指反混淆后的 `daemon.pretty.js`（除非另注 `cli`/`stdio`）。凡未证实的推断均显式标注。


---

## §0 端到端：一个消息如何穿过整个 agent 大脑

**这张图就是"一句话结论"的时间展开**：它把四条论点——先落日志再执行（Part III）、稳定认知进 system·易变状态进 user（Part I）、会话被 actor 持有并驱动（Part II）、经验回流成直觉层（Part IV）——拍成一条从入站到产出的时间线。行尾的 `[→Part]` 是通往各部分的导航锚点。

```
外部输入 (channel.message)                                    [→Part III §5 Gateway 入站边界]
   │
   ▼  ① 封装为不可变事件  Xt()  → id=evt_<uuid>, ts=ISO      [30948/30940]  [→§4]
   │
   ▼  ② 去重前置  YX() 算 key                                [75651]        [→§4]
   │      命中重复 → 取回既有事件 + 重放上次 gateway 回执 → deduplicated:true，不 append
   │
   ▼  ③ APPEND-BEFORE-EXECUTE：Qt() 原子写 WAL 分区           [30992/76089]  [→Part III §4 铁律]
   │      var/events/YYYY-MM-DD.jsonl (UTC)，记 byte_offset/byte_len
   │      → 写 by_id 索引 → 写 by_session 索引
   │
   ▼  ④ ma() 推进 gateway 消费者 watermark                    [31852]
   │      run/queue_offsets/gateway.json  (经 by_id 反查偏移)
   │
   ▼  ⑤ ha() 更新 status.json
   │
   ▼  ⑥ 按 routing_hint.target 入队                           [75878]        [→Part III §5 分流]
   │      gateway → 同步处理不入队
   │      meta    → 写 meta:subconscious mailbox 指针                        [→Part IV §6]
   │      session → 向 session_key mailbox append '- [ ] @evt(<id>)'   [76123]
   │
   ▼  ⑦ bus.emit('spine.event', r) → session.wake                [76134]     [→Part II §3 actor 唤醒]
   │
   ▼  ⑧ runner 读 mailbox 的 @evt 指针 → nl() 经 by_id seek WAL 取正文  [31024]
   │
   ▼  ⑨ 装配上下文（两个正交注入面）                                          [→Part I §1 认知装配]
   │      system-prompt 面：WT() 6 层叠装（身份→通道→实例→广播板→Runtime Context→job）  [57186]
   │      user-message 面：fde() 瞬态块（time/skip/gateway/interrupted/job-tick→user-input）  [61156]
   │
   ▼  ⑩ drain 合批 → createAgentSdkAdapter → SDK query()      [57297/57054]  [→Part I §2 Turn/Drain]
   │                                                          （后端 claude/codex 路由 [→Part II §8]）
   │
   ▼  ⑪ agent 产出 → append agent.tool_use / tool_result / result 回 WAL
   │      更新 session state.json：last_event_id / last_event_at / sdk_session_id   [60582]
   │
   ▼  ⑫ 经验沉淀：日志 → 潜意识 cadence tick(≈37min) → memory-weaver 三段流水线   [→Part IV §6§7]
          → 回写 memory/CLAUDE.md 广播板 → 下一次前台会话经 WT 再注入
```

**闭环**：经验 → 事件日志 → 潜意识加工 → 广播板 → 系统提示 → 新的经验。这正是关键句 4（后台自治）与关键句 1（认知装配）合起来的闭环——后台把经验压成直觉层，前台每个新会话经 `WT` 自动加载。


---

# 第一部分 · 前台交互：上下文装配 + 单一长驻会话的受控执行

> **关键句**：一次前台交互 = 可确定的上下文装配（§1）+ 单一长驻会话的受控执行（§2）。运行时决定拼什么、何时发一次 query、如何合并与 steering，模型只在这段上下文上推理。


---

## §1 认知装配

**认知装配的本质是一次正交切分：把 agent 上下文拆成"稳定认知"与"易变具身状态"两个注入面——稳定的（身份/人格/直觉广播板）由 `WT` 一次装进 system-prompt 前缀以吃满 prompt caching，易变的（时间流逝/中断/job tick/带外动作）由 `fde` 每 turn 瞬态塞进 user 消息；且 Claude 与 Codex 共用 `WT` 这一套装配器（Codex 只多套一层 `<aladuo:system-context>` 壳），并非两套并行封装。**

这套切分之所以值得单独成节，是因为它同时优化了两个互相冲突的目标：既要让前缀足够稳定以命中 prompt cache，又要让 agent 感知到它本无的具身信号（时间、被打断、后台节拍）。运行时把这两类内容路由到两个物理位置，从根上避免了"易变状态污染缓存前缀"。下面四个论点自上而下展开：稳定面怎么装（论点一）、易变面怎么装（论点二）、两条后端为何同源（论点三）、以及不走 WT 的两条旁路（论点四）。

| 注入面 | 频率 | 装载内容 | 载体 | 缓存友好性 |
|---|---|---|---|---|
| **System-prompt 面** | 每会话/每 turn 重算 | 身份、通道人格、实例特化、直觉广播板、运行上下文、job mission | `WT` 输出的前缀 | 前缀稳定，利于 prompt caching |
| **User-message 面** | 每 turn 瞬态 | 流逝时间、被打断、job tick、gateway 侧信道结果 | `fde` 输出的 text blocks | 每 turn 变，不入前缀 |

---

### 论点一：稳定认知由 `WT` 六层一次装进 system-prompt 前缀

**所以呢**：agent 的"我是谁 / 我这个通道该有什么人格 / 我此刻记住了哪些跨会话启发式"这类稳定信息，全部在一处（`WT`）按固定层序拼成一个前缀。层序固定 + 内容稳定，才能让同一 agent 的连续 turn 反复命中同一缓存前缀。

**六层装配顺序**（confirmed）。`WT(e,t,n,r)`（导出 `buildSystemPromptForChannelConfig`，`daemon.pretty.js:57186`）按固定顺序 `[i,o,s,c,a,u].filter(Boolean).join("\n\n")` 拼接，两处 `join` 分别在 `57208`（override 分支）与 `57212`（append 分支）：

| 层 | 变量 | 来源 | 位置 | 说明 |
|---|---|---|---|---|
| 1 身份 | `i` | `b_()` 读 `ALADUO_META_PROMPT_PATH` 或 `ALADUO_BOOTSTRAP_DIR/meta-prompt.md` | `57187`（`b_` 定义 `57168`） | 不变 identity；活体 meta-prompt.md=14126 bytes |
| 2 通道 | `o` | `e.kind_prompt` | `57188` | 通道级人格 |
| 3 实例 | `s` | `e.instance_prompt` | `57189` | 实例特化（覆盖类型级） |
| 4 广播板 | `c` | `r.content`（memoryBoard），仅当 `r && r.content.trim().length>0` | `57196` | 直觉层，见下 |
| 5 运行上下文 | `a` | `## Runtime Context`（仅注入 `session_key`/`channel_kind`），仅当 `t` 存在 | `57190` | 相对稳定，**不含时间戳** |
| 6 任务 | `u` | `tle(n)` 生成 `## Job Mission`，仅当有 jobContext | `57207`（`tle` 定义 `57180`） | stateless 变体额外强调"上文无历史，靠文件持久化"（`57181`） |

- 第 4 层的 `if(r && r.content.trim().length>0)` 是布尔短路：`r` 为 undefined（无 memoryBoard）时不解引用、不抛错（confirmed）。
- `b_()`（`57168`）依次探 `ALADUO_META_PROMPT_PATH`、`ALADUO_BOOTSTRAP_DIR/meta-prompt.md`，取首个非空 trim（confirmed）。

**prompt_mode 分叉**（confirmed）。`57208`：`override` → 返回纯字符串 `||""`，整体替换 Claude Code 预设；默认 `append`（`57217`）→ 返回 `{type:"preset", preset:"claude_code", append:l}`，`l` 为空（`57216` `||void 0`）则返回 `undefined`（即无 append）。

**数据源订正**（confirmed）。调用链 `EU`（`59953`）在 `59982` 调 `WT(g, t, {content,jobId,cron,stateless}, n.memoryBoard)`。**Claude 的 kind/instance/prompt_mode/time_gap 全部来自 `g`（effective_config，`59962` 经 `$i("effective_config_ms",…z1)` 取得并缓存），不是来自 `QXe`**（`QXe` 的用途见论点四）。此外 `WT` 被调两次：批处理/admission 路径 `59982` 与 live streaming 路径 `60718`，同一装配复用于两种进场方式。

**广播板包装：OVERRIDE 前缀 + dossier 纪律**（confirmed）。第 4 层的 memoryBoard 整段被常量包装（`57199–57205`）：

```js
c = V9e.test(d)
  ? `${Jue}\n\n${d}\n\n${H9e}`   // 含 [[slug]]
  : `${Jue}\n\n${d}`;            // 不含
// V9e = /\[\[[^\]]+\]\]/                                   （57709）
// Jue = "…IMPORTANT: These instructions OVERRIDE any default behavior…你 MUST 精确遵守"  （57708）
// H9e = "The [[slug]] links…are dossier entry points, not footnotes…"  （57709）
```

即广播板整段以 OVERRIDE 前缀 `Jue` 包装；含 wiki-link 时追加 dossier 纪律 `H9e`（"[[slug]] 是深档入口，触发时先读再行动"）。**注意：此 `Jue` 包装对 Claude 与 Codex 同源同文**——因为 Codex 复用的正是 `WT` 的整段输出（详见论点三），此处原文档"仅 Claude 用 `Jue`"的断言 refuted。

**广播板来源：`@include` transclusion**（confirmed）。`Ype(memoryBroadcastPath)`（`71601`）→ `Xpe`（`71617`）递归解析 `memory/CLAUDE.md`：用 `@path` 前缀语法（正则 `Zpe=/(?:^|\s)@((?:[^\s\\]|\\ )+)/g`，`71750`）提取 include，按深度上限 `CXe=5`（`71618` `if(n>=CXe)return[]`）递归内联，扩展名白名单 `AXe`（实测约 120 个扩展名）。每个被 transclude 的文件头是 `Contents of ${path} (project instructions, checked into the codebase):`（`DXe:71609` + 后缀常量 `NXe:71750`），非裸冒号。

- **去环细节订正**（confirmed）：visited 集主检的是 `t.has(o)`，其中 `o=Wpe(i)` 是 resolve+win32 小写后的路径（`71621`），**不是 realpath**；realpath 由 `LXe`（`71652`）另行求得后在 `71626` 以 `t.add(o), t.add(Wpe(a))` 额外加入 visited 兜住软链别名。即"resolve 主检 + realpath 补检"，原文档"realpath 去重防环"表述略含糊。

**活体冷启动印证**（confirmed）。本机 `~/aladuo/memory/CLAUDE.md` 为 0 字节 → `X.memoryBoard` 为空 → `73374` 不构造 memoryBoard → `WT` 不注入第 4 层。这印证机制本身：广播板初始为空，由潜意识逐步写入 durable heuristics 后才在下一次会话被注入——**渐进式冷启动，而非硬编码知识**。

---

### 论点二：易变具身状态由 `fde` 每 turn 瞬态塞进 user 消息

**所以呢**：时间流逝、被打断、job 节拍、带外动作结果这些"每 turn 都可能变"的信号，若进 system prompt 会不断击穿缓存前缀。运行时把它们做成带 tag 的 text block，前置到用户输入之前、进 **user 消息而非 system prompt**，既让 agent 感知具身状态，又不污染缓存前缀。

**块顺序**（confirmed）。`fde(e,t,n)`（`61156`）返回 `blocks[]`，push 顺序逐条对上：

```
daemon-restart-hint        （61181）
  → gateway-notice          （61185；包 <system-reminder>，尾附
                              "this context may or may not be relevant…
                               should not respond unless highly relevant" 61194）
  → time-context            （61200；<time-context last_interaction=… current_time=…>）
  → skip-rewind             （61206；仅 isUserMessage!==false 时）
  → interrupted-context     （61212）
  → job-tick                （61219；run_number/triggered_at）
  → user-input              （61223）
```

**slash 命令短路**（confirmed）。若用户输入 `e.trimStart().startsWith("/")`（`61165`），跳过全部注入只发 user-input 原文——命令式输入不该被时间/中断噪声污染。

**time-gap 阈值的读取位置订正**（confirmed）。time-gap 阈值确实来自 effective config 的 `time_gap_minutes`，但**不在 `fde` 内读取**：`EU:59965` 先算 `b=(g?.time_gap_minutes ?? lde)*60*1e3`（`lde=60` 分钟，定义在 `61969`）构造出 timeGap 对象再传入 `fde`，`fde` 只消费 `t.timeGap`。

---

### 论点三：Claude 与 Codex 共用 `WT`，Codex 只多一层 `<aladuo:system-context>` 壳

**所以呢**：这是本节相对原文档的最大修正。原文档描述"两套并行封装器 + 共享上游 `QXe` 内容"，并据此报告了"双重 `Contents of` 头嵌套""Codex developerInstructions 携带时间戳"两处漂移。沿真实调用链核验，**这两处漂移在 v0.5.8 运行时都不发生**：Codex 的系统提示就是 `WT` 那一整串（含 identity/kind/instance/广播板/`Jue`/runtime/job），二者差异只剩最外层那层壳。这条修正直接决定了本节领起结论能否成立。

**为何 `sle`/`ale` 的封装分支不可达**（confirmed，静态调用链）：
- `sle`/`ale` 全仓仅在 `57951/57952`（`S_.run` 内）被调用，用的是闭包 `t`（`S_(e,t)` 的第 2 参 = instructions）。
- 但两处 `S_` 构造都**只传一个 config 参、不传 instructions**：`73346` `y.codexAdapter=c({sandbox,ephemeral,model,dynamicTools})`（`c=S_`）、潜意识路径 `74666` 同样 `S_({sandbox,ephemeral,dynamicTools})`。故运行时 `t===undefined`。
- 于是 `sle(t??{},d)` = `sle({},d)`：`e.identity/kindPrompt/instancePrompt/memoryBoard` 全 undefined，`57852/57856/57861` 三个分支全不触发——`Contents of …(intuition layer…)` 措辞（`57861`）是**当前路径不可达的死代码**。`ale({})`：`e.sessionKey/channelKind/runtimeDirectives` 全空 → `t.length===0` → 返回 undefined，`developerInstructions` 根本不产生，`- timestamp:`（`57873`）**不注入**。

**Codex 实际拿到什么**（confirmed）。`d=ole(c.systemPrompt)`（`57950/57846`）= 把 `WT` 的 preset `{append}` 抽成字符串。`ole`（`57846`）正是 `WT`→Codex 的桥，让 Codex 复用 `WT` 输出这条链闭合。所以 Codex 的 baseInstructions = `<aladuo:system-context>… ## Runner System Prompt\n\n{WT 整段}…</aladuo:system-context>`。

| | Claude | Codex |
|---|---|---|
| 稳定认知来源 | `WT` 输出 | **同一份 `WT` 输出**（经 `ole` 抽字符串） |
| system 载体 | `{type:"preset", preset:"claude_code", append}` | `baseInstructions`，内嵌 `## Runner System Prompt` + WT 整段 |
| 外层壳 | 无（纯拼接） | `<aladuo:system-context>` |
| 广播板 / `Jue` | 有 | **有（同源同文）** |
| 时间戳 | 仅在 user 面（`fde` time-context） | **无**（`ale` 返回 undefined，反而缓存友好） |

**结论**：Codex 的 identity/kind/instance/广播板/`Jue`/runtime/job 与 Claude 完全同源同文，二者差异只剩最外层 `<aladuo:system-context>` 这层壳。原文档"验证发现两处漂移"两条均 refuted——反而 Codex 系统提示没有时间戳、比 Claude 更缓存友好，与原文档担忧相反。

**适配器选择**（confirmed）。`xe(y)`（`72813`）决定路径：codex→`y.codexAdapter`（走上述 `S_`），channel-claude→streaming 包装，其余→裸 `Xc`。

**SDK 适配器兜底**（confirmed）。`Xc`（`createAgentSdkAdapter`，`57297`）仅当 `t.systemPrompt===void 0`（`57305` else 分支）走兜底：`p=[b_(), APPEND_SYSTEM_PROMPT].filter(...)`（`57309`）；`c&&p`→拼接（`57314`）、`c`→整体替换（`57316`）、`p`→append preset（`57316–57320`）。即便未设 `APPEND_SYSTEM_PROMPT`，只要 `b_()` 非空 `p` 就非空并 append meta-prompt（`b_()` 返回 undefined 则 `p` 空、无 append）。permissionMode（`57304`）= `t.permissionMode ?? ALADUO_PERMISSION_MODE ?? (host?bypassPermissions:void 0)`。**注意这是降级分支**：正常 drain 里 `systemPrompt` 由 `WT` 提供，此兜底不进，仅在"上游没给 systemPrompt"时生效。

---

### 论点四：不走 `WT` 的两条旁路——潜意识分区注入与指纹漂移信号

**所以呢**：`WT` 装配的是前台会话的稳定认知。系统还有两处独立于 `WT` 的上下文机制：潜意识分区会话用另一套注入器（它没有前台对话历史，需要绝对路径 + 收件箱），以及 `QXe` 产出的 instructions 指纹（它不进任何提示词，只驱动 resumed session 失效）。厘清这两条旁路，才能解释"为何 `QXe` 要重算 identity/kind/instance 却不用于提示词"。

**潜意识分区注入**（confirmed）。partition（`meta:subconscious`）不走 `WT`：
- `gQe`（`74644`）：首行 `## Runtime Context`（`74645`）+ Timestamp + Sessions + `### Key Paths`（含 `memoryBroadcastPath` 等全绝对路径，`74647`）。
- `yQe`（`74651`）：`## Inbox` + "After processing each item, delete the corresponding file … to ack it."（`74655`）——每条 `.pending` 文件，处理后删文件 ack。
- 另有 **Session Mailbox 旁路** `XS`（`31688`）：`["# Session Mailbox","","## Inbox",""]`（`31689`）写盘供 agent 主动 Read，不进 system prompt——属"working notes"层。

**`QXe` 的真正用途：instructions 指纹 / 漂移失效**（confirmed）。`QXe`（`72000`）确实存在且在 `73127` 被 `l2` 调用，但它**不进任一路的实际提示词**（Claude 用 `b_()`+effective_config，Codex 用 `WT` 输出）。它的实际用途有二：
1. 产出 `memoryBoard`（`72004` `Ype…rendered.trim()`）供 `WT` 两路复用；
2. 供 `l2`（`73127`）算 instructions 指纹做漂移检测——指纹 = `JSON.stringify([identity,kindPrompt,instancePrompt,memoryBoard,mission])`（`71884`）；漂移则在 `73135`（`gate2Fired && runtime==="claude"`）发 `session.streaming_invalidated`（reason `"instructions_drift"`）。

即 `QXe` 的 identity/kindPrompt/instancePrompt 只进指纹、不进提示词——它是驱动 resumed session 失效的独立信号面。此外 `Qle`（`59948`）/ `autoloadAdditionalDirectoryClaudeMd`（`60747/73347`）门控 memoryBoard 与 additionalDirectories 的 CLAUDE.md 自动加载，是广播板之外第二条"文件即上下文"注入。

---

> **给 Agent PM 的洞察**
> - **双注入面是本框架最可复用的单点设计**：稳定认知放 system prompt（每会话装一次、利于缓存前缀命中），易变运行时状态放 user 消息瞬态注入。既保护缓存前缀，又让 agent 感知"时间流逝""被中断"等它本无的具身信号。这正是本节领起结论的核心——两个注入面的正交切分。
> - **"共用装配器 + 薄外壳"胜过"两套并行封装"**：核验推翻了原以为的"Claude/Codex 各写一套装配器"。真相是两路共用 `WT`，Codex 只多套一层 `<aladuo:system-context>` 壳（`ole` 桥接）。多模型后端 agent 应把"装配面共用、执行面才分叉"作为纪律，避免各写一遍导致措辞漂移（本次核验中原以为的"双 `Contents of` 头""Codex 时间戳"两处漂移，实为不可达死代码，根本不发生）。装配同、执行异——执行/命令面的后端分叉见 §8。
> - **广播板 = 潜意识→意识的单一通道**：后台把跨会话 durable 启发式压成"一行一指针"的直觉层，前台每个新会话经 `WT` 第 4 层自动加载。`[[slug]]` 指针 + `H9e` 纪律实现"默认不展开、触发才读 dossier"，控制上下文膨胀。全新安装板为空即无注入——渐进式冷启动。
> - **`override` vs `append` 是干净的能力边界开关**：默认 append 复用 Claude Code 内置提示（工具/安全/格式），override 让通道完全自定义人格。三层 prompt（identity/kind/instance）+ override = "共享内核 + 通道特化 + 实例特化"清晰叠加。
> - **指纹与提示词解耦**：`QXe` 重算 identity/kind/instance 却只喂指纹、不喂提示词，用漂移信号（`instructions_drift`）独立驱动 resumed session 失效——把"内容是否变了"的检测与"内容如何装配"彻底分离，值得任何做 session resume 的运行时借鉴。
> - **gateway-notice 机制**：把模型上下文外执行的带外动作，作为 `<system-reminder>` 告知"已生效、勿重复"，解决了"带外副作用与模型认知不同步"的经典问题，任何有旁路控制面的 agent 都该借鉴。


---

## §2 Turn/Drain 循环与 SDK

Turn/Drain 把离散用户消息重写为"带合并窗口的邮箱批 + 单一长驻流式 SDK 会话"：一次 drain 只在可合并谓词允许的**前导窗口**上发一次 query，靠 **accepted 门控、PostToolUse additionalContext 注入、三态抢占边界、hold-stdin** 四条控制线，在不重开对话的前提下实现 turn 合并、mid-turn steering、后台 subagent 续跑与优雅抢占。下面四个论点自上而下拆解这句话：先是"离散消息如何被循环切成批"，再是"一个批如何变成一次 SDK query"，然后是"长驻会话上四条控制线如何不重开对话地改写正在跑的 turn"，最后是"失败如何收敛"。

### 论点一：循环层是 `Tt`，不是 `cde`——一次 drain 只吃"一个前导可合并窗口"

**所以呢**：理解"多条消息为什么被分多次 turn 消费"的关键，是把"循环"与"单批处理器"分层。`cde` 不是 drain 循环，它是每次迭代被调用一次的**单批处理器**；真正的循环是 `Tt`。一次 `cde` 只从 mailbox 顶部切出**一个**可合并窗口（单 batch），窗口边界外的事件留给 `Tt` 的下一次迭代——所以"离散消息 → 若干 turn"是靠循环反复调用、而非一次合并成多批实现的。

- **drain 循环本体 = `Tt`（`daemon:73018`），再抽循环 `for (; y.status !== "ended" && x;)`（`daemon:73114`）**。`q.drainPromise` 在 `daemon:73013`/`73016` 被赋值为 `Tt(q)`（或 `preStart().then(()=>Tt(q))`）；状态字面量里的 `drainPromise: null`（`72967`）只是字段声明，不是"进入循环"。`cde` 在循环体内每次迭代调用一次（调用点 `daemon:73366`）。
- **`cde`（`daemon:60020`）单批骨架**：`mailbox_merge`（`YS`，`60118`）→ `mailbox_parse`（`Rg`，`60129`）→ `mailbox_render`（`XS`，`60150`）→ `IU(...)` 切窗口。选项键在 cde 侧读作 `n.batchSize ?? f5e`、`n.mergeWindowMs ?? p5e`（`60151`/`60152`），传入 `IU` 时命名为 `fallbackBatchSize`/`mergeWindowMs`（`60155`-`60158`）。
- **`IU`（`daemon:61298`）只返回单一 batch**：顺序累积 items 到数组 `i`，遇 `i.length >= fallbackBatchSize`（notify 批则 `Infinity`）/ notify-homogeneity 变化 / `Math.abs(p - o) > mergeWindowMs` / 不同目标 就 `break`，剩余事件留给下一次 `Tt` 迭代（`61309`-`61328`）。随后 cde 对该单一 batch 内部 items 做 `for (let F of T)` 拼成 `Be`（`60253`），再 **`EU` 一次（`60393`）+ `ode` 一次（`60424`）**——"每个 batch 发一次 query"成立，但"一次 IU = 若干 batch"不成立。
- **真正的合并门是可合并谓词，比 mergeWindowMs 更决定性**：`I5e`/`P5e`/`_de`/`$5e`/`kU`（`daemon:61349`-`61375`）——`e.length < 2` 不合并；`channel.message` 批要求无 `/` 斜杠命令（`P5e`）；notify 批要求全部满足 `kU`；且同一 `primaryTargetSessionKey`（`_de`: `set.size===1`）。telemetry `sdk_start` 携带 `coalesced: Be.length>1`（`60418`）。

### 论点二：SDK 适配层把 duoduo run-config 诚实翻译成一次 `query()`

**所以呢**：一个 batch 变成一次 SDK 调用，中间隔着一层把内部 run-config 翻成 SDK options 的适配器 `Xc`。这一层的分支（systemPrompt / permissionMode / thinking）直接决定"发出去的 prompt 长什么样、缓存能不能吃满",错一个分支就打偏。

- **query 本体**：从 `@anthropic-ai/claude-agent-sdk` 导入并别名 `Wue`（`daemon:57054`）。两种执行通道：非流式 `run`（`57344`）与流式 `createStreamingQuery`（`57574`-`57582`，`includePartialMessages:!0`）。
- **`permissionMode` 优先级**：`t.permissionMode ?? ALADUO_PERMISSION_MODE ?? (host? "bypassPermissions" : void 0)`（`daemon:57304`，host 判定 `Ho(process.env)==="host"`）。
- **`systemPrompt` 分支**：**仅当未设 `SYSTEM_PROMPT`（`c`）且存在 append 内容（`p`）时**才用 `{type:"preset", preset:"claude_code", append:p}`（三元在 `57314`-`57320`）；一旦 `SYSTEM_PROMPT` 有值，用裸字符串（`c` 或 `c\n\np`），不走 preset。分支自 `daemon:57305` `if (t.systemPrompt !== void 0) ... else {}` 起，append 组装 `p = [b_(), u].filter().join`（`57309`），即 `b_()`（duoduo 基座提示）拼 `APPEND_SYSTEM_PROMPT`。
- **工具集**：`allowedTools`/`disallowedTools`/`mcpServers`/`additionalDirectories` 透传（`57322`）；drain 侧再经 `ade`（`60007`）做 allow/deny 求差 `i=new Set(n); o=r?.filter(a=>!i.has(a))`（`60007`-`60011`）。
- **thinking 开关**：`includePartialMessages` 触发时强制 `maxThinkingTokens=0`（`daemon:57329`：`n?.includePartialMessages && (r.includePartialMessages=!0, r.maxThinkingTokens=0)`）。
- **适配器选择 `xe(y)`（`daemon:72813`）**：codex + codexAdapter → codexAdapter；`origin!=="channel"` 或无 `createStreamingQuery` → 一次性适配器 `s`；否则惰性长驻 `streamingAdapter`。

### 论点三：长驻流式会话上，四条控制线不重开对话地改写正在跑的 turn

**所以呢**：这是本节最独特处。同一 session 复用同一个长驻 `query()` 进程，输入由队列驱动的 async generator 逐块喂入；于是"合并、steer、抢占、后台续跑"全部被实现为对这条长驻输入流的操控，而非新开对话。四条控制线各管一件事：

**(a) sessionId 粘连 + 配置指纹重建——复用的边界。** 复用现有 `streamingState` 的条件（`z`，`daemon:72250`）：`streamingState && !closed && !needsRecreation && configSignature===j && (hasAcceptedTurn || initialSessionId===W)`。指纹 `H`（`72190`）= `JSON.stringify({cwd, settingSources, persistSession, permissionMode, allowedTools, disallowedTools, additionalDirectories, autoloadAdditionalDirectoryClaudeMd})`。**配置指纹变化就重建**：复用失败 → `await K(y)`（`72201`）关旧 query + abort + await loopPromise → 重新 `createStreamingQuery`。输入生成器 `Le()`（`72270`）由队列类 `II`（`71763`，`items/waiters/enqueue/dequeue/drain`）驱动；turn 项在 `72822` 入列（含 `accepted/streamedText/turnStreamedText/toolUseMap/toolBlockIndexMap/skipCalled/interruptRequested`）。

**(b) accepted 门控——决定"新输入是新 turn 还是 steer"。** **[本节最需更正的实质错误]** 实测 `daemon:72279`：
```
B.currentTurn !== null && B.currentTurn !== G && B.currentTurn.accepted || (B.currentTurn = G, G.accepted = !1, ...)
```
因 `&&` 先于 `||`，**采纳 G 为新 currentTurn（重置）发生在守卫为假时**，即 `currentTurn===null || currentTurn===G || !currentTurn.accepted`。**当上一 turn 已 accepted 且不同时恰恰不切换**——保留旧 turn 为 current，同时 `for await (let ge of G.input.prompt) yield ge`（`72280`）把新入列 prompt 灌进正在跑的 turn，这正是 steer。（原草稿"accepted 时才切换到新 turn"方向反了；其后半句"只有当前 turn 已 accept，后续输入才作为 steer"反而是对的。）orphan 接管 `orphanExecuting` 可为 `"foreign"`（`72315`）。

**(c) mid-turn steering——park 在 admission callback，消费在 PostToolUse hook。** 入队/park 的**决策发生在 admission callback（`daemon:73180`-`73335`）**，它是与 `cde` 并行的第二条 SDK 入口：在已有 live streaming turn 时被调用，自己调 `EU`（`73197`）生成 `coalescedPromptText`，再按 runtime 分叉——claude 走"park `pendingSteer` 或 `enqueueAsNewTurn`"。park 判据 `jme = !!w2 && w2.accepted && !Dme && !ht.isNotifyOnly && S2.length>0`（`73314`，`w2 = fv.currentTurn`），打印 "parked claude steer"（`73328`），`pendingSteer` 字段在 `73318`（`steerText/eventIds/claimedEventIds/enqueueAsNewTurn/requeueLines/requeueEventIds/processedEventIds/settled`）。**注入（消费）发生在 PostToolUse hook（matcher `"*"`，`72319`-`72363`）**：检查 `pendingSteer` → `settled` + `markDone(lr)` → 以 `hookSpecificOutput.additionalContext = G.join("\n\n")`（`72356`-`72362`）返回给 SDK。同一 hook 里的独立 notify-steer 路径处理 `pendingNotifySteer`（`72340`-`72354`）：`HX(inboxPaths)` 清 inbox 注入 `notifyText`，带 `B.currentTurn===ge.spawningTurn` 约束，专把后台 Agent 完成回调冒泡进当前 turn。

**(d) 三态抢占边界——`D()` 置标志、`A(y)` 才扳机。** `pendingPreemptBoundary` 为三态 `"accept" | "tool_use" | "tool_result"` + hard/soft 两档强度。设值函数 `D(y,I,j)`（`daemon:72180`）：tool_result 分支（`72182`）、accept/`defer_accept`（`72184`）、tool_use 与 `I==="soft"` 软抢占（`72186`）。**但 `D()` 只置 pending 标志；真正的 abort 由 `onExecutionEvent` 闭包 `A(y)`（`daemon:73202`）消费**——tool_use 到达时 `activeToolUseIds.add` + 若 `boundary==="tool_use"` 则清标志并 `A(y)`；tool_result 时 `delete` + 若 `boundary==="tool_result" && size===0` 则 `A(y)`。二者分离正是"deferred preempt 何时兑现"的答案。Codex 路径改走 `turn/steer` RPC（`58344`），失败回退（`58354` "falling back to new turn"，`73239` "codex turn/steer landed"，`73246` "codex steer fell back to redrain"）。

**(e) hold-stdin——后台 subagent 续跑。** drain 传 `holdInputOpenForBackgroundAgents = runtime==="claude" && origin!=="channel"`（`daemon:73372`）。`run` 中 `R = holdInput...`（`57418`），prompt 换成生成器 `Ne()`（`57445`：`for await ... yield C; await A`）：yield 完 prompt 后 `await A` 让 stdin 不关，后台 subagent 完成回调（in-process MCP）仍可送达。`A` 的 resolve 走 `te()`（`57431`：`E || P && T.size===0 && O()`）——**需同时满足 `P`（已收到 result，`57557` 置 `P=!0`）与 `T.size===0`**（`T` 增删来自 SDK system 事件 `task_started`/`task_notification`，`57479`/`57483`），非仅"后台 task 跑完"；finally 的 `z()` 会强制 resolve（`57435`/`57563`）。idle 看门狗 `D = rU(ALADUO_HOLD_INPUT_IDLE_TIMEOUT_MS, 6e5)`（默认 10min，`57426`），触发打印 "hold-input idle watchdog fired"（`57439`）。

> Skip 语义横跨该长驻会话：非流式 `f_` hook 置 `d=!0`（`57360`），流式 `f_` matcher（`72313`）置 `G.skipCalled=!0`（`72316`），drain 侧 codex 补 `ge.skipped=!0`（`60508`），`if (ge.skipped) O=!0` 抑制 outbox（`60531`）。

### 论点四：失败面收敛成一条用户可见文本 + 一个 spine 事件

**所以呢**：SDK turn 抛错不会静默丢失或裸露堆栈，而是被产品化成统一格式，既能回给用户又能进事件日志（可被后续 drain 与 usage 复算）。

- **drain-error（`daemon:60448`-`60505`）**：try/catch 中取消类错误 `y_`（`60449`）/`__`（`60468`）/`xU`（`60483`）走 cancelled 收尾；其余 `throw await oR(..., {stage:"sdk_turn"})`（`60501`，`stage` 于 `60504`）。`oR`（`61622`）生成用户文本 `` `[duoduo:drain-error] agent turn failed at ${n.stage}` ``（`61625`，后接 `L5e(r)` 诊断），并向 spine 追加 `type:"agent.error"`（`61644`）。
- **执行事件桥接**：包装器 `j`（`daemon:60366`）统计 tool_use/tool_result 计数、捕获 `compact_boundary`，喂 drain record 的 `tool_calls`/`tool_errors` 与 `session.compact`，也是 spine `agent.*` 事件的上游。**活体印证**：`spine.tail` 可见 `agent.tool_use`/`agent.tool_result` 从 SDK 适配器路径流出，印证 `EU→ode` → onExecutionEvent → session.execution/spine 的桥接。
- **开关**：`DISABLE_ADAPTIVE`/`DISABLE_THINKING`/`DISABLE_INTERLEAVED_THINKING`/`MAX_THINKING_TOKENS` 各仅出现一次，全在错误提示串 `L5e`（`61620`）；daemon 内无读取这些 env 的分支，故 duoduo 自身不消费——但底层 claude 二进制是否透传消费属**未证实推测**。

### 证据表

| 机制主张 | 证据（字面量/代码片段） | 位置 | 置信 |
|---|---|---|---|
| drain 循环本体是 `Tt`，`cde` 是循环体内单批处理器 | `q.drainPromise = Tt(q)`；`for (; y.status !== "ended" && x;)`；`cde(...)` 调用点 | daemon:73016 / 73114 / 73366 | confirmed |
| 一次 `cde` 经 `IU` 只切出一个前导可合并窗口（单 batch），余留给下次迭代 | `IU` 顺序累积，遇 batchSize/notify 变化/mergeWindowMs/不同目标 `break`，`return {items:i, events:r}` | daemon:60020 / 61298-61328 | confirmed |
| 合并谓词（同目标、无斜杠命令、notify-homogeneous）是合并的真正边界 | `I5e`/`P5e`（`startsWith("/")` 拒）/`_de`（`size===1`）/`$5e`/`kU` | daemon:61349-61375 | confirmed |
| SDK 调用即 `@anthropic-ai/claude-agent-sdk` 的 `query` | `query as Wue` | daemon:57054 | confirmed |
| permissionMode 优先级，host 默认 bypass | `t.permissionMode ?? ALADUO_PERMISSION_MODE ?? (Ho(...)==="host" ? "bypassPermissions" : void 0)` | daemon:57304 | confirmed |
| systemPrompt 仅当未设 SYSTEM_PROMPT 且有 append 才用 preset；否则裸字符串 | `if (t.systemPrompt!==void 0)...else{}`；`{type:"preset",preset:"claude_code",append:p}`；`p=[b_(),u].filter().join` | daemon:57305 / 57309 / 57314-57320 | confirmed |
| `ade` 工具集 allow/deny 求差 | `i=new Set(n); o=r?.filter(a=>!i.has(a))` | daemon:60007-60011 | confirmed |
| includePartialMessages 强制关 thinking | `n?.includePartialMessages && (r.includePartialMessages=!0, r.maxThinkingTokens=0)` | daemon:57329 | confirmed |
| 适配器选择 `xe(y)` | codex→codexAdapter；非 channel/无 streaming→一次性 `s`；否则长驻 streamingAdapter | daemon:72813 | confirmed |
| streamingAdapter sessionId 粘连复用条件 + 指纹重建 | `streamingState && !closed && !needsRecreation && configSignature===j && (hasAcceptedTurn||initialSessionId===W)`；`H`=JSON.stringify指纹；重建走 `K(y)` | daemon:72250 / 72190 / 72201 | confirmed |
| 长驻流式输入靠队列驱动 generator | `async function* Le(){ ... for await (let ge of G.input.prompt) yield ge }`；队列类 `II`；turn 入列 | daemon:72270 / 71763 / 72822 | confirmed |
| **accepted 门控（布尔已订正）**：上一 turn 已 accepted 且不同时**不切换**，把新 prompt 灌进当前 turn = steer | `B.currentTurn!==null && B.currentTurn!==G && B.currentTurn.accepted \|\| (B.currentTurn=G, G.accepted=!1, ...)` | daemon:72279 | confirmed（方向已订正） |
| steering 决策在 admission callback（park），消费在 PostToolUse hook（注入） | `EU` 生成 coalescedPromptText；`jme=!!w2&&w2.accepted&&!Dme&&!ht.isNotifyOnly&&S2.length>0`；"parked claude steer"；`additionalContext=G.join("\n\n")` | daemon:73197 / 73314 / 73328 / 72356-72362 | confirmed |
| notify-steer 独立路径，冒泡背景 Agent 回调 | `pendingNotifySteer`；`HX(inboxPaths)`；`B.currentTurn===ge.spawningTurn` | daemon:72340-72354 | confirmed |
| 抢占三态 accept/tool_use/tool_result + hard/soft；`D()` 置标志、`A(y)` 扳机 abort | `D(y,I,j)` 三分支；`I==="soft"`；`defer_accept`；`A(y)` 消费 `activeToolUseIds.add/delete` | daemon:72180-72186 / 73202 | confirmed |
| Codex 走 turn/steer RPC，失败回退 redrain | `r.request("turn/steer",...)`；"falling back to new turn"；"codex steer fell back to redrain" | daemon:58344 / 58354 / 73246 | confirmed |
| hold-stdin：`await A`，resolve 需 `P && T.size===0`，含 idle 看门狗 | `holdInputOpenForBackgroundAgents`；`Ne(){...yield C; await A}`；`te()=E \|\| P && T.size===0 && O()`；`P=!0`@57557；`rU(...,6e5)`；"hold-input idle watchdog fired" | daemon:73372 / 57418 / 57426 / 57431 / 57439 | confirmed |
| Skip 联动跳过 SDK 结果并抑制 outbox | `G.skipCalled=!0`；drain 侧 `ge.skipped=!0`；`if(ge.skipped) O=!0` | daemon:72316 / 60508 / 60531 | confirmed |
| drain-error 冒泡为文本回复 + spine 事件 | `[duoduo:drain-error] agent turn failed at ${n.stage}`；`type:"agent.error"`；throw at `stage:"sdk_turn"` | daemon:61625 / 61644 / 60501-60504 | confirmed |
| 执行事件包装器 `j` 统计工具计数 + compact_boundary，喂 drain record/spine | tool_use/tool_result 计数、`compact_boundary` 捕获 | daemon:60366 | confirmed |
| drain record 结构与 `usage.get` 聚合字段一致 | `total_drains/total_tool_calls/.../perf{...sdk_ttft_ms}`（例 memory-committer `total_drains=2`） | daemon:60057 + 活体 usage.get | confirmed（静态+活体） |
| DISABLE_*/MAX_THINKING_TOKENS 仅存在于错误提示，非 duoduo 消费 | grep 计数各 1，全在 `L5e` 提示串（61620）；daemon 无读取分支 | daemon:61620 | 未证实推测（透传消费未直接证实） |

### 关键数据结构 / 事件 / 文件格式（真实字段名）

- **session actor 状态**（`daemon:72956`）：`status, drainPromise, currentAbortController, query, streamingState, streamingAdapter, isStreaming, activeToolUseIds(Set), pendingPreempt, pendingPreemptBoundary, pendingSteer, pendingNotifySteer, pendingAdmittedBatches, inflightEventIds, notifyCalledDuringDrain, runtime, codexAdapter`（另有 `pendingClear/admissionInProgress/admissionCallback/streamAbortController/wakeResolver/idleSince/consecutiveConservativeRedrive` 未在草稿列出）。
- **streamingState**（`72255`）：`queue, abortController, configSignature, initialSessionId, hasAcceptedTurn, needsRecreation, closed, currentTurn, orphanExecuting`。
- **turn/queue 项**（`72822`）：`input, resolve, reject, accepted, sessionId, streamedText, turnStreamedText, toolUseMap, toolBlockIndexMap, skipCalled, interruptRequested`。
- **pendingSteer**（`73318`）：`steerText, eventIds, claimedEventIds, enqueueAsNewTurn, requeueLines, requeueEventIds, processedEventIds, settled`。
- **pendingNotifySteer**（`72340`-`72354`）：`notifyText, inboxPaths, spawningTurn` 等，走 `HX(...)` 清 inbox 后注入。
- **drain record**（追加到 drainRecordPath，`60057`；活体经 `usage.get` 按 session 聚合印证）：`id, session_key, sdk_session_id, drain_started_at, drain_duration_ms, sdk_duration_ms, events_processed, events_skipped, tool_calls, tool_errors, output_chars, usage{input_tokens,output_tokens,cache_creation_input_tokens,cache_read_input_tokens,total_cost_usd,protocol,model,context_used_tokens}, perf{mailbox_merge_ms,...,sdk_ttft_ms_total,sdk_ttft_samples}`。
- **SDK options**（`Xc`，`57303` 起）：`resume, abortController, cwd, settingSources, persistSession, outputFormat, model, permissionMode, systemPrompt, allowedTools, disallowedTools, mcpServers, additionalDirectories, env, pathToClaudeCodeExecutable, hooks, includePartialMessages, maxThinkingTokens`。
- **内建 hooks**：PreToolUse matcher `"Bash"` 拦截 `run_in_background`（改导向 Agent 工具，`72303`）；PreToolUse matcher `f_` 检测 Skip（`57360`/`72313`/`72316`）；PostToolUse matcher `"*"` 做 steer/notify-steer 注入（`72319`-`72363`）。

### 给 Agent PM 的洞察

> 1. **"turn ≠ 消息"是这套设计的中心一步，且分层要看清。** 循环层 `Tt` 反复调用单批处理器 `cde`，每次只吃一个"可合并谓词允许的前导窗口"（同目标、无斜杠命令、mergeWindow 内）。这天然做了输入去抖/合并、降低 query 次数与 cache miss，代价是单条消息延迟受窗口影响。PM 要把"消息""batch""turn"三层解耦：一次 drain 迭代 = 一个 batch = 一次 query，多条消息可能跨多次迭代分成多个 turn。
>
> 2. **steering 是"决策在 admission callback、消费在 PostToolUse hook"的两段式，且受 accepted 门控保护——方向别记反。** 只有当前 turn **已 accepted**，后续输入才被灌进正在跑的 turn 作为 steer（`72279` 布尔守卫为假 → 不切新 turn）；未 accepted 则采纳为新 currentTurn。真正注入靠 SDK 的 PostToolUse `additionalContext`，在工具边界插入，保住工具执行原子性又实现"边跑边追加"。这是把 agent-sdk 的 hook 能力当控制面用的巧思，可直接借鉴。
>
> 3. **长驻 streamingQuery + configSignature 粘连是延迟/成本优化的核心，但抢占是"置标志/扳机"两段式。** 同会话同配置复用一个 query 进程避免冷启动与重放；指纹（cwd/permissionMode/allowedTools 等）一变就 `K(y)` 强制重建。抢占用 `D()` 置三态边界标志、`onExecutionEvent` 的 `A(y)` 在对应工具边界才真正 abort——deferred preempt 的兑现时机取决于 `activeToolUseIds` 何时清空。PM 应尽量稳定单会话工具集/权限。
>
> 4. **背景 subagent 靠"hold stdin + P&&T.size===0 双条件 + idle 看门狗 + notify-steer 回调冒泡"续跑。** stdin 保活的释放需**同时**满足"已收到 result"与"追踪的后台 task 全部完成"，非仅后者；超过默认 10 分钟静默会 force-release，牺牲 in-process MCP 回调。长任务应走独立 job 而非 background Agent。
>
> 5. **失败面产品化收敛。** drain-error 统一为 `[duoduo:drain-error]` 文本 + `agent.error` spine 事件（可被 usage/后续 drain 复算），并内置"关 thinking"诊断话术。注意 `DISABLE_*`/`MAX_THINKING_TOKENS` 在 daemon 内仅出现在错误提示串，是否真正透传消费属未证实推测——对多模型/第三方 endpoint，thinking 线协议不兼容是头号坑，值得产品层预置开关与提示。


---


---

# 第二部分 · 会话编排：有状态对象的隔离、调度与后端路由

> **关键句**：会话是被编排与路由的有状态对象。运行时用一 key 一 actor + 两层锁 + 双有界可让出池把一外部身份扩成多内部会话（§3），并在 claude/codex 两值枚举上把每个会话诚实路由到对应后端（§8）——先讲被谁持有/调度，再讲被谁执行。


---

## §3 Session Actor / 生命周期 / 并发

**Session 是一个有状态 actor 运行时：session_key 前缀纯函数派生平面与权限、一 key 一 actor 的内存 Map 编排、两层锁（跨重启 pid/boot_id 进程写锁 + 按 key 串行的 `si` 异步互斥）、双有界可让出池（channel 10 / job 6，idle 主动让槽而 `attachedChannels` 钉活），在单 daemon 单进程内把"一外部身份 → 多内部会话"做成了低延迟前台、可抢占续写、又能回收资源的运行时。** 下面四条论点自上而下拆解这句结论：命名如何即编排、两层锁如何分工、池与生命周期如何让出与回收、唤醒/抢占/隔离如何在不损坏状态的前提下续写。

---

### 论点 1 · 命名即编排：前缀纯函数派生一切，一 key 一 actor 内存编排

**所以呢**：duoduo 不需要独立的会话注册表 / 权限表——`session_key` 这个字符串**本身**就编码了平面、kind、权限与后端归属，路由与隔离全部从前缀纯函数派生；而每个 key 在内存里对应至多一个 actor，编排就是一张 `Map`。这把"一外部身份 → 多内部会话"降维成"命名空间 + 纯函数 + Map"，无外部状态。

- **key 格式与派生**：`session_key = <scope>:<name>:<hash(workspaceAbsPath)>`，由 `dte`（`stdio.pretty.js:46451`）拼装：`` `${t}:${n}:${ute(a)}` ``，其中 `a=Af(e.workspaceAbsPath)`（`46453`）、`ute` 为 hash（`46435`），`hR` 注入 `scope:"stdio"`（`46458`）。活体 `system.status` 返回 `stdio:default:28d3ca682f86` 逐段印证。**confirmed**。
- **前缀 → plane / kind**：kind 由 `Os(e)`（`daemon.pretty.js:35584`）前缀分类（`meta:/cadence:→meta`、`subconscious:→subconscious`、`system:→system`、`job:→job`，否则 `channel`）；plane 由 `B5e(e)`（`61737`：`system:/meta:/cadence:→system`，否则 `work`）。**confirmed**。
- **一 key 一 actor**：注册表 `let _ = new Map`（`72126`），`ve(y,I)`（`72951`）负责生成 actor，`actorRunId: Y=++R` 单调自增（`72956`），`_.set(y,q)`。活体 `system.status` 只有单一 actor（status=`idle`），印证"至多一个"。**confirmed**。
- **kind 的第二真值来源（文档此前漏列）**：`ve` 内 `gk(t, {...})` 把 `display_name/kind` upsert 进 meta.md（`72997`），此处 `kind` 从 **origin** 二次派生（`origin==="job"?"job":origin==="system"?"system":startsWith("meta:")?"meta":"channel"`）——与 `Os` 的前缀派生**并存**，是 kind 的另一条真值来源。**confirmed**。

---

### 论点 2 · 两层锁分工：进程写锁保运维健壮性，`si` 异步互斥保数据一致性

**所以呢**："lease lock"在代码里其实是**两把互不相干的锁**，各解决一个问题，绝不能混谈：一把跨重启防"同目录多 daemon 写者"（运维），一把按 key 串行防"同会话并发写状态"（数据）。

- **进程级 runtime 写锁**——保证同一 runtime_dir 只有一个 daemon 写者。锁文件 `run/locks/daemon-writer.json`（`Yj`，`77207`），记 `{runtime_dir, pid, boot_id, started_at, last_heartbeat_at}`。`start()` 内 `S=await Fie(n); if(!S.acquired) throw \`Runtime lock already held by pid=${...}\``（**`78790`**，此前标 78791 漂 1 行）；心跳 `setInterval(()=>Uie(n),_)`、`_=Cme("ALADUO_RUNTIME_LOCK_HEARTBEAT_MS",3e4,1e3)`（**`78802-78804`**，此前标 78805 漂 ~2 行）。夺锁前 `HWe`（`77245`）判 stale，逐字符为：
  ```
  Number.isNaN(r) || t.getTime()-r > n || (e.boot_id && e.boot_id !== zie()) || !qWe(e.pid)
  ```
  即心跳超 TTL（`ttlMs??12e4`=120s，`Fie` 内 `77259`）、**`boot_id` 存在且不符**（重启；`e.boot_id &&` 是空值守卫，boot_id 缺失时不据此判 stale）、或 `qWe`=`process.kill(pid,0)`（`77211`）探测进程已死，则视为可抢占。`boot_id` 取 `/proc/sys/kernel/random/boot_id` + macOS `sysctl kern.boottime` + uptime 兜底（`BWe`，`77221`）。活体 `system.config`：`heartbeat_ms=30000`、`runtime_lock_heartbeat_ms=30000`。**confirmed**。
- **会话级异步互斥 `si(session_key, fn)`**（`31382`）——`WS: Map<key, 尾Promise>`，把该 key 的所有状态变更闭包串成链：`i=WS.get(e)??Promise.resolve()` → `WS.set(e,r)` → `await i` → finally `n(); WS.get(e)===r&&WS.delete(e)`（逐字符匹配）。state.json/meta 写、mailbox merge、outbox cursor 全按 key 串行。调用点已全验：`34133/34168/34218/34251/34284`（state/mailbox 写）、`76920`（`V1` delivery-cursor，`[delivery-cursor] skip cursor write: session archived`）、`78124`；此前漏列的 `31517`(`_c(t),si(t,…)`)、`35800/35818`(alias) 也走 `si`。配合"一 key 一 actor"形成双保险。**confirmed**。

---

### 论点 3 · 池与生命周期：双有界可让出池 + active/idle/ended，让槽回收而前台钉活

**所以呢**：并发用"双有界池 + 可让出的池槽"而非固定线程——channel/job 分池，后台批处理饿不死前台；执行槽（占用 vs 让出）与会话存活（actor 是否回收）被**解耦**：idle 主动让槽却仍可被前台附着钉住不死，容量因而在会话间自由流动。

- **双有界池 channel=10 / job=6**：池对象 `h`(channel)@`72077`、`g`(job)@`72083`，各持 `{name, activeCount, maxConcurrent, wakeQueue}`；`f=e.maxConcurrentChannel??e.maxConcurrent??10`、`m=e.maxConcurrentJob??6`（`72086-72087`）；`v(y,I)` 按 origin 选池（`72087`）。actor 创建时抢槽 `F=v(y,q.origin); F.activeCount++, q.holdsPoolSlot=!0`（`72993-72994`）；超限入队 `q.wakeQueue.push(y)`（`Ne` 内 `72932`）。活体 `system.config`：`max_concurrent_channel=10, max_concurrent_job=6`。**confirmed**。
- **三态 active → idle → ended**：idle 分支 `73543`、`y.status="ended"`（`73634/73635`）均已亲见。**confirmed**。
- **idle 让槽 + `Ht(idle_ms)` 等待 + 前台钉活**：drain 空转后 `released pool slot (idle)`（`We.activeCount--, y.holdsPoolSlot=!1`，`73549`），进 `Ht(y,I)`（`73667`）等待——`wakeResolver=()=>{Y();j(!0)}` 与 `setTimeout(()=>{Y();j(!1)},I)` **竞争**。超时且无附着→`idle timeout, no attachments, exiting`（`73577`）退 ended；**有附着则继续等**→`idle timeout but has attachments, continuing wait`（`73566`），前台通道把 actor 钉住不回收；被唤醒→重抢槽（pool-full→`wakeQueue.unshift`，否则 `activeCount++`，`73585-73592`）。`idle_ms` 源：`idleTimeoutMs:i=36e5`（`72052`）、config `ALADUO_SESSION_IDLE_MS`（`77521`）、注入 `78879`。活体 `idle_ms=3600000`，stdio 会话正处 idle。**confirmed**。
- **dequeue 原地复用 `S()`（行号已订正）**：出队唤醒时若目标是"idle 且无池槽且有 drainPromise"的 actor，走 `pendingWake+wakeResolver` **原地唤醒**而非新建 `ve()`，随后 `return`；池重满则 `unshift` 回队首（`dequeue deferred: pool re-filled`）；否则回落 `ve(I, c2(I)??…)`。`function S(y)` 定义在 **`72091`**、原地复用体在 **`72100-72125`**（此前误标 `72905-72914`——那实为 `Ne` 内 soft-preempt 边界日志，与 dequeue 无关，本节正文与洞察 #2 均已订正）。**confirmed**。
- **重启 actor 的 origin 从何而来（文档此前漏列的闭环节点）**：`S()` 与 `Ne()` 回落新建时 `ve(I, c2(I))`——`c2(y)`（定义 `71871`，调用 `72123`/`72941`）负责推断被出队/唤醒 actor 应落 channel 还是 job 池，是"重抢槽"闭环里决定池归属的关键。**confirmed（机制），origin 推断细节为静态阅读**。

---

### 论点 4 · 唤醒 / 抢占 / 隔离：边界感知续写，硬前缀隔离，收尾再校验

**所以呢**：有状态 agent 的"打断 / 续写"不是硬 kill，而是**边界感知**——能不打断就直接续喂（活流注入），要打断也只在工具调用边界；同时用前缀白名单挡住越权唤醒，用一次性布尔上限防收尾自旋。这三点合起来保证"续写不损坏状态、隔离不被绕过、结束不空转"。

- **唤醒与抢占 `Ne`/`D`**：`Ne(y,I)`（`72845`）默认 `j=I?.preempt??"allow"`（`72858`）；归档会话 wake 被抑制（`Ni(y)`→`wake suppressed`，`72852`）；idle actor 直接 `Y.wakeResolver()`（`72866`）。`D(y,I,j)`（`72180`）在 `tool_use/tool_result/accept` 边界延迟中断，`I==="soft"` 分支存在，返回 `defer_*/immediate/noop`；`force→D(Y,"immediate",W)`（`72892`）、`allow→D(Y,"soft",W)`（`72905`）。**confirmed**。
- **preempt 档位映射 `_2`**（`77569`）：`!t||!t.startsWith("/")?"allow":…"/cancel"?"force":"never"`（逐字符匹配）——普通消息→`allow`、`/cancel`→`force`、其它斜杠命令→`never`。`allow` 在内部派生为 `soft` 模式（非外部档位）。**confirmed**。
- **活流注入 = idle 之外的第二条低延迟续接（文档此前只点到、未追全）**：`Ne` 内仅当 `j==="allow"&&(B||J)&&Y.admissionCallback&&!Y.admissionInProgress` 时把新批次**直接并入当前 turn**（`72873`），无需打断亦无需 idle 重启；`admissionInProgress` 双端 finally 复位防并发注入。`admissionCallback` 由 drain 循环安装，`Le().then(...)` 复位 `admissionInProgress` 把新批并入本 turn——这是"不打断直接续喂"的路径，区别于 idle 唤醒。**confirmed（注入判据），安装/复位时序为静态阅读**。
- **`wakeResolver` 单槽不变量（并发同步点）**：同一 `wakeResolver` 字段被 `Ht`(idle 等待) **设置**、被 `Ne`/`S`(唤醒/出队) **消费并置 null**（见 `72101` 的 `wakeResolver(),wakeResolver=null`），是 idle↔wake 竞争的**唯一同步点**，构成一条并发不变量。**confirmed**。
- **Plane/kind 硬隔离**：`session.notify`（`77945`）内联 `s=Os(o.session_key); if(s!=="channel"&&s!=="job") return {ok:!1,reason:"forbidden_kind",…}`——拒绝把外部通知投给 subconscious/system/meta 平面；`session.compact`（`78001`）更严 `a=Os(...); if(a!=="channel")…`，且 `if(Ni(...)) reason:"archiving"`（`78007`）。白名单谓词 `F1(e){return Os(e)==="channel"||Os(e)==="job"}`（`35590`）存在但供 `listUserVisible`，notify/compact 用内联 `Os` 判断。**confirmed**。
- **归档态统一短路 `ol()`（文档此前漏列）**：`ol(e,t)=DX(vf(e,t))&&!DX(Pr(e,t))`（`31250`，归档目录存在且活动目录不存在）——tombstone 判定贯穿 delivery-cursor（`76920`）、compact、drain 收尾，是归档态对所有写路径的统一短路机制。归档错误 `ZD extends Error {kind="session_archiving"}`（`31413-31414`），`_c` 抛之（`31517`）。**confirmed**。
- **收尾再校验 `Ze` + 一次性重驱**：`Ze(y,I)`（`73683`）actor end 后重扫 inbox，返回 `fresh/conservative/none`；`fresh`→重新 wake（`=!1`）；`conservative`(瞬时读失败) 受 `consecutiveConservativeRedrive` 约束——该字段**确为布尔**：初始 `??!1`（`72990`），已 true 则 `conservative re-drive suppressed (cap spent)`（`73643`），首次则 `=!0`+`re-entering wake path once`（`73646`）——即只重驱一次防自旋（`73638-73651`）。**confirmed**。

---

### 证据表

| 机制主张 | 证据(字面量/片段) | 位置 | 置信 |
|---|---|---|---|
| 进程级 runtime 写锁 + pid/boot_id/心跳/TTL 抢占 | `daemon-writer.json`；`Runtime lock already held by pid=${...}`；`HWe`: `Number.isNaN(r) \|\| t.getTime()-r>n \|\| (e.boot_id && e.boot_id!==zie()) \|\| !qWe(e.pid)`；`qWe`=`process.kill(e,0)`；TTL `ttlMs??12e4` | daemon `77207/77211/77245/77259`；抢锁 `78790`；心跳 `78802-78804` | confirmed |
| 会话级异步互斥（串行化状态变更） | `si(e,t){ i=WS.get(e)??Promise.resolve(); WS.set(e,r); await i; try{return await t()} finally{n(); WS.get(e)===r&&WS.delete(e)} }` | daemon `31382`（调用点 `31517/34133/34168/34218/34251/34284/35800/35818/76920/78124`） | confirmed |
| 一 session_key 一 actor + 单调 actorRunId + active/idle/ended | `let _ = new Map`（`72126`）；`ve()` 生成、`actorRunId: Y=++R`；`status:"active"→"idle"→"ended"` | daemon `72951-72956/73543/73634` | confirmed |
| 双有界池：channel=10 / job=6，超限入 wakeQueue | `h`@`72077`/`g`@`72083` `{name,activeCount,maxConcurrent,wakeQueue}`；`f=…??10`、`m=…??6`；`q.wakeQueue.push(y)` | daemon `72077/72083/72086-72087`；`72932`；RPC `system.config`→`max_concurrent_channel:10, max_concurrent_job:6` | confirmed |
| idle 释放池槽 + `Ht(idle_ms)` 等待，前台附着钉住 actor | `released pool slot (idle)`；`Ht(y,I){ wakeResolver=j(!0) vs setTimeout(j(!1),I) }`；`idle timeout but has attachments, continuing wait` | daemon `73549/73667/73566`；重抢槽 `73585-73592`；`idle_ms:3600000` RPC | confirmed |
| dequeue 原地复用 idle actor（**行号已订正**） | `S(y){ …if(j.status==="idle"&&!j.holdsPoolSlot&&j.drainPromise){ pendingWake=!0; wakeResolver(); "resuming idle actor from dequeue"; return } …回落 ve(I,c2(I)) }` | daemon `72091-72125`（此前误标 72905-72914） | confirmed |
| 唤醒/抢占：Ne 归档抑制 + idle resolve + 活流注入；D 边界延迟 | `Ne`：`Ni→wake suppressed`；`allow&&(B\|\|J)&&admissionCallback&&!admissionInProgress`；`D`：`tool_use/tool_result/accept` 边界，`force→immediate`/`allow→soft` | daemon `72845/72852/72866/72873`；`72180/72892/72905` | confirmed |
| preempt 档位映射 `_2` | `!t\|\|!t.startsWith("/")?"allow":…/cancel?"force":"never"`；`Ne` 默认 `j=I?.preempt??"allow"` | daemon `77569`；`72858` | confirmed |
| Plane/kind 隔离：notify 拒非 channel/job，compact 仅 channel | `s=Os(o.session_key); if(s!=="channel"&&s!=="job") reason:"forbidden_kind"`；`compact`：`if(a!=="channel")` + `if(Ni)reason:"archiving"` | daemon `77945-77951`；`78001-78007`；`Os`@`35584`；`F1`@`35590` | confirmed |
| session_key 格式 `<scope>:<name>:<hash(workspaceAbsPath)>` | `dte: \`${t}:${n}:${ute(a)}\``（`a=Af(e.workspaceAbsPath)`）；`hR({scope:"stdio",...})`；活体 `stdio:default:28d3ca682f86` | stdio `46451/46453/46458`；`session list` RPC | confirmed |
| 会话目录 = sessionsDir/sha256(key)，含 inbox/mailbox/state.json；归档 tombstone | `Pr=join(sessionsDir,Ai(t))`；`Ai=sha256(e).digest(hex)`；`ol()=DX(vf)&&!DX(Pr)`；`inbox/mailbox.md/mailbox/pending/notes.jsonl/meta.md/state.json` | daemon `31232/31238/31250/31254-31284` | confirmed |
| rehydrate 扫描 + state.json 字段 | `MX(e)` 扫 `e.sessionsDir` 后 `stat().isDirectory()&&qqe` 读取；`Cne` 字段集 | daemon `31307`（MX）；`35606`（Cne） | confirmed |
| ingress→wake；outbox replay；delivery-cursor 跳归档 | `channel.ingress`→`routing.enqueued && emit("session.wake",...)`；`replayed outbox backlog`；`V1` 用 `ol()` 跳归档写游标 | daemon `78271/~78312`；`78751`；`76920` | confirmed |

### 关键数据结构 / 事件 / 文件格式（真实字面量）

- **Actor 对象**（内存态，`72954-72998`）：`sessionKey, actorRunId(=++R), sdkSessionId, sdkSessionIdVerified, status, currentAbortController, query, streamingState, streamingAdapter, drainPromise, wakeResolver(单槽 resolver，Ht 设置/Ne·S 消费置 null), pendingWake, isStreaming, activeToolUseIds:Set, pendingPreempt, pendingPreemptBoundary("tool_use"/"tool_result"/"accept"，由 D() @72180 设置), admissionCallback, admissionInProgress, holdsPoolSlot, attachedChannels:Set, origin("channel"/"job"/"system"), jobId, jobStateless, runtime("claude"/"codex"), codexAdapter, idleSince, consecutiveConservativeRedrive(布尔，初始 ??!1 @72990)`。
- **池对象**（`h`@`72077` / `g`@`72083`）：`{name:"channel"|"job", activeCount, maxConcurrent, wakeQueue:[]}`。
- **runtime 锁文件** `run/locks/daemon-writer.json`：`{runtime_dir, pid, boot_id, started_at, last_heartbeat_at}`（`boot_id` 取 `/proc/sys/kernel/random/boot_id` + macOS `sysctl kern.boottime`/uptime 兜底，`BWe`@`77221`）。
- **会话磁盘布局** `var/sessions/<sha256(key)>/`：`state.json`、`meta.md`、`mailbox.md`（渲染标题 `["# Session Mailbox","","## Inbox",""]`，`31689`）、`mailbox/pending/`、`mailbox/notes.jsonl`、`inbox/`。归档态迁到 `var/sessions-archive/<sha256(key)>/`（`vf`@`31246`；`ol()` 判归档 tombstone `31250`），归档进行中由 `Ni`/`JS`/`GS`（`Tg` Set）抑制一切 wake/ingress，错误 `kind="session_archiving"`（`31414`）。
  - *注（未证实推测）*：将该错误类命名为 `SessionArchivingError` 系对 minified 符号 `ZD` 的推测命名；代码可证的只有 `ZD extends Error` 且 `kind="session_archiving"`（`31413-31414`）。
- **state.json 字段**（`Cne`@`35606`）：`session_key, cwd, plane, permission_profile, created_at, last_event_id, last_event_at, last_seen_daemon_started_at, source_channel_id, last_error`；`display_name/kind/owner_session` 来自 meta（由 `gk`@`72997` upsert，kind 在此从 origin 二次派生）。
- **preempt 值来源** `_2`（`77569`）：无斜杠命令→`"allow"`、`/cancel`→`"force"`、其它斜杠命令→`"never"`；`Ne` 默认 `j=I?.preempt??"allow"`（`72858`）。内部 `D(actor,"soft"|"immediate",boundary)` 的 `soft` 是由 `allow` 派生的内部模式名，非外部档位。
- **相关事件/RPC**：入口 `channel.ingress`/`session.notify`/`session.wake`（`emit("session.wake",{sessionKey,preempt})`）；隔离判定返回 `reason:"forbidden_kind"`/`"archiving"`/`"ambiguous"`/`"not_found"`。

### 给 Agent PM 的洞察

> 1. **"外部单身份、内部多会话" = session_key 命名空间 + 一 key 一 actor + 前缀即平面**。路由/隔离/权限全部从 `session_key` 前缀（`stdio:`/`job:`/`meta:`/`subconscious:`/`system:`）纯函数派生（`Os`/`B5e`），无需额外注册表（呼应本节论点 1）。代价是"平面"是约定式字符串契约——`session.notify` 靠前缀白名单挡住 work→system/subconscious 的越权唤醒（只放行 channel/job），这是可借鉴的**轻量能力边界**，但也意味着改前缀即改权限，需谨慎治理。

> 2. **并发用"双有界池 + 可让出的池槽"而非固定线程**。channel(10)/job(6) 分池避免后台批处理饿死前台交互；idle actor **主动释放池槽**（`73549`）再挂起等待，dequeue 时对 idle-with-drainPromise 的 actor **原地唤醒复用**（`72091-72125`，此前误标 72905-72914，已订正），让容量在会话间流动。可借鉴：把"占用执行槽"与"会话存活"解耦——idle 不占槽，但 `attachedChannels` 能把 actor 钉活，兼顾资源回收与前台低延迟续接（呼应论点 3）。

> 3. **抢占是"边界感知"的而非硬 kill**。外部 preempt 枚举为 **`allow`/`force`/`never`** 三档（`_2` 由用户命令映射）；`allow` 档优先走**活流注入**（不打断、直接把新批并入当前 turn），退而求其次才在 `tool_use/tool_result/accept` 边界以 `soft` 模式延迟中断（`D`），避免在半个工具调用中截断导致状态损坏；`force` 走 `immediate`。这是有状态 agent 做"打断/续写"的关键取舍（呼应论点 4），值得任何流式 agent 产品照搬。

> 4. **两层锁分工清晰**：进程级 runtime 锁（跨重启、pid+boot_id 探活）解决"同目录多 daemon"；会话级 `si` 异步互斥解决"同会话并发写状态"。前者是运维健壮性，后者是数据一致性——不要用一把锁混着做（呼应论点 2）。

> 5. **能力边界**：actor 之上没有真正的分布式/多进程调度，全在单 daemon 单进程内用 Map+Promise 编排，`wakeResolver` 单槽是 idle↔wake 竞争的唯一同步点；`unhandledRejection` 被吞、`uncaughtException` 直接 `process.exit(1)` 靠外部重启恢复（`78842-78845`）。适合"单机常驻个人 agent"，若要横向扩展会话，需要把内存 `Map _`/池/`si` 换成外部化的租约与队列。


---

## §8 Claude/Codex 对等运行时抽象与路由

**领起结论：`runtime` 只是一个 `claude`/`codex` 两值字符串枚举，却是一层"薄名字、厚差异"的抽象——duoduo 不抹平 SDK（进程内 append-only jsonl）与 app-server（常驻 JSON-RPC 子进程）的差异，而是在选择链（显式声明 > channel frontmatter > `ALADUO_DEFAULT_RUNTIME` > `claude`）与命令层用 `runtime === "claude"` 分支*诚实路由*，靠 `CLAUDE.md → AGENTS.md` symlink 与 protocol 分桶会计跨后端复用同一套指令与溯源。** 下面四个论点自上而下展开这句：①名字很薄（两值枚举 + 诚实的选择链）；②差异很厚（两种不对称的执行形态与探测机制）；③命令层不假装对等（undo/model/compact 逐 runtime 分叉）；④骨架靠复用而非抹平（symlink + 分桶 + 认证短路，但权限/thinking 面故意不对等）。

---

### 论点①　名字很薄：两值枚举 + 诚实的选择链，"显式意图 > 自动兜底"

**所以呢**：runtime 的合法取值只有两个，选择逻辑不玩魔法——它把"用户/actor 明确要 codex"当作不可降级的意图直接放行，只对"从 channel frontmatter 派生出来的 codex"才做可用性门控。这是一条刻意的产品价值排序（尊重显式意图，宁可晚炸也不静默降级）。

- **枚举只有两值，且是两处独立词法作用域的常量、非笔误**：`bqe = ["claude","codex"]`（`daemon.pretty.js:30870`，`FS` init 块内）与并行副本 `R6e = ["claude","codex"]`（`34409`，`h1` init 块）。默认值解析 `tl(e=process.env)`（`30861`）：`ALADUO_DEFAULT_RUNTIME` 非字符串 → `"claude"`；trim/lowercase 后空串 → `"claude"`；`bqe.includes(n) ? n : "claude"`（confirmed）。
- **选择链 A——channel/Job 会话（函数 `p`，`daemon.pretty.js:72058-72071`）**：`if (I?.runtime === "codex") return "codex"`（**`72059`，显式声明 codex 直接返回，不做可用性门控**）→ 无 `source_channel_id` 则 `I?.runtime ?? "claude"` → 否则回溯 `Ps(W).channel_kind → Ec()` 取 frontmatter，`(Y?.runtime ?? F?.runtime) === "codex" && (await l()).ok ? "codex" : I?.runtime ?? "claude"`（`72069-72070`）。可用性探测经记忆化 `l = () => (u || (u = a()), u)`，其中 `a = e.codexAvailability ?? eu`（`72054`，即依赖注入点）。〔原文洞察 #3 引用的 `72058` 应指向直接返回行 **`72059`**〕（confirmed，直接读取核对）。
- **选择链 B——潜意识 partition（函数 `S`，`daemon.pretty.js:74717`）**：`H = x.runtime`（partition frontmatter，`74721`）→ `K = H ?? tl()`（`74722`）。若 `K` 不可用则跳过该 partition 并发 `agent.error{outcome:"runtime_unavailable", runtime:K, runtime_source: H ? "explicit" : "default"}`（`74739-74741`）——注意这条与选择链 A 的失败前移相反，partition 路径*会*显式发不可用事件（confirmed）。
- **"runtime"一词在本运行时被重载两义，须消歧**：`system.runtime.info` RPC（`daemon.pretty.js:78227`）返回的是*守护进程实例身份*——`{version, runtime_id, runtime_mode: host|container, runtime_dir, work_dir, kernel_dir}`（活体实测确认），**不含 `available_runtimes`、与模型后端无关**。本节所讲的 `runtime` 始终指*模型后端*；读者勿把 `runtime.info` 误当成后端探测入口（confirmed，含活体印证）。

### 论点②　差异很厚：两种不对称的执行形态，各带可注入、可去重的探测引擎

**所以呢**：同一个字符串背后是两种根本不同的进程模型。理解"`available_runtimes` 会不会阻塞或重复探测"，必须看到探测被结果缓存 + in-flight promise 双重去重，且两侧都留了测试注入缝——这正是"探测可注入、选择可单测"论断的完整两半。

- **claude = 进程内 SDK，无子进程**：模块顶层静态 `import { query as Wue } from "@anthropic-ai/claude-agent-sdk"`（`daemon.pretty.js:57055`）。可用性同步验证器 `ele()`（`57137`）：`CLAUDE_CODE_EXECUTABLE` 设了就放行（`57138`）；否则平台白名单 6 种、unsupported 抛错（`57143`）；原生二进制 `require.resolve("${u}/claude")` 在其后的 for 循环 `57152-57156`〔原文把二进制 resolve 当作 `57143`，略偏——`57143` 只是平台断言〕（confirmed）。
- **真正的探测引擎是 `Que()`（probeClaudeAvailability，`57087`），5s 超时套在这里而非 `ele`**：`Promise.race([iU()包裹, setTimeout(Kue)])`（`57090-57110`，`Kue = 5e3` 精确在 `57717`）。**双重去重**：结果缓存 `Yc`（读 `57088`、写 `return Yc = r, r` 于 `57111`）+ in-flight promise `Vl`（并发探测复用同一 promise，`57089`）。派生读取 `isClaudeAvailable(oU)= Yc?.ok===!0`（`57118`）、`claudeUnavailableReason(v_)= Yc?.ok===!1 ? Yc.reason`（`57122`）（confirmed，直接读取核对）。
  - 〔订正原文"未证实推测：`Yc` 无写入点"——现坐实为 **confirmed**：写点在 `57111`。〕
- **claude 侧测试注入缝 `iU`**：`iU = Xue = () => ele()`（`57717`），验证器经 `__setClaudeVerifierForTest`（`G9e`，`57134`：`iU=e, Yc=void 0, Vl=void 0`）可替换并清缓存——与 codex 侧的注入缝对称（confirmed）。
- **codex = 外部 CLI + 常驻 app-server 子进程**：探测 `eu(e="codex")`（`57769`）两步各 5s——`execFile(e,["--version"],{timeout:5e3})` 后 `codex login status` 断言 `(i+o).toLowerCase().includes("logged in")`（`57794`）。运行时 `KT.start()` 内 `this.proc = eKe(this.binary, ["app-server"], {cwd, stdio:["pipe","pipe","pipe"], env:{...process.env,...this.env}, detached:!0})`（`58531`），走换行分隔 JSON-RPC（confirmed）。
- **codex 侧缓存是另一对变量 `sU`/`aU`**：`isCodexAvailable(w_)= sU===!0`（`57749`），写点在 `rKe`（primeCodexAvailability，`sU=t.ok, aU=t.ok?void 0:t.reason`，`57757`）与 `iKe`（`sU=e, aU=void 0`，`57761`）。测试注入 `__setCodexAvailabilityForTests: () => iKe` 导出在 `57733`，`iKe` 定义在 `57760`〔原文写 `57722` 系行号漂移，`57722` 无对应〕（confirmed）。
- **`available_runtimes` 由两探针拼装**：会话探针 `ZQe`（`77751`）`s() && c.push("claude"), a() && c.push("codex")`（`77764`），`descriptor.runtime` 经 `VQe`（`77748`）归一化上报 `VQe(f.runtime ?? l?.runtime)`（`77797`），非原样透传（confirmed）。

### 论点③　命令层不假装对等：undo/model/compact 按 `runtime === "claude"` 诚实分叉

**所以呢**：这是本子系统最关键的状态机分叉。因为 Claude 会话是 append-only jsonl（只能"算 cutoff → 下次 drain 才 fork 新 session"），而 Codex app-server 原生支持同步 `thread/rollback`，同名命令在"何时生效、session 是否连续"上根本不同。PM 若设计撤销/回滚体验，不能承诺跨后端统一。

- **`/undo`——Claude 延迟成 fork、Codex 同步 rollback**：Claude adapter `undo()` 只扫 jsonl 算 `cutoff_message_uuid`，返回 `{kind:"succeeded", runtime:"claude", sessionIdChanged:!0, cutoff_message_uuid:f}`（`57690-57697`），不真正改历史；命令层 `j5e`（`61483`）写 `pending_undo:{from, upToMessageUuid, requested_at}`（`61525-61533`），回 `↩️ Undo queued (...)`（`61535`）；真正的 `d5e(F.from,{upToMessageId})`（forkSession，`60184`）推迟到 drain 头部执行，守卫 `z.pendingUndo && (n.runtime === "claude" || n.runtime === void 0)`（`60179`），失败则保留 `pending_undo` 并中止 drain（`60202`）。Codex adapter `undo()` 直发 `thread/rollback{threadId, numTurns}`（`58302`）、同步生效、`sessionIdChanged:!1`（`58310`）；drain 头部 else 分支 `z.pendingUndo && n.runtime !== "claude" → (z.pendingUndo=void 0, Is(...,"pending_undo"))`（`60225`）清掉 codex 会话遗留的 pending（confirmed，逐行核对）。
- **`/model`——Claude 试图即时、Codex 只能延迟 fork**：`setSessionModel` 内 `if (await p(y,j) === "codex")` → 写 `It(...model_runtime: I!==null?"codex":null, pending_model_fork:!0, applied:"stored")`（`74327-74344`）；claude 路径 `q="stored"; setModel 成功→q="live"`，写 `model_runtime:"claude", pending_model_fork:null, applied:q`（`74352-74365`）。codex 回执 `Codex session — a switch takes effect from the next message.`（`76437`）。runtime flip 时经 `!(i ? i!==o : o==="codex")` 守卫清空 `model/model_runtime/pending_model_fork`（`61672-61682`）（confirmed）。
- **codex 侧 fork 时序的落地（与 claude `d5e` 对称的另一半）**：codex thread 生命周期三分支（`57995`）——`forkFrom → "thread/fork"`、`sessionId → "thread/resume"`、else → `"thread/start"`；`z5e`（`61690`，日志 `resolved pending_model_fork at codex drain start`）在 drain 起点把 `pending_fork_to` 设为当前 sessionId，才让 codex 的 model 切换在下一条消息 fork 生效（confirmed）。
- **`/compact`——门控只锁 claude，实际抵达回执的是 codex**：外层守卫 `J.event.routing_hint?.intent === "history-control"`（`60596`）；内层 `if (Zt === "/compact" && (n.runtime === "claude" || n.runtime === void 0))`（`60604`）→ `Oa(t)==="channel" ? Le=!0 :（发 "only available in interactive sessions" + continue）`（`60605-60624`）。`Oa(e)`（`60968`）把 `job:→"job"`、`meta:→"meta"`、`system:|cadence:→"system"`、含 `:` → `"channel"`，否则 unknown。**codex 根本不进这个拦截块**（守卫限 claude/void），落到 `if (!Le)`（`60624`）→ `j5e`（`61483`）→ `r.compact()` → `📦 History compacted (runtime: ${c.runtime})`（`61501`）。所以：claude channel 走 `Le=true` 透传 SDK 原生（不产该串），claude 非 channel 被拦，唯 codex compact 抵达 `61501`（confirmed，codex 路由链已补全）。

### 论点④　骨架靠复用而非抹平：一套指令 + 一套溯源跨后端，但权限/thinking 面故意不对等

**所以呢**：duoduo 不为每个后端各维护一份指令与会计口径，而是靠 symlink 复用同一 system 指令、靠 protocol 分桶让 token 溯源跨后端归位；但它*不*把权限模型与 thinking 可见性也抹平——codex 有沙箱枚举与 reasoning 退订开关，claude 侧没有对应物，两后端的安全/可观测面是诚实的不对等。

- **同一套指令**：codex 会话启动 `cU(e)`（`57808`）若工作目录有 `CLAUDE.md` 而无 `AGENTS.md`，自动 `await n.symlink("CLAUDE.md","AGENTS.md")`（日志 `[codex] created AGENTS.md symlink`，`57813`）——让一套 system 指令喂两个后端（confirmed）。
- **同一套溯源，两套口径**：usage 按 protocol 分桶（`35400`）——`anthropic → cache.anthropic.{drains,cache_read_tokens,cache_create_tokens,fresh_input_tokens}`；`codex → cache.codex.{drains,input_tokens,cached_tokens}`；其余 `unsupported_drains++`。Anthropic 有 cache_creation、Codex 只有 cached，口径不同但都落回同一 drain record（confirmed）。
- **认证来源三态 + `claude_code_local` 短路**（仅 host 模式）：`aGe(e)`（`77378`）三值枚举 `claude_code_local|anthropic_api_key|compatible_endpoint`；env 读取 `EL` 取 `ALADUO_CLAUDE_AUTH_SOURCE ?? ALADUO_AUTH_SOURCE`（`77381-77384`，非法值→void 0）。分派体 `r === "claude_code_local" → return n`（`77502`，提前返回不注入 ANTHROPIC_*）；否则 `for (i of DQe){ o=er(i,null); o.source!=="unset" && (n[Tme(i)]=o) }`（`77503-77506`）注入覆盖。活体 `duoduo daemon config` → `claude_auth_source: claude_code_local (env)`，与短路路径一致（confirmed，含活体印证）。
- **duoduo 向 codex 叠加自有工具，但 codex 内置工具不可禁用**：`disallowedTools` 被显式忽略并告警 `[codex-adapter] disallowedTools ignored — Codex built-in tools cannot be disabled`（`57954`）；另一面握手中 `experimentalApi: !!n.dynamicTools?.length`（**两处 initialize 站点** `57900` 与 `57940`）门控，随后 `for (C of n.dynamicTools) ae.set(C.name, C.handler); r.setToolHandlers(ae)`（`57942-57944`）（confirmed）。
- **权限与 thinking 面故意不对等**：codex 沙箱经 `Gp()`/`ALADUO_CODEX_SANDBOX`（`57765`）映射 `read-only | workspace-write(默认) | danger-full-access`，握手固定 `approvalPolicy:"never"`（`57963`）；`optOutNotificationMethods`（`57902`/`57942`）显式退订 codex 的 reasoning 增量流（`item/reasoning/*Delta`），直接决定 codex thinking 是否回传前端。claude 侧无对应沙箱枚举与退订开关——这是"两后端权限/推理可见性不对等"的开关点（confirmed）。

---

### 证据表

| 机制主张 | 证据（字面量/代码片段） | 位置 | 置信 |
|---|---|---|---|
| runtime 枚举只有 claude/codex（两处独立常量） | `bqe = ["claude","codex"]`；并行副本 `R6e = ["claude","codex"]` | daemon.pretty.js:30870, 34409 | confirmed |
| 默认 runtime 由 ALADUO_DEFAULT_RUNTIME 决定，回退 claude | `tl(e=process.env)`；`bqe.includes(n) ? n : "claude"` | daemon.pretty.js:30861-30868 | confirmed |
| claude=进程内 SDK（顶层静态 import，无子进程） | `import { query as Wue } from "@anthropic-ai/claude-agent-sdk"` | daemon.pretty.js:57055 | confirmed |
| claude 可用性=CLAUDE_CODE_EXECUTABLE 短路 → 平台白名单 → 原生二进制 resolve | `if (h_(process.env.CLAUDE_CODE_EXECUTABLE)) return;`；平台断言；`require.resolve("${u}/claude")` for 循环 | daemon.pretty.js:57138, 57143, 57152-57156 | confirmed |
| 探测引擎 Que()：5s 超时 + Yc 结果缓存 + Vl in-flight 去重 | `if (Yc) return Yc; if (Vl) return Vl;`；`Promise.race([...,setTimeout(Kue)])`；`return Yc = r, r`；`Kue=5e3` | daemon.pretty.js:57087-57114, 57717 | confirmed |
| claude 探测可注入（__setClaudeVerifierForTest 清缓存） | `iU = () => ele()`；`G9e`：`iU=e, Yc=void 0, Vl=void 0` | daemon.pretty.js:57717, 57134 | confirmed |
| codex=外部 CLI，探测 --version + login status（各 5s） | `r(e,["--version"],{timeout:5e3})`；`(i+o).toLowerCase().includes("logged in")` | daemon.pretty.js:57769-57810 | confirmed |
| codex 运行时=spawn app-server 常驻子进程 | `this.proc = eKe(this.binary,["app-server"],{...detached:!0})` | daemon.pretty.js:58531 | confirmed |
| codex 探测缓存 sU/aU + __setCodexAvailabilityForTests（行号订正） | `isCodexAvailable = sU===!0`；`rKe`：`sU=t.ok, aU=...`；export `() => iKe` | daemon.pretty.js:57749, 57757, 57733, 57760 | confirmed |
| available_runtimes 由两探针拼装，descriptor.runtime 经 VQe 归一化 | `s() && c.push("claude"), a() && c.push("codex")`；`VQe(f.runtime ?? l?.runtime)` | daemon.pretty.js:77751, 77764, 77797 | confirmed |
| 选择链 A：显式 codex 直返(不门控)，channel 派生 codex 才门控 | `if (I?.runtime === "codex") return "codex"`（直返 72059）；`...==="codex" && (await l()).ok ? "codex" : ...` | daemon.pretty.js:72058-72071 | confirmed |
| 选择链 B：partition frontmatter ?? tl()；不可用发 runtime_unavailable | `H = x.runtime, K = H ?? tl()`；`outcome:"runtime_unavailable", runtime_source: H?"explicit":"default"` | daemon.pretty.js:74717-74722, 74739-74741 | confirmed |
| runtime.info 暴露 daemon 身份而非模型后端（消歧） | `{version, runtime_id, runtime_mode, runtime_dir, work_dir, kernel_dir}`，无 available_runtimes | daemon.pretty.js:78227（活体印证） | confirmed |
| Claude /undo 延迟成 fork（下次 drain，守卫含 runtime===void 0） | `↩️ Undo queued (...)`；`z.pendingUndo && (n.runtime==="claude"\|\|n.runtime===void 0)`；`d5e(F.from,{upToMessageId})` | daemon.pretty.js:57690-57697, 61525-61535, 60179-60202 | confirmed |
| Codex /undo 同步 rollback、session 不变、清遗留 pending_undo | `r.request("thread/rollback",{threadId,numTurns})`；`sessionIdChanged:!1`；else 分支清 pending_undo | daemon.pretty.js:58302-58310, 60225 | confirmed |
| Codex /model 只能 stored + pending_model_fork；flip 清覆盖 | `model_runtime:...codex, pending_model_fork:!0, applied:"stored"`；`a switch takes effect from the next message.` | daemon.pretty.js:74327-74365, 76437, 61672-61682 | confirmed |
| codex fork 时序：thread 生命周期三分支 + drain 起点 resolve | `forkFrom→thread/fork \| sessionId→thread/resume \| else→thread/start`；`z5e` resolved pending_model_fork | daemon.pretty.js:57995, 61690 | confirmed |
| /compact：外层 history-control 守卫 + claude channel 放行、codex 抵达回执 | `intent==="history-control"`；`Zt==="/compact" && (runtime==="claude"\|\|void 0)`；`Oa(t)==="channel"?Le=!0`；`📦 History compacted` | daemon.pretty.js:60596, 60604-60624, 60968, 61501 | confirmed |
| 认证来源三态枚举 + claude_code_local 短路 | `aGe`；`ALADUO_CLAUDE_AUTH_SOURCE ?? ALADUO_AUTH_SOURCE`；`r==="claude_code_local") return n` | daemon.pretty.js:77378, 77381-77384, 77502-77506 | confirmed（含活体） |
| Codex 内置工具不可禁用/disallowedTools 被忽略 | `[codex-adapter] disallowedTools ignored — Codex built-in tools cannot be disabled` | daemon.pretty.js:57954 | confirmed |
| duoduo 向 codex 叠加 dynamicTools（两处 handshake 站点） | `experimentalApi: !!n.dynamicTools?.length`（57900/57940）；`r.setToolHandlers(ae)` | daemon.pretty.js:57900, 57938-57944 | confirmed |
| codex 会话自动 symlink CLAUDE.md → AGENTS.md | `[codex] created AGENTS.md symlink` | daemon.pretty.js:57808-57813 | confirmed |
| usage 按 protocol 分桶（anthropic vs codex） | `cache.anthropic.{...cache_read/create...}` vs `cache.codex.{...input/cached...}`，其余 `unsupported_drains` | daemon.pretty.js:35400 | confirmed |
| codex 沙箱枚举 + no-approval + reasoning 退订（与 claude 不对等） | `ALADUO_CODEX_SANDBOX`→`read-only\|workspace-write\|danger-full-access`；`approvalPolicy:"never"`；`optOutNotificationMethods` | daemon.pretty.js:57765, 57963, 57902/57942 | confirmed |
| Job frontmatter runtime 语义（默认 claude，显式才用 codex） | `.default(e[0])`；`'claude' (default) uses Claude Code; 'codex' uses Codex (GPT)...` | daemon.pretty.js:68741 | confirmed |
| partition frontmatter runtime 校验（非法回退全局默认） | `a==="claude"\|\|a==="codex" ? c=a : a!==void 0 && Ue("[playlist] ...invalid runtime frontmatter...")` | daemon.pretty.js:42355-42358 | confirmed |

### 关键数据结构 / 事件 / 文件格式（真实字段名）

- **探针返回**（RPC 会话探针 `ZQe`）：`{ configured, session_exists, available_runtimes:["claude"|"codex"], descriptor:{cwd, runtime, display_name, bound_by, require_mention}, kind_defaults:{cwd, runtime} }`；`descriptor.runtime` 经 `VQe()` 归一化后上报，非原样透传（`daemon.pretty.js:77776-77803`）。
- **daemon 身份**（RPC `system.runtime.info`，与后端无关）：`{version, runtime_id, runtime_mode:host|container, runtime_dir, work_dir, kernel_dir}`（`daemon.pretty.js:78227`，活体实测）。
- **state.json 运行时相关字段**：`sdk_session_id`、`pending_undo:{from, upToMessageUuid, requested_at}`、`pending_fork_to`、`model`、`model_runtime:"claude"|"codex"`、`pending_model_fork:boolean`（`daemon.pretty.js:61525, 74327-74344, 61672-61682, 61690`）。
- **partition CLAUDE.md frontmatter**：`runtime: claude|codex`（非法值告警并回退全局默认，`daemon.pretty.js:42355-42358`）；同一 frontmatter 还含 `schedule.{enabled,cooldown_ticks,max_duration_ms}`。
- **undo/compact 结果**：codex `{kind:"succeeded"|"noop"|"failed", runtime:"codex", newSessionId, sessionIdChanged, droppedTurns, triggered_at}`（`58302-58310`）；claude 版多 `cutoff_message_uuid`（`57690-57697`）。
- **usage 按 protocol 分桶**：`cache.anthropic.{drains,cache_read_tokens,cache_create_tokens,fresh_input_tokens}` vs `cache.codex.{drains,input_tokens,cached_tokens}`，其余归 `unsupported_drains`（`daemon.pretty.js:35400`）。
- **codex app-server 握手**：`initialize{clientInfo:{title:"duoduo-runtime",name:"duoduo",version:"0.1.0"}, capabilities:{experimentalApi:!!n.dynamicTools?.length, optOutNotificationMethods:["item/reasoning/summaryTextDelta",...]}}` → `notify("initialized")` → thread 生命周期三分支（fork/resume/start）；沙箱经 `ALADUO_CODEX_SANDBOX`（`Gp`）映射 `read-only|workspace-write|danger-full-access`，`approvalPolicy:"never"`（`daemon.pretty.js:57900-57945, 57963`）。

### 给 Agent PM 的洞察

> 1. **"对等抽象"是薄名字、厚差异，且这层诚实是刻意的。** runtime 只是一个两值字符串，但 claude 是进程内 SDK（append-only jsonl）、codex 是常驻子进程 + JSON-RPC，导致同名操作（undo/model/compact/token 会计）在时序和语义上分叉。抽象层不强行抹平，而是在命令层用 `runtime === "claude"` 分支显式处理——对可维护性是诚实取舍，但意味着每加一个 runtime，history-control 类命令都要补分支。这正是领起结论"薄名字、厚差异、诚实路由"的落点。

> 2. **undo 的"延迟 fork vs 同步 rollback"是能力边界的直接投影。** Claude 会话 append-only，撤销只能"算 cutoff → 下次 drain fork 新 session"，必然延迟且换 session id（`sessionIdChanged:true`）；Codex 原生 `thread/rollback` 可原地同步撤销（`sessionIdChanged:false`）。设计撤销/回滚体验须预期不同后端在"何时生效、session 是否连续"上根本不同，不能承诺统一体验。

> 3. **显式声明的 runtime 不做可用性门控，是刻意的失败前移。** `I.runtime==="codex"` 直接返回（`72059`）不检查登录，而 channel 派生的 codex 才门控 `(await l()).ok`。好处是"用户/actor 明确要 codex 就不静默降级到 claude"，代价是未登录会在 drain 时才炸（partition 路径则显式发 `runtime_unavailable`）。这是"尊重显式意图 > 自动兜底"的产品价值排序。

> 4. **一套指令喂两个后端，靠 CLAUDE.md → AGENTS.md symlink + protocol 分桶复用溯源。** codex 启动自动 symlink（`cU`，`57808`），token 会计按 protocol 分桶归位（`35400`）——多后端框架若想避免"每个后端各维护一份指令/一套溯源"，这是低成本落地范式。§1 已确证 Claude/Codex *共用 `WT` 装配器*（codex 只多套 `<aladuo:system-context>` 壳）：即"装配面共用、执行/命令面分叉"——本节只讲执行异，装配同见 §1。

> 5. **认证来源用 `claude_code_local` 短路，把"本地已登录的 Claude Code"当默认路径**，避免误注入第三方 endpoint env；`compatible_endpoint` 显式承担 wire-format 风险。把"官方本地登录 / 官方 API key / 兼容第三方端点"三态显式建模，比一个布尔"是否自建 endpoint"更能精准分派行为与错误提示。

> 6. **可借鉴的三段式解耦：探测可注入、选择可单测、adapter 可替换。** 可用性探测两侧对称留缝——claude `__setClaudeVerifierForTest`（`57134`，清 `Yc`/`Vl` 缓存）、codex `__setCodexAvailabilityForTests`（`57733`）；运行时选择（`p`/`S`）与 adapter 经 `codexAvailability`/`codexAdapterFactory` 依赖注入（`72054`）。探测被 `Yc` 结果缓存 + `Vl` in-flight promise 双重去重（`57087-57114`），故 `available_runtimes` 不会阻塞或重复拉起验证器——多后端 agent 框架值得照搬。

> 7. **权限与 thinking 可见性故意不对等，PM/安全视角须显式区分。** codex 有沙箱枚举（`ALADUO_CODEX_SANDBOX`，默认 workspace-write）+ 固定 `approvalPolicy:"never"` + reasoning 流退订开关（`optOutNotificationMethods`），claude 侧无对应物。跨后端不要假设"同样的安全边界与推理可观测性"。


---

# 第三部分 · 可信之源：先落日志，再执行 / 入队

> **关键句**：可信来自一条铁律。Spine 的 append-before-execute 把所有状态变成可从日志


---

## §4 Spine / WAL / 事件溯源

**Spine 是 duoduo 唯一的真理之源：一个纯文件 JSONL 预写日志，以「事件先原子 append 再写 mailbox 指针」的 append-before-execute 契约，把所有会话状态、去重、消费进度都变成崩溃后可从「日志 + 指针」精确重建的派生视图——零数据库，顺序靠单进程 promise 链，去重是尽力而为的近似幂等。**

一切都从这条日志派生：会话状态、去重表、消费进度、status，都不是权威数据，而是可丢弃、可从 `var/events/YYYY-MM-DD.jsonl`（按 UTC 日期分区，`HS(e)` 用 `toISOString().slice(0,10)` 切日，`daemon.pretty.js:30944`）加索引重放出来的物化视图。下面四个论点分别回答：**写怎么保证不丢（写路径）、重复怎么处理（去重）、崩溃后怎么读回来（读路径与恢复）、外部怎么观测（读接口与事件全集）**。

### 论点一 · 写路径：先落 WAL、再写指针，且每条事件是「WAL 行 + 两个索引」的三写原子单元

**所以呢**：因为持久化严格早于任何副作用，崩溃后未处理的工作永远能从「mailbox 里的 `- [ ] @evt(id)` 指针 + WAL 行」精确恢复；而单条 append 其实是三次协同写入，`ma`/`nl` 等下游读路径都隐式依赖索引已落盘，构成 `append → 索引 → watermark` 的固定依赖链。

**append-before-execute 的时序在代码里真的这样串联（confirmed）。** 沿网关摄入主函数 `Sne`(`76020`) 的真实控制流：`Xt` 封装事件(`76022`)→`Qt(e,r)` 把不可变事件 append 进 Spine(`76089`)→`ma`/`ha` 推进 watermark 与 status→**之后**才在路由分支写 mailbox 指针（meta 分支 `qo(...)` `76113-76114`，session 分支 `76123-76124`）。路由分叉由 `mne`(`75878`) 决策：`routing_hint.target ∈ {gateway, meta, session}` 决定指针写到 `meta:subconscious` 还是具体 session_key。

**存在第二条同构摄入源 `route.deliver`（会话间路由投递，confirmed）。** 会话→会话的路由投递走 `route.deliver` 全链(`35720-35744`)：先 `Qt(e,f)` append(`35736`)，后 `qo(e,c,\`- [ ] @evt(${f.id})\`)` 写指针(`35744`)，且入口带 `ol()` archived 检查短路。它与 `Sne` 是「先 append 后写指针」的同一契约，是 §4 应认清的第二类摄入源。

**单条 append = 三写原子单元（confirmed，原文只点了一半）。** `Qt()`(`30992`) 内部先 `Tqe()`(`30955`) 写 WAL 行，再写两个索引：`Rqe`(`30983` 定义/`30994` 调用)追加 `by_id`、`OX`(`31012` 定义/`30999` 调用)追加 `by_session`（含 `session_key`+`ts`）。三者对应磁盘 append 与内存 Map 的同步更新——`ma` 反查偏移、`nl` 随机读都**强依赖 by_id 已写入**，这就是 `append → 索引 → watermark` 的隐式依赖链。

**字节区间与全序（confirmed）。** `Tqe()` 执行 `qS.open(i,"a")`(`30962`)→`stat().size` 取 **byte_offset**(`30964`，stat 早于 write)→`write().bytesWritten` 取 **byte_len**(`30966`)→`close`(`30975`)，故 `[offset, offset+len)` 恰为该事件行字节区间。全序由 per-file promise 链保证（应用层互斥，非 fsync/DB 事务）：`xqe`(`30934`) `.then(t,t)` 两回调相同，成功失败都续链，同一分区 append 顺序与偏移计算无竞态。**架构假设**：单 daemon 单进程写；跨进程并发写同一分区无保护。

| 机制主张 | 证据 | 位置 | 置信 |
|---|---|---|---|
| 网关摄入先 append 后写指针 | `Sne`：`Qt`(76089)→`ma/ha`→分支写 `- [ ] @evt(id)`(76113/76123) | daemon 76020-76124 | confirmed |
| route.deliver 同构（含 archived 短路） | `Qt`(35736)→`qo(...@evt)`(35744)，`ol()` 短路 | daemon 35720-35744 | confirmed |
| 路由分叉由 mne 决策 | `routing_hint.target ∈ {gateway,meta,session}` | daemon 75878 | confirmed |
| 单 append = WAL+by_id+by_session 三写 | `Qt`→`Tqe`；`Rqe`(30994)/`OX`(30999) | daemon 30983/31012 | confirmed |
| byte_offset=写前 stat().size，byte_len=bytesWritten | open→stat→write→close | daemon 30955-30975 | confirmed |
| 全序=per-file promise 链 | `xqe` `.then(t,t)` | daemon 30934 | confirmed |
| UTC 日切分区 | `HS(e)` `toISOString().slice(0,10)` | daemon 30944 | confirmed |

### 论点二 · 去重：时间桶 + 内容哈希的近似幂等，命中即幂等重放而非静默丢弃

**所以呢**：去重是「尽力而为」而非严格幂等——它给重复输入回放上一次的网关回执（对渠道体验友好），但内存表满即整表清空会短时丢失去重能力，对副作用敏感的场景不能把它当幂等键。

**三档 key，`channel.command` 的免疫条件需修正（confirmed with correction）。** `YX()`(`75651`，默认窗口 `t=5` min) 按优先级产 key，`<source.kind>` 为前缀。关键修正：`channel.command→null` 的判断在 **source_id 档之后**——`76044` 无条件从 `t.dedupSourceId` 写 `dedup.source_id`（不区分 eventType），故带 `dedup.source_id` 的 command 仍会在优先级 1 命中去重。准确表述是「**无 source_id 的 channel.command 永不去重**」，而非「channel.command 永不去重」。

| 优先级 | 条件 | key 形态 | 行号 |
|---|---|---|---|
| 1 | 有 `dedup.source_id` | `<kind>:<source_id>` | 75654 |
| —（在 1 之后判定）| `type==='channel.command'` 且无 source_id | `null`（不去重）| 75655 |
| 2 | 有 `dedup.hash` | `<kind>:hash:<hash>:<bucket>` | 75656-75658 |
| 3 | 有 `payload.text` | `<kind>:text:<sha256>:<bucket>` | 75660-75663 |

时间桶 `bucket = floor(getTime()/(t*60000))` = `floor(epoch_ms/300000)`（`KX`, `75668`）。活体印证 key 形态 `stdio:text:<sha256>:5942938`，bucket `5942938×300000ms ≈ 2026-07-01T04:50:00Z`，与其 `ts=04:51:51` 同桶。

**命中即幂等重放（confirmed）。** `Sne` 重复分支(`76061`)：`p.duplicate && p.existing?.event_id` → `nl(e, existing.event_id)`(`76062`) 取回原事件 → `jf(e, f.id)`(`76064`) 反查该事件上次生成的 gateway outbox 记录 → 返回 `{deduplicated:true, gatewayResponse:m?.payload.text, gatewayOutboxId:m?.id, routing.enqueued:false}`。`jf`(`34666`) 按 event_id 反查 outbox（`H6e` 索引→`$s`，回退 `Df.find` `in_reply_to_event_id`）。**不重写 mailbox、`enqueued:false`** 均确认——把完整网关回执重放给渠道，这是「去重即幂等重放」的产品语义。

**满即整表 clear（confirmed，真实近似幂等风险）。** 去重存储 `QS`(`75602`)：`maxEntries = n.maxEntries ?? 1e4`(`75607`)，`record()` 中 `entries.size >= maxEntries && entries.clear()`(`75632`)——**满即整表清空（非 LRU）**。磁盘日志经 `fHe`(`75872`) = `registryDir/dedup.jsonl`(`75873`) 仍增长但 clear 后不再 load，故短时间内旧 key 去重能力真的会丢失；`by_id` 不参与 dedup 判定。活体确认路径 `/home/linewalker/.aladuo/var/registry/dedup.jsonl`。

### 论点三 · 读路径与恢复：索引随机读 + 消费者 watermark + rehydrate，把「日志 + 指针」还原成活会话

**所以呢**：正因为写侧同时落了索引，读侧才能 O(1) 随机读、消费者才能续跑、进程重启才能从文件重建活会话集——这是「派生视图可重建」这条塔尖结论的兑现方式。

**索引与随机读（confirmed）。** 两个 append-only 索引懒加载入内存 Map 并随 append 增量更新：`by_id.jsonl` `{event_id, partition, byte_offset, byte_len}`(`30994-30998`) 支撑 `nl()` 随机读 `read(o,0,n.byte_len,n.byte_offset)`(`31033`)；`by_session.jsonl` 追加 `session_key`+`ts`(`30999-31005`)，同 key 累积成 list。首次访问由 `$qe`(`31050`)/`Oqe`(`31060`) 整文件流式 load 进 Map，之后随 append 增量更新——**这正是「随机读 O(1)」的前提**。解析失败回退整文件顺扫 `Aqe`(`31101`，调用点 `31043`)。指针化的价值：mailbox 只存 `@evt(id)` 不存正文，避免正文双写与漂移。

**消费者 watermark（confirmed 结构，但 jobs/gateway 语义需修正）。** `ma()`(`31852`) 先 `UD(e,n)`(`31853`) 经 by_id 反查偏移，再 `s2e` 写 `run/queue_offsets/<consumer>.json`，字段 `{updated_at, partition, byte_offset, last_event_id}`（活体 `jobs.json` 逐字段吻合）。全部 `ma()` 调用点仅 5 处，对应三个消费者：

| consumer | 触发点 | 语义（已修正）| 置信 |
|---|---|---|---|
| `gateway` | 76089 | **网关摄入管线(`Sne`)的高水位，对每一条经 `Sne` 摄入的事件在路由前无条件推进**，覆盖全部摄入事件；非「仅 gateway-targeted 同步不入队」| confirmed |
| `jobs` | 75269 | **由每次 cadence 扫 due-job 的 `system.cadence_tick` 事件推进**（`75269` 位于 cadence_tick 主体 `vme`/job 扫描 `75258-75269` 内，事件类型 `system.cadence_tick` `75260`）；非「由 `job.spawn/complete/fail` 推进」| confirmed（refuted 原说法）|
| `meta_session` | 74747/74902/74926/75040 | 由潜意识/meta partition 事件推进 | confirmed |

  - jobs 的决定性活体证据：`jobs.json` 的 `last_event_id=evt_7e3d…` 在 events 文件里正是 `{"type":"system.cadence_tick",…count:0}`。job 到期扫描本身就是 cadence 循环的一环，故 jobs watermark 挂在 cadence tick 上。
  - gateway 的活体证据：`gateway.json` 的 `last_event_id` 指向一条 `channel.message`（普通摄入事件，非 gateway-targeted 专有）。

**持久化分层（confirmed）。** 消费者进度放**易失 `run/`**（`runQueueOffsetsDir`, `o2e` `31847`；重启可从 WAL 重建），会话游标/state 放**持久 `var/`**（`sessionsDir`；会话身份必须跨重启）。活体 `run/queue_offsets/{gateway,jobs,meta_session}.json` 三消费者齐全——这是「运行时进度 vs 实体身份」的干净范式。

**rehydrate（confirmed，行号微漂移 + 一处未证实）。** `MX()`(`31307`) readdir `sessionsDir` → 逐个读 `<hash>/state.json` 的 `session_key`(`31323`) 重建活跃会话集。自愈写回：缺 `session_key` 时遍历 `registrySessionsDir`(`31329`)、`decodeURIComponent`(`31332`)、`Ai(u)===目录名`(`31333`) 反解，**写回 state.json 实际在 `31335-31339`**（原文引 `31330` 是该自愈块起点，略偏）。resume 失败 append `agent.error{stage:'resume'}`(`60567`, `source.kind='runner'`) 留痕。state.json 的 `schema_version:2` 本轮未在调用链独立复核——**标未证实推测**。

### 论点四 · 读接口与事件全集：spine.tail 尾读 + 十一类落库事件

**所以呢**：外部只能通过 `spine.tail` 观测这条日志，且并非所有 RPC/bus 事件都会落库——只有经 `Xt`+`Qt` 构造的才是 Spine 权威事件，这条边界决定了「真理之源」到底包含什么。

**spine.tail 尾读（confirmed，活体已验证）。** `Hie()`(`77319`)：`limit = clamp(t?.limit ?? 200, 1, 500)`(`77320`)。无 `after_id` → 尾取 N 条 + `has_more = h>0`(`77325-77330`)；有 `after_id` → 当日 `findIndex` 游标之后(`77332`)，未命中则 `setUTCDate(-1)` 回退前一日分区拼接 `[...prev.slice(f+1), ...a]`(`77343-77350`)。活体 `spine.tail limit:3` 现返回 `agent.tool_use/agent.tool_result`（`source.kind=meta`, `name=subconscious:memory-committer`, `session_key=meta:subconscious`）——**此为取样示例，返回何种事件取决于探测时点**（原文「3×system.cadence_tick」同理只是彼时取样）。

**事件类型全集（需修正：补 `route.deliver`）。** 经 `Xt` 封装并 `Qt` 落库的合法 Spine 事件：

```
channel.message / channel.command / channel.attached
agent.result / agent.error / agent.tool_use / agent.tool_result
job.spawn / job.complete / job.fail
system.cadence_tick
route.deliver                                 ← 会话→会话路由投递，Qt(35736)，原「全集」漏列
```

`GROUND_TRUTH` 中的 `channel.ack/ingress/pull/spawn/describe`、`session.*`、`job.completed/spawned` 等**未见** `Xt`+`Qt` 构造点，属 RPC/bus 而非 Spine 落库，原文正确地未纳入。潜意识产出**复用** `agent.result`：`source.kind=meta`, `name=subconscious:<partition>`(`74887`), `payload.tick_type='subconscious'`(`74896`)，活体亦印证。

| 机制主张 | 证据 | 位置 | 置信 |
|---|---|---|---|
| spine.tail limit clamp [1,500] 默认 200 | `Hie` `clamp(...??200,1,500)` | daemon 77320 | confirmed |
| after_id 未命中回退前一日 | `setUTCDate(-1)` + 拼接 | daemon 77343-77350 | confirmed |
| 落库事件含 route.deliver | `Xt`+`Qt(35736)` | daemon 35722/35736 | confirmed |
| 潜意识复用 agent.result | `tick_type:'subconscious'` | daemon 74887/74896 | confirmed |

> **给 Agent PM 的洞察**
> - **真理之源 = 纯文件 JSONL WAL，零数据库依赖**：所有派生态（会话状态/去重/消费进度/status）都可从「日志 + 指针」重建，极简、天然可审计、git-friendly——这正是本节塔尖结论的运营含义。
> - **append-before-execute 是可靠性契约的基石，且有两条摄入源**：网关摄入（`Sne`）与会话间路由（`route.deliver`）都遵守「先原子 append、再写 `- [ ] @evt(id)` 指针」；崩溃后从「mailbox 指针 + WAL」精确恢复未处理工作，mailbox 只存指针不存正文。
> - **单条 append 是三写原子单元**：WAL 行 + by_id + by_session，下游 watermark 反查与随机读强依赖索引已落盘；要横向扩展写侧，必须同时打破「单进程 promise 链保序」与「三写同步」两个假设。
> - **去重是尽力而为、命中即幂等重放**：5 min 时间桶 + 内容哈希，无 `source_id` 的 `channel.command` 永不去重；命中回放上次网关回执（`deduplicated:true`, `enqueued:false`），但内存 Map 满即整表 clear 会短暂丢失去重能力——对重复副作用敏感的场景，产品侧需知这不是幂等键。
> - **watermark 语义要看清挂点**：`jobs` 游标挂在 `system.cadence_tick`（因 due-job 扫描是 cadence 一环），`gateway` 是整条摄入管线的高水位而非「目标同步」标记——误读会导致对「谁消费到哪」的错误运维假设。
> - **持久化分层（run/ 可重建 vs var/ 必须留存）** 是区分「运行时进度」与「实体身份」的干净范式；UTC 日切分区同时是潜意识 scan-gap「做梦」的工作单元，日志分区即时间盒。


---

## §5 Gateway 边界 / RPC / 通道协议

**Gateway 是 daemon 唯一的 loopback 单端口控制面：它把所有外部输入收敛为 if/else 分发的 JSON-RPC，入站即按斜杠命令 / intent 分流（gateway 内联短路 / session 唤醒 / meta 潜意识），并以「先落 spine 日志 → 再追加 Markdown 邮箱 → 最后 emit `session.wake`」的 WAL-before-enqueue 时序保证崩溃可重放，对外用零依赖 protocol 契约同时支持 HTTP 拉（drain）与 WS 推（订阅 + backlog 回放）两种通道形态——它是整个 agent「输入可靠化与是否动用模型」的边界闸门。**

下面四个论点自上而下支撑这句结论：控制面的**形态**（单端口 if/else）→ 入站的**分流闸门**（能不进模型就不进）→ 可靠性的**时序契约**（WAL-before-enqueue）→ 对外的**双通道数据面 + 契约包**。

---

### 论点 1 · 单端口 loopback 控制面：一个 fastify 实例 + 一条 if/else 分发链

**所以呢**：整个 daemon 对外只有一个可确定的物理边界——一个绑在 `127.0.0.1` 的端口、一条巨型 if/else 链。没有服务发现、没有鉴权、没有路由表抽象，安全边界完全押在「本机单用户」假设上。这让控制面极易审计，也划死了它的产品边界：这是单机自治 runtime，不是可暴露的多租户服务。

- **一个 fastify 实例，只注册 5 个 HTTP 入口。** `GET /healthz`（`xne()` 返回 `{status:"ok"}`，`76156`）、`GET /readyz`（就绪探针 `kne`，`76145`）、`GET /dashboard`（把 `bootstrapDir/dashboard.html` 作为静态文件读出，读不到 catch 回 404，非在线渲染，`78149-78158`）、`POST /rpc`（`78616`）、`GET /ws`（fastify-websocket，包在 `t.register(async function(g){…})` 内以 `g.get("/ws",{websocket:!0})` 注册，`78627`）。监听 `ALADUO_PORT ?? PORT ?? 20233`、host `ALADUO_DAEMON_HOST ?? "127.0.0.1"`（`78892-78893`）。活体 `:20233/healthz → {"status":"ok"}`。
  - **`readyz` 语义要点**：`kne`（`76145`）实为「能否 append 到 events 日志文件」的探针，未就绪回 `503 not_ready`——它探的是 spine 写入能力，而非泛化的「服务活着」。
  - **20234 / save-api 不存在于本 build**：三份代码 grep `20234|save-api|save_api` 皆空、活体 `curl :20234` 无 HTTP 响应（升格为**已证实**，非推测）。

- **RPC「注册表」实为一条巨型 if/else 链，不是 Map。** 所有方法在同一个 `async function h(g, v)`（起于 `78166`）内按 `g.method` 字符串逐个分派，`v` 携带 WS 上下文（`wsSubscriberId`）。链上分发的**远不止 channel.\* 方法**，而是全套 handler：`system.runtime.info`（`78227`）、`session.archive/list/set_alias/notify/compact`（`78247-78266`）、`channel.file.upload/download`（`78365/78373`，活体 `channel.file.upload → -32602` 证明 handler 存在）、`channel.ingress/command/pull/ack`、`job.create/get/list`（`78447-78507`）、`usage.get`（`78508`）、`system.status`（`78539`）、`system.config`（`78589`）、`spine.tail`（`78592`）、`system.shutdown`（`78624`）。**只有真正未匹配的方法才落链尾 `-32601 Method not found`**（`78600-78602`；活体 `bogus.method → {"code":-32601}` 复现）。

- **请求体守卫 `Hg` = protocol 的 `isJsonRpcRequest`。** `Hg`（`76528-76531`）：`t.jsonrpc==="2.0" && typeof t.method==="string"`（另含 object 判空）。`POST /rpc` 未过守卫直接 `400`（`78618`）。**WS 侧同用 `Hg`，但未过回的是 JSON-RPC `-32600 Invalid Request`（`78676-78684`），不是 HTTP 400**——两条传输的失败形态不同。入参校验用 protocol 导出的 `isXxxParams` 守卫（如 channel.pull 的 `zf`），失败抛 `bn("Invalid params")` → `-32602`；未捕获异常统一 `-32603 Internal error`。

- **`system.shutdown` 能直接自杀。** `/rpc`（`78624-78625`）与 WS（`78767-78768`）均 `__triggerShutdown → setImmediate(()=>process.kill(process.pid,"SIGTERM"))`。控制面自带「关掉我自己」的能力，进一步印证其单机信任模型。

---

### 论点 2 · 入站即分流闸门：斜杠命令 / intent 决定「要不要动用模型」

**所以呢**：这是本节最值得抄的一条。routing target 三态（`gateway` / `meta` / `session`）在**入站边界**就决定一条消息要不要真正唤醒一个 agent。`/status /config /cd /debug` 这类命令在网关层被内联短路、根本不进模型；只有带内容的消息才唤醒 session。对话式 agent 想省 token，这就是「入站即分流、能不进模型就不进」的实现样板。

- **真正的 target 决策在入口 wrapper `wne` → `pHe`，不在 `Sne` 内。** handler 收到 channel.ingress/command 后，先由 `wne`（message，`75969`）/ `L1`（command）做**斜杠命令解析**再调 `Sne`——`wne` 里 `D1(t.text)` 判斜杠命令、`Rk` 取命令、`j1` 判 intent，再喂 `pHe`（`75963`）裁 target：带参内容 → `session`，`status/config/navigate/debug` 类 intent 或纯命令 → `gateway`（内联短路、不进模型）。这一层命令预处理是「洞察 #5」的真实机制所在，此前文档直接跳到 `Sne` 掩盖了它。
- **`mne` 只是读取器，不是决策器。** `mne`（`75878`）仅 `return routing_hint.target ∈ {gateway,meta,session} ? … : "session"`——它读回 `pHe` 已写进 `routing_hint` 的结果。`Sne` 内 `d = mne(r)`（**落点 `76101`**）据此分三路。
- **三路的落地形态**：`gateway` → `mHe`（`76103`）内联应答，返回 responseText/outboxId 并 log `[gateway] gateway-targeted event (no enqueue)`，**完全不入队、不唤醒**；`meta` → 写 mailbox key `"meta:subconscious"`（`76114`）；`session` → 写 `t.sessionKey` 的 mailbox（`76124`）。
- **channel.ingress 的入站守卫**：`Ni(w.session_key)` 命中归档中 → `-32011`（`78274-78277`）；workspace 不可用 → `-32010, message:R.guidance`（`78287-78290`）。`source_kind` 缺省按传输层推断 `w.source_kind ?? (v?.wsSubscriberId ? "ws" : "rpc")`（`78278`）。

---

### 论点 3 · WAL-before-enqueue：先落盘、后入队、最后唤醒，崩溃可重放

**所以呢**：可靠性不靠队列中间件，而靠一条铁律——事件先原子 append 进 spine 日志，才追加进 mailbox，才 emit 唤醒。任何一步崩溃都能从「spine log + mailbox 指针」精确复原。代价是「队列」就是纯 Markdown 文件，吞吐/并发靠文件锁与内存索引兜底。

- **精确落点在 `Sne`（gateway 入站规范化，`76020`）。** 顺序：`Xt()` 构造 spine 事件（`76022`）→ 幂等去重 `checkAndRecordDetailed`（`76056`；命中则复用既有事件、`enqueued:!1`，经 `jf` 反查既有 outbox 回填 `gatewayResponse/gatewayOutboxId` 原样返回，即「去重即重放上次回执」，`76064-76073`）→ `yHe` 把原始 payload 持久化为 `raw_path`（`76078`）→ **`await Qt(e, r)` 把事件 append 进 spine 事件日志（这是 WAL，`76089`）** → `ma` 更新索引（`76089`）→ `d = mne(r)` 决定 routing target（`76101`）→ 只有 session/meta 目标才 `qo(…,"- [ ] @evt(<id>)")` 追加进 mailbox（enqueue，`76124/76114`）→ 最后 `bus.emit("spine.event", r)`（`76134`）。
- **`session.wake` 不在 `Sne` 内**，而由**调用方**在 `routing.enqueued` 为真时 emit：channel.ingress（`78312`）、channel.command（`78357`）、另一 gateway 调用方（`78024`）。即「先事件落盘 → 后入队 → 最后由调用方唤醒」。
- **channel.ack 是双路径游标提交**（`78420-78446`）：按 `:` 前缀 channel 反查 `$s`/`Vte` 走一路；否则直接 `uo` 查记录、必要时 `kk` 重建后经 `qne`/`J1` 提交投递游标——含 `-32602 Invalid cursor` 游标校验分支与 `-32002` 归档中守卫。它不只是「置 sent」，而是带校验与归档态的游标推进。

---

### 论点 4 · 对外双通道数据面 + 零依赖契约包：HTTP 拉（drain）vs WS 推（订阅 + backlog 回放）

**所以呢**：同一个 `channel.pull` 方法对简单适配器（只 poll HTTP）和富客户端（订阅长连流）各取所需，而两端共享同一个随包发布的编译期契约，杜绝手抄漂移——这是想做 Agent 平台化的解耦支点。**关键更正**：RPC 才是 drain，WS 根本不 drain。

- **RPC 形态 = drain，且门控于 `return_mask` 含 `"final"`。** `T = R.includes("final")`（`78385`）；`P = T ? await G1({… limit: w.limit ?? Number(process.env.ALADUO_PULL_LIMIT ?? 50) …}) : []`（`78398/78402`），返回 `records / next_cursor(P[last].id) / idle(P.length===0)`（`78405-78412`）。不含 `final` 则 records 恒为空。
- **WS 形态 = 打开持久订阅 +（含 `final`）回放 backlog，records 不在 RPC result 里返回。** WS 上下文里 channel.pull **直接短路、根本不 drain**：`if(v?.wsSubscriberId) return await UQe({…}), _.result={opened:!0, …}, _`（`78386-78397`）——不调 `G1`、result 里无 records。真正的排空在 WS 外层 message handler：`O.result && !O.error` 后 `l.subscribe`（`78702`）打开订阅，再由 `Bne` 以 `session.output` 通知形式回放 outbox backlog（`78736`）。**`G1` drain 仅 RPC 路径独有**；此前文档把 RPC 的 drain 语义误挂到了 WS 上。
- **replay 窗口去重**：`ALADUO_SUBSCRIBE_REPLAY_LIMIT ?? 0`（`78733`），期间用 `w = new Set` 抑制重复（`suppressed duplicate output during replay window`，`78708-78709`）；`onDelivered` 推进游标 `W1`、`gl` 标 sent、`Lf` 写 `.sent_ids`（`78744-78748`）。WS 送信器 `R(P,E)`（`78638-78660`）正常推 `session.output` 时若 `E` 且有 consumerId 则 `W1` 推进投递游标；replay 期用 `R(_e,!1)` 关闭该副作用、改由 `onDelivered` 推进——这是「replay 不重复推进游标」的关键。
- **订阅注册表 `H1`（`76752`）做 sessionKey→订阅者扇出。** `Map<sessionKey,Set<id>>` + `Map<id,subscriber>`，按每订阅者 `returnMask`（默认 `["final","stream"]`，`76757`）过滤：`final`→`session.output`（`76766`）、`stream`→`session.stream`（`76792`）、`tool`→`session.execution`（`76816`）、`stream_end`（`76831`）；发送异常 `catch{d(v)}` 自动摘除订阅者。`returnMask` 值域校验器是 `y2`（`77557-77561`：`final|stream|stream_end|tool`，空回退 `["final","stream"]`），默认掩码常量在 `H1@76757`（此前文档引 `76595` 为幻影行号）。
- **stream_end reason 能力降级契约**：`H1` 内 `m==="interrupted" || v.acceptStreamEndReasons?.includes(m) ? m : "interrupted"`（`76840`），与 WS 订阅透传 `acceptStreamEndReasons`（`78706`）一致——daemon 按消费者声明的能力把不认识的 reason 降级为 `"interrupted"`，老插件优雅退化。
- **零依赖契约包 `@openduo/protocol@0.5.8`**（`"dependencies":{}`、`"main":"src/index.ts"`，源码 `.ts` 随包发布，位于 `@openduo/duoduo/node_modules/@openduo/protocol/src/`）：`rpc.ts` 信封与守卫、`channel.ts` 全部 params + 校验器 + `outboxToOutbound`、`outbox.ts` `OutboxRecord`/`TurnMeta`、`notifications.ts` 4 种下推、`channel-binding.ts` `ChannelType`。通道插件以 npm tarball 安装（`cli.pretty.js:116315`：`mkdtemp aladuo-channel-plugin-`、`tar -xzf`、`package.installing` 标记）。
- **outbox 落盘**：id `obx_${randomUUID()}`（`34552`），路径 `join(outboxDir, t, `${n}.json`)`（`34556`）；双索引 `by_event.jsonl`（`34708`）/`by_id.jsonl`（`34809`）+ `.sent_ids`（`34712`）+ `replay/`（`34788`）+ `.pending_queue.jsonl`（`35137`）。

---

### 证据表

| 机制主张 | 证据（字面量/片段） | 位置 | 置信 |
|---|---|---|---|
| fastify 单端口网关，注册 healthz/readyz/dashboard/rpc/ws | `t.get("/healthz"…xne())`, `t.get("/dashboard"…)`, `t.get("/readyz"…kne)`, `/rpc`, `g.get("/ws",{websocket:!0}…)` | daemon:78149-78159/78616/78627 | confirmed |
| readyz 探针 kne = 能否 append events 日志，否则 503 not_ready | `await kne(n) ? {status:"ok"} : v.code(503).send({status:"not_ready"})` | daemon:76145/78159 | confirmed |
| 端口默认 20233、host 127.0.0.1 | `Number(process.env.ALADUO_PORT ?? process.env.PORT ?? 20233)`；`ALADUO_DAEMON_HOST ?? "127.0.0.1"` | daemon:78892-78893 | confirmed |
| RPC 是 if/else 链而非 Map；链含 system./session./job./usage./spine./channel.* 全套 handler；仅未匹配 →-32601 | `async function h(g,v)` 起 78166；`system.runtime.info`/`session.*`/`job.*`/`usage.get`/`spine.tail`/`channel.file.upload`；链尾 `-32601` + 活体 `bogus.method→-32601` | daemon:78166/78227/78247/78365/78447/78508/78592/78600-78602 | confirmed |
| 请求体守卫 Hg = isJsonRpcRequest；/rpc 未过 400，WS 未过 -32600 | `Hg`：`t.jsonrpc==="2.0" && typeof t.method=="string"`；活体 `{"method":"x"}→400` | daemon:76528-76531 / 78618 / 78676-78684 | confirmed |
| WAL：事件先 append 再入队 | `await Qt(e,r)`（append 事件日志，76089）在 `qo(…,"- [ ] @evt(…)")` 入队之前 | daemon:76089 / 76114/76124 | confirmed |
| routing target 决策在 wne→pHe（斜杠命令/intent），mne 仅读取器 | `pHe`：intent status/config/navigate/debug 或纯命令 →gateway；`mne` return target∈{…}?…:"session" | daemon:75963-75975 / 75878 | confirmed |
| Sne 内 mne 落点 + spine.event emit | `d=mne(r)`（76101）；`bus.emit("spine.event",r)`（76134） | daemon:76101 / 76134 | confirmed |
| session.wake 由调用方按 routing.enqueued 触发（非 Sne 内） | `X.routing.enqueued && emit("session.wake"…)` | daemon:78024 / 78312 / 78357 | confirmed |
| gateway 目标事件内联应答、不入队 | `[gateway] gateway-targeted event (no enqueue)`；meta 写 `"meta:subconscious"` | daemon:76103-76114 | confirmed |
| protocol 零依赖契约包，源码随包发布（嵌套路径） | `"dependencies":{}`、`"main":"src/index.ts"`；`ChannelRpcMethods = describe｜spawn｜ingress｜command｜pull｜ack` | @openduo/duoduo/node_modules/@openduo/protocol/src/{channel,rpc}.ts | confirmed |
| channel.ingress：archiving 守卫 -32011、workspace 守卫 -32010 | `code:-32011`（`Ni(w.session_key)`）；`code:-32010,message:R.guidance` | daemon:78274-78290 | confirmed |
| source_kind 缺省按传输层推断 | `w.source_kind ?? (v?.wsSubscriberId?"ws":"rpc")` | daemon:78278 | confirmed |
| channel.pull RPC = drain，门控 return_mask 含 "final" | `T=R.includes("final")`；`P=T?await G1({… limit… ??50}):[]`；返回 records/next_cursor/idle | daemon:78385/78398/78402/78405-78412 | confirmed |
| channel.pull WS = 打开持久订阅 + backlog 回放，不 drain、records 不在 result | `if(v?.wsSubscriberId) return await UQe(…), _.result={opened:!0,…}`（无 records）；外层 `l.subscribe`；`Bne` 回放 backlog | daemon:78386-78397 / 78702 / 78736 | confirmed |
| channel.pull replay 窗口去重 + 游标推进 | `ALADUO_SUBSCRIBE_REPLAY_LIMIT ?? 0`；`suppressed duplicate output during replay window`；`onDelivered`→W1/gl/Lf | daemon:78733 / 78708-78709 / 78744-78748 | confirmed |
| channel.ack 双路径提交 + -32602 invalid cursor / -32002 归档 | `:` 前缀反查 `$s`/`Vte` 一路；`uo`+`kk`+`qne`/`J1` 一路；游标校验 -32602、归档 -32002 | daemon:78420-78446 | confirmed |
| outbox 落盘 `<kind>/<id>.json`，id=obx_<uuid> | `obx_${randomUUID()}`（34552）；`join(outboxDir,t,`${n}.json`)`（34556） | daemon:34552 / 34556 | confirmed |
| outbox 双索引 by_event/by_id + .sent_ids + replay + pending_queue | `by_event.jsonl`, `by_id.jsonl`, `.sent_ids`, `replay/`, `.pending_queue.jsonl` | daemon:34708/34712/34788/34809 / 35137 | confirmed |
| 订阅按 returnMask 扇出三类通知 + 异常摘除 | `session.output`(76766)/`session.stream`(76792)/`session.execution`(76816)/`stream_end`(76831)；默认 `["final","stream"]`；`catch{d(v)}` | daemon:76752-76840 | confirmed |
| returnMask 校验值域 | `y2`：`"final"|"stream"|"stream_end"|"tool"`；空则回退 `["final","stream"]` | daemon:77557-77561 / H1 默认 76757 | confirmed |
| stream_end reason 降级契约（代码侧落点） | `m==="interrupted"||v.acceptStreamEndReasons?.includes(m)?m:"interrupted"`；WS 透传 `acceptStreamEndReasons` | daemon:76840 / 78706 / protocol channel.ts:79-83 | confirmed |
| system.shutdown 自杀 | `/rpc` 与 WS 均 `__triggerShutdown` → `setImmediate(()=>process.kill(process.pid,"SIGTERM"))` | daemon:78624-78625 / 78767-78768 | confirmed |
| 20234 save-api 不存在于本 build | grep `20234\|save-api\|save_api` 三文件皆空；活体 `curl :20234 → 000 无响应` | — | confirmed（活体+静态） |

### 关键数据结构 / 事件 / 文件格式（真实字段名）

- **JSON-RPC 信封**（`rpc.ts`）：请求 `{jsonrpc:"2.0", id?, method, params?}`；响应 `{jsonrpc:"2.0", id, result? | error:{code,message,data?}}`。错误码：`-32700` parse、`-32600` invalid request（WS 守卫失败落此，非 400）、`-32601` method not found、`-32602` invalid params / invalid cursor、`-32603` internal；业务码 `-32010`（workspace 不可用）、`-32011`（**channel.ingress** 归档守卫，`78274`）、`-32002`（**channel.ack** 归档守卫，`78420-78446`；语义同为归档中，挂在不同方法）。

- **RPC 方法清单**（daemon if/else 链 `h(g,v)` 实际分发的全集，非仅 channel.\*）：
  - `system.runtime.info`（`78227`）、`system.status`（`78539`）、`system.config`（`78589`）、`system.shutdown`（`78624`，触发自身 SIGTERM）
  - `session.archive / list / set_alias / notify / compact`（`78247-78266`）
  - `job.create / get / list`（`78447-78507`）
  - `usage.get`（`78508`）、`spine.tail`（`78592`）
  - `channel.describe / spawn / ingress / command / pull / ack`（`ChannelRpcMethods` 联合类型），外加 `channel.file.upload / download`（`78365/78373`）
  - **其余（真正未匹配的方法）落链尾 → `-32601 Method not found`**
  - `outboxToOutbound`（`channel.ts:336`）为出站记录→通道 outbound 的投影函数（非 RPC 方法，随契约包导出）
  - 注意：`session.wake / spine.event / cadence.tick` 是**总线事件**不是 RPC；`session.output / stream / execution / stream_end` 是**服务端→客户端通知**（`notifications.ts`），仅在 WS 上单向下推

- **`OutboxRecord`**（`outbox.ts`，磁盘 `outboxDir/<channel_kind>/<id>.json`）：`id, idempotency_key, created_at, channel_kind, session_key, in_reply_to_event_id?, routing:{policy:"reply_to_origin"|"reply_override"|"fanout", origin_event_id, origin_session_key, origin_channel_kind, fanout_index, fanout_total}, payload:{text?, attachments[], data?, rendering_hints:{format:"markdown"|"text"|"card", mentions[]}}, stream:{stream_id, seq, is_final}, status:"pending"|"sent"|"failed", attempts, last_attempt_at, last_error`。

- **`TurnMeta`**（`outbox.ts:13`，投影到 `payload.data.turn_meta`，供通道渲染卡片页脚）：`elapsed_ms, total_input_tokens, output_tokens, cache_hit_rate, total_cost_usd, model, context_used_tokens, protocol:"anthropic"|"codex"`。

- **索引/游标文件**（同 outboxDir）：`index/by_event.jsonl`（event_id→记录，用于 in_reply_to 反查，内存缓存 `b1`）、`index/by_id.jsonl`、`.sent_ids`（已投递集合，内存缓存 `Ute`）、`replay/<session_key>.jsonl`、`.pending_queue.jsonl`。

- **channel.ingress params**：`{session_key, display_name?, text?, idempotency_key?, cwd_abs?, attachments[], source_kind?, channel_id?}`；返回 `{event_id, gateway_response, outbox_id}`。`source_kind` 缺省按传输层推断 `wsSubscriberId?"ws":"rpc"`（`78278`）。

- **channel.pull params**：`{session_key, consumer_id, cursor?, limit?, wait_ms?, return_mask:("final"|"stream"|"stream_end"|"tool")[], channel_capabilities:{outbound:{accept_mime[], max_bytes?, accept_stream_end_reasons?[]}}}`。返回形态因传输而异：RPC 回 `{records, next_cursor, idle}`（含 `final` 时）；WS 回 `{opened:true, session_key, consumer_id, cursor, return_mask}`（records 走订阅推送，不在 result 内）。

- **服务端下推通知**（`notifications.ts`）：`session.output{session_key,record}`、`session.stream{session_key,chunk,is_sidechain?}`、`session.execution{session_key,event:(tool_use|thought_chunk|tool_result|tool_input_delta)}`、`session.stream_end{session_key,reason:"interrupted"|"skipped"}`。

- **邮箱入队标记**（enqueue 的物理形式）：向 mailbox 文件追加一行 `- [ ] @evt(<event_id>)`；meta 目标写入 mailbox key `meta:subconscious`。

### 给 Agent PM 的洞察

> 1. **入站即分流，是「输入闸门」而非「消息队列」——这才是本节的塔尖。** routing target 三态（gateway/meta/session）在 `wne`→`pHe` 阶段就据斜杠命令 / intent 判定，`/status /config` 类命令直接内联回执、不入队不唤醒，等于在网关层做一次廉价的「是否需要动用模型」短路。对话式 agent 若想省 token，可借鉴这种「入站即分流、能不进模型就不进」的分层——它把「代码守骨架、模型做裁决」的边界物化在了控制面第一跳。

> 2. **WAL-before-enqueue 是可靠性核心，但入队媒介是 Markdown 邮箱文件而非队列中间件。** 事件先 append 进 spine 日志（`Qt`）再往 mailbox 追加 `- [ ] @evt(id)`，崩溃可重放；幂等命中时「去重即重放上次回执」（回填 `gatewayResponse/gatewayOutboxId`），语义完整。代价是「队列」就是纯文件，吞吐/并发靠文件锁与内存索引缓存（`b1/Ute`）兜底——适合个人级自治 agent，规模化到多租户高并发时这层会成瓶颈。

> 3. **「契约包 + 拉/推双形态」是通道生态的解耦支点，但拉/推语义并不对称。** RPC 是 drain（`G1` 排空，门控 `final`），WS 是订阅 + backlog 回放（`opened:true` 短路，records 走推送）——同一个 `channel.pull` 让「简单适配器只 poll、富客户端订阅流」各取所需，且共享随包发布的零依赖 `.ts` 契约避免手抄漂移。设计通道协议时，务必写清「同一方法在不同传输上返回形态不同」，否则极易误以为 WS 也 drain。

> 4. **能力协商做了向后兼容的「降级而非报错」。** `accept_stream_end_reasons`/`accept_mime` 让 daemon 按消费者声明的能力下调输出（不认识的 stream_end reason 降级为 `interrupted`，`76840`），新语义对老消费者优雅退化。做长期演进的 agent 协议时，这种「生产者按消费者能力下调输出」比版本号更抗腐蚀。

> 5. **控制面刻意极简、无鉴权、绑定 loopback。** 单端口、if/else 分派、默认 `127.0.0.1`、`/rpc` 无 token 校验——安全边界完全押在「本机单用户」假设上；`system.shutdown` 甚至能直接 `SIGTERM` 自身。作为产品能力边界要清楚：这是单机自治 runtime，不是可暴露的多租户服务。

（相关文件：`daemon.pretty.js:78149-78811`（fastify/RPC/WS）、`75963-75975`（pHe/wne 分流）、`76020-76134`（Sne WAL 入站）、`78024/78312/78357`（session.wake 触发点）、`34540-34820 / 35137`（outbox 落盘与索引）、`76752-76840`（订阅扇出/降级）；`@openduo/duoduo/node_modules/@openduo/protocol/src/{rpc,channel,outbox,notifications,channel-binding}.ts`。）


---

# 第四部分 · 后台自治：靠心跳自我维护而绝不越权

> **关键句**：无人对话时，运行时靠心跳自我维护。潜意识引擎经活动门节流后唤起无状态一次性 LLM 分区会话做维护（§6），记忆系统只做只读测量与软删 GC、一切内容改写交回模型（§7）；机器真正强制的只剩契约门。心跳先转，才有 memory-weaver 加工经验——收束回 §0 的闭环。


---

## §6 Cadence 心跳 / Subconscious 引擎

**潜意识引擎是 duoduo 的"自主神经系统"：一条 37 分钟心跳，经内存指纹活动门节流后，按用户可改写的 playlist 轮流唤起一批无状态一次性 LLM 分区会话做自我维护；全部跨拍状态落在文件，而机器真正强制的边界只剩契约门 `pL` 与 `disallowedTools` 两处。** 这句话统辖本节四个论点：心跳的**节拍与解耦**、潜意识引擎的**三重节流门**、分区的**无状态执行与两级路由**、以及**唯二的机器强制边界**。以下每个论点先给结论，再落 file:line 证据（行号已对齐 beautified，均随活体 daemon 印证）。

---

### 论点 1 · 一条心跳、两级解耦：emit 广播不被维护环阻塞，60s cron 是另一条独立定时器

**所以呢：** duoduo 把"系统自我维护"、"任务调度"、"自主思考"分到不同节拍/不同门，慢的 LLM 会话拖不垮维护与定时作业。此前分析把它们混成"一个心跳两个环"是误读——实为**两条互不相干的定时器**，且潜意识总线在心跳回调里被最先广播、绕过维护环重入门。

- **37min 心跳**：`let D=Cme("ALADUO_CADENCE_INTERVAL_MS",222e4,1e3)`（`daemon.pretty.js:78916`），env 可覆盖、带 `1e3` 最小 clamp；活体 `duoduo daemon config` → `interval_ms: 37min (2,220,000ms) (default)`。单个 `setInterval` 回调体第一个表达式就是 `f.emit("cadence.tick")`（`78921-78922`），**在 `if(H){...skipped...;return}` 重入门之前**；随后 `H=!0; o(d).then(...).finally(()=>H=!1)` 才跑维护环（`o`=runCadenceTick，解构自 `78829`，调用点 `78928`）。故潜意识总线不受维护环 `H` 阻塞。（confirmed）
- **60s job-scheduler 是另一条定时器**：pid0 里 `A=s({paths,sessionManager})`（`78911`）、`A.start()`（`78915`）单独启动，到期 cron 扫描 `h2` 在 `75279` 起。与 37min 心跳完全解耦，不属维护环。（confirmed；原稿"78908"应为 `78911`）
- **维护环 `SQe`（`75239`）顺序**：`await Yp(e),await Qp(e)`（`75240`）→ `runMemoryCheckTick`（`75245`）→ `sweepTombstonedSessionRecords`（`75251`，try/catch 非致命）→ `_me`（`75257`）→ `vme`（`75258`）→ 构造 `type:"system.cadence_tick"`（字面量在 `75260`，`payload.count` 在 `75266`）→ `Qt/ma` 持久化 + `ha(...cadence:{last_tick:r.ts})`（`75269`）。（confirmed；原稿"emit 在 75258"应为 type 字面量 `75260`、count `75266`，机制无误）
- **`Yp/Qp` 是 broadcast lint，`_me` 才是队列合并**：`Yp`（`59584`）`stat(memoryBroadcastPath)`、`Qp`（`59761`）`readFile` → 检测未解析 wiki 链，断链时 `enqueuedLintTask:!0`、日志 `"[memory] CLAUDE.md has unresolved wiki links; queued lint task"`；`_me`（`75179`）读 `cadenceInboxDir` 的 `.pending`、`kQe(r,i)` 合并进 `cadenceQueuePath`（`75209`）、`75213` unlink 已并文件、返回 `i.length`。（confirmed）

---

### 论点 2 · 潜意识引擎靠总线事件驱动，三重门把固定节拍变成事件驱动的自适应节奏

**所以呢：** 引擎自身没有定时器，只挂在心跳总线上；三重门（重入/停机、内存指纹活动门、cooldown/backoff）联合实现"没有新证据就不空转"——把固定 37min 节拍变成随记忆变更自适应的节奏。

- **总线挂载、非自持定时器**：`_Qe`（`74661`）内 `n.on("cadence.tick",w)`（`75058`），日志 `"[meta-session] started, listening for cadence ticks"`（`75064`）。`w`（`75044`）是去重包装：记在途 promise `p`，若 `l||d` 直接 `b()` 不追踪。（confirmed；原稿日志"75063"应为 `75064`）
- **门一 · 重入 + 停机**：`74981 if(l||d){...skipping tick...;return}`——`l`=processing、`d`=stopRequested，**独立于维护环 `H` 的第二套门**。（confirmed）
- **门二 · 内存指纹活动门**：`74991` 处 `let[x,R,T,P,E]=await Promise.all([$I(memoryFragmentsDir),$I(memoryEntitiesDir),$I(memoryTopicsDir),mQe(t),hQe(t)]),O=[...].join(":"),A=fQe(O)`；`74992 if(m!==null&&A===m){...activity gate: skipping tick (fingerprint unchanged)...}` 整跳。（confirmed；原稿指纹"74987"应为 `74991`）
- **门三 · cooldown / backoff（round-robin 选择器 `_`, `74967`）**：逐项 `74969 done→skip`；`74971 !A||!enabled→return O`（交由 `v` 用 `zx` 勾掉推进）；`74973 backoff(f2)→continue`；cooldown 判定在 `74974-74976`：`H=Math.max(0,A.schedule.cooldown_ticks),K=g.get(O.name); if(K===void 0||T-K>=H) return O`（`g`=分区→上次 tick 序号 Map，`74675`）。失败退避 `m2`（`74487-74500`）是**线性、非指数**：`success/invalid_output→null`（`74488`）；timeout `74491 if(t<=2)return null` 后 `min(t*i,sQe)`（`74492`）；error `74496 if(t<=1)return null` 后 `min(t*2*i,aQe)`（`74497`）；常量 `sQe=72e5(2h)/aQe=144e5(4h)/p2=222e4`（`74512`）。`f2`（`74482`）读 `backoff_until` 判定退避中；`v` 在选取前后各读一遍全分区 state，用 `f2` 过滤出本拍 `backedOff`（`74708-74710`）。（confirmed；原稿 cooldown 段"74971"精确片段应为 `74974-74976`）
- **选取 + 空闲补跑**：`75005 K=await v(D,H,h)`；`75006 if(K?.name&&c>1&&(!r||r.activeCount()<=1)) for(z=1;z<c&&await v(...);z++)`，`c=maxPartitionsPerIdleTick??2`（`74675`）。（confirmed）
- **同拍二次 broadcast lint（易漏节点）**：除维护环 `SQe:75240` 外，`b` 里在分区选取**之前**又跑一遍 `await Yp(t),await Qp(t)`（`75002`）。（confirmed）

---

### 论点 3 · 分区是无状态一次性 LLM 会话；playlist 是可自改写的纯文本状态机，且存在"确定性入队 + LLM 出队"两级路由

**所以呢：** 调度不硬编码 cron，而是 agent 自己能改写的 `playlist.md` checkbox 轮次 + 分区 frontmatter；每分区是一次性 SDK 会话，"除了写进文件的都不记得"，跨 tick 协作全靠 inbox 与共享 `memory/`。

- **playlist 状态机**：`np`（`74680`/def `42371`）、`YWe`（`42389`）只解析 `## Current Round`，`- [x]`=done、`- [ ]`=未做，遇下一 `## ` 停。`zx`（`42410`）把 `- [ ] <name>`→`- [x]`（`42420`）、造 `- <ISO> executed=<name>`（`42422`）、splice 进 `## History`（`42424`）。整轮全勾时 `Wie`（def `42428`）用 `n=t.filter(s=>s.schedule.enabled)`（`42430`，按 name 排序）重建 round，日志 `"[playlist] rebuilt round" {count,names}`（`42468`）；`v` 内 `74682 if(await Wie(t)===0) return null` 进 idle。（confirmed；原稿"42456 filter enabled"应为 `42430`、History 行"42427"应为 `42422/42424`）
- **分区执行 `S`（`74717`）**：无状态一次性 SDK 会话 `persistSession:!1`（`74819`）；提示词 `74796 C = 正文 + "### Partition"(ae 74791) + R(gQe 上下文, 调用点 75004) + Ze(yQe inbox, 74790)`；超时 `ke=Math.max(1,x.schedule.max_duration_ms)`（`74846`）、`74849 setTimeout(()=>F(Fe),ke)`、`74852 O=await Promise.race([$e,wn])`。结果四分类由 `lQe(x.name,lme(O?.text))`（`74865`）判定——其中 `invalid_output` 是"跑成功但产物不合格"的唯一判定点。成功落 `agent.result tick_type:"subconscious"`（`74896`），失败落 `agent.error stage:"partition_execution"`（`74917`）；并写一条 `_l` usage drain record（`74869`，`session_key: meta:subconscious:<partition>`，`cancelled:E==="timeout"`）——这正是 `usage.get` 能显现潜意识开销的动态节点。runtime 由 frontmatter claude/codex 选（`KWe 42355-42357`）。（confirmed；原稿超时"74847"应为 `74846`）
- **上下文注入**：`gQe`（`74644`）建 `## Runtime Context` + `### Key Paths`（kernel/memory/entities/topics/fragments/registry/events/jobs/cadence inbox·queue/subconscious 目录清单）；`yQe`（`74651`）建 `## Inbox`（含 memory-weaver 专属 Stage1/Stage2 提示，`74655`）。（confirmed）
- **两级路由（易漏节点）**：`_me`（`75179`）只做**确定性**的 `.pending`→`queue.md` 合并；真正把 `queue.md` 的 checkbox 任务**路由进各分区 directed inbox** 的是 `cadence-executor` 这个 **LLM 分区**（其 `CLAUDE.md` 自述 dispatcher 角色："route checkbox tasks from the shared cadence queue into the directed inbox"）。即 `_me`（确定性入队）+ cadence-executor（LLM 出队分发）两级。（confirmed，磁盘实证）
- **原"未证实推测"已解开**：`cadence-executor: enabled (cooldown 1, timeout 10min)` 在代码里搜不到，因为它是**用户数据里的分区名，不是代码**——磁盘实证 `subconscious/cadence-executor/CLAUDE.md` frontmatter `schedule:{enabled:true,cooldown_ticks:1,max_duration_ms:600000}`；`daemon config` 的 `[Subconscious]` 段就是逐分区渲染各自 frontmatter schedule（经 `KWe:42345` 解析）。10min≠默认 60s 只是该分区**覆盖了 `eL` 默认（`eL={enabled:!0,cooldown_ticks:1,max_duration_ms:6e4}`, `42513-42516`）**。四分区 `cadence-executor/memory-committer/memory-weaver/pattern-tracker` 的 cooldown 1/3/5/7、timeout 10/30/35/15min 均为 per-partition frontmatter 覆盖。（原"未证实/待查"→ confirmed：per-partition frontmatter 覆盖）

---

### 论点 4 · 机器真正强制的边界只有两处：契约门 `pL` 与 `disallowedTools`；memory lint 全程只读、契约门控

**所以呢：** 自治 agent 的"自我修改"必须区分"提示词约束"（软、模型可违反）与"运行时强制"（硬、不可绕过）。软边界写在提示词；机器强制的关键不变量只落在契约门与工具禁用两处，memory lint 只做只读测量。

- **契约门 `pL`（`43609`）= 6 拒因 + null 放行**：`partition-absent`（`43610`）/ `self-id-mismatch`（`43611`）/ `partition-disabled`（`43612`）/ switch `valid→consumes.has(e)?null:"kind-not-consumed"`（`43615`）/ `no-contract→n?null:"no-contract"`（`43617`）/ `parse-fail→n?null:"parse-fail"`（`43619`）——第三参 `n`(flagFallback) 可放行后两者。（原稿"5+2 态"标签改为更准确的"6 拒因 + null 放行"。契约状态由 `uL:43474` 读分区 CLAUDE.md 的 `contract:` frontmatter 产出）（confirmed）
- **`pL` 是双重角色门（易漏节点）**：不仅逐项裁决投递，还能**整拍短路** lint——`runMemoryCheckTick`（`43679`）里 `43698 a=qJe(()=>Eoe(s)); 43699 if(!a&&!r) return o`，`Eoe`（`43623`）内部对所有契约调 `pL`，若无任何契约 consume 任何 kind（且未开 forget），整个 memory-check tick 直接空返。（confirmed）
- **lint 全程只读、每类每 tick 至多一条、契约门控**：受 `gL`（`43656`）读的 `ALADUO_EXP_MEMORY_CHECK`(check) 与 `ALADUO_EXP_MEMORY_FORGET&&check`(forget，依赖前者) 开关。子步：`43707 orphan-states`（无条件）；check 门内 `43712 board-lint / 43715 entity-lint / 43718 node-lint / 43721 gap-lint / 43724 orphan-newborn-island`；forget 门内 `43729 orphan-forget`。投递经 `xoe`（`43571`）→ posted/withheld，投递前按 `cL`（`43451`）按内存节点路径路由到分区名（`rel.startsWith("topics/")&&(slug lesson-/groove-)?"pattern-tracker":"memory-weaver"`，`orphan-forget` 分支 `43737 Toe(s,cL(p))`）。活体 `daemon status`：`memory_check: check=off forget=off (posting governed by partition contracts below)` + 4 条 contract。（confirmed）
- **自编程硬边界 `disallowedTools`**：`g_=["EnterPlanMode","ExitPlanMode","AskUserQuestion","WebFetch","WebSearch","EnterWorktree"]`（`57708`）→ `ne=[...g_]`（`74810`）→ `disallowedTools:ne`（`74826`）。（confirmed）
- **`system.cadence_tick` 是 Spine 事件、非 RPC（动态印证）**：活体 `spine.tail` 复现 `system.cadence_tick` 事件流，紧随 `agent.tool_use/tool_result(memory-weaver)` → `agent.result tick_type=subconscious partition=memory-weaver` → `pattern-tracker`，动态印证 round-robin 顺序执行分区、每分区落 `agent.result`。（confirmed，动态）

---

### 证据表

| 机制主张 | 证据（字面量 / 代码片段） | 位置 | 置信 |
|---|---|---|---|
| 心跳周期 `Cme("...",222e4,1e3)`，env 可覆盖、带 1e3 clamp | `interval_ms: 37min (2,220,000ms) (default)` | `daemon.pretty.js:78916`；`duoduo daemon config` | confirmed |
| 单 `setInterval` 同拍先 emit `cadence.tick` 再跑维护环，emit 在重入门 `H` 之前 | `f.emit("cadence.tick"); if(H){...return}; H=!0; o(d)...finally(()=>H=!1)` | `daemon.pretty.js:78921-78928` | confirmed |
| cron 扫描 `h2` 属独立 60s job-scheduler，非维护环 | `A=s({...}); A.start()`；`h2` 到期扫描 | `daemon.pretty.js:78911/78915`、`75279` | confirmed（更正原稿 78908→78911） |
| 维护环 `SQe` 顺序：Yp/Qp→memcheck→sweep→_me→vme→emit→落 last_tick | `await Yp(e),await Qp(e)`…`type:"system.cadence_tick"`…`ha(...cadence:{last_tick})` | `daemon.pretty.js:75240/75245/75251/75257/75258/75260/75266/75269` | confirmed |
| `Yp/Qp`=memory broadcast lint（非队列合并）；队列合并是 `_me` | `Qp` 断链 `enqueuedLintTask:!0`；`_me` `kQe` 合并 `.pending`→`cadenceQueuePath` | `daemon.pretty.js:59584/59761`、`75179/75209/75213` | confirmed |
| 潜意识环靠总线事件、非自持定时器 | `n.on("cadence.tick", w)`；`"[meta-session] started, listening for cadence ticks"` | `daemon.pretty.js:75058/75064` | confirmed |
| 门一 重入/停机：`l`(processing)/`d`(stopRequested) 独立于维护环 H | `if(l||d){...skipping tick...;return}` | `daemon.pretty.js:74981` | confirmed |
| 门二 活动门：内存指纹不变则整跳 | `A=fQe([$I(...),$I(...),$I(...),mQe,hQe].join(":"))`;`if(m!==null&&A===m){...activity gate...}` | `daemon.pretty.js:74991/74992-74994` | confirmed（更正 74987→74991） |
| 门三 cooldown：`T-K>=H` 才选中 | `H=Math.max(0,cooldown_ticks),K=g.get(name); if(K===void 0||T-K>=H) return O` | `daemon.pretty.js:74974-74976` | confirmed |
| 失败退避线性、2h/4h 封顶、前 1–2 次宽限 | timeout `t<=2` 免、`min(t*i,72e5)`；error `t<=1` 免、`min(t*2*i,144e5)`；success/invalid→null | `daemon.pretty.js:74487-74500`、`74512` | confirmed |
| `v` 用 `f2` 读 `backoff_until` 过滤本拍 backedOff | `f2` 判退避；`backedOff` 报告 | `daemon.pretty.js:74482`、`74708-74710` | confirmed |
| 空闲补跑：maxPartitionsPerIdleTick 默认 2、仅活跃会话≤1 | `c=maxPartitionsPerIdleTick??2`;`if(K?.name&&c>1&&(!r||r.activeCount()<=1)) for(...)` | `daemon.pretty.js:74675`、`75006` | confirmed |
| playlist 状态机：解析/勾选/History/整轮重建 | `YWe` 只解析 `## Current Round`；`zx` `- [x]`+`executed=`；`Wie` filter enabled 重建 | `daemon.pretty.js:42389`、`42420/42422/42424`、`42428/42430/42468`、`74682` | confirmed（更正 42456→42430、42427→42422/42424） |
| 分区无状态、超时=max_duration_ms、四分类由 `lQe` 判 | `persistSession:!1`;`ke=Math.max(1,max_duration_ms)`;`Promise.race`;`lQe(name,lme(text))` | `daemon.pretty.js:74819/74846/74849/74852/74865` | confirmed（更正 74847→74846） |
| 成功/失败落 Spine + usage drain record | `agent.result tick_type:"subconscious"`;`agent.error stage:"partition_execution"`;`_l` drain `cancelled:E==="timeout"` | `daemon.pretty.js:74896/74917/74869` | confirmed |
| 上下文注入 gQe(路径清单)/yQe(inbox) | `## Runtime Context`+`### Key Paths`；`## Inbox`(memory-weaver Stage1/2) | `daemon.pretty.js:74644/75004`、`74651/74790` | confirmed |
| 两级路由：`_me` 确定性入队 + cadence-executor LLM 出队分发 | `_me` `.pending`→`queue.md`；cadence-executor CLAUDE.md 自述 dispatcher | `daemon.pretty.js:75179`；`subconscious/cadence-executor/CLAUDE.md` | confirmed |
| cadence-executor 等四分区 = 用户数据分区，schedule 覆盖 eL 默认 | frontmatter `schedule:{enabled:true,cooldown_ticks:1,max_duration_ms:600000}`；`eL={...,cooldown_ticks:1,max_duration_ms:6e4}` | `subconscious/*/CLAUDE.md`；`daemon.pretty.js:42345/42513-42516`；`duoduo daemon config` | confirmed（原"未证实"已解开） |
| 契约门 `pL`：6 拒因 + null 放行，双重角色（逐项 + 整拍短路） | `kind-not-consumed`/`partition-absent`/`self-id-mismatch`/`partition-disabled`/`no-contract`/`parse-fail`；`if(!a&&!r) return o` | `daemon.pretty.js:43609-43619`、`43474`、`43623`、`43698-43699` | confirmed |
| memory lint 只读、每类≤1条、受 check/forget 门；路由 `cL` | `orphan-states`/`board`/`entity`/`node`/`gap`/`orphan-newborn-island`/`orphan-forget`；`cL` 路由分区 | `daemon.pretty.js:43656/43679/43707/43712-43729`、`43451/43571` | confirmed |
| 自编程硬边界：`disallowedTools` | `g_=["EnterPlanMode","ExitPlanMode","AskUserQuestion","WebFetch","WebSearch","EnterWorktree"]`；`disallowedTools:ne` | `daemon.pretty.js:57708`、`74810/74826` | confirmed |
| `system.cadence_tick` 是 Spine 事件而非 RPC 方法 | `type:"system.cadence_tick", source:{kind:"system",name:"cadence"}, payload:{count}`；`spine.tail` 复现 | `daemon.pretty.js:75260`；活体 `spine.tail` | confirmed（动态） |

### 关键数据结构 / 事件 / 文件格式（真实字面量）

- **`playlist.md`**：`# Subconscious Playlist` / `## Current Round`（`- [ ] <name>` / `- [x] <name>`）/ `## History`（`- <ISO> executed=<name>`）。`YWe` 只解析 `## Current Round` 段。
- **分区 frontmatter**：`schedule:{enabled:bool, cooldown_ticks:int, max_duration_ms:int}`（默认 `eL={enabled:!0,cooldown_ticks:1,max_duration_ms:6e4}`，per-partition 可覆盖，如 cadence-executor 覆盖为 600000）；可选 `runtime: claude|codex`；`contract:{partition:string, consumes:string[]}`。
- **分区状态文件**（`partitionStateDir`, `uv`/`d2`, `74933/74944`）：`{last_started_at,last_finished_at,last_result,consecutive_failures,backoff_until}`，`last_result ∈ success|timeout|invalid_output|error`。
- **定向 inbox**：`var/subconscious/<partition>/inbox/*.pending` 与 `*.json`（`Jie`, def `42473`）；pending body 为一行队列行、换行结尾。
- **cadence 队列**：`var/cadence/queue.md`（checkbox 任务行），`.pending` 暂存文件在 tick 内由 `_me` 确定性合并入队，再由 cadence-executor LLM 分区出队分发到各 directed inbox。
- **Spine 事件**：`system.cadence_tick`（source `{kind:"system",name:"cadence"}`，payload `{count}`）、`agent.result`（`tick_type:"subconscious", partition, runtime`）、`agent.error`（`stage:"partition_execution", outcome`）、`job.spawn`。
- **usage drain record**（`_l`, `74869`）：`session_key: meta:subconscious:<partition>`，含 `tool_calls/tool_errors/usage/cancelled(=E==="timeout")`——`usage.get` 可见。
- **contract 门 `pL` 裁决集**：`null`（放行）/ `kind-not-consumed` / `partition-absent` / `self-id-mismatch` / `partition-disabled` / `no-contract` / `parse-fail`。

### 给 Agent PM 的洞察

> **1. 两条定时器 + 独立门是清晰的关注点分离，别误读成"一个心跳两个环"。** 确定性维护（memory lint + 墓碑清扫 + 队列合并，幂等、跑在 37min 心跳上，重入门 `H`）与到期 cron 调度（`h2`，独立 60s job-scheduler，自己的定时器与门）各自独立；LLM 分区执行（非确定性）再复用心跳但用独立 `l`/`d` 门与 `H` 解耦。呼应本节结论：慢的 LLM 会话拖不垮维护与定时作业。

> **2. playlist 是可被 agent 自己改写的纯文本状态机，调度分"确定性入队 + LLM 出队"两级。** 调度不是硬编码 cron，而是 `playlist.md` checkbox 轮次 + 分区 frontmatter；`_me` 只做确定性 `.pending`→`queue.md` 合并，真正的任务分发交给 cadence-executor 这个 LLM 分区。代价是依赖文件锁/单进程串行保证一致性。

> **3. 能力边界"软 + 硬"双层，机器真正强制的只有契约门 `pL` 与 `disallowedTools`。** 软边界写在提示词（禁改 spine/lock/其他分区 CLAUDE.md，模型可违反）；硬边界一是 `disallowedTools`（禁 WebFetch/WebSearch/PlanMode/EnterWorktree），二是 `pL` 契约门——它既逐项裁决 lint 产物能否进某分区 inbox（6 种拒因），又能在无契约 consume 时整拍短路掉 memory-check。关键不变量必须落在运行时强制、而非提示词。

> **4. 多重"不空转"节流把固定节拍变成事件驱动的自适应节奏。** 活动门（内存指纹未变即跳过）、`cooldown_ticks`（每分区最小间隔）、失败**线性**退避（`m2`，2h/4h 封顶且前 1–2 次宽限）、`maxPartitionsPerIdleTick`（空闲多跑但有上限、仅活跃会话≤1 补跑）。可复用的省成本模式：定时轮询 + 变更指纹门控 + 每任务冷却 + 失败退避。

> **5. 无状态分区 + 文件即记忆，开销在 usage drain record 里可观测。** 每分区一次性 SDK 会话，"除了写进文件的都不记得"；跨 tick 协作全靠 inbox `.pending` 与共享 `memory/`，每次执行写一条 `session_key: meta:subconscious:<partition>` 的 drain record，`usage.get` 可显现潜意识开销。代价是每 tick 冷启动的上下文重建，靠 `gQe` 注入路径 + `yQe` inbox 摘要弥补。


---

## §7 记忆系统

**记忆系统把"某条知识还有没有用"物化为 board→`[[link]]` 图可达性 + effectiveness 轨迹证据：daemon 侧只做只读、每类每 tick 至多一条、契约门控的 lint 测量，与带 48h 宽限 + 双 flag + git 软删的孤儿 GC，绝不改内容；一切改写交给 memory-weaver 三段流水线在自己的 tick 上按"事件→fragment→effectiveness→改板"可复算链完成——即"代码测量、模型裁决"的记忆自治架构。**

这条结论把本节拆成四个 MECE 论点：**(A)** 效用被物化成一张 markdown 知识图，可达性 = 效用；**(B)** daemon 侧全部动作是只读、每类每 tick 单条、契约门控的测量，永不改内容；**(C)** 唯一的破坏性动作（孤儿 GC）被 48h 宽限 + 双 flag + git 软删三重封住；**(D)** 内容改写整段委派给 memory-weaver 三段流水线。下面逐点先说"所以呢"，再给证据。

---

### A. 效用被物化为图可达性 —— board 是唯一"根"，`[[link]]` 闭包决定谁还活着

**所以呢**：记忆系统不靠时间戳或访问计数判断一条知识是否"还有用"，而是把它翻译成一个纯几何问题——从广播板 `CLAUDE.md` 出发，沿 `[[slug]]` wiki-link 做可达性闭包，触达不到的 topics 节点就是 orphan。这让"效用"成为可确定、可复算的图属性，daemon 无需理解语义即可测量。

**A1 · 目录结构就是这张图的物理布局。** `Ac(e)`（`42522`–`42530`）恰好返回 **5 个字段**：`memoryDir`（根目录）+ `boardPath`（`CLAUDE.md` 文件，即广播板 / 唯一"根"）+ 3 个子目录 `entitiesDir` / `topicsDir` / `effectivenessDir`。

```
memoryDir/
  CLAUDE.md          ← boardPath：广播板 / 直觉层（可达性的唯一"根"）
  entities/          ← 实体档案
  topics/            ← 节点：lesson-* / groove-*
  effectiveness/     ← 每条 board 行一份效果轨迹（附属证据层）
  fragments/<date>/  ← scanner 证据；★ 不在 Ac 内，由 gap-lint/scanner 独立引用
  state/meta-memory-state.json  ← ★ 也不在 Ac 内，属另一路径（meta-memory）
```

> 修正：现有文档写"4 个子路径 + memoryDir + boardPath"是自相矛盾的措辞（boardPath 被算了两次）。正确表述 = memoryDir + boardPath（文件）+ 3 个子目录。`fragments/` 与 `state/meta-memory-state.json` **都不在 `Ac` 内**（旧文档只标注了 fragments/，漏标 state/）。

**A2 · 可达性 BFS 把"效用"算成不动点。** 种子来自 `Pl(e).filter(oL)`（`42929`），其中 `Pl`（`42561`）用手写解析器 `sy`（`42536`）扫 board 上全部 `[[...]]`——`sy` 遇第一个 `]` 即止（`42544`）。`op(e,t)`（`42927`）从种子 BFS 到不动点（`42932`–`42942`），reader `ip`（`42912`）读每个 slug 的 `topics/<slug>.md` + `entities/<slug>.md`。**不在可达集内的 topics 节点 = orphan**，这是整个 lint/orphan 体系的核心几何。

**A3 · effectiveness 是附属证据层，不能独立支撑可达性。** `ip` 仅当 topics/entities 至少一存在（`i.length>0`，`42918`）才追加读 `effectiveness/<slug>.md`（`42919`–`42920`）。即：孤立的 effectiveness 文件不阻止其 slug 成为 orphan——effectiveness 是轨迹证据，不是节点本体。这处"非对称守卫"由 `42918` 逐字印证。

---

### B. daemon 侧只做只读测量：每类每 tick 至多一条、契约门控，永不改内容

**所以呢**：整个 `runMemoryCheckTick` 是一台"体检仪"而非"手术刀"。它把五类 lint 的最差单条结果打包成 `.pending` 证据文件投递给潜意识分区收件箱，自己绝不 touch 任何知识内容。三个约束——每类单条节流、契约门控、只读——共同保证测量廉价、可审计、无副作用。

**B1 · 主循环逐 lint `try/catch` 隔离，且投递执行器是 `xoe` 而非门控函数。** `UJe`（`43679`=`runMemoryCheckTick`，导出于 `43646`）逐个用 `$l(...)` 包裹（`43750` try/catch），单个子 lint 崩溃不中断其余。真正的**投递执行器是 `xoe`（`43571`）**：它 `mkdirSync(inbox)` → 写 `pendingFilename` → 分类 posted/withheld/errors（`43589`–`43604`），`already-pending`（`43598`）与 `--force`（`43578`）逻辑都在这里；`UJe` 的闭包 `u`（`43701`）把每个 lint 的 selected 结果喂给 `xoe`。门控函数 `pL` 只是 `xoe` 内部的 gate 判定，不是投递本身。

**B2 · 五类 lint，kind 全部 `.v1`。** 五个调用点（`43713`–`43728`）：

| lint | 调用点→本体 | 产出信号 | 判据要点（含精度修正） |
|---|---|---|---|
| **board-lint** | `Qie(c,mL)` `43713`→`42803`（逻辑 `dJe` `42867`） | REVISE / SINK / MERGE | 见 B3 |
| **entity-lint** | `ioe` `43715`→`42979`（`pJe`） | `entity-converge.v1` | entity 缺收敛四段 `roe=["What it is now","Relationship","Open variables","Trend"]`（`43026`）；打分 `kb*1e3+dated`（`42995`） |
| **node-lint** | `soe` `43718`→`43057`（`_Je` `43045`） | `node-converge.v1` | 见 B3 |
| **gap-lint** | `loe(e.eventsDir,c)` `43721`→`43215` | `scan-gap.v1` | 见 B3 |
| **orphan** | `hoe(l)`+`_oe(yoe(l),t)` `43724`–`43728` | `orphan-newborn.v1` / `orphan-islands.v1` | NEWBORN→warn，ISLAND→weaver note（见 C） |

kind 值全部带 `.v1`（`Kr` 表 `42651`–`42660`）。

**B3 · 各 lint 判据的精度修正**（旧文档过度简化处）：

- **board-lint（`dJe` `42867`）**：REVISE 过滤 = `trajectory!=='NO-EFF' && cls==='behavioral' && fmt==='legacy' && !(WEAKENING && (REMOVE||DROP))`，partition **硬编码 `'pattern-tracker'`**（`42876`，不经 `cL`）。**修正**：`SINK`（`42880`）与 `MERGE`（`42889`）**也含 `trajectory!=='NO-EFF'` 前置**（旧文档只在 REVISE 提及）。trajectory（STRENGTHENING/NEUTRAL/WEAKENING via `QWe`）与 verdict（PRESERVE/KEEP/REMOVE/REWRITE/SHARPEN/DROP via `tJe`）从 effectiveness 文件解析。
- **node-lint（`_Je` `43045`）**：`escalated=!reachable`（`soe` `43084`），escalated 时打 `WASTED-COMPUTE`（`43052`）。**修正**：合法 section 由 `gJe`（`43030`–`43031`）判——`Condition`/`Procedure` 恒合法，`References` **仅 groove 合法**（lesson 用 References 也算非法 section）；旧文档"非 Condition/Procedure/References"未区分节点类型。
- **gap-lint（`loe` `43215`）**：黑名单 `wJe`（`43247`）过滤内部 source kind，只把外部事件当证据。链路：`kJe`（`43127`）列 `var/events/<date>.jsonl` → `xJe`（`43142`）列已有 `fragments/<date>/` → `EJe`（`43156`）按 `o.source?.kind` 过滤黑名单计数（`43178`）→ `TJe`（`43188`）合小时 band。黑名单 `pQe` 在 **`75094`** 复用（`74606` 调用）——"外部 vs 内部事件"是代码库稳定的领域概念。**动态印证（值为时点快照，已漂移）**：机制 confirmed；具体值今日（2026-07-01）活体 `duoduo memory check --dry-run --json` 为 `"gap":{"date":"2026-07-01","bands":[[4,4]]}`（旧文档写的 `2026-06-30 bands=[[19,19]]` 是上一日快照）。

**B4 · 每类每 tick 至多一条（`mL=1`）。** `mL=1`（`43775`）是每类 lint 的默认 limit：`dJe`/`ioe`/`soe` 都 `slice(0,n)` 只取**最差 1 条**（help 的 `--limit=N default 1`）。即每 tick 每类最多投一个 worst-first 信号——这是"测量廉价"的核心节流，旧文档未提。

**B5 · 契约门控 `pL`：只有声明 `consumes` 的分区才收到对应信号。** `pL`（`43609`）分支：partition-absent / self-id-mismatch / `!enabled` → withheld；contract valid → `consumes.has(kind) ? 放行 : 'kind-not-consumed'`；no-contract / parse-fail → 回退 flagFallback（= check flag）。契约解析本体 `uL`（`43474`）返回 5 态（partition-absent / parse-fail / no-contract / self-id-mismatch / valid），`Yie`（`42645`）把 consumes 名规范化补 `.v1`；`fL`（`43565`）把每分区契约缓存进 `e.contracts` Map，同 tick 内 `pL`/`Eoe`/`Toe` 复用同一份，避免反复解析 frontmatter。

**B6 · 前置短路：没有下游读者就不测量。** `Eoe`（`43623`）在跑任何 lint 前遍历所有 `Kr` × `zJe=['pattern-tracker','memory-weaver']`（`43640`），任一 kind 过闸即测量；`if(!a && !r) return`（`43699`）——"有没有订阅者"是是否测量的前置门。

> 修正（`cL` 定位过泛）：旧文档把 `cL`（`43451`）描述为通用"路由"。实际 `cL` **仅两处调用**：orphan-newborn 分区路由（`43339`）和 forget 警告门 `Toe`（`43737`）。**各 lint 信号的 partition 是每类硬编码的**（REVISE/NODE_CONVERGE→pattern-tracker；SINK/MERGE/ENTITY_CONVERGE/SCAN_GAP/ORPHAN_ISLANDS→memory-weaver），并不走 `cL`。`cL` 只决定 lesson-/groove- 孤儿告警投给哪个分区。

---

### C. 唯一的破坏性动作被三重封住：48h 宽限 + 双 flag + git 软删

**所以呢**：daemon 唯一会删文件的地方是孤儿 GC，而它被设计成"几乎不可能误删"——先把孤儿分成三态给足宽限，再要求两个实验 flag 同开，最后即使删也只是 git 软删（历史可恢复），且"没被警告过就不许删"。对自治 agent 的记忆安全，"遗忘 = 可逆软删除"是关键设计。

**C1 · Orphan 三态状态机（`moe` `43311`）给 STALE 之前留足宽限。** `moe` 套壳 `$Je`（`43261`，真正算 orphans/indeg/mtime），状态判定（`43323`–`43324`）：

```
age = mtimeMs>0 ? (refTimestampMs - mtimeMs)/poe : +∞     (poe = 3600*1e3, 43469)
indeg >= 1                → ISLAND    （被别的档案引用，但 board 不可达）
else age < r              → NEWBORN   （r = newbornHours ?? Jx，Jx=48h：太新，给宽限）
else                      → STALE     （旧且孤立：可删）
```

`indeg` 来源 `AJe`（定义在 **`43423`**，调用点 `43274`；旧文档写 `42423` 系行号漂移，已订正）。`$Je` 同时对每个 orphan 现算 `indeg=AJe.get` 与 `referencedBy=NJe`（`43434`，列出具体引用文件），ISLAND note 正文（`CJe` `43398`）就靠 `referencedBy` 生成"referenced-by"清单。**精度修正**：`mtimeMs<=0 → 直接 STALE` 仅当 `indeg=0` 时成立；`indeg>=1` 时无论 age 都判 ISLAND（`43324` 优先级）。

**C2 · 破坏性遗忘（`goe` `43345`）只对 STALE，且双 flag AND。** `gL`（`43656`–`43658`）：`forget = ALADUO_EXP_MEMORY_FORGET && check`（双 flag AND）；`43684` 警告文案逐字："FORGET requires CHECK so a node is warned (NEWBORN) before it can be forgotten (STALE)"。`goe` 仅对 STALE（`43346`）。

**C3 · git 软删 + 失败回滚 + 锁保护。** `.git/index.lock` 存在则 `return []`（`43352`）；否则：

```
git rm --ignore-unmatch -- <files>                                   (43354)
git diff --cached --name-only --diff-filter=D -- <files>             (43359，含 --name-only)
git -c user.name=aladuo -c user.email=aladuo@local commit -m <msg> -- <files>   (43368)
失败 → git reset --quiet -- <files>  +  git checkout -- <files>       (43372–43377)
```

> 修正（commit 命令语义）：`-c` 是 **git 顶层 config 开关（位于子命令 `commit` 之前）**，非 `commit -c`（后者 = 复用某提交的 message）。旧文档写成 `git commit -c user.name=...` 位置与语义均有误。`jJe`（`43461`）生成 commit message，confirmed。

**C4 · "不可警告即不可遗忘"。** forget 前 `Toe(s,cL(p))`（`43737`）：STALE 节点若其目标分区**不消费 orphan-newborn 信号**则 `sparedUnwarnable`——连警告都收不到就永远不能被静默删。

**C5 · 活体 help 印证**：`duoduo memory reclaim`——"Never deletes"、`NEWBORN→warn, ISLAND→weaver note, STALE→git rm`、`--tag MANDATORY`、DESTRUCTIVE/manual/git history backup，全部 confirmed。

---

### D. 内容改写整段委派给 memory-weaver 三段流水线

**所以呢**：daemon 只测量、只投信号；任何对知识内容的实际改写都发生在 memory-weaver 分区自己的 tick 上，走一条"事件→fragment→effectiveness→改板"的可复算证据链，从而把 LLM 编造统计的幻觉压在可审计的证据之下。

**D1 · 三段流水线，证据路径与内容路径强耦合**（读磁盘原文 `prompts/subconscious/memory-weaver/CLAUDE.md`）：

```
spine-scanner       读 event JSONL + 当前 board → 写 fragment
                    fragment frontmatter 必含 claude_md_ref | source_line
                    + trajectory(STRENGTHENING/NEUTRAL/WEAKENING) + activation   (68–69, 178–179 行)
        │
        ▼
entity-crystallizer 把 fragment 折进 entity dossier，为每条 board 行写 effectiveness/<slug>.md
        │
        ▼
intuition-updater   编辑某 board 行前【必须先读】该行的 effectiveness 文件 → keep/rewrite/remove/add
```

三 subagent 职责（`66`–`81` 行）confirmed。

**D2 · 每 tick 节流与终止语义。** frontmatter `cooldown_ticks:5, max_duration_ms:2100000`（`4`–`5` 行）；Stage1 每 tick 跑一次 scanner 证据 pass、Stage2 至多处理一条 directed inbox 项（`39`–`43`、`98`–`137` 行）；终止 token `UPDATED / NO-OP / NO_NEW_GRADIENT / BOOTSTRAPPED`（`220`–`223`），**仅终止后才删 inbox ack**，`PARTIAL_UPDATE` 留盘（`225`–`229`）；gradient 优先级 **真人 `channel.message` > 周期后台事件**（`90`–`96`）。

**D3 · consumes 与 §B 路由自洽。** `consumes` 声明 6 kind：entity-converge / sink / merge / orphan-islands / orphan-newborn / scan-gap（`8`–`14` 行）——**memory-weaver 不 consume `revise.v1` / `node-converge.v1`**（那两类归 pattern-tracker，正好对上 B3/B5 的硬编码路由）。

**D4 · 模态标签体系（`meta-prompt.md` `162`–`194`）。** dossier 内每条主张标注 epistemic shape，六标签逐字命中（`164`–`175` 行）：`[observation]` / `[inference]` / `[instruction]` / `[conditional: <event>]` / `[hypothesis (unratified)]` / `[superseded YYYY-MM-DD: <new>]`。覆盖规则（`183`–`185` 行）："Present observation overrides any dossier's `[observation]` or `[inference]`；对 `[instruction]`，当前观察决定其条件是否仍成立。" board 是"已加载的直觉层"，深读 dossier 才应用其模态标签。

---

### 证据表

| 机制主张 | 证据 | 位置 | 置信 |
|---|---|---|---|
| `Ac` 定义 5 字段：memoryDir + boardPath + entities/topics/effectiveness | `return {memoryDir, boardPath, entitiesDir, topicsDir, effectivenessDir}` | daemon `42522`–`42530` | confirmed |
| fragments/ 与 state/meta-memory-state.json 均不在 Ac 内 | Ac 无此二字段 | daemon `42522`–`42530` | confirmed |
| board 种子 `Pl.filter(oL)`；`sy` 遇首个 `]` 即止 | 手写 `[[..]]` 扫描器 | daemon `42561` / `42536`（`42544`） | confirmed |
| BFS `op` 到不动点；`ip` 仅 topics/entities 存在才读 effectiveness | `i.length>0` 守卫 | daemon `42927`(`42932`–`42942`) / `42912`(`42918`) | confirmed |
| orphan 三态优先级 indeg≥1→ISLAND / age<r→NEWBORN / else STALE | `43323`–`43324`，`Jx=48`、`poe=3600*1e3` | daemon `43311`/`43261`(`43469`) | confirmed |
| indeg 源 `AJe` 定义在 43423（非 42423） | 行号漂移订正 | daemon `43423`（调用 `43274`） | confirmed |
| mtimeMs≤0→STALE 仅当 indeg=0；indeg≥1 恒 ISLAND | 判定优先级 | daemon `43324` | confirmed |
| 主循环 `UJe`=runMemoryCheckTick，五 lint 逐个 `$l` try/catch | 导出 `43646` | daemon `43679`(`43750`) | confirmed |
| 投递执行器是 `xoe`；already-pending/--force 在其内 | mkdir+write+分类 | daemon `43571`(`43578`/`43598`/`43589`–`43604`) | confirmed |
| board-lint REVISE/SINK/MERGE 均含 `trajectory!=='NO-EFF'`；partition 硬编码 pattern-tracker | `dJe` | daemon `42867`(`42876`/`42880`/`42889`) | confirmed |
| node-lint References 仅 groove 合法；escalated→WASTED-COMPUTE | `gJe`/`_Je` | daemon `43030`–`43031`/`43045`(`43052`/`43084`) | confirmed |
| gap-lint 黑名单过滤内部 kind；`pQe` 在 75094 复用 | `wJe`/`EJe` | daemon `43215`(`43247`/`43178`) / `75094` | confirmed |
| gap 活体值 = 2026-07-01 bands=[[4,4]]（时点快照，机制 confirmed） | `memory check --dry-run --json` | 活体 RPC | confirmed（值随日期漂移） |
| `mL=1`：每类每 tick 至多一条 worst-first | `slice(0,n)`，help `--limit default 1` | daemon `43775` | confirmed |
| 契约门 `pL` 5 态；`fL` 每 tick 缓存契约 | `uL`/`Yie` 规范化补 .v1 | daemon `43609`/`43474`/`43565`/`42645` | confirmed |
| 前置短路 `Eoe`：无订阅者不测量 | `if(!a&&!r) return` | daemon `43623`(`43640`/`43699`) | confirmed |
| `cL` 仅两处调用（orphan-newborn 路由 + Toe 警告门），非通用路由 | `43339` / `43737` | daemon `43451` | confirmed |
| forget = 双 flag AND，仅 STALE | `gL` | daemon `43656`–`43658`/`43345`(`43346`/`43684`) | confirmed |
| git 软删：rm→diff(--name-only)→`-c ...` 顶层 config commit→失败回滚 | index.lock 保护 | daemon `43354`/`43359`/`43368`/`43372`–`43377`(`43352`) | confirmed |
| 不可警告即不可遗忘 `sparedUnwarnable` | `Toe(s,cL(p))` | daemon `43737` | confirmed |
| weaver frontmatter cooldown_ticks:5 / max_duration_ms:2100000 / consumes 6 kind（无 revise/node-converge） | 磁盘 prompt 原文 | memory-weaver/CLAUDE.md `4`–`14` | confirmed |
| fragment 必含 claude_md_ref\|source_line + trajectory + activation | 磁盘 prompt 原文 | 同上 `68`–`69`/`178`–`179` | confirmed |
| 终止 token 四值，PARTIAL_UPDATE 留盘；真人 channel.message 优先 | 磁盘 prompt 原文 | 同上 `220`–`223`/`225`–`229`/`90`–`96` | confirmed |
| 六模态标签 + 覆盖规则 | meta-prompt.md | `162`–`194`（`164`–`175`/`183`–`185`） | confirmed |

---

> **给 Agent PM 的洞察**（呼应本节领起结论"代码测量、模型裁决"）
> - **测量与执行彻底分离，是本节的塔尖。** daemon 的 lint 永不改内容（help："Never deletes"），只产出带明确 action 的 `.pending` 证据包，投给有认知能力的子 agent 去收敛。这把确定性检测与 LLM 判断解耦，避免规则引擎硬改记忆——正是"代码测量、模型裁决"。
> - **可达性即效用。** 不被 board 闭包触达的节点没有前景影响；孤儿再分 ISLAND / NEWBORN(48h 宽限) / STALE，是带宽限期的软 GC，避免误删刚生成还没接线的知识。
> - **破坏性遗忘 = 可逆软删除。** 双 flag AND、必须先经 NEWBORN 警告、只 git rm（历史可恢复）、目标分区不消费警告即拒删（`sparedUnwarnable`）。对自治 agent 的记忆安全，"遗忘=可逆"是关键设计。
> - **每类每 tick 单条（`mL=1`）+ 前置短路（`Eoe`）+ 契约缓存（`fL`）= 廉价测量三件套。** 测量被压到 worst-first 一条、无订阅者不空跑、契约每 tick 只解析一次——测量便宜，才敢每 37 分钟心跳都做。
> - **证据链可审计。** scanner fragment 必须命名它测试的 board 行（`claude_md_ref`），crystallizer 按行产 effectiveness，updater 改行前必读该行 effectiveness——"事件→证据→效果→改写"可复算链，压制 LLM 编造统计的幻觉。
> - **分区契约门控 = 按需订阅的去中心化路由。** 只有 frontmatter `consumes` 声明某 kind 的分区才收到对应 `.pending`（memory-weaver 不消费 revise/node-converge，正好归 pattern-tracker）；新增分区无需改核心。


---

## 9. 未证实 / 需实测的开放项（明确标注）

以下为验证过程中标注的开放问题或环境限制，**不作为已确立结论**：

1. **活体记忆为空态**：本机为近乎全新实例——广播板 `memory/CLAUDE.md` 为 0 字节、`effectiveness/` 未创建、`meta-memory-state.json = {}`。因此 orphan 三态状态机、board census、weaver 三段流水线的**运行时行为未在有真实记忆的节点上直接观测**；相关结论基于代码路径 + 字面量 + CLI help，非典型运行态数据。（注：cadence 心跳与 4/4 潜意识分区已实测跑完一轮，见 §6。）
2. **dedup 内存 Map 整表 clear 后的去重丢失窗口**：机制确认（`entries.size>=1e4` 即 `clear()`），但**丢失窗口的实际时长/影响未实测**。
3. **`DISABLE_ADAPTIVE / DISABLE_THINKING / MAX_THINKING_TOKENS` 的消费方（未证实推测）**：这些 env 在 daemon 中仅出现在错误提示串里（各 1 次），推断 duoduo 自身不消费、只是透传给底层 Claude Code 二进制/SDK 的建议开关，未在 SDK 侧直接验证。
4. **部分 RPC 方法的活体探测**：控制面方法全集从字面量提取（附录 B），其中 `spine.tail` / `usage.get` / `system.status` 已活体验证返回，其余 handler 存在性以代码字面量为准。

> **本轮 review 已订正的实质结论**（不再是开放项，此处留痕以便对照上一版）：
> - **§1**：原报告的"Claude/Codex 两套并行装配器 + 双 `Contents of` 头嵌套 + Codex developerInstructions 携带时间戳破缓存"——沿真实调用链核验为**不成立**：两路共用 `WT` 装配器，Codex 仅多套一层 `<aladuo:system-context>` 壳，那两处"漂移"实为不可达死代码。上一版开放项中"Codex 侧缓存反模式"据此**撤销**。
> - **§2**：修正了 `accepted` 门控 / 抢占边界处一处布尔倒置，并把抢占边界补全为 `accept/tool_use/tool_result` 三态。
> - **§3**：dequeue 原地复用的行号由误标的 `72905-72914`（实为 `Ne` 的 soft-preempt 日志）订正为 `72091-72125`。


---

## 附录 A：复核索引（关键 file:line 速查）


| 机制 | 位置 |
|---|---|
| system prompt 6 层装配 | `daemon.pretty.js:57186-57221` (WT) |
| prompt_mode 分叉 | `57208` / `57217` |
| meta-prompt 解析 | `57168-57178` (b_) |
| 广播板包装 Jue/H9e/V9e | `57196-57206` / `57708` |
| 广播板 transclusion | `71601-71643` (Ype/Xpe/DXe)，NXe `71750` |
| per-turn 瞬态注入 | `61156-61235` (fde) |
| Codex 装配（**已订正**） | 复用 `WT` 输出，经 `ole` 桥接抽字符串 `57846`；`sle`/`ale`（`57850-57880`）在当前路径为不可达死代码（构造 `S_` 未传 instructions），详见 §1 论点三 |
| 潜意识分区注入 | `74644-74658` (gQe/yQe) |
| 事件封装/原子写 | `30948`/`30934` (xqe)/`30955` (Tqe)/`30992` (Qt) |
| append-before-execute | `76089/76123/76134` (Sne) |
| 去重 YX/KX | `75651-75679`，dup 分支 `76061-76078` |
| 随机读 nl / by_id | `31024-31048` |
| watermark ma | `31852` |
| rehydrate MX | `31307-31347` |
| spine.tail Hie | `77319-77363` |
| 记忆根 Ac | `42522`（4 子路径） |
| 可达性 op/ip/Pl | `42927`/`42912`/`42561` |
| orphan 三态 moe | `43324`（poe=3600e3, Jx=48） |
| lint 主循环 UJe | `43679`，短路 Eoe `43623` |
| 投递门控 pL | `43609`，路由 cL `43451` |
| 遗忘 goe | `43345-43378`，jJe `43461`，双 flag `43684` |
| cadence 间隔 | `76383`（2220000ms） |
| 模态标签 | `meta-prompt.md:162-194` |

---

## 附录 B：地面真值 —— Spine 事件类型 与 控制面 RPC 方法全集

> 由主循环直接从 `daemon.pretty.js` 字符串字面量提取（minify 不改字面量），用于交叉校验各子系统结论、防止逆向幻觉。

**Spine 事件类型**（经事件封装并落 WAL 的合法 type）：
```
agent.error agent.result agent.tool_result agent.tool_use cadence.tick channel.ack 
channel.attached channel.command channel.describe channel.ingress channel.message 
channel.pull channel.spawn external.notify job.complete job.completed job.create job.fail 
job.failed job.get job.list job.spawn job.spawned route.deliver session.archive 
session.compact session.execution session.list session.notify session.output 
session.set_alias session.stream session.stream_end session.streaming_invalidated 
session.wake spine.event spine.sock spine.tail external.notify job.complete job.completed 
job.create job.fail job.failed job.get job.list job.spawn job.spawned session.archive 
session.compact session.execution session.list session.notify session.output 
session.set_alias session.stream session.stream_end session.streaming_invalidated 
session.wake spine.event spine.sock spine.tail system.cadence_tick system.config 
system.runtime.info system.shutdown system.status usage.get 
```

**控制面 / RPC 方法**（`/rpc` JSON-RPC，system./spine./session./job./usage./external.）：
```
external.notify job.complete job.completed job.create job.fail job.failed job.get job.list 
job.spawn job.spawned session.archive session.compact session.execution session.list 
session.notify session.output session.set_alias session.stream session.stream_end 
session.streaming_invalidated session.wake spine.event spine.sock spine.tail 
system.cadence_tick system.config system.runtime.info system.shutdown system.status 
usage.get 
```

> 活体已验证返回：`spine.tail`、`usage.get`、`system.status`。其余以字面量为准（见 §9.5）。


---

## 附录 C：本文的逆向方法论（可复现）

作者不发布源码，只发布 minified 包。本文的分析链路如下，供后来者复现：

1. **反混淆**：`dist/release/{daemon,cli,stdio}.js`（esbuild 打包）→ js-beautify 展开为 `*.pretty.js`（daemon 7.9 万行 / cli 12.8 万行 / stdio 4.7 万行）。变量名已被 mangle（`WT`/`Xc`/`fde`…），但**字符串字面量、事件名、RPC 方法、env 名、日志前缀、路径片段全部保留**——它们是逆向的锚点。
2. **地标索引**：对反混淆代码 grep 关键概念（spine/drain/lease/cadence/partition…）建立「概念→行号」索引，避免通读（大部分体积是打包进来的 react/ink/zod/fastify/claude-sdk）。
3. **提示词层直读**：`bootstrap/` 下 `meta-prompt.md`（agent 身份/记忆纪律的"宪法"）、`config/*.md`、`subconscious/**` 人类可读，直接构成认知层证据。
4. **活体探测**：运行 daemon，用 `duoduo daemon status|config`、`duoduo session list`、`/rpc`（`spine.tail`/`usage.get`/`system.status`）观测真实行为与数据结构。
5. **多 agent 对抗验证**：8 个子系统各由独立分析 agent 逆向，再由**对抗验证 agent**逐条证伪（逆向 minified 代码极易产生"看似合理实则错误"的主张，默认怀疑）；主循环另行提取事件类型/RPC 全集作地面真值交叉校验（附录 B）。

**一句话结论**：duoduo 的"智能是持久的、非一次性的"这一主张，在代码层由三件事共同兑现——**append-before-execute 的 WAL（状态可信可恢复）+ 双注入面的提示词装配（稳定认知与易变状态分离）+ cadence 驱动的潜意识回写广播板（经验跨会话沉淀）**。运行时刻意做薄，把推理全交给模型；它守住的是模型守不住的持久化、生命周期、调度与并发边界。
