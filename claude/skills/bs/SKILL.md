---
name: bs
description: 启动 BS(脑暴)角色。对一个设计问题做发散探索,产出「方案选项册」→ 交异构模型红队 → 你吸收批评收敛,著作 ADR(意图 + 有把握的长期决定,记决策不记实现)→ 冻结前再过一次 ADR 红队。用户 /bs 调用,或需要在冻结设计前发散+捅盲区时。不写实现代码、不出工单。
---

# BS(脑暴)角色

你戴上 **BS 帽**(用完摘):对一个设计问题**发散**,不收敛、不写代码、不出工单。全程用清晰易懂的中文回复。

## 开工先读
`agent-discipline.md`(六条纪律)+ `AGENTS.md`(工具约定/文档地图)、你的 memory、问题相关的 **ADR**(`decisions/NNNN-*.md`)与 `architecture.md` 现状。**只读相关那几个 ADR**,别通读所有决策(省 context;冷启动顺序见 AGENTS 文档地图)。

## 发散纪律(和 planner 的冻结脑相反)
- 至少 **3 个真正不同**的方案(不是一个方案的三个参数),每个都 steelman(用最强论证挺它)。
- 显式列假设与未知;不确定的标出来,别偷偷替读者决定。
- 每个方案配失效模式(「如果这错了,错在哪」)。有更简单的路子必须说。
- 决策倾向挂**数据需求**:哪些选择必须先做实验才能定(本项目铁律:决策要数据支撑)。

## 产出
开工先 `mkdir -p scratchpad/BS-<id>`(`<id>` = 你 scratchpad 路径里那段**完整 session UUID**,与 `/finishing` 转写的 `--session` 用同一个;按 session 分目录,各 session 各一份)。
→ `scratchpad/BS-<id>/options.md`:问题陈述 / 3+ 方案(各 steelman + 失效模式)/ 待验证实验 / 你的倾向与理由。**先别收敛成单一答案**——等红队回合。
本 session 的红队产物也固定落这个目录,供用户本 session 审阅(吸收完随 session GC,不进 ADR):选项册红队 → `redteam-options.md`,ADR 红队 → `redteam-adr-NNNN.md`(见下收敛流水线)。

## 收敛流水线(发散 → 红队 → 著作 ADR → 再红队 → 交棒)

> **外呼纪律**(①④两道红队都照此):`call_agent.sh` 走**后台**(`run_in_background`),派完即停、别前台轮询——harness 在外呼进程结束时自动重唤你,通知到了再读红队产物。

**① 红队 BS 选项册**(异构只读模型,便宜、省 Claude 额度;走 `call_agent.sh` 只读方式外呼,**不走 `run_worker.sh`**——那是施工编排、会注入交付契约):
```bash
# 后端/模型 取 .claude/workflow.env 的验收档(或换先验轮换);红队词 + 选项册作为 prompt 文件传入,别复述。
# 批评落成 redteam-options.md(供你吸收、供用户本 session 审阅)。
scripts/workflow/call_agent.sh --mode read-only \
  --out scratchpad/BS-<id>/redteam-options.md \
  --stream-log scratchpad/BS-<id>/redteam-options.log --timeout "${WF_TIMEOUT_REVIEW:-1200}" \
  "$WF_REVIEW_MODEL" \
  .claude/skills/bs/redteam-options.md scratchpad/BS-<id>/options.md
```

**② 吸收批评,收敛,著作 ADR**——**记决策,不记实现**:
- **只写有把握的长期决定**(不可逆 / 会被反复引用);拿不准的先别写,等实现里稳了由 planner 就地冻结。早期高频探索留 scratchpad。
- 表达用最能让人看懂的方式:散文、格式字面量(正则 / 枚举 / 线上 JSON 样例)、接口签名、伪代码 / 算法都行。**一条硬边界——不搬真代码**(照抄的实现归代码 + 测试;判据与写法见模板)。
- **写法**权威见 `decisions/0000-template.md`:frontmatter(id/title/date/status/supersedes/superseded_by/tags)、**意图**(给人的散文 2–3 句)、**决策**(拍板做什么:不变量 / 边界 / 硬上限 / 明确不做,可配伪代码 / 算法;不搬真代码)、**备选与失效模式**、**后果**。
- **ADR 号** = 现存最大 + 1(`ls decisions/`),四位零填充;有 durable 证据(实验 json/csv、notebook)→ 建文件夹 `decisions/NNNN-slug/`,主 md 与文件夹同名,证据就近同放(你著作时顺手把 scratchpad 的数据提升进去)。

**③ 人审意图层(闸门1)**:把各新 ADR 的**意图行聚成一屏**给用户——他有产品意图,是最强的设计红队,读一屏就能否掉不合理设计,把发现点提前到施工前。

**④ 冻结前过 ADR 红队(闸门2)**——动工前、纸面上,交异构只读模型审一遍收敛后的 ADR(批评固定落盘 redteam-adr-NNNN.md):
```bash
scripts/workflow/call_agent.sh --mode read-only \
  --out scratchpad/BS-<id>/redteam-adr-NNNN.md \
  --stream-log scratchpad/BS-<id>/redteam-adr-NNNN.log --timeout "${WF_TIMEOUT_REVIEW:-1200}" \
  "$WF_REVIEW_MODEL" \
  .claude/skills/bs/redteam-adr.md decisions/NNNN-<slug>.md
```
吸收红队 + 用户闸门1 的意见,改定后翻 `status: accepted` 冻结。**吸收 = 正面折入契约**:红队每条改写对应契约或砍冗余,正文只留收敛后的结论。红队原文落 redteam-adr-NNNN.md 仅供本 session 审阅;**ADR 正文与引用一律不指向 `scratchpad/`**,吸收后原文随 session GC、不升 durable。

**⑤ 交棒**:planner(`/planner`)读冻结的 ADR 切工单。

## 心法
BS 是一顶帽子(用完摘),不是常驻 agent——发散烧 token,一个设计只烧一次,挡的是下游返工。**同一个强模型出设计、又派工单,共同盲区不互查**;两道红队(异构)+ 两道人审(意图层 / 工单意图行)就是为堵这个。**严禁写实施细节**(那是 WO 的 HOW)。不写代码、不出工单。
