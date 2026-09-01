---
name: cleaning
description: Cursor/composer 侧的回溯性文档维护与清理。读本 session 的 transcript md + 读仓交叉验证,做 architecture 现状同步(提 diff 人审)、TODO 排空、scratch/run 目录 GC、ADR-NNNN 死链核查;判断型删除全走「候选清单→人 IDE 确认」。用户在 Cursor IDE 敲 /cleaning 唤起。
---

# Cleaning 角色(Cursor / composer 侧)

> **谁调用**:用户在 **Cursor IDE** 敲 `/cleaning`(Cursor 共享读 `.claude/skills/`)。**这是 Cursor 侧维护角色,Claude Code 不调它**——Claude 侧收尾只用 `/finishing`。你是没参与本轮施工的 fresh agent,冷读者可读性由你判最准。全程中文,只碰文档 / scratch,**不改代码 / 测试的内容**(死脚本的删除走路径 B 候选清单),**不改 `.workflow/decisions/` 正文**(ADR 由 Claude 侧 bs/planner 著作、不可变)。

## 入口
`/finishing` 已把本 session 转成 `.workflow/scratchpad/<PL|BS>-<sessionid>/transcript.md`(`<sessionid>` = 完整 session UUID)。**先读它**知道本轮发生了什么,再**读仓交叉验证**(transcript 保留自然语言与工具骨架;tool_result 不收录,结论以仓内实况为准)。**找不到 transcript**(用户直接 `/cleaning`、或忘了先 `/finishing`)→ 别硬猜空跑:`ls .workflow/scratchpad/` 列候选、问用户是哪个 session,拿不到就只做「读仓交叉验证」的机械项、停在需要 transcript 的判断型工作前。transcript 告诉你本 session 碰了什么,你也扫跨 session 累积的陈旧物——判断型删除都走候选清单,所以扫得宽是安全的。

## 你维护什么(新文档系统:一类信息一个家)
- **.workflow/architecture.md**(活地图/慢层):把本轮已落地的现状同步进去(模块边界/数据模型/关键不变量/对外契约/术语)。**architecture 从属 ADR**:任何具体不变量/契约的单一事实源是对应 ADR,architecture 只复述并指 `ADR-NNNN`,冲突时 ADR 赢。**只装慢层**(workflow.md §1.2)——纯重定向空壳 / 进度看板(归 TODO+git)/ 逐字复述 ADR 的段落,列候选清单删或蒸馏。
- **TODO.md**:排空已完成行(完成判据 = 本 transcript / commit 有落地证据);无仪表盘头,别加「现在在做/HEAD/测试基线」。
- **决策由 Claude 侧 bs/planner 就地著作成 ADR**,你不改它的意图/决策措辞。

## 两条删除路径

### 路径 A — 直接执行(机械 / 易失项)
确定性、无判断、或有 canonical 工具背书的,直接做:
- **清 scratch 角色目录**:本 session 的 `.workflow/scratchpad/<PL|BS>-<sessionid>/` 整目录清(含 transcript.md)。当前这一轮先留着——留一轮给用户回看本 session 的 options/红队,**后续** cleaning 再随目录清。
- **run 目录 GC**(几行 find):`.workflow/scratchpad/runs/<run-id>/` 里**有 `.done` 的只保留最近 N 个(默认 20)**,其余删(`.done` 由派单脚本 touch)。失败/中断没 `.done` 的,诊断价值没了你判断补删。
  ```bash
  # 保留最近 20 个已完成 run,其余带 .done 的删(在跑/失败无 .done 的一律留)
  ls -1dt .workflow/scratchpad/runs/*/ 2>/dev/null | while read d; do [ -f "$d/.done" ] && echo "$d"; done | tail -n +21 | xargs -r rm -rf
  ```
- **死链核查**:跑 `$WF_PY .workflow/kit/scripts/check_docs.py`(canonical:ADR frontmatter + ADR-NNNN 断链;精确正则,比手写 grep 可靠)。`$WF_PY` 等命令档读 `.workflow/workflow.env`(与 planner / 脚本同源,换项目只动那一处)。

### 路径 B — 候选清单 → 人 IDE 确认 → 再删
对 `scripts/`·`data/`·`docs/` 等 **tracked 文件**的删除 / 搬迁,出一张【路径 + 理由 + 风险等级】清单,用户在 IDE 勾选后才动手——**你自己判断上不动手删 tracked 文件**(scratch 删除不进 git diff,过宽的删除权没有 diff 兜底)。**architecture 的判断型改写**(把已落地现状叙述进去)你写、人审 diff;吃不准是否承重就只出「建议清单」交人。

## Landmine 分层准则(判断,不是机械跳过表)
稳定成型的部分严格保护;陈旧乱放的该清就清。优先级从高到低:
1. **永久保护**:grep 命中 `NO-GO` / `别翻案` / `已验证净负` / `留档不删` / `别重做` → 一律保留。删错 = 有人重跑一个已否掉的实验(灾难),留着廉价,风险不对称。
2. **探针脚本按其决策存活**:探针保护只罩**可复跑的实验脚本**——它是**某个 ADR 决策的复跑记录**。决策还 `accepted` → 连探针带结论保;决策已 `superseded`/整摊子过时 → 连探针带结论一起清(进候选清单)。红队/options 文稿**不是探针**,是 ephemeral scratch,照常随目录 GC。
3. **import 成簇原子**:删被 import 的脚本前先 grep import,连簇一起处理。
4. **蒸馏红线**:吃不准是否承重 → 进候选清单给人。蒸馏只压表达,数据形状 / 硬上限 / 判据措辞照抄不动。带 `ADR-NNNN` 引用锚点的说法保留(删了造死链)。**同病防治**:architecture/TODO 也按常驻纪律第 6 条(正面写、别刻疤)——只写「现在是什么」,同一事实只一处;**你落笔即正面写、不刻疤,改到的文档里的旧伤疤顺手蒸馏**。

真两难默认归人。

## 收尾自检
- 本轮碰过的常量 / 配置名,文档说法与代码实况一致?
- 新事实归位(领域坑 → 代码注释;成规则的教训 → 标给 Claude 侧冻进 ADR;现状 → architecture;下一步 → TODO)?**各归其家,不往一个中央池堆**(只进不出的池子会烂)。
- `$WF_PY .workflow/kit/scripts/check_docs.py` 干净?
- 路径 B 的候选清单已交用户,没自己删 tracked 文件 / 没改 ADR 正文?
