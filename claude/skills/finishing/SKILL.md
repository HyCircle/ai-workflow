---
name: finishing
description: 收束当前 Claude session。把本轮已稳定的设计结论就地冻结成 ADR(decisions/NNNN,整块意图+契约),把会话转写成一份 scratch transcript 供 Cursor 侧 /cleaning 读,再出几行给用户续命的总结。用户 /finishing 调用。
---

# Finishing 角色(Claude 收尾)

用户敲 `/finishing` 收束本 session。你做三步,全程中文。**顺序固定:① 冻结 → ③ 总结/交棒 → ② 转写**(转写必须最后跑,才能把交棒写进 jsonl)。
**你只做:著作当轮已稳定的决策 + 出总结/交棒 + 转写会话。文档维护(architecture / TODO / 死链 / scratch 清理)全部交 Cursor 侧 `/cleaning`。**

## ① 冻结本轮设计契约(若有)
本 session 若产生了**已稳定到粘性**的新决策(不可逆 / 会被反复引用),就地著作成 **ADR**(`decisions/NNNN-slug.md`,NNNN = 现存最大+1),整块两海拔:
- **意图**(给人的散文 2–3 句:为什么存在 / 用户可见价值 / 边界;禁 § 引用、禁代码);
- **决策(契约)**(可测:数据形状 / 不变量 / 硬上限 / 明确不做 / 能证伪判据;**不写 file:line / 算法步骤**——那是 WO 的 HOW);
- 再补「备选与失效模式」「后果」。写法权威见 `decisions/0000-template.md`。

改决策 = **开新 ADR**,旧 ADR 翻 `status: superseded` + `superseded_by`,**不改旧正文**(文件级 supersede,不在文内打补丁)。支撑某 ADR 的实验数据顺手提升进 `decisions/NNNN-slug/` 就近同放。
**只冻已稳定的**——早期高频探索、未收敛的念头别冻(免 supersede 链爆炸);设计发散属 `/bs`,这步只定型已收敛的结论。纯施工/临时批次可能无可冻结项 → 跳过。

**为什么现在冻结**:泡在满上下文里的你才能忠实冻结契约;从摘要重推会失真。回溯蒸馏(叙述已冻结的决策进 architecture)是 `/cleaning` 的活。

## ③ 出总结 + 交棒(≤~10 行;在转写之前)
给用户一段【本会话总结 + 下会话起始 prompt】:做完什么、卡在哪、下个 session 冷启动带的最小上下文(指针为主,冷启动顺序:AGENTS → architecture → TODO → 相关 ADR)。
**必须先落盘或先进入会话**再跑转写,否则 transcript 丢交棒。任选:写入 `scratchpad/<PL|BS>-<UUID>/handoff.md`;或保证本条总结已作为助手回复进入当前会话。交棒句应能在 transcript 里被搜到(「交棒」/「下会话」等)。

## ② 转写会话 → transcript(最后一步)
`<UUID>` = 你 scratchpad 路径里那段**完整** uuid(与 `~/.claude/projects/…/<UUID>.jsonl` 同名)。目录就是本 session 的 planner/BS 开工时用同一个 `<UUID>` 建的那个(`PL-<UUID>`/`BS-<UUID>`);下面 `mkdir -p` 幂等,若已在则复用,别另起短名目录。角色前缀:planner 用 `PL`,BS 用 `BS`。

```bash
mkdir -p scratchpad/<PL|BS>-<UUID>
uv run python scripts/workflow/transcribe_session.py --session <UUID> --out scratchpad/<PL|BS>-<UUID>/transcript.md
```

`--session` 必须是**完整 UUID**(脚本按 `<UUID>.jsonl` 精确匹配,截断即 not found)。脚本默认:压工具骨架(留 `[tool] Name({关键参数})`,丢 `[result]` 正文)、保全部自然语言、空 thinking 丢弃;approx-token 软顶(默认 100k),超顶只沿压缩梯子压工具噪声,对最新 NL / 交棒**禁止**静默硬截断。确定性、无 LLM、落盘前 best-effort 打码 secret;transcript 落 gitignored scratch、本地消费、随目录被 `/cleaning` 清除。脚本报错就把错贴给用户。

## 交棒
清理 / 维护在 Cursor IDE:用户敲 `/cleaning`,fresh agent 读 transcript + 读仓做维护(architecture / TODO / 死链 / scratch),人审 diff。
