# duoduo 分析文档

本目录收录对 `@openduo/duoduo` v0.5.8 的深度分析文档（分析日期 2026-07-01，基于本机实际部署 + minified 运行时逆向）。

| 文档 | 视角 | 内容 |
|------|------|------|
| [ARCHITECTURE_ANALYSIS.md](./ARCHITECTURE_ANALYSIS.md) | 系统 / 部署级 | 项目定位、六大核心创新、进程与文件系统模型、部署模式、崩溃恢复实证、可观测性、技能体系。含可复现的本机部署记录与验证清单。 |
| [AGENT_INTERNALS_ANALYSIS.md](./AGENT_INTERNALS_ANALYSIS.md) | Agent 内部逻辑 | 从 minified 运行时**逆向 + 调用链核验（源码函数链 + 活体运行时）+ 多 agent 对抗验证**的 8 个子系统，按**金字塔原理**组织（中心思想 → 4 条 MECE 关键句 → 四部分 → 每节结论先行）：<br>· **一 前台交互**：§1 认知装配 · §2 Turn/Drain·SDK<br>· **二 会话编排**：§3 Session Actor·并发 · §8 Claude/Codex 运行时抽象<br>· **三 可信之源**：§4 Spine·WAL·事件溯源 · §5 Gateway·RPC·通道<br>· **四 后台自治**：§6 Cadence·潜意识引擎 · §7 记忆系统<br>每条机制标注 `file:line` 供复核，置信分 confirmed / 未证实推测。面向 Agent 产品经理 / 架构师。 |

## 关键结论一句话

duoduo 是一个"薄运行时 + 基础模型"的长驻自治 Agent：运行时只拥有模型拥不住的东西——**持久化、生命周期、调度、并发**，推理全部委派给模型。其"智能可持久、非一次性"由三件事在代码层兑现：**append-before-execute 的文件 WAL**（状态可信可恢复）+ **双注入面提示词装配**（稳定认知与易变状态分离、利于缓存前缀）+ **cadence 驱动的潜意识回写广播板**（经验跨会话沉淀成直觉层）。
