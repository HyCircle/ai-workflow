---
name: finishing
description: 收束当前 Claude session。出收尾总结 + 交棒(含本轮未冻决定的候选),把会话转写成一份 scratch transcript 供 Cursor 侧 /cleaning 读。决定的冻结在成熟当下由 bs/planner 就地做,不在这儿。用户 /finishing 调用。
---

# Finishing 角色(Claude 收尾)

用户敲 `/finishing` 收束本 session。你做两步,全程中文。**顺序固定:① 总结/交棒 → ② 转写**(转写必须最后跑,才能把交棒写进 jsonl)。
**你只做:出总结/交棒 + 转写会话。决定的冻结不在这儿**——ADR 在决定成熟的当下由 bs/planner 就地冻(自带单轮红队);finishing 只把「本轮稳了但还没冻」的决定列进交棒当候选。**文档维护(architecture / TODO / 死链 / scratch 清理)全部交 Cursor 侧 `/cleaning`。**

## ① 出总结 + 交棒(≤~10 行,作为助手回复;在转写之前)
给用户一段【本会话总结 + 下 session 开场提示词】:做完什么、卡在哪、下个 session 冷启动带的最小上下文(指针为主,冷启动顺序:agent-discipline → AGENTS → architecture → TODO → 相关 ADR)。**本轮若有稳定但还没冻的决定,列一行候选**(下次由 bs/planner 就地冻)。**末尾固定一段可复制的「下 session 开场提示词」**——转写后它在 transcript 尾部,下 session 直接复制,或读 transcript 尾部定位。
交棒只进会话、不落文件:转写保全部自然语言(含本条总结与用户对 /finishing 的要求),transcript 就是交棒的文档。

## ② 转写会话 → transcript(最后一步)
`<UUID>` = 你 scratchpad 路径里那段**完整** uuid(与 `~/.claude/projects/…/<UUID>.jsonl` 同名)。目录就是本 session 的 planner/BS 开工时用同一个 `<UUID>` 建的那个(`PL-<UUID>`/`BS-<UUID>`);下面 `mkdir -p` 幂等,若已在则复用,别另起短名目录。角色前缀:planner 用 `PL`,BS 用 `BS`。

```bash
mkdir -p .workflow/scratchpad/<PL|BS>-<UUID>
$WF_PY .workflow/kit/scripts/transcribe_session.py --session <UUID> --out .workflow/scratchpad/<PL|BS>-<UUID>/transcript.md
```
(`$WF_PY` 读 `.workflow/workflow.env`,与 planner / 脚本同源;换项目只动那一处。)

`--session` 必须是**完整 UUID**(脚本按 `<UUID>.jsonl` 精确匹配)。脚本:保全部自然语言;tool_use 压成 `[tool] Name({关键参数})` 骨架、连续纯工具 Assistant 段合并、丢 tool_result 正文与空 thinking;确定性、无 LLM、落盘前 best-effort 打码 secret。transcript 落 gitignored scratch、本地消费、随目录被 `/cleaning` 清除。脚本报错就把错贴给用户。

## 交棒
清理 / 维护在 Cursor IDE:用户敲 `/cleaning`,fresh agent 读 transcript + 读仓做维护(architecture / TODO / 死链 / scratch),人审 diff。
